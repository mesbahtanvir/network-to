# Implementation Plan: Honest States

**Branch**: `003-honest-states` | **Date**: 2026-09-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/003-honest-states/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Make a Pass unobservable by the other member, give the single notice channel a kind with
persistent errors and Retry, and make every optimistic save roll back and say what happened.
Backend: one migration redefines `respond_to_introduction`, `get_current_introduction`, and
`private.generate_one_introduction` around one new helper, `private.introduction_passed_by`,
so a Pass records a response but leaves the introduction open for the other member until its
existing expiry; both members passing closes it; a member's own Pass hides it from them and
frees them for matching at their cadence. Client: `AppNotice` (success, information, error)
replaces the untyped `transientMessage`; `NTInlineNotice` renders it with the right symbol,
Dismiss, and Retry; every save captures the previous state, rolls back on failure, and
registers a retry; private feedback becomes pessimistic; the store remembers the introduction
it was waiting on so the ended state appears once at expiry. No new table, notification kind,
secret, or scheduled job.

## Technical Context

**Language/Version**: PL/pgSQL on Postgres 17 (Supabase); Swift 6 (SwiftUI, iOS 17+, strict
concurrency complete)

**Primary Dependencies**: none new (pgTAP, XCTest, `supabase-swift` already present)

**Storage**: existing `public.introductions` and `public.introduction_responses` (semantics of
`status` clarified, no schema change); on the phone one `UserDefaults` key per member for the
waited introduction id

**Testing**: pgTAP (`supabase/tests/database/introduction_privacy.test.sql`, new), XCTest
(`NetworkToTests/HonestStatesTests.swift`, new; existing `AppStoreTests` adjusted for the
pessimistic feedback API), local harness `scratchpad/harness/run_db_tests.sh`, the iOS
workflow on the PR

**Target Platform**: iPhone iOS 17.0+; Supabase hosted project

**Project Type**: Mobile app + Supabase backend (existing layout)

**Performance Goals**: no new queries on hot paths beyond one `exists` per candidate row in
matching (indexed by the responses primary key) and one per read of the current introduction

**Constraints**: nothing a member can read may differ between "passed" and "unanswered" before
expiry (FR-008); expiry unchanged (FR-003); one notice at a time (FR-014); errors persist,
others auto-dismiss (FR-011); rollback on failure for every listed save (FR-017); no success
before confirmation (FR-016); no new operational data

**Scale/Scope**: 1 migration (4 functions), 1 pgTAP file, ~1 new Swift file, 1 new test file,
~9 edited Swift files, 6 documents, constitution amendment

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Principles touched: I, II, IV, V, VI, VII, VIII.

- **I (one introduction, never a feed)**: Today still shows one thing; the ended state is one
  card with one action and is skipped when a new introduction exists. PASS.
- **II (reciprocal interest is the only gate)**: the read model hides a member's own Pass and
  nothing else; the response RPC returns `waiting` whether the other member is silent or
  passed; status changes only on mutual interest, on both passing, on expiry, or on the
  existing safety paths. A one-sided decision is no longer revealed by presence, error, or
  timing. This tightens the principle, recorded as an amendment (v1.4.0). PASS.
- **IV (members own their data)**: no new data about members. The phone keeps one introduction
  id per member for the ended courtesy, cleared by Continue, a new introduction, mutual
  interest, or account deletion. No notification is added. PASS.
- **V (native, accessible, single store)**: `AppStore` still owns the notice (`notice`,
  `private(set)`), the pending retry, and the waited id; every failure is raised through store
  methods; optimistic transitions now roll back as the principle already requires;
  `NTInlineNotice` uses tokens and Dynamic Type; the state matrix below adds the honest rows.
  The feedback sheet keeps an inline error by design (FR-024). PASS.
- **VI (backend owns trust)**: the redefined RPCs keep `security definer`, empty
  `search_path`, revoke-then-grant to `authenticated`; the helper is private and revoked from
  every role; the response RPC remains idempotent per member (primary key on responses). PASS.
- **VII (deterministic tests, CI-only deploys)**: pgTAP for every backend rule with privilege
  assertions for the new helper; XCTest for every rollback, retry, notice kind, and the ended
  state, driven by a named failure trigger on the mock; iOS workflow must be green. PASS.
- **VIII (calm technology)**: see the Calm Technology check below. PASS.

Gate details required by the plan gate:

| Item | RLS / grants | Privilege assertions | Secret | Push payload | Idempotency | Retention |
|------|--------------|----------------------|--------|--------------|-------------|-----------|
| `private.introduction_passed_by(uuid, uuid)` (new) | private schema; `security definer`, empty `search_path`; revoked from `public`, `anon`, `authenticated`, `service_role` | added: no role may execute | none | n/a | read-only | n/a |
| `public.respond_to_introduction(uuid, text)` (redefined) | unchanged: execute revoked from `public`, `anon`; granted to `authenticated` | existing assertion kept; behaviour asserted for pass-then-interested, interested-then-pass, both-pass, mutual, stale | none | unchanged: `mutual_interest` events only on mutual interest | primary key on `(introduction_id, user_id)`; second call raises "Response already recorded" | unchanged |
| `public.get_current_introduction()` (redefined) | unchanged | asserted: null for the passer, present for the other member | none | n/a | read | unchanged |
| `private.generate_one_introduction()` (redefined) | unchanged (revoked from every role) | asserted: passer matchable, waiting member not | none | unchanged: `introduction_ready` on creation | existing pair index | unchanged |
| `AppNotice` / pending retry (phone memory) | n/a | n/a | none | n/a | one notice at a time | never stored; cleared on sign-out |
| `networkto.introduction.waited.<memberID>` (`UserDefaults`) | device-local | n/a | none | n/a | overwrite | cleared by Continue, a new introduction, mutual interest, deletion |

No new table, scheduled job, notification kind, or secret.

### State matrix and offline states

| Surface | Resting | In progress | Success | Recoverable failure | Terminal | Offline |
|---------|---------|-------------|---------|---------------------|----------|---------|
| Introduction (other member passed) | Open, unchanged | Submitting Interested | Private waiting, identical to the unanswered case | Response fails: buttons back, error notice with the backend message | Ended at expiry: "This introduction didn't work out", Continue | Same as failure |
| Ended introduction card | Shown once after expiry while the member was waiting | n/a | Continue returns to searching | n/a | Skipped when a new introduction exists | Shown from memory; refresh failure shows an information notice |
| Notice banner | One notice, kind-specific symbol | n/a | Success/information dismiss themselves in ~2 s | Error stays with Dismiss and Retry | Replaced by a newer notice | Errors from offline saves persist until dismissed |
| Available today | Off or active | Saving | Banner reflects saved state | Rolled back, "Availability wasn’t saved.", Retry | n/a | Rolled back, Retry |
| Preferences (introduction, meeting) | Saved values | Saving | "… saved" after confirmation | Previous values back, "… weren’t saved.", Retry | n/a | Same |
| Safety (block, unblock, end conversation, remove Connection) | Current lists | Saving | Existing success wording after confirmation | State restored, error notice, Retry | n/a | Same |
| Coffee plan | No plan | Saving | Meeting details shown after confirmation | "Coffee plan wasn’t sent.", Retry | n/a | Same |
| Private feedback sheet | Choices | Submitting (button disabled) | Sheet closes; Connection or searching as before | Inline "Feedback wasn’t submitted." with Retry; nothing recorded | n/a | Same |
| Profile edit | Edited text | Saving | Saved silently (as today) | Text kept, "Profile changes weren’t saved.", Retry | n/a | Same |
| Refresh | Loaded state | Refreshing | Replaced from snapshot | Information "Couldn’t refresh right now." | n/a | Same |

### Tests this plan adds

- pgTAP `supabase/tests/database/introduction_privacy.test.sql`: helper privileges; pass keeps
  the other member's read model unchanged (status, expiry, presence); interested after a pass
  returns `waiting` and leaves status `offered`; no `mutual_interest` events; the passer's
  read model is null; matching pairs the passer with a third member while the waiting member
  is excluded; both passing closes; expiry through `run_retention_maintenance` ends it for the
  waiting member; responding to an expired introduction raises; the mutual path is unchanged.
- XCTest `NetworkToTests/HonestStatesTests.swift`: notice kinds and persistence rules, replace
  and dismiss, sign-out clears; rollback and retry for availability (set and clear),
  introduction preferences, meeting preferences, unblock, block from a Connection and from a
  conversation, remove Connection, end conversation, coffee plan, profile edit; pessimistic
  feedback (failure leaves state and returns false; success applies); success notices only
  after confirmation; ended introduction shown once after waiting, cleared by Continue,
  skipped when a new introduction exists, remembered across launches.
- `AppStoreTests`: feedback tests await the new API; response and block tests unchanged.
- `MockBackendService`: explicit save implementations with `setSavesFail(_:)` and an
  `introductionAvailable` flag for the ended-introduction snapshot.

### Calm Technology check (Principle VIII)

- *Reduce or add attention?* Reduces: the rejection moment disappears; errors stop looking like
  confirmations; nothing new asks for attention.
- *Inform or alarm?* Informs: a failed save says what was not saved and offers one Retry; no
  modal, no red flash; refresh failures are informational.
- *Can it live in the periphery?* Yes: the same banner, one card on Today.
- *Help two people meet, or keep them in the app?* Neutral; it protects trust in the answer
  flow that leads to meeting.
- *Fail quietly?* Yes: rollbacks are silent, only a member's own failed action persists, and
  the ended state asks for one tap.
- *Is there a simpler way?* The expiry already exists; hiding a Pass is a filter in the read
  model plus two conditions; notices reuse the channel.
- *Would a thoughtful professional find it normal?* Yes.

## Project Structure

### Documentation (this feature)

```text
specs/003-honest-states/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── database.md      # RPC and read-model behaviour after the change
│   └── client.md        # notice, retry, save, and ended-introduction contracts
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
supabase/
├── migrations/20260912130000_private_pass.sql          # new
└── tests/database/introduction_privacy.test.sql        # new

NetworkTo/
├── Models/Models.swift                                  # edit: AppNotice
├── App/AppStore.swift                                   # edit: notice, retry, rollbacks, waited introduction, pessimistic feedback
├── DesignSystem/Components.swift                        # edit: NTInlineNotice
├── Features/Main/MainTabView.swift                      # edit: notice overlay by kind
├── Features/Messages/MessagesView.swift                 # edit: feedback sheet inline error and retry
├── Features/Messages/SafetyAndMeetupViews.swift         # unchanged call sites (planMeetup is pessimistic in the store)
├── Features/Introduction/IntroductionFlowView.swift     # edit: pass feedback success notice
├── Features/Profile/ProfileView.swift                   # edit: information notice
├── Features/Profile/PreferenceViews.swift               # edit: information notice
├── Features/Subscription/MembershipView.swift           # edit: success notice
└── Services/MockBackendService.swift                    # edit: save implementations, failure trigger, snapshot flag

NetworkToTests/
├── HonestStatesTests.swift                              # new
├── AppStoreTests.swift                                  # edit: async feedback
├── NotificationStoreTests.swift, NotificationRegistrationTests.swift  # edit: notice assertions

NetworkTo.xcodeproj/project.pbxproj                      # edit: register the test file
docs/, README.md, .specify/memory/constitution.md        # edit
```

**Structure Decision**: the existing layout; the backend change is one migration that
redefines three functions and adds one helper; the client change stays inside the store and
the design system with small view edits.

## Complexity Tracking

No constitution violations. The feedback sheet's inline error is local view state by design
(FR-024) because the sheet must stay open with the member's choices; the store still owns
the outcome.

## Operator steps outside the repository

None. The migration deploys through the existing workflow.
