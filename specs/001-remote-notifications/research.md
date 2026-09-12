# Research: iPhone Remote Notifications

**Feature**: 001-remote-notifications | **Date**: 2026-09-12

Each unknown below records the decision taken, why, and what was rejected. The research read
the current SDK headers (`UNUserNotificationCenterDelegate` is not main-actor annotated in the
iOS 17.5 and 18.0 SDKs; `UNNotification` and `UNNotificationResponse` are not `Sendable`), the
backend payload builder (`supabase/functions/_shared/apns.ts`), the device-token RPCs
(`supabase/migrations/20260905000600_production_hardening.sql`), and the existing app
structure (`AppStore`, `NetworkToApp`, `MessagesView`, `TodayView`, `ProfileView`,
`project.pbxproj`).

## 1. When and how to ask for permission

**Decision**: Ask only from the invitation card the spec defines, rendered at the top of Today
while `NotificationInvitePolicy.shouldOffer` is true: signed in, onboarding complete,
`membership.hasAccess`, phase `.searching` or `.waiting`, the phone's status `.notDetermined`,
and no "Not now" recorded for this member on this phone. "Turn on notifications" calls
`requestNotificationAuthorization()` which is the only path to
`UNUserNotificationCenter.requestAuthorization(options: [.alert, .sound])`; "Not now" records
the choice per member in `UserDefaults`. The Profile row also presents the dialog while the
status is `.notDetermined`, and opens iPhone Settings otherwise. Status is re-read on every
activation because iOS gives no callback when Settings change.

**Rationale**: Apple's guidance and the spec agree: ask once, in context, after the value is
clear, never at launch or during onboarding, and never imitate the system alert. Today's
searching and private-waiting states are the first honest promises of an asynchronous
outcome. Requesting only alerts and sound matches the payload (`aps.alert`, `sound: default`)
and FR-005; the icon badge is never shown, so its permission is not requested.

**Rejected**: prompting from `NetworkToApp`'s launch task (spends the one prompt without
context and fires for members who have not finished onboarding); an eighth onboarding step (the
spec forbids asking during onboarding); prompting inside `respondInterested()` (interrupts the
gesture, no explanation); provisional authorization (silent delivery to Notification Center
only, plus Apple's inline Keep/Turn off controls that recreate delivery preferences in-app);
`.providesAppNotificationSettings` (there is no in-app settings screen to open); a modal
pre-permission sheet (blocks Today and risks looking like the system alert); a separate
`NotificationStore` `@StateObject` (Principle V names one `AppStore` as the owner of rendered
state; the OS boundary is injected into `AppStore` instead).

## 2. Token registration

**Decision**: `AppDelegate` receives the raw token, formats it as lowercase zero-padded hex
(`String(format: "%02x", $0)`), pairs it with `PushEnvironment.current()`, and hands a
`DeviceRegistration` to `AppStore.receiveDeviceRegistration(_:)`. The store buffers it as
`pendingDeviceRegistration` and runs `syncDeviceRegistration()` whenever readiness holds
(`backend.isLive && hasAuthenticated && hasCompletedOnboarding`): it calls
`register_device_token` on every delivery (so each activation refreshes `updated_at`, FR-007),
remembers the registration per member, and removes the previously remembered token when it
differs (FR-009). Failures keep the token pending and show nothing (FR-008). The app asks iOS
for the token with `registerForRemoteNotifications()` after the permission decision, after
session restore, after onboarding completion, and on every scene activation while permission
is allowed; iOS re-delivers the cached token each time.

**Rationale**: `register_device_token` throws "Authentication required" before the session is
restored and the token frequently arrives first, so buffering is load-bearing. The RPC's
upsert reassigns the token to whoever registers it, which is what a shared phone needs (FR-014).
One RPC per activation is cheap and is what the spec's last-confirmed-time scenario requires.

**Rejected**: registering only when the token changes (the spec requires the refresh on every
activation); registering regardless of authorization (a token for a denied member makes the
backend mark events delivered while iOS discards them); a `#if DEBUG` environment heuristic
(see 3).

## 3. APNs environment

**Decision**: `PushEnvironment.current()` reads `embedded.mobileprovision` from the bundle,
slices the XML plist between `<?xml` and `</plist>`, and maps `Entitlements["aps-environment"]`
`development` to `.sandbox` and `production` to `.production`. No embedded profile means an App
Store install: `.production`. On the simulator it returns `nil` and nothing is registered. The
parser is a pure function with unit tests.

**Rationale**: the entitlement in the profile is exactly what APNs checks, so it cannot
disagree with the token's environment; `#if DEBUG` mislabels TestFlight builds and archived
Debug builds, and a wrong label makes APNs answer `BadDeviceToken`, after which the backend
retires the token silently. Simulator tokens are not routable, so not registering them keeps
the operations signal clean.

**Rejected**: `#if DEBUG` as the source of truth; the `sandboxReceipt` heuristic (receipt
presence differs between TestFlight and App Store in ways unrelated to APNs); registering
simulator tokens as sandbox.

## 4. Tap routing and navigation

**Decision**: `NotificationRoute(userInfo:)` reads the top-level `kind`, `introduction_id`,
`conversation_id` keys that `apnsPayload` writes: `introduction_ready` becomes
`.introduction(id)`, the other four become `.conversation(id, kind:)`, unknown kinds are
ignored, malformed ids become `nil`. `AppDelegate` is the `UNUserNotificationCenterDelegate`,
assigned in `didFinishLaunchingWithOptions` (before launch completes, or a cold-launch tap is
lost), and buffers one route until `attach(_:)` connects the store. `AppStore` holds
`pendingNotificationRoute` until the first session restore has been attempted (live backend) or
immediately (mock), then applies it: discard when not signed in or onboarding is incomplete
(FR-022); `.introduction` selects Today (Today's ready state is the introduction surface);
`.conversation` selects Messages and sets `messagesPath = [.conversation(id)]` when the loaded
conversation matches (or the id is absent), then runs a silent refresh and re-checks once so a
conversation that only exists after the refresh is pushed too. `MessagesView` moves to
`NavigationStack(path: $store.messagesPath)` with a value-based link and
`.navigationDestination(for: MessagesDestination.self)`; `ConversationView.onAppear` keeps
calling `openConversation()`, so a message is marked read only once the conversation is on
screen (FR-020).

**Rationale**: the store is the single owner of navigation state; a route received before the
session is restored must neither be applied to an empty store nor be lost. The mock backend
skips the refresh so tests stay deterministic. Warm taps navigate at once and refresh after,
which is what "opens directly" means; cold launches refresh first because the restore already
does so.

**Rejected**: reading `launchOptions[.remoteNotification]` (double-routes with `didReceive`);
holding a route across a later sign-in (the spec discards it and lands on Today); pushing
`IntroductionFlowView` programmatically (Today's ready state already presents the introduction,
and Today keeps its view-destination links).

## 5. Swift 6 concurrency at the delegate boundary

**Decision**: `AppDelegate` is `@MainActor` and implements the async variants of the two
`UNUserNotificationCenterDelegate` methods as `nonisolated`; each parses the non-Sendable
`UNNotification` into the Sendable `NotificationRoute` before awaiting a main-actor method on
`self`. Only Sendable values cross isolation. Exactly one variant (async) of each method is
implemented. The `NotificationCenterClient` protocol methods are `async` so the system
implementation can read `notificationSettings()` and map to the Sendable
`NotificationAuthorizationStatus` inside the call; `registerForRemoteNotifications()` is a
`@MainActor` requirement because `UIApplication.shared` is main-actor isolated. Test doubles are
`@MainActor` classes, which satisfy async requirements without locks.

**Rationale**: the protocol is not main-actor annotated in the SDK, so a main-actor witness
would be rejected under `SWIFT_STRICT_CONCURRENCY = complete`; `MainActor.assumeIsolated` and
`@preconcurrency` conformance would trade a compile error for a runtime trap.

**Rejected**: completion-handler variants (need a manual hop and risk implementing both
forms); `Task.detached`; `@unchecked Sendable` anywhere (forbidden by Principle V).

## 6. Project files

**Decision**: create `NetworkTo/NetworkTo.entitlements` with `aps-environment = development`
and set `CODE_SIGN_ENTITLEMENTS = NetworkTo/NetworkTo.entitlements` on the app target's Debug
and Release configurations only (`J10000000000000000000003`, `J10000000000000000000004`);
register the entitlements file as a `PBXFileReference` in the `NetworkTo` group without a
`PBXBuildFile`. Every new Swift file gets the four hand-written entries the objectVersion 56
project needs (`PBXBuildFile`, `PBXFileReference`, group child, Sources phase entry for the
correct target). No `Info.plist` change: iOS has no usage-description key for notifications, and
`UIBackgroundModes` must not be added because the backend sends alert pushes only.

**Rationale**: the project has no synchronized folders, so a file on disk that is not in the
pbxproj is not compiled; the test target must not inherit the entitlement (its bundle has no
push capability and device signing would fail). Automatic signing registers the capability on
the App ID at the first device build and rewrites the entitlement to `production` for
TestFlight and App Store exports.

**Rejected**: adding `SystemCapabilities` to `TargetAttributes` (Xcode UI bookkeeping the build
never reads); project-level `CODE_SIGN_ENTITLEMENTS`; upgrading the project format.

## 7. Test strategy

**Decision**: three layers. Pure Foundation logic (`NotificationRouting.swift`) is tested
directly. `AppStore` is tested with `MockBackendService(latency: .zero)` and
`MockNotificationCenterClient`, using `async` store entry points so registration and routing
are observable without polling; `signOut()` exposes its task so the unregister-before-sign-out
order can be awaited. The two OS boundaries (the permission alert and APNs token delivery) plus
cold-launch tap timing are verified manually with the checklist in quickstart.md, including
`xcrun simctl push` for routing without a backend.

**Rationale**: the hosted test run launches the real app, so nothing on the launch path may
present a system alert; the policy guarantees the prompt only follows a member's tap, and the
system client touches `UNUserNotificationCenter` only inside its methods, never in `init`.

**Rejected**: UI tests driving the system alert (flaky and needs interruption monitors); a
`nonisolated(unsafe)` token slot for tests (forbidden).

## Risks carried into implementation

- Until Push Notifications is enabled on the App ID, device builds report
  `didFailToRegisterForRemoteNotificationsWithError` ("no valid aps-environment entitlement");
  the failure is logged, never shown.
- A misdetected environment yields `BadDeviceToken`; the operations alert on repeated delivery
  failures is the detection signal, and a TestFlight check that `device_tokens.environment` is
  `production` is in the quickstart.
- An offline sign-out leaves the token attached until this phone is registered again or APNs
  retires it (accepted in the spec).
- Cold-launch tap timing can only be verified on a device or simulator by force-quitting the
  app and tapping a pushed notification.
