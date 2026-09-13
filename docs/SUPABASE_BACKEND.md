# Supabase backend

network.to uses Supabase as its application backend: Auth for passwordless work-email access, Postgres for product state, Row Level Security for authorization, database functions for sensitive transitions, Realtime publication for participant-scoped updates, and Edge Functions for privileged jobs.

The iOS app contains only the project URL and publishable key. Never add a service-role key to Xcode, an `.xcconfig`, or the app bundle.

## Local setup

Requirements:

- Docker Desktop running
- Supabase CLI
- Xcode 26 or later

From the repository root:

```sh
supabase start
supabase db reset
supabase test db
supabase status
```

`db reset` applies the ordered migrations and `supabase/seed.sql`. The seed adds development-only companies and work-email domains; production companies are added by migration as a product decision, as the constitution requires.

In Xcode, open Product → Scheme → Edit Scheme → Run → Arguments and add:

```text
SUPABASE_URL=http://127.0.0.1:55321
SUPABASE_PUBLISHABLE_KEY=<the publishable/anon key printed by supabase status>
```

The local email inbox is available at `http://127.0.0.1:55324`. Supabase sends the magic link there instead of sending real email. Keep the app’s waiting screen open, then open the link from Mailpit to complete the PKCE flow. Remove both environment overrides to return to the hosted project, or add the Debug launch argument `--mock-backend` for deterministic local data. This repository uses the `5532x` range so it can coexist with another Supabase project using the CLI defaults.

## Data model and privacy boundary

The migrations create:

- the verified company registry: one `companies` row per company (display name, industry, website, coverage clause, approval status, and the served company mark) with one or more `company_domains` rows per company, plus private member profiles
- professional history, career direction, growth goals, contributions, and matching preferences
- selective introductions and private per-member responses
- conversations and messages created only after reciprocal interest
- meetup plans, private feedback, and member-owned connections
- blocks, reports, private résumé records, device tokens, and notification events
- private membership state, including the non-resettable account trial and verified App Store entitlement
- notification delivery bookkeeping, App Store Server Notification records, operational incidents, and posted operations alerts, kept in the private schema or behind service-role-only functions
- company mark versions, mark operations runs, and per-company outcomes in the private schema; the mark files themselves live in the public `company-marks` Storage bucket under versioned paths

The native client listens to its RLS-filtered notification-event stream and refreshes relationship state when an introduction becomes mutual, a message arrives, or meetup state changes. It also refreshes when the app returns to the foreground.

Every exposed table has RLS enabled. Direct profile access is self-only. The other member’s limited professional profile is returned only by relationship-scoped read functions. A client cannot read the other person’s Interested/Pass response.

High-impact transitions use `security definer` database functions with an empty `search_path` and explicit grants:

- `save_professional_profile` writes a profile and its professional history in one transaction, so onboarding cannot leave a partially saved account.
- `respond_to_introduction` records a decision once and atomically creates a conversation only when both members are interested. A Pass is private: it hides the introduction from the member who passed and frees them for matching at their cadence, while the introduction stays open for the other member, with its original expiry, until it expires, becomes mutual, or is blocked; it closes at once only when both members have passed. An Interested response after the other member's Pass returns the same waiting outcome as one nobody has answered.
- `send_message` verifies conversation participation and uses a client-generated UUID so retries cannot create duplicate messages.
- `create_meetup` and the feedback functions enforce conversation participation.
- `block_member`, `end_conversation`, and `submit_member_report` validate an existing relationship before changing state.
- The private matching job first limits candidates to the same normalized city, then requires reciprocal professional relevance and overlapping meeting preferences while respecting each member's exact cadence, blocks, pauses, repeat-introduction constraints, and one active introduction per member (an introduction a member passed on no longer counts as theirs). Cross-company and cross-industry introductions receive a ranking bonus.
- Matching requires both members to have an active free month or verified subscription. Expiry pauses only future matching; conversations and connections remain accessible.

## Authentication

The app uses passwordless email magic links with Supabase’s PKCE flow. Before a new Auth user is created, `hook_restrict_signup_by_company_domain` rejects unapproved domains. The post-signup trigger copies trusted company and industry values from `company_domains`; the client cannot overwrite those fields.

The verification flow supports both common inbox locations:

- The iPhone creates a short-lived handoff and includes its ID as a query parameter in the HTTPS callback URL.
- Whether the link opens on the same iPhone or on a managed laptop, the Edge Function deposits only the short-lived, single-use authorization code on the server. It then redirects the browser to a clean confirmation URL with no authorization code or handoff ID in the address bar.
- The waiting iPhone claims the code with a separate 256-bit secret and exchanges it using the PKCE verifier that never left the phone. No access token, refresh token, password, or code needs to be copied between devices.

Handoff rows live in the private schema for at most ten minutes. Database functions are service-role-only, and a successful claim deletes the row atomically.

Local hook and email-template settings live in `supabase/config.toml`. For a hosted project, confirm the following after linking the project:

1. Authentication → Hooks → Before User Created points to `public.hook_restrict_signup_by_company_domain`.
2. Site URL points to the hosted `auth-handoff` Edge Function.
3. Allowed redirect URLs contain both the exact HTTPS handoff URL and `networkto://auth/callback`.
4. TOTP MFA remains available even though the first-party app does not require enrollment.
5. Configure the hosted confirmation and magic-link templates from `supabase/templates/`, then configure custom production SMTP before inviting users outside the Supabase project team. The default sender is intended for testing and is rate-limited. The templates construct the `/auth/v1/verify` URL explicitly so PKCE callback query parameters are preserved.

## Scheduled work and Edge Functions

- Postgres schedules five jobs through `pg_cron`: `private.run_matching_batch(25)` hourly at minute 7, `private.run_meetup_followups()` hourly at minute 37, `private.dispatch_notification_delivery()` every minute, `private.run_operations_alerts()` every 15 minutes, and `private.run_retention_maintenance()` daily at 04:15 UTC. Matching outcomes are recorded in `private.matching_runs` for operations review.
- `auth-handoff`: completes the HTTPS callback server-side, clears its secrets from the browser URL, and relays a single-use PKCE authorization code from a work laptop to the originating iPhone. Its confirmation is intentionally plain text because Supabase Edge Functions rewrite HTML responses as `text/plain`.
- `delete-account`: verifies the caller, deletes private résumé objects, then deletes the Auth user so database rows cascade. Any failure is recorded as an operational incident.
- `process-resume`: authenticates the member, enforces a durable per-account quota, sends bounded text extracted and contact-redacted on the iPhone to the DeepSeek Responses API, and returns a schema-constrained factual draft for review.
- `sync-subscription`: authenticates the member, verifies StoreKit 2 signed transaction data against Apple’s certificate chain, bundle ID, product ID, expiry, and account token, then records access through a service-role-only database function.
- `deliver-notifications`: called by the database schedule with `NOTIFICATION_JOB_SECRET`. It claims due notification events for members with a registered device, sends each through APNs with a token-based (ES256) provider key, retires tokens Apple reports as unregistered, and records every outcome on the event. Requires `APNS_KEY_ID`, `APNS_TEAM_ID`, and `APNS_PRIVATE_KEY` (the `.p8` contents; escaped newlines are accepted); `APNS_BUNDLE_ID` overrides the default topic.
- `app-store-notifications`: receives App Store Server Notifications v2, verifies Apple's signature for the claimed environment, maps the notification to a membership state, and records it through an idempotent, order-aware database function.
- `generate-introductions`: an optional manual operations endpoint protected by `MATCHING_JOB_SECRET`; it is not required for the scheduled production path and does not need to be deployed by default.
- `company-marks`: the operations action for company marks, protected by `COMPANY_MARKS_JOB_SECRET`. `populate` fetches each approved company's own published icon (from the website on its registry entry, following only that site's redirects, never an icon service), keeps the largest still PNG or JPEG of at least 128 px and at most 1 MiB, stores it as `company-marks/<key>/<version>.<png|jpg>`, and records an outcome per company (`fetched`, `no_icon_published`, `fetch_failed` with a reason). It processes ten companies per invocation and continues itself until the registry is covered; a second start while a run is running records `skipped`. `refresh` re-fetches named companies as a new version, `status` returns the whole registry's mark state, and `purge` deletes the files of versions retired more than 30 days ago (also triggered by the daily retention job).

`auth-handoff` also applies durable, salted IP rate limits. Generate a separate random 256-bit `HANDOFF_RATE_LIMIT_SALT`; never reuse a signing, database, or Apple key.

Scheduled HTTP calls read their configuration from Supabase Vault, so no secret or project URL lives in a migration. Create these once per project from the SQL editor:

```sql
select vault.create_secret('https://<project-ref>.supabase.co', 'project_url');
select vault.create_secret('<random 256-bit secret>', 'notification_job_secret');
select vault.create_secret('https://hooks.example.com/services/...', 'ops_alert_webhook_url');
select vault.create_secret('<another random 256-bit secret>', 'company_marks_job_secret');
```

`notification_job_secret` must equal the `NOTIFICATION_JOB_SECRET` function secret and `company_marks_job_secret` must equal `COMPANY_MARKS_JOB_SECRET`. Until `project_url` and `notification_job_secret` exist the dispatcher stays idle, until `ops_alert_webhook_url` exists alerts stay pending, and until `company_marks_job_secret` exists the daily job skips the mark-file purge; nothing fails loudly in a project that has not been configured yet.

## Company marks

Every approved company may serve one company mark: its own publicly published icon, fetched once server-side and shown beside the verified company name on the introduction screen, in conversations, in Connections, and on the member's own profile. The phone reads marks only from this project's Storage host (`/storage/v1/object/public/company-marks/<key>/<version>.<ext>`) without a session, keeps a copy in its Caches directory, and falls back to a company monogram whenever no mark is served. The mark reference (`{"key","version","path"}`) travels inside the existing relationship-scoped read models and `get_own_company_mark()`; it names the company, never an email domain, and is null unless the company is approved and its mark is `available`.

Operate marks with the `company-marks` function and a few service-role functions from the SQL editor:

```sh
curl -sS -X POST "https://<project-ref>.supabase.co/functions/v1/company-marks" \
  -H "x-job-secret: $COMPANY_MARKS_JOB_SECRET" -H "content-type: application/json" \
  -d '{"action":"populate","requested_by":"<your name>"}'
```

```sql
select public.get_company_mark_overview();                 -- every company with mark status, version, last fetch, reason
select public.set_company_mark_withheld('shopify', true);  -- unsuitable icon: members see the company monogram
select public.request_company_mark_refresh('shopify');     -- rebrand: the next populate stores a new version
```

Marks are never refreshed automatically. Run records are kept for 180 days; files of superseded, withheld, or withdrawn versions are deleted within 30 days by the purge action, which the daily maintenance job requests through `pg_net` once the Vault secret exists. Setting a company's status to anything but `approved` withdraws its mark immediately without changing existing members' company name, access, conversations, or connections.

## Production deployment

Production changes are deployed only by [`.github/workflows/supabase.yml`](../.github/workflows/supabase.yml). Do not run `supabase db push` or `supabase functions deploy` against the hosted project from a development machine.

Create a protected GitHub environment named `production` and add these encrypted environment secrets:

- `SUPABASE_ACCESS_TOKEN`: a Supabase personal access token with access to the project
- `SUPABASE_DB_PASSWORD`: the production project database password
- `SUPABASE_PROJECT_ID`: the production project reference

Pull requests that touch `supabase/**` or the workflow start a local database, run the pgTAP suite, type-check every Edge Function, and run the Deno unit tests. A push to `main` deploys only after that validation passes, and only from `main`, even for manual runs. Each deployment applies migrations first, then deploys `auth-handoff`, `app-store-notifications`, `deliver-notifications`, and `company-marks` without gateway JWT verification because each authenticates its caller itself, then `delete-account`, `process-resume`, and `sync-subscription`. `generate-introductions` is deliberately excluded because the database schedule is the production matching path.

Deployments reach staging before production. Create a second Supabase project and a GitHub environment named `staging` holding the same three secret names for that project. Until those secrets exist, the staging job reports that it was skipped and production proceeds, so the pipeline works with one project today and two later.

Server-side function secrets are still configured separately in the Supabase Dashboard. They are not copied into GitHub unless a future workflow explicitly manages secret rotation.

For initial GitHub environment setup, obtain these values from the Supabase Dashboard rather than committing them:

```sh
SUPABASE_ACCESS_TOKEN=<personal-access-token>
SUPABASE_DB_PASSWORD=<project-database-password>
SUPABASE_PROJECT_ID=<project-reference>
```

Supabase provides its URL and server-side keys to deployed functions. The database migration installs the matching and maintenance schedules, so no public scheduler URL or matching secret is needed for normal operation.

## Notifications

Notification preferences and permission remain in native iPhone Settings, as intended. Supabase stores validated device registrations, creates deduplicated notification events, and delivers them:

- `private.dispatch_notification_delivery()` runs every minute. When an event is due for a member with a registered device, it posts to `deliver-notifications` through `pg_net` using the Vault secrets above; otherwise it does nothing.
- `claim_notification_deliveries` hands the function a bounded batch and counts each claim as an attempt, so failures back off exponentially and stop after eight attempts. `complete_notification_delivery` records success or the last error, and `retire_device_token` removes tokens APNs reports as unregistered. All three are service-role-only.
- Payloads carry only identifiers and calm copy. A pending introduction stays anonymous, message bodies are never pushed, and a Pass never notifies anyone.
- Meetups become `feedback_due` three hours after their scheduled start and both participants receive one `feedback_due` event, so private feedback is requested even when nobody reopens the conversation.
- Undelivered events stay available to the in-app stream and are removed after 90 days.

Delivery needs an APNs authentication key from the Apple Developer account: set `APNS_KEY_ID`, `APNS_TEAM_ID`, and `APNS_PRIVATE_KEY` as function secrets and never place the key in iOS. Until they are set, claimed events fail with "APNs is not configured", which the operations alert surfaces.

The iOS app asks for permission once, from a card at the top of Today after onboarding (never at launch, on the sign-in screens, or during onboarding), and only while the phone has never been asked; a member who chooses "Not now" is not asked again and can turn notifications on from the Profile row. While alerts are allowed and a member with complete onboarding is signed in, the app registers the phone's APNs token through `register_device_token` on every activation, so `updated_at` is the registration's last-confirmed time. The channel is read from the embedded provisioning profile: `sandbox` for a development-profile build, `production` for TestFlight and App Store installs; the simulator and demonstration mode register nothing. Before signing out the app removes the token through `unregister_device_token`, waiting at most five seconds; after a confirmed account deletion it forgets its local notification memory. Tapping a notification opens Today for `introduction_ready` and the referenced conversation for the other four kinds, in every app state; while the member is already on that screen the banner is suppressed and the state refreshes quietly, and notifications about an item leave the phone's list once the item is on screen. The app target carries `NetworkTo/NetworkTo.entitlements` (`aps-environment`), so Push Notifications must be enabled on the App ID in the Apple Developer account before a device build can obtain a token; automatic signing does this on the first device build when Xcode is signed in with an account allowed to edit identifiers.

## Membership and App Store setup

The free month begins when professional onboarding changes from incomplete to complete. It is stored in `private.memberships`, so deleting the app or changing devices does not restart it. When the free month ends, new matching stops while existing messages and connections remain usable.

Create one auto-renewable monthly subscription in App Store Connect with product ID `com.mesbahtanvir.networkto.monthly` and the intended US price point (the local StoreKit fixture is $9.99). Set the numeric App Store application ID as a function secret before accepting production receipts:

```sh
supabase secrets set APPLE_APP_ID=<numeric-app-store-id>
```

The app sends StoreKit’s JWS transaction after purchase, restore, and authenticated launch. The server rejects Xcode-local transactions, cross-account transaction replay, the wrong bundle or product, revoked receipts, and unverified payloads. Renewals, cancellations, billing retry, grace periods, and refunds update membership even when the app is closed: point both the production and sandbox server notification URLs in App Store Connect (version 2) at `https://<project-ref>.supabase.co/functions/v1/app-store-notifications`. The function verifies each payload against Apple's certificate chain, bundle ID, environment, and app ID, then `record_app_store_notification` applies it once. Redelivered notifications return `duplicate`, notifications older than the state already applied return `stale`, notifications for unknown members or other products are recorded but ignored, and failures are recorded for alerting. Members are matched by the `appAccountToken` the app attaches at purchase, falling back to the original transaction already on file. A verified transaction for a member without a membership row never starts a free month.

## Résumé handling

The résumé fast path uses the native iOS document picker and accepts PDFs smaller than 10 MB. PDFKit reads embedded text locally; pages without readable embedded text use Apple Vision OCR. Before any text leaves the phone, common email addresses, phone numbers, and URLs are removed. The source PDF is never uploaded by this flow.

The authenticated `process-resume` function uses `deepseek-v4-flash` by default with a strict JSON schema. It accepts at most 40,000 characters and treats résumé contents as untrusted source data rather than instructions. It can draft identity, current role and scope, an explicitly supported current focus, experience range, expertise, work history, education, and a neutral summary of demonstrated experience. It never drafts ambitions, growth goals, personality, protected traits, compensation, contact details, willingness to help, or contribution boundaries.

The iOS flow reports real stages—local reading, contact-detail protection, professional drafting, and review. The returned draft is held separately from the member profile. Every inferred field, topic, and work-history item has an individual remove control, and nothing is applied until the member explicitly confirms the selected details. After confirmation, onboarding skips factual sections that are already complete and asks the member to write the professional ambition that cannot safely be inferred.

Set `DEEPSEEK_API_KEY` as a Supabase function secret to enable live drafting. `DEEPSEEK_RESUME_MODEL` is optional and defaults to `deepseek-v4-flash`.

## Production status and remaining launch dependencies

Already implemented:

- Fifteen migrations, RLS, private schemas, transactional profile writes, idempotent messages, account-scoped trials, same-city subscription-aware matching schedules, meetup follow-ups, notification delivery bookkeeping, App Store Server Notification handling, retention, and Edge Function abuse controls.
- Hosted `auth-handoff`, `delete-account`, `process-resume`, and `sync-subscription` functions, plus a live cross-device handoff smoke test.
- `deliver-notifications` and `app-store-notifications` functions, driven by the database schedule and Apple respectively, each authenticating its own caller.
- Operations alerts for failed or stalled matching, repeated notification delivery failures, App Store notifications that could not be applied, new member reports, and account-deletion failures, posted once each to a Vault-configured webhook.
- CI validation with pgTAP and Deno unit tests, and a staging-then-production deployment path that deploys only from `main`.
- Database behavior and authorization coverage for two isolated users; run `supabase test db` before each deployment.
- A registry of 249 verified companies over 258 work-email domains, each recorded with the coverage clause that admitted it, and company marks fetched from each company's own website, served versioned from the project's storage, with withhold, refresh, and purge operations.
- iPhone remote notifications: permission asked once from Today after onboarding, token registration on every activation and removal before sign-out, tap routing to Today or the referenced conversation, banner suppression on the destination screen, and delivery preferences kept in iPhone Settings.

Required before a public App Store launch:

- Configure custom SMTP and verify delivery from representative corporate inboxes.
- Create the App Store Connect subscription, set `APPLE_APP_ID`, add final hosted Terms and Privacy URLs, and point App Store Server Notifications v2 (production and sandbox) at the deployed `app-store-notifications` function.
- Create an APNs authentication key, set `APNS_KEY_ID`, `APNS_TEAM_ID`, and `APNS_PRIVATE_KEY` as function secrets, and enable Push Notifications on the App ID `com.mesbahtanvir.networkto` so device builds obtain a token; never expose the APNs private key to iOS.
- Create the Vault secrets `project_url`, `notification_job_secret`, and `ops_alert_webhook_url`, and set the matching `NOTIFICATION_JOB_SECRET` function secret.
- Complete privacy and data-processing review for DeepSeek before inviting public users, and disclose that redacted résumé text is processed by the provider.
- Create the staging Supabase project and the `staging` GitHub environment so every `main` deployment reaches staging before production.
- Create the Vault secret `company_marks_job_secret` with the matching `COMPANY_MARKS_JOB_SECRET` function secret, run the `company-marks` populate action once, and review the companies it reports as `no_icon_published` or `fetch_failed`.
- Grow the company registry only by migration as a product decision, and add CAPTCHA or additional Auth abuse controls if observed traffic warrants it.
- Keep the service-role key restricted to trusted server-side functions and jobs.

## Production data hygiene

Repository fixture identities and fictional company domains are never valid production members. Migration `20260911031054_remove_production_fixture_data.sql` removes only those exact fixtures and immediately applies the existing retention policy. It deliberately preserves incomplete onboarding accounts, inactive profiles, and real-company accounts because none of those states proves that a member is disposable.

The cleanup aborts if a fixture identity owns a Storage object. Storage objects must be removed through the Storage API before deleting the Auth user so the underlying object is deleted along with its metadata. Future production cleanup must follow the same rule: use an explicit reviewed identity set, never a broad condition such as age, inactivity, or incomplete onboarding.
