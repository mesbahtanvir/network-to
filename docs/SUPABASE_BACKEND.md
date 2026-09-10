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

`db reset` applies the ordered migrations and `supabase/seed.sql`. The seed contains development company-domain decisions; production domains should be reviewed and maintained as operational data.

In Xcode, open Product → Scheme → Edit Scheme → Run → Arguments and add:

```text
SUPABASE_URL=http://127.0.0.1:55321
SUPABASE_PUBLISHABLE_KEY=<the publishable/anon key printed by supabase status>
```

The local email inbox is available at `http://127.0.0.1:55324`. Supabase sends the magic link there instead of sending real email. Keep the app’s waiting screen open, then open the link from Mailpit to complete the PKCE flow. Remove both environment overrides to return to the hosted project, or add the Debug launch argument `--mock-backend` for deterministic local data. This repository uses the `5532x` range so it can coexist with another Supabase project using the CLI defaults.

## Data model and privacy boundary

The migrations create:

- verified company domains and private member profiles
- professional history, career direction, growth goals, contributions, and matching preferences
- selective introductions and private per-member responses
- conversations and messages created only after reciprocal interest
- meetup plans, private feedback, and member-owned connections
- blocks, reports, private résumé records, device tokens, and notification events
- private membership state, including the non-resettable account trial and verified App Store entitlement

The native client listens to its RLS-filtered notification-event stream and refreshes relationship state when an introduction becomes mutual, a message arrives, or meetup state changes. It also refreshes when the app returns to the foreground.

Every exposed table has RLS enabled. Direct profile access is self-only. The other member’s limited professional profile is returned only by relationship-scoped read functions. A client cannot read the other person’s Interested/Pass response.

High-impact transitions use `security definer` database functions with an empty `search_path` and explicit grants:

- `save_professional_profile` writes a profile and its professional history in one transaction, so onboarding cannot leave a partially saved account.
- `respond_to_introduction` records a decision once and atomically creates a conversation only when both members are interested.
- `send_message` verifies conversation participation and uses a client-generated UUID so retries cannot create duplicate messages.
- `create_meetup` and the feedback functions enforce conversation participation.
- `block_member`, `end_conversation`, and `submit_member_report` validate an existing relationship before changing state.
- The private matching job first limits candidates to the same normalized city, then requires reciprocal professional relevance and overlapping meeting preferences while respecting each member's exact cadence, blocks, pauses, and repeat-introduction constraints. Cross-company and cross-industry introductions receive a ranking bonus.
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

- Postgres schedules `private.run_matching_batch(25)` hourly at minute 7 and retention maintenance daily at 04:15 UTC through `pg_cron`. Matching outcomes are recorded in `private.matching_runs` for operations review.
- `auth-handoff`: completes the HTTPS callback server-side, clears its secrets from the browser URL, and relays a single-use PKCE authorization code from a work laptop to the originating iPhone. Its confirmation is intentionally plain text because Supabase Edge Functions rewrite HTML responses as `text/plain`.
- `delete-account`: verifies the caller, deletes private résumé objects, then deletes the Auth user so database rows cascade.
- `process-resume`: authenticates the member, enforces a durable per-account quota, sends bounded text extracted and contact-redacted on the iPhone to the DeepSeek Responses API, and returns a schema-constrained factual draft for review.
- `sync-subscription`: authenticates the member, verifies StoreKit 2 signed transaction data against Apple’s certificate chain, bundle ID, product ID, expiry, and account token, then records access through a service-role-only database function.
- `generate-introductions`: an optional manual operations endpoint protected by `MATCHING_JOB_SECRET`; it is not required for the scheduled production path and does not need to be deployed by default.

`auth-handoff` also applies durable, salted IP rate limits. Generate a separate random 256-bit `HANDOFF_RATE_LIMIT_SALT`; never reuse a signing, database, or Apple key.

Example hosted deployment:

```sh
supabase login
supabase link --project-ref <project-ref>
supabase db push
supabase secrets set HANDOFF_RATE_LIMIT_SALT=<random-256-bit-secret>
supabase functions deploy auth-handoff --no-verify-jwt
supabase functions deploy delete-account
supabase functions deploy process-resume
supabase functions deploy sync-subscription
```

Supabase provides its URL and server-side keys to deployed functions. The database migration installs the matching and maintenance schedules, so no public scheduler URL or matching secret is needed for normal operation.

## Notifications

Notification preferences and permission remain in native iPhone Settings, as intended. Supabase stores validated device registrations and creates deduplicated notification events. Actual remote delivery must still cross Apple Push Notification service; APNs is the unavoidable Apple transport boundary, not a second application backend. Device registration from the signed app and an APNs-delivery function can be enabled after an Apple Push Notification key, key ID, and team ID are available.

## Membership and App Store setup

The free month begins when professional onboarding changes from incomplete to complete. It is stored in `private.memberships`, so deleting the app or changing devices does not restart it. When the free month ends, new matching stops while existing messages and connections remain usable.

Create one auto-renewable monthly subscription in App Store Connect with product ID `com.mesbahtanvir.networkto.monthly` and the intended US price point (the local StoreKit fixture is $9.99). Set the numeric App Store application ID as a function secret before accepting production receipts:

```sh
supabase secrets set APPLE_APP_ID=<numeric-app-store-id>
```

The app sends StoreKit’s JWS transaction after purchase, restore, and authenticated launch. The server rejects Xcode-local transactions, cross-account transaction replay, the wrong bundle or product, revoked receipts, and unverified payloads. Before release, configure App Store Server Notifications v2 so renewals, cancellations, billing retry, grace period, and refunds update membership even when the app is not opened.

## Résumé handling

The résumé fast path uses the native iOS document picker and accepts PDFs smaller than 10 MB. PDFKit reads embedded text locally; pages without readable embedded text use Apple Vision OCR. Before any text leaves the phone, common email addresses, phone numbers, and URLs are removed. The source PDF is never uploaded by this flow.

The authenticated `process-resume` function uses `deepseek-v4-flash` by default with a strict JSON schema. It accepts at most 40,000 characters and treats résumé contents as untrusted source data rather than instructions. It can draft identity, current role and scope, an explicitly supported current focus, experience range, expertise, work history, education, and a neutral summary of demonstrated experience. It never drafts ambitions, growth goals, personality, protected traits, compensation, contact details, willingness to help, or contribution boundaries.

The iOS flow reports real stages—local reading, contact-detail protection, professional drafting, and review. The returned draft is held separately from the member profile. Every inferred field, topic, and work-history item has an individual remove control, and nothing is applied until the member explicitly confirms the selected details. After confirmation, onboarding skips factual sections that are already complete and asks the member to write the professional ambition that cannot safely be inferred.

Set `DEEPSEEK_API_KEY` as a Supabase function secret to enable live drafting. `DEEPSEEK_RESUME_MODEL` is optional and defaults to `deepseek-v4-flash`.

## Production status and remaining launch dependencies

Already implemented:

- Nine hosted migrations, RLS, private schemas, transactional profile writes, idempotent messages, account-scoped trials, same-city subscription-aware matching schedules, retention, and Edge Function abuse controls.
- Hosted `auth-handoff`, `delete-account`, `process-resume`, and `sync-subscription` functions, plus a live cross-device handoff smoke test.
- Database behavior and authorization coverage for two isolated users; run `supabase test db` before each deployment.
- The initial 40-company big-tech and established adjacent-company domain registry.

Required before a public App Store launch:

- Configure custom SMTP and verify delivery from representative corporate inboxes.
- Create the App Store Connect subscription, set `APPLE_APP_ID`, add final hosted Terms and Privacy URLs, and enable App Store Server Notifications v2.
- Add APNs credentials as function secrets and enable signed-device registration and delivery; never expose the APNs private key to iOS.
- Complete privacy and data-processing review for DeepSeek before inviting public users, and disclose that redacted résumé text is processed by the provider.
- Deploy from CI to separate staging and production projects and alert on failed matching runs, notification delivery, reports, and deletion failures.
- Review the company-domain registry operationally and add CAPTCHA or additional Auth abuse controls if observed traffic warrants it.
- Keep the service-role key restricted to trusted server-side functions and jobs.
