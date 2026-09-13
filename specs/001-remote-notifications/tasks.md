# Tasks: iPhone Remote Notifications

**Input**: Design documents from `/specs/001-remote-notifications/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Requested by the constitution (Principle VII) and the plan: XCTest tasks are included
and land in the same change as the behaviour they protect. The pgTAP and Deno suites are
unchanged because the backend is not touched.

**Organization**: Tasks are grouped by user story. Story 1 (ask, register, stop) is the MVP;
Story 2 (tap routing) and Story 3 (calm arrival) share the delegate and store plumbing built
in the foundational phase; Story 4 (Settings) is the Profile row.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4)
- Include exact file paths in descriptions

## Path Conventions

Mobile app: `NetworkTo/` (SwiftUI app), `NetworkToTests/`, `NetworkTo.xcodeproj/`, `docs/`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: the entitlement and project wiring every story needs

- [X] T001 Create `NetworkTo/NetworkTo.entitlements` with `aps-environment` = `development`
- [X] T002 In `NetworkTo.xcodeproj/project.pbxproj` add the entitlements `PBXFileReference` (no build file) as a child of the `NetworkTo` group and set `CODE_SIGN_ENTITLEMENTS = NetworkTo/NetworkTo.entitlements;` in the app target's Debug and Release configurations only (`J10000000000000000000003`, `J10000000000000000000004`)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: the value types, the OS boundary, the backend requirements, and the store state every story renders through

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T003 [P] Create `NetworkTo/Services/NotificationRouting.swift` (Foundation only) with `NotificationAuthorizationStatus`, `PushEnvironment` (`parse`, `resolve`, `current`), `DeviceRegistration`, `NotificationRoute`, `NotificationItem`, and `NotificationInvitePolicy` per data-model.md
- [X] T004 [P] Create `NetworkTo/Services/NotificationCenterClient.swift` with the `NotificationCenterClient` protocol and `SystemNotificationCenterClient` (`[.alert, .sound]` only; re-reads settings after the request; touches `UNUserNotificationCenter` only inside methods; removes delivered notifications by identifier match)
- [X] T005 [P] Add `registerDeviceToken(_:environment:)` and `unregisterDeviceToken(_:)` with no-op defaults to `NetworkTo/Services/BackendService.swift`
- [X] T006 [P] Implement both RPC calls in `NetworkTo/Services/SupabaseBackendService.swift` with `DeviceTokenParameters` (`p_token`, `p_environment`) and `DeviceTokenRemovalParameters` (`p_token`)
- [X] T007 [P] Implement recording versions in `NetworkTo/Services/MockBackendService.swift` (`registeredDevices`, `unregisteredDeviceTokens`, ordered `events`, `signOut` logged, failure for tokens starting with `dead`)
- [X] T008 Add the stored notification state to `NetworkTo/App/AppStore.swift` (`notificationAuthorization`, `hasDeclinedNotificationInvite`, `messagesPath`, `pendingNotificationRoute`, `pendingDeviceRegistration`, `registeredDeviceRegistration`, `signOutTask`, `hasAttemptedSessionRestore`, `refreshTask`, injected `notificationCenter`), `MessagesDestination`, the per-member memory keys, and the coalesced `refreshFromBackend(silently:)` (depends on T003, T004)
- [X] T009 Add the `// MARK: - Notifications` section to `NetworkTo/App/AppStore.swift` with the API in contracts/client.md: invitation policy and decline, authorization refresh and request, `registerForRemoteNotificationsIfAllowed`, `receiveDeviceRegistration` and `syncDeviceRegistration`, route handling and application, `isViewingDestination`, `shouldPresentArrivingNotification`, `didViewNotificationItem`, memory load and clear (depends on T008)
- [X] T010 Create `NetworkTo/App/AppDelegate.swift`: `UNUserNotificationCenter` delegate assignment in `didFinishLaunching`, token and failure callbacks, `attach(_:)` with one-slot buffers, `nonisolated` async `didReceive` and `willPresent` witnesses (depends on T009)
- [X] T011 Wire `NetworkTo/App/NetworkToApp.swift`: `@UIApplicationDelegateAdaptor`, `attach(store)` first in `.task`, `registerForRemoteNotificationsIfAllowed()` after restore and on every `.active` scene phase (depends on T010)
- [X] T012 Register `AppDelegate.swift`, `NotificationRouting.swift`, `NotificationCenterClient.swift`, the entitlements file, and the four test files in `NetworkTo.xcodeproj/project.pbxproj` (PBXBuildFile, PBXFileReference, group children, correct Sources phases)
- [X] T013 [P] Create `NetworkToTests/NotificationTestDoubles.swift` with `MockNotificationCenterClient` (`@MainActor` class recording requests, registrations, and removed items)
- [X] T014 [P] Create `NetworkToTests/NotificationRoutingTests.swift`: hex token formatting and validation, `PushEnvironment.parse`/`resolve`, `NotificationRoute(userInfo:)` for all five kinds plus unknown and malformed ids, `NotificationItem.matches`, the `NotificationInvitePolicy` table

**Checkpoint**: the store owns notification state; the delegate delivers tokens and routes; nothing prompts, registers, or routes yet from the UI

---

## Phase 3: User Story 1 - Ask at the Right Moment, Register the Phone, and Stop on Sign-Out (Priority: P1) 🎯 MVP

**Goal**: one calm invitation on Today after onboarding; silent registration on every activation while allowed; removal before sign-out; memory cleared after deletion

**Independent Test**: fresh install → sign up → onboarding → card appears only on Today searching/waiting; Turn on → dialog → `device_tokens` row; Not now → never again, Profile row presents the dialog; sign out → row removed within 5 s (quickstart steps 1–5, 7, 8)

### Tests for User Story 1

- [X] T015 [P] [US1] Create `NetworkToTests/NotificationStoreTests.swift`: status refresh and request through the mock client (prompt only when never asked, never twice, denied never prompts), invitation visibility for every phase and gate, "Not now" persisted across store instances and cleared after deletion, registration requested from iOS only when allowed and ready
- [X] T016 [P] [US1] Create `NetworkToTests/NotificationRegistrationTests.swift` (registration part): token buffered before readiness and registered once with the expected hex and environment; repeated delivery re-registers; changed token registers the new one and removes the old; failure keeps the token pending and sets no `transientMessage`; `signOut()` removes the token before `signOut` in the mock event log and forgets it; sign-out on the mock backend with no token logs only `signOut`

### Implementation for User Story 1

- [X] T017 [US1] Add `NTNotificationInviteCard(turnOn:notNow:)` to `NetworkTo/DesignSystem/Components.swift` with the FR-003 copy, `NTPrimaryButtonStyle`/`NTSecondaryButtonStyle`, `ntSurface()`, VoiceOver label and hints, no motion
- [X] T018 [US1] Render the card first in Today's content stack when `store.shouldOfferNotificationInvite` in `NetworkTo/Features/Today/TodayView.swift`
- [X] T019 [US1] In `NetworkTo/App/AppStore.swift` make `signOut()` capture the remembered registration, forget it and the pending token, clear the pending route and `messagesPath`, and run the bounded removal before `backend.signOut()` in `signOutTask`; call `registerForRemoteNotificationsIfAllowed()` after `completeLiveAuthentication` and successful `completeOnboarding`; sync a pending registration at the end of `restoreBackendSession`
- [X] T020 [US1] In `NetworkTo/App/AppStore.swift` clear the declined choice and the remembered registration only after `backend.deleteAccount()` returns in `deleteAccount()`, and reload the per-member memory whenever `member` is replaced by a refresh

**Checkpoint**: User Story 1 works end to end on a device once the App ID carries the push capability

---

## Phase 4: User Story 2 - Tapping a Notification Opens the Right Screen (Priority: P2)

**Goal**: a tap opens Today or the referenced conversation in every app state; nothing is recorded by the tap

**Independent Test**: `xcrun simctl push` each kind with the app open, backgrounded, and force-quit (quickstart "Simulator routing check"); staging device check for real events (quickstart step 6)

### Tests for User Story 2

- [X] T021 [P] [US2] Extend `NetworkToTests/NotificationRegistrationTests.swift` (routing part): `.conversation` route after mutual interest selects Messages and pushes the conversation without clearing `isUnread`; mismatched id lands on Messages with an empty path; nil id opens the only conversation; `.introduction` selects Today; a route while signed out or before onboarding is discarded; sign-out clears a pending route and the path

### Implementation for User Story 2

- [X] T022 [US2] In `NetworkTo/Features/Messages/MessagesView.swift` bind `NavigationStack(path: $store.messagesPath)`, replace the view-destination link with `NavigationLink(value: MessagesDestination.conversation(id))`, and add `.navigationDestination(for: MessagesDestination.self) { _ in ConversationView() }`
- [X] T023 [US2] Apply pending routes at the end of `restoreBackendSession()` (both outcomes) in `NetworkTo/App/AppStore.swift` so a cold-launch tap waits for the restore and refresh, and is discarded when the session is invalid

**Checkpoint**: every kind routes correctly from `simctl push` with the mock backend

---

## Phase 5: User Story 3 - Calm Behaviour When a Notification Arrives While the App Is Open (Priority: P3)

**Goal**: no banner on the destination screen, the standard banner once elsewhere, silent refresh, delivered notifications cleared once the item is on screen

**Independent Test**: push a `new_message` with the conversation open (no banner, content refreshes) and from Connections (one banner); open the conversation and confirm the phone's list no longer holds it (quickstart "Simulator routing check")

### Tests for User Story 3

- [X] T024 [P] [US3] Extend `NetworkToTests/NotificationRegistrationTests.swift` (presentation part): `isViewingDestination` true only for Today with an introduction route and for the pushed matching conversation; `shouldPresentArrivingNotification` false on the destination and true elsewhere, including Today when a mutual-interest route arrives; `didViewNotificationItem` forwards the item to the client

### Implementation for User Story 3

- [X] T025 [US3] In `NetworkTo/Features/Messages/MessagesView.swift` call `store.didViewNotificationItem(.conversation(id))` from `ConversationView.onAppear` next to `openConversation()`
- [X] T026 [P] [US3] In `NetworkTo/Features/Today/TodayView.swift` clear introduction notifications whenever Today is selected in the `.ready` phase (`onChange(of:initial:)`), and in `NetworkTo/Features/Introduction/IntroductionFlowView.swift` on appear

**Checkpoint**: arrival behaviour matches the presentation table in contracts/notification-payload.md

---

## Phase 6: User Story 4 - Preferences Stay in iPhone Settings (Priority: P4)

**Goal**: the Profile row reflects the phone's status, presents the dialog when never asked, opens iPhone Settings otherwise, and falls back to one quiet notice

**Independent Test**: tap the row in each status; turn notifications off and on in Settings and confirm the registration is untouched (quickstart step 4)

### Implementation for User Story 4

- [X] T027 [US4] In `NetworkTo/Features/Profile/ProfileView.swift` make the Notifications row status-aware (subtitle per status, dialog when `canPrompt`, Settings URL otherwise, `AppStore.notificationSettingsFallbackNotice` through `transientMessage` when the URL cannot be opened, hint per action)

---

## Phase 7: Polish & Cross-Cutting Concerns

- [X] T028 [P] Update `docs/SUPABASE_BACKEND.md`: Notifications section describes the client registration, environment detection, sign-out removal, and the App ID capability step; launch list item rewritten
- [X] T029 [P] Update `README.md` (implemented list: remote notifications for the five kinds, asked once on Today, preferences in iPhone Settings)
- [X] T030 [P] Update `docs/UI_DESIGN_SPEC.md` (deep-link statement in §4, T-01/T-05 required states, P-07 states, §8 Today note, §11 "Notification invitation" component) and `docs/COMPONENT_STATE_SHEET.md` (`NTNotificationInviteCard` in §10, matrix row in §11)
- [X] T031 [P] Update `docs/ACCESSIBILITY_REVIEW.md` §5 with the invitation card gates (reading order, hints, 320 pt, largest sizes)
- [X] T032 Self-review the diff against the constitution PR gate (tokens and `NT` naming, canonical copy, accessibility contract, `isLive` gating, `Sendable` and `private(set)` discipline, no secret in the iOS target) and record the Xcode test requirement in the PR description
- [X] T033 Mark every task complete in this file and update the PR body

---

## Dependencies & Execution Order

- Phase 1 has no dependencies. Phase 2 depends on Phase 1 only for T002 (signing) and blocks every story.
- Within Phase 2: T003–T007 in parallel; T008 after T003 and T004; T009 after T008; T010 after T009; T011 after T010; T012 after every new file exists; T013 and T014 after T003.
- US1 (Phase 3) after Phase 2; US2 and US3 share `MessagesView` edits (T022 before T025); US4 is independent of US2 and US3.
- Polish after all stories.

## Implementation Strategy

1. Phases 1 and 2, then run the unit tests on a Mac (`xcodebuild test`).
2. US1 and verify on a device (quickstart steps 1–5, 7, 8).
3. US2 and US3 with `simctl push`, then on a staging device.
4. US4 and the documentation.
5. Record the Xcode test pass in the PR before merge (constitution PR gate).
