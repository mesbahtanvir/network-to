# network.to Constitution

## Core Principles

### I. One Introduction, Never a Feed

network.to offers ambitious professionals in North American cities one selective, same-city
introduction at a time, aimed at cross-company and cross-industry relationships. It is built
for the newcomer builder: someone who recently moved to a big city, works in technology, and
wants like-minded people with shared goals and things to do together, building genuine
relationships slowly and in person rather than seeking quick interactions, with no romantic
or sexual framing. The audience starts with technology and widens only in the order recorded
in `docs/PRODUCT_DEFINITION.md`; a step that admits members without a qualifying work email
loosens Principle IV and requires a MAJOR amendment first. Every rule below protects that shape.

- Today MUST present at most one introduction or one single most useful next action. It MUST
  NOT render a list, queue, carousel, or infinite scroll of candidates, and MUST NOT invite
  comparison between people.
- The product MUST NOT have a feed, a member directory, search or browsing of other members,
  event discovery, cold messaging, or a swipe deck. Members configure only themselves: goals,
  expertise, availability, cadence, city, and private constraints.
- Matching MUST run server-side on the schedule; the client MUST NOT generate introductions.
  Matching MUST stay within the same normalized city, require reciprocal professional
  relevance and overlapping meeting preferences, and honour each member's cadence, pause,
  blocks, the 180-day no-repeat rule, and one active introduction per member.
- There MUST be no introduction quota. Sending nothing is required over sending an
  introduction below the quality threshold, and the empty state MUST NOT be filled with
  articles, events, profiles, or engagement content.
- Every introduction MUST explain reciprocal professional value in plain language: why you
  should meet and why they may want to meet you. Interested and Pass MUST be text-labeled
  buttons with equal accessible hit areas; no swipe gesture, heart, or check/X pair may
  trigger a decision.
- Bottom navigation MUST be exactly Today, Connections, Messages, Profile, with no centre
  action and no separate notification centre. Badges MUST count only actionable unread items.

Rationale: a single considered introduction is the product. A browsing surface turns it into
a directory, and a queue turns a decision into comparison shopping.

### II. Reciprocal Interest Is the Only Gate

- A member's Interested or Pass response MUST NOT be readable by the other member through any
  table, function, Realtime event, notification, or UI state unless both chose Interested.
  RLS and the relationship-scoped read functions MUST enforce this, not client code.
- A conversation, its composer, and message badges MUST exist only after both members respond
  Interested. `respond_to_introduction` MUST record a decision exactly once and MUST create the
  conversation atomically with the second Interested response. The client MUST treat a mutual
  result as a signal to refresh from the backend, never as permission to build a conversation
  locally.
- No member MUST be able to message or contact another member without a mutual introduction.
- A Pass MUST never notify anyone. Waiting and non-mutual states MUST NOT attribute the
  outcome to either member and MUST NOT apply pressure (no countdowns, no status checks).
- A Pass MUST be unobservable by the other member: it MUST NOT change the introduction's
  status, expiry, presence, or waiting outcome as that member reads them, nor any
  notification, badge, copy, or timing they receive. An introduction MUST end for a waiting
  member only at its expiry, at mutual interest, or at a block, with one ended state shown
  once; only both members passing closes it at once. The member who passed MUST NOT see the
  introduction again and MUST be eligible for a new one at their cadence.
- The product MUST NOT compute or display a compatibility score, ranking, like, follower
  count, rating, endorsement, or popularity signal. Ranking machinery MUST stay invisible and
  relevance MUST be explained in plain professional language without AI branding.
- Profile photos MUST NOT appear before mutual interest; the decision screen uses the person's
  monogram and the verified company's mark. The product owner adopted this rule on 2026-09-11 in
  `docs/PRODUCT_DEFINITION.md` and `docs/DESIGN_PHILOSOPHY.md`; admitting photos before mutual
  interest is a MAJOR amendment.

Rationale: privacy of the decision is what makes passing cheap and interest honest. Any leak
of one-sided interest turns a professional introduction into a dating mechanic.

### III. The Outcome Is an In-Person 1:1 Meeting

- The terminal action MUST be an in-person 1:1 conversation. Messaging exists to coordinate
  it: plain text with timestamps and a persistent context strip naming the reason for the
  introduction. V1 MUST NOT add reactions, voice notes, stories, group chat, disappearing
  content, read-pressure mechanics, calendar booking, venue discovery, or group events.
- Location MUST be coarse and temporary: no continuous tracking, no precise location, no map of
  members, only broad within-city areas. Available Today MUST be an explicit opt-in with an
  area, a time window, and a displayed expiry, and MUST expire automatically.
- Post-meetup feedback MUST be private and limited to the fixed outcomes. Stars, public
  reviews, and visible reliability scores MUST NOT exist. A Connection MUST be created only
  when the outcome is not Didn't meet, the member explicitly chose to stay connected, and no
  connection with that person exists. A meetup MUST become feedback-due three hours after its
  scheduled start, with exactly one `feedback_due` event per participant.
- Matching MUST include a member only while they hold an active free month or a verified
  subscription. Expiry pauses only future matching; conversations and connections MUST remain
  accessible.

Rationale: the relationship becomes real by meeting. Anything that makes staying in the app
more rewarding than meeting works against the outcome the product exists to produce.

### IV. Members Own Their Data and the Product Protects It

- Authentication MUST be a passwordless magic link tied to a qualifying work email using the
  PKCE flow. Passwords and social login MUST NOT be added. Unapproved domains MUST be refused
  by the Before User Created hook and again by the signup trigger. Company and industry MUST be
  copied server-side from `company_domains`; the client MUST NOT overwrite them. Verification
  means only control of a company email and MUST be disclosed as such.
- The laptop-to-iPhone handoff MUST deposit only a single-use authorization code, claimed with a
  separate 256-bit secret compared by hash. The PKCE verifier MUST never leave the phone,
  handoff rows MUST live at most ten minutes in the private schema, a claim MUST delete the
  row atomically, claims MUST stop after ten failures, and the browser MUST land on a URL
  carrying no code or handoff ID.
- Gender MUST NOT be requested, stored, exposed, filtered on, or used in matching or ranking.
- Résumé handling MUST keep the PDF on the device, remove email addresses, phone numbers, and
  URLs before any text leaves the phone, show the real processing stages, and hold the draft
  apart from the profile until the member confirms it. Every inferred item MUST be removable.
  Drafting MUST NOT infer ambitions, growth goals, personality, protected traits, compensation,
  contact details, willingness to help, or contribution boundaries.
- Block, Report, and End conversation MUST be reachable from a safety menu. A block MUST be
  honoured on every pairing path. Reports MUST be private, use the fixed categories, and MUST
  never notify the reported member.
- Account deletion MUST require a destructive confirmation; the server MUST delete private
  résumé objects and then the Auth user so every row cascades, recording any failure as an
  operational incident. The client MUST clear local state only after the backend confirms.
- Push notifications MUST exist only for the kinds `introduction_ready`, `mutual_interest`,
  `new_message`, `meetup_reminder`, and `feedback_due`; adding a kind is an amendment. They
  MUST NOT be used for streaks or re-engagement. Delivery preferences MUST live in native
  iPhone Settings. Payloads MUST carry only identifiers, the counterpart's first name where a
  relationship already exists, and the copy defined for the kind; message bodies MUST never be
  pushed and a pending introduction MUST stay anonymous.
- Wherever access differs, fields MUST be labeled with who can see them (Introduction, Coarse
  only, Only you, Private).

Rationale: members hand over a résumé, a work identity, and a private decision. Each is kept
in the narrowest form the feature needs, because trust is the product.

### V. A Native, Accessible, Single-Store iOS Client

- The client MUST be a native SwiftUI iPhone app for iOS 17 or later, compiled in Swift 6 with
  `SWIFT_STRICT_CONCURRENCY = complete` on the app and test targets. Types crossing the
  `BackendService` boundary MUST be `Sendable`. `@unchecked Sendable`, `nonisolated(unsafe)`,
  and downgraded concurrency settings MUST NOT be merged.
- One `@MainActor AppStore` MUST own all rendered state. Invariant-bearing state MUST be
  `private(set)` and change only through store methods that guard their preconditions. Every
  backend call MUST go through `BackendService`; behaviour MUST branch on `isLive`, never on
  the concrete type, and mock-only conveniences MUST be guarded by `!backend.isLive`. New
  protocol requirements SHOULD ship a no-op default. `BackendFactory.make()` MUST be the only
  place the implementation is chosen, and an unexpanded configuration value MUST degrade to
  the mock rather than reach a bogus host.
- When live, refresh MUST replace domain state from one `BackendSnapshot` and derive the phase
  from it; sessions MUST be restored on launch and when the scene becomes active; realtime is
  an enhancement and foreground refresh is the recovery path. An optimistic transition MUST
  roll back on failure and offer Retry with the same values, or the change MUST apply only
  after the backend confirms. The store's `notice` MUST be the single notice channel; every
  notice MUST carry a kind (success, information, error) that its symbol, tint, and text agree
  on; success and information MUST dismiss themselves while an error MUST stay until
  dismissed, retried, or replaced; a success notice MUST follow the backend's confirmation or
  a change kept only on the phone; a failed refresh MUST be information. A StoreKit
  transaction MUST be forwarded server-side; the live client MUST never grant access locally.
- Screens MUST compose native SwiftUI controls and MUST NOT recreate native accessibility,
  focus, keyboard, or navigation behaviour. Reusable components MUST use the `NT` prefix and
  MUST take colour, spacing, radius, and type from `NTColor`, `NTSpacing`, `NTRadius`, and
  Dynamic Type styles; hard-coded values MUST NOT appear.
- Every surface MUST meet the accessibility contract in `docs/ACCESSIBILITY_REVIEW.md` and
  `docs/UI_DESIGN_SPEC.md`: Dynamic Type through accessibility sizes, WCAG AA contrast in light
  and dark, VoiceOver label, hint, and value, 44 x 44 pt targets, native focus order, Reduce
  Motion and Reduce Transparency honoured, colour never the sole indicator, layouts intact at
  320 pt. Motion MUST use system transitions only; looping, pulsing, countdown, and confetti
  animation MUST NOT be used.
- Copy MUST use the canonical vocabulary listed in `docs/UI_DESIGN_SPEC.md` section 12
  (Introduction, Interested, Pass, mutual interest, conversation, Connection, Meet, Available
  today, Verified company, company mark, member) and MUST NOT use match, compatibility, score,
  like, swipe, deck, nearby people, streak, or AI-powered, romantic language, or artificial
  urgency.
- Every surface MUST implement the state matrix in `docs/COMPONENT_STATE_SHEET.md` (resting, in
  progress, success, recoverable failure with retry, terminal or expired) and the offline
  states it names. Behaviour marked PRD locked MUST NOT be renegotiated in UI work.

Rationale: platform controls carry accessibility and focus behaviour for free, a single store
fed by a single snapshot makes every invariant testable in one place, and refusing attention
mechanics keeps the product professional.

### VI. The Backend Owns Trust

- Every exposed table MUST have Row Level Security enabled before any grant. Migrations MUST
  revoke all privileges from `anon` and `authenticated`, then grant back the least needed,
  using column grants where a member may edit part of a row. Policies MUST reference the
  caller as `(select auth.uid())`. Direct profile access MUST be self-only; another member's
  limited profile MUST be returned only by relationship-scoped read functions.
- Every high-impact transition MUST be a `security definer` function with an empty
  `search_path`, fully qualified relations, an `auth.uid()` null check that raises, and an
  explicit `revoke execute` followed by `grant execute` to the exact role. A function with no
  privilege statement is a defect. Once an RPC exists for a write, the direct table privilege
  MUST be revoked. Read-then-write RPCs MUST lock with `for update`; batch jobs MUST take an
  advisory lock and record `skipped` when it is held.
- Internal helpers, schedulers, and operational tables MUST live in the `private` schema,
  revoked from every client role. Participant and block checks MUST use the private helpers,
  and errors MUST NOT distinguish "absent" from "not a participant".
- The iOS app MUST contain only the project URL and publishable key. Service-role and APNs
  keys MUST exist only as server-side secrets, no secret or project URL MUST appear in a
  migration, scheduled jobs MUST read their configuration from Vault, and every secret MUST be
  generated independently.
- Every Edge Function MUST authenticate its own caller: a member JWT, a job secret compared in
  constant time, or Apple's signature. Functions MUST return JSON envelopes, reject wrong
  methods with 405, mutate state only through service-role RPCs, and log snake_case event
  names with identifiers only, never tokens, secrets, or member text. Rate limiters MUST store
  hashes, never raw identifiers.
- Writes a client may retry MUST be idempotent, external and scheduled transitions MUST be
  redelivery-safe, every RPC MUST validate and bound its inputs, and enumerations and
  structural invariants MUST be constraints or partial unique indexes.
- Notification events MUST be created server-side only. Delivery claims MUST count as
  attempts, back off exponentially, stop after eight, use `skip locked`, claim only members
  with a registered device, and record an outcome for every claimed event. Tokens APNs reports
  as unregistered MUST be retired.
- Scheduled jobs MUST record every run and MUST NOT raise. Missing configuration MUST NOT crash
  or spam: without Vault secrets the dispatcher stays idle and alerts stay pending; missing
  APNs secrets produce a recorded failure that the operations alert surfaces.
- Retention MUST purge every operational table on schedule (notification events 90 days,
  matching runs 180 days, edge rate limits 2 days, App Store notification records 400 days,
  posted alerts 30 days, incidents 180 days, company mark runs 180 days, files of retired
  company mark versions 30 days, expired handoffs and availabilities daily). Every new
  operational table MUST add a rule there with a pgTAP proof.
- StoreKit 2 transactions and App Store Server Notifications MUST be verified server-side
  against Apple's certificate chain, bundle ID, product ID, environment, and account token. A
  verified transaction MUST never start a free month; the free month begins only when
  onboarding completes and MUST NOT reset on reinstall or device change.

Rationale: the client is an untrusted process on someone else's phone. The promises in
Principles II through IV hold only if Postgres and the Edge Functions enforce them, and a
leaked server key defeats every other control in this document.

### VII. Deterministic Tests and CI-Only Deploys

- An iOS change is done only when the Xcode test scheme passes and the iOS workflow
  (`.github/workflows/ios.yml`: unit tests on a simulator, then a Release compile) is green on
  the pull request; a migration only when `supabase db reset` and `supabase test db` pass
  locally; an Edge Function change only when `deno check` and `deno test supabase/functions`
  pass. The PR description MUST record which of these ran.
- Previews and unit tests MUST use deterministic mock data. Launch arguments that select the
  mock MUST be honoured only in DEBUG and MUST NOT reach the hosted backend. Fixtures MUST use
  fixed identifiers, injectable latency, and named failure triggers rather than randomness.
- Every product invariant added to `AppStore` MUST ship with a named `@MainActor` XCTest built
  on isolated `UserDefaults` and `MockBackendService(latency: .zero)`.
- Every new public RPC and private table MUST get pgTAP privilege assertions for
  `authenticated`, `anon`, and `service_role`; every cron job MUST be asserted scheduled
  exactly once; `plan(N)` MUST equal the assertion count; member-facing behaviour MUST be
  tested by impersonating roles. Pure Edge Function logic MUST live in `_shared` with a
  sibling `*_test.ts`; `index.ts` keeps transport glue only.
- Hosted migrations and Edge Functions MUST be deployed only by
  `.github/workflows/supabase.yml`, only from `main`, only after validation passes, migrations
  before functions, staging before production. Manual deploys from a development machine
  MUST NOT occur.
- `README.md` and `docs/SUPABASE_BACKEND.md` MUST describe only shipped behaviour and MUST be
  updated in the same PR as the change they describe.

Rationale: the iOS workflow is the only build of the app outside a developer's machine and
Supabase changes reach production automatically from `main`, so the listed commands, the
workflow runs, and the named tests are the only evidence that a change works.

### VIII. Calm Technology

network.to is calm technology in the sense of Weiser, Brown, and Case: it requires the least
attention, informs without alarming, and gets out of the way so two people can meet. The
design philosophy in `docs/DESIGN_PHILOSOPHY.md` is binding.

- Every surface MUST require the smallest amount of attention that completes the member's
  next action, and the app MUST give no reason to be opened when nothing has changed: no
  streaks, check-ins, content to consume, or engagement prompts.
- Member-facing copy MUST use plain professional language and MUST NOT contain exclamation
  points, artificial urgency (Principle V), or countdowns (Principle II). Waiting and empty
  states MUST state what is true and what happens next and MUST offer at most one action.
  Recoverable-failure states MUST state what was saved, what was not, and the member's next
  action.
- Status MUST live in the periphery: quiet status pills, badges that count only actionable
  items, and company marks. Elements MUST NOT pulse, bounce, loop, or animate to attract
  attention (this restates the motion rule in Principle V and adds bounce and attention-seeking
  motion), and the app MUST NOT play its own sounds; the system notification sound is the only
  sound.
- The product MUST amplify people rather than imitate them: it introduces and steps back,
  explains relevance in the member's own context, shows no scores or AI branding, and never
  writes a member's goals for them.
- Every feature MUST work when it fails: offline states that say whether an action was saved,
  queued, or not submitted; visual elements with a native fallback (the company monogram when a
  company mark cannot load); server jobs that record failures instead of crashing.
- Every feature MUST use the minimum technology that solves the problem and MUST respect
  professional social norms: private interest, socially inexpensive passing, honest
  verification wording, reachable but unobtrusive safety actions.
- Every spec and plan MUST include a Calm Technology check answering the questions at the end
  of `docs/DESIGN_PHILOSOPHY.md`; a proposal that fails one MUST be redesigned or dropped.

Rationale: the product's purpose is to get two people to meet in person. Anything that holds
attention inside the app, alarms, or performs is working against that purpose.

## Product and Platform Constraints

- Client: SwiftUI, iOS 17.0 minimum, iPhone only, Xcode 26, Swift 6 with strict concurrency,
  bundle `com.mesbahtanvir.networkto`, sole dependency `supabase-swift`. Source layout is
  `NetworkTo/App`, `Models`, `Services`, `DesignSystem`, and `Features/<Feature>`; new files
  MUST be registered in the hand-maintained `project.pbxproj`. Configuration reads
  `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` from the environment first, then Info.plist.
- Membership: one account-scoped free month beginning at onboarding completion, then the
  monthly product `com.mesbahtanvir.networkto.monthly` at Apple's localized price.
- Company registry: `companies` lists well-known North American technology companies and
  employers, one row per company with one or more `company_domains`, each recorded with the
  coverage clause that admitted it; expansion is a product decision recorded in a migration.
  Each approved company SHOULD have a company mark fetched only from the company's own website
  and served by the product backend from the public `company-marks` bucket under versioned
  paths; the client MUST fall back to the company monogram, MUST show a mark only while the
  affiliation is verified and the company approved, and MUST NOT fetch marks from any
  third-party service. Marks are never refreshed automatically; the product team withholds,
  refreshes, and inspects them through the `company-marks` operations action.
- Backend: Supabase Auth (PKCE magic link, Before User Created hook), Postgres with RLS and
  `security definer` RPCs, Realtime limited to `conversations`, `messages`, `meetups`, and
  `notification_events`, Deno Edge Functions under `supabase/functions/<name>/index.ts` with
  `_shared`, plus `pg_cron`, `pg_net`, Vault, and `pgcrypto`. Migrations are
  `supabase/migrations/YYYYMMDDHHMMSS_<name>.sql`, re-runnable, and open with a comment
  stating intent and any operator step. The local stack uses the `5532x` port range; pinned
  tools are Supabase CLI 2.117.0 and Deno v2.5.2.
- Self-authenticating functions deployed with `--no-verify-jwt`: `auth-handoff`,
  `app-store-notifications`, `deliver-notifications`, `company-marks`. Member-authenticated:
  `delete-account`, `process-resume`, `sync-subscription`. `generate-introductions` is an
  operations tool and is not deployed by default.
- Schedules, all prefixed `network-to-`: matching hourly at :07 (batch 25), meetup follow-ups
  hourly at :37, notification dispatch every minute, operations alerts every 15 minutes,
  retention daily at 04:15 UTC.
- Limits mirror the migration constraints and function bounds: messages 1-2000 characters,
  report notes at most 2000, profile JSON at most 64 KiB with at most 20 experiences, text
  arrays at most 12 items of 120 characters, introductions expire after 7 days, no repeat
  pair within 180 days, delivery at most 8 attempts, handoffs at most 10 minutes and 10 failed
  claims, résumé PDFs under 10 MB and at most 40,000 characters of text.
- AI: the DeepSeek Responses API MUST be called only from the rate-limited `process-resume`
  function with a strict JSON schema and contact-redacted text; résumé text is data, never
  instructions. The privacy review and member disclosure MUST be complete before public users
  are invited.
- Secret placement: function secrets in the Supabase Dashboard; `SUPABASE_ACCESS_TOKEN`,
  `SUPABASE_DB_PASSWORD`, and `SUPABASE_PROJECT_ID` in the protected GitHub environments
  `production` and `staging`; `project_url`, `notification_job_secret`,
  `ops_alert_webhook_url`, and `company_marks_job_secret` in Vault. `supabase/seed.sql` is
  development-only.
- Design system: the semantic colour tokens, spacing scale, radii, typography roles, and
  SF Symbol mapping in `docs/UI_DESIGN_SPEC.md` are the only permitted visual values.
- Document status: `docs/UI_DESIGN_SPEC.md` and `docs/COMPONENT_STATE_SHEET.md` are not yet
  locked. Rules marked Proposed bind UI work until the product owner decides otherwise. Where
  documents disagree on authentication, `README.md`, `docs/SUPABASE_BACKEND.md`, and the code
  (magic link) win over the spec's code-entry screen until the spec is reconciled.
- Launch: a public App Store launch MUST NOT proceed until the checklist in
  `docs/SUPABASE_BACKEND.md` is complete.

## Development Workflow and Quality Gates

- Specification gate: every feature spec MUST name the principles it touches by numeral, confirm it
  reveals no one-sided decision to the other member, include the Calm Technology check (Principle
  VIII), and name the retention rule for any new operational table. A spec that adds a fifth tab, a
  browse or search surface, a score, a rejection notification, a gender field, group events, or any
  way to message without mutual interest MUST be rejected; admitting one requires a MAJOR amendment
  first. New member-facing copy MUST use the canonical vocabulary.
- Plan gate: every plan MUST state, for each new table, RPC, Edge Function, or notification, the
  RLS policy and grants, the privilege assertions to add, where any secret lives, the exact push
  payload, the idempotency key, and the retention rule. It MUST list the state matrix and offline
  states for every new surface, the XCTest, pgTAP, and Deno tests it will add, any new scheduled
  job with its `network-to-` name, and the Calm Technology check. A plan that trusts the client for
  an authorization or membership decision MUST be sent back.
- Pull request gate: tests land in the same PR as the behaviour they protect. A PR touching
  `NetworkTo/`, `NetworkToTests/`, or the project file MUST have a green iOS workflow run
  (unit tests and Release compile) on its head commit before merge, and a change the
  workflow cannot exercise (a device-only behaviour such as push registration) MUST record
  its manual check in the PR description. The reviewer MUST verify tokens and `NT` naming,
  canonical copy, the accessibility contract, `isLive` gating, and `Sendable` and
  `private(set)` discipline by reading the diff. For the backend the reviewer MUST confirm
  the validate job passed, new tables carry RLS with revoke-then-grant, new functions carry
  revoke-then-grant and an empty `search_path`, retryable RPCs are idempotent, privilege
  assertions and cron assertions exist, and no secret or URL appears in a migration or the
  iOS target.
- SHOULD deviations: a SHOULD rule may be departed from only when the PR description records
  the rule by principle numeral and the reason. An unrecorded deviation is a blocking finding.
- Deploy gate: merges to `main` touching `supabase/**` deploy automatically: validate, then
  staging (skipped with a notice until its secrets exist), then production, serialised under
  one concurrency group. Nothing else deploys anything.
- Runtime gate: operations alerts for failed or stalled matching, repeated delivery failures,
  unapplied App Store notifications, new member reports, and account-deletion failures are the
  production monitoring signal and MUST post once each to the Vault-configured webhook.

## Governance

This constitution supersedes every other practice in the repository. Where a spec, plan,
design document, or PR conflicts with it, the constitution wins, and behaviour it marks as
refused or PRD locked is not open for renegotiation in feature work. A change that needs an
exception MUST amend the constitution first, in its own PR.

Amendment procedure: an amendment is a pull request that edits this file together with the
documents it reconciles. It MUST state the rule being added, changed, or removed, the
evidence or product decision motivating it, the affected specs, plans, templates, and docs,
and a migration plan for existing code. It MUST be approved by the product owner (the
repository owner). Merging an amendment MUST bump the version and set Last Amended to the
merge date. The concrete rules and the Calm Technology check questions in
`docs/DESIGN_PHILOSOPHY.md`, and the audience and widening order in
`docs/PRODUCT_DEFINITION.md`, are part of this constitution for versioning: changing them is
an amendment (MINOR to add or tighten, MAJOR to loosen), not a documentation update.

Migration plan for 1.1.0 and 1.2.0 (existing code measured against Principles V and VIII):
the repeating pulse on the résumé processing glyph and the perpetual spinner on the private
waiting state were removed, and Today now greets the signed-in member and names the actual
counterpart, all in the 1.2.0 PR. The three follow-ups recorded then (a counterpart's Pass
observable through `respond_to_introduction` and the client's ended state; `transientMessage`
rendering errors with the success glyph and auto-dismissing; availability, preference, meetup,
feedback, and safety saves keeping optimistic state after a failure) were closed in 1.4.0, and
no SHOULD deviation from Principles V and VIII remains recorded.

1.3.0 (MINOR): `.github/workflows/ios.yml` now runs the unit tests and a Release compile for
every pull request that touches the app, so Principle VII and the pull request gate require a
green iOS workflow run instead of a manually recorded Xcode pass; device-only behaviour keeps
a recorded manual check. No feature code changes.

1.4.0 (MINOR): Principle II gains the rule that a Pass is unobservable by the other member,
and Principle V now requires notices with a kind, errors that stay with Retry, and saves that
roll back or wait for confirmation. `respond_to_introduction`, `get_current_introduction`, and
the matching job hide a member's own Pass and hold the other member's introduction to its
expiry; the client's `notice` replaces `transientMessage`; every listed save restores its
state on failure or applies only after confirmation; the ended state appears once, at the
expiry. The three follow-ups above are closed; `docs/UI_DESIGN_SPEC.md`,
`docs/COMPONENT_STATE_SHEET.md`, `docs/DESIGN_PHILOSOPHY.md`, and `docs/SUPABASE_BACKEND.md`
describe the shipped behaviour.

Versioning follows MAJOR.MINOR.PATCH:
- MAJOR: a principle is removed or redefined, a refused surface is admitted, a privacy or
  trust boundary in Principles II, IV, or VI is loosened, or a gate becomes optional.
- MINOR: a principle, section, or gate is added, an existing rule is materially expanded, or a
  limit or schedule under Product and Platform Constraints changes with its migration.
- PATCH: wording, clarification, typo, or reference fixes that change nothing about what is
  permitted or required.

Compliance review happens at the specification, plan, and pull request gates above. A
reviewer who blocks MUST cite the principle by numeral. Complexity beyond the constraints
section MUST be justified in the plan alongside the simpler alternative that was rejected.
Runtime and setup guidance lives in `README.md`, `docs/SUPABASE_BACKEND.md`,
`docs/UI_DESIGN_SPEC.md`, `docs/COMPONENT_STATE_SHEET.md`, `docs/ACCESSIBILITY_REVIEW.md`,
`docs/PRODUCT_DEFINITION.md`, and `docs/DESIGN_PHILOSOPHY.md`, which MUST be updated in the
same PR as any change that alters what they describe.

**Version**: 1.4.0 | **Ratified**: 2026-09-11 | **Last Amended**: 2026-09-12
