# Tasks: Honest States

**Input**: Design documents from `/specs/003-honest-states/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Requested by the constitution (Principle VII) and the plan: pgTAP and XCTest tasks
are included and land in the same change as the behaviour they protect.

**Organization**: Story 1 is the backend change plus the phone's ended state; Story 2 is the
notice channel every save then uses; Story 3 converts each save.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

Mobile + backend: `NetworkTo/`, `NetworkToTests/`, `supabase/migrations/`,
`supabase/tests/database/`, `docs/`.

---

## Phase 1: Setup

- [X] T001 Create `supabase/migrations/20260912130000_private_pass.sql` with the opening comment (intent, no operator step) and `private.introduction_passed_by(uuid, uuid)` with revoke-all

---

## Phase 2: Foundational

**Purpose**: the notice channel and the mock failure trigger every story renders through

- [X] T002 [P] Add `AppNotice` to `NetworkTo/Models/Models.swift`
- [X] T003 [P] Add explicit save implementations, `setSavesFail(_:)`, and the `introductionAvailable` init flag to `NetworkTo/Services/MockBackendService.swift`
- [X] T004 Replace `transientMessage` in `NetworkTo/App/AppStore.swift` with `notice`, `pendingRetry`, `presentSuccess`, `presentInformation`, `presentError`, `dismissNotice`, `dismissNotice(id:)`, `retryFailedAction`; convert every existing write to the right kind; refresh failures become information; clear on sign-out and deletion (depends on T002)
- [X] T005 Add `NTInlineNotice` to `NetworkTo/DesignSystem/Components.swift` (depends on T002)
- [X] T006 Render the notice by kind in `NetworkTo/Features/Main/MainTabView.swift` (auto-dismiss only for non-persisting notices, Reduce Motion) (depends on T005)
- [X] T007 [P] Replace direct notice writes in `NetworkTo/Features/Subscription/MembershipView.swift`, `NetworkTo/Features/Profile/ProfileView.swift`, `NetworkTo/Features/Profile/PreferenceViews.swift`, `NetworkTo/Features/Introduction/IntroductionFlowView.swift` (depends on T004)
- [X] T008 [P] Update `transientMessage` assertions in `NetworkToTests/NotificationStoreTests.swift` and `NetworkToTests/NotificationRegistrationTests.swift` to `notice` (depends on T004)

---

## Phase 3: User Story 1 - A Pass Is Never Observable (Priority: P1) 🎯 MVP

**Goal**: a Pass changes nothing the other member can read; the introduction ends at expiry for both cases alike

**Independent Test**: pgTAP file plus the ended-state store tests

- [X] T009 [US1] In `supabase/migrations/20260912130000_private_pass.sql` redefine `public.respond_to_introduction` per contracts/database.md (pass keeps `offered` unless both passed; interested after a pass returns `waiting`; mutual unchanged) with revoke-then-grant restated
- [X] T010 [US1] In the same migration redefine `public.get_current_introduction` (adds the passed-by filter, keeps `company_mark`) and `private.generate_one_introduction` (active-introduction predicate ignores a member's own passed introductions)
- [X] T011 [US1] Create `supabase/tests/database/introduction_privacy.test.sql` per contracts/database.md with the correct `plan(N)`
- [X] T012 [US1] Add `waitedIntroductionID` memory to `NetworkTo/App/AppStore.swift`: remembered on a waiting response and on refresh, ended state when the introduction is gone, cleared by Continue, a new introduction, mutual interest, or deletion
- [X] T013 [US1] Tests in `NetworkToTests/HonestStatesTests.swift` for the ended state (shown once, Continue, new introduction skips it, remembered across launches)

**Checkpoint**: backend rule proven; the phone shows the ended state only at expiry

---

## Phase 4: User Story 2 - Notices Mean What They Show (Priority: P2)

- [X] T014 [US2] Tests in `NetworkToTests/HonestStatesTests.swift` for notice kinds, persistence, replacement, dismiss, retry, sign-out clearing, and the information notice on refresh failure

**Checkpoint**: every notice carries a kind; errors persist with Retry

---

## Phase 5: User Story 3 - Every Save Says What Happened (Priority: P3)

- [X] T015 [US3] In `NetworkTo/App/AppStore.swift` add the optimistic-save helper and convert `setAvailability`, `clearAvailability`, `saveNetworkingPreferences`, `saveMeetingPreferences`, `unblock`, `block`/`blockCurrentPerson`, `removeConnection`, `endCurrentConversation` (rollback + retry; success only after confirmation)
- [X] T016 [US3] In `NetworkTo/App/AppStore.swift` make `planMeetup` pessimistic, keep profile edits with a retrying save, and make `recordFeedback(_:stayConnected:)` async returning `Bool` with a synchronous `applyFeedback` used by the demonstration preview
- [X] T017 [US3] In `NetworkTo/Features/Messages/MessagesView.swift` make the feedback sheet submit asynchronously, show the inline error with Retry, and close only on success
- [X] T018 [US3] Update `NetworkToTests/AppStoreTests.swift` feedback tests for the async API
- [X] T019 [US3] Tests in `NetworkToTests/HonestStatesTests.swift` for rollback and retry of every save, pessimistic plan and feedback, and success-after-confirmation

**Checkpoint**: every listed save restores state on failure and offers Retry

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T020 Register `NetworkToTests/HonestStatesTests.swift` in `NetworkTo.xcodeproj/project.pbxproj`
- [X] T021 [P] Update `docs/UI_DESIGN_SPEC.md` (flow 6.2 ended-state timing, T-05 states, notice rules), `docs/COMPONENT_STATE_SHEET.md` (`NTInlineNotice` as implemented, `NTOfflineState` coverage, matrix rows), `docs/DESIGN_PHILOSOPHY.md` (sections 6 and 8 now describe shipped behaviour)
- [X] T022 [P] Update `docs/SUPABASE_BACKEND.md` (introduction lifecycle: a Pass never closes the introduction for the other member; matching eligibility) and `README.md`
- [X] T023 Amend `.specify/memory/constitution.md` to v1.4.0: Principle II gains the "a Pass is unobservable" rule; the migration plan records the three follow-ups as resolved
- [X] T024 Run `scratchpad/harness/run_db_tests.sh`, `deno check`, and `deno test supabase/functions`; commit; push; update the PR description; confirm the iOS workflow is green

---

## Dependencies & Execution Order

- T001 → T009/T010 → T011. T002 → T004 → T005 → T006; T007 and T008 after T004.
- US1 phone work (T012, T013) after T004; US3 (T015–T019) after T004 and T003.
- Polish after all stories.

## Implementation Strategy

1. Migration and pgTAP first (the promise), validated locally.
2. Notice channel, then saves, with the store tests growing alongside.
3. Docs and the constitution amendment, then validation and the PR update.
