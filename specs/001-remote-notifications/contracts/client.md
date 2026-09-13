# Client Contracts: iPhone Remote Notifications

Everything below is Swift 6 with strict concurrency. Types are `Sendable`; the store is
`@MainActor`; the only files importing UserNotifications are `AppDelegate.swift` and
`NotificationCenterClient.swift`.

## `NotificationCenterClient` (`NetworkTo/Services/NotificationCenterClient.swift`)

```swift
protocol NotificationCenterClient: Sendable {
    func authorizationStatus() async -> NotificationAuthorizationStatus
    /// Presents the phone's dialog when never asked; returns the fresh status either way.
    func requestAuthorization() async -> NotificationAuthorizationStatus
    @MainActor func registerForRemoteNotifications()
    func removeDeliveredNotifications(about item: NotificationItem) async
}

struct SystemNotificationCenterClient: NotificationCenterClient   // UNUserNotificationCenter + UIApplication
```

Rules: `SystemNotificationCenterClient` touches `UNUserNotificationCenter.current()` only inside
its methods; `requestAuthorization()` passes `[.alert, .sound]` and re-reads
`notificationSettings()` afterwards rather than trusting the returned Bool; `.provisional` and
`.ephemeral` map to `.authorized`, `@unknown default` maps to `.denied`.

## `BackendService` additions

```swift
func registerDeviceToken(_ token: String, environment: PushEnvironment) async throws   // default: no-op
func unregisterDeviceToken(_ token: String) async throws                               // default: no-op
```

`SupabaseBackendService` calls `register_device_token` with `p_token`/`p_environment` and
`unregister_device_token` with `p_token`. `MockBackendService` records
`registeredDevices: [DeviceRegistration]`, `unregisteredDeviceTokens: [String]`, and an ordered
`events: [String]` (`register:<token>`, `unregister:<token>`, `signOut`), and throws
`MockServiceError.requestFailed` for a token starting with `dead`.

## `AppStore` API (`NetworkTo/App/AppStore.swift`, `// MARK: - Notifications`)

```swift
// Permission and invitation
var shouldOfferNotificationInvite: Bool                       // NotificationInvitePolicy applied to the store
func refreshNotificationAuthorization() async                 // reads the status; no UI
func requestNotificationAuthorization() async                 // guards .notDetermined; registers when allowed
func declineNotificationInvite()                              // records "Not now" for this member on this phone
static let notificationSettingsFallbackNotice: String         // "Notifications are managed in iPhone Settings under network.to"

// Registration
var isReadyForDeviceRegistration: Bool                        // isLive && hasAuthenticated && hasCompletedOnboarding
func registerForRemoteNotificationsIfAllowed() async          // refresh status; ask iOS for the token when allowed and ready
func receiveDeviceRegistration(_ registration: DeviceRegistration) async   // buffer, then sync when ready

// Routing and presentation
func handleNotificationRoute(_ route: NotificationRoute)      // buffer until the first restore attempt, then apply or discard
func isViewingDestination(of route: NotificationRoute) -> Bool
func shouldPresentArrivingNotification(_ route: NotificationRoute?) -> Bool   // triggers a silent refresh when live
func didViewNotificationItem(_ item: NotificationItem)        // removes delivered notifications about the item
```

Behavioural contract:

- `requestNotificationAuthorization()` never presents the dialog twice: it returns immediately
  unless the status is `.notDetermined`.
- `receiveDeviceRegistration` registers on every delivery while ready; on success it remembers
  the registration for the member and removes the previously remembered token when it differs;
  on failure it keeps the token pending and never sets `transientMessage`.
- `signOut()` captures the remembered registration, forgets it and the pending token, clears
  the pending route and `messagesPath`, then in `signOutTask` awaits the removal for at most
  5 seconds before `backend.signOut()`.
- `deleteAccount()` clears the declined choice and the remembered registration only after
  `backend.deleteAccount()` returns.
- `handleNotificationRoute` applies `.introduction` as `selectedTab = .today` and
  `.conversation(id, _)` as `selectedTab = .messages` plus `messagesPath = [.conversation(c.id)]`
  when `canMessage` and (`id == nil || c.id == id`); when live it then runs
  `refreshFromBackend(silently: true)` and re-applies the conversation push once. A route
  received while not signed in or before onboarding is complete is discarded.
- `isViewingDestination(of:)`: `.introduction` → `selectedTab == .today`; `.conversation(id, _)`
  → `selectedTab == .messages && conversation?.id == id && messagesPath.last == .conversation(id)`;
  a `nil` id never counts as viewing.
- `refreshFromBackend(silently:)` coalesces concurrent calls onto one in-flight task; the
  silent variant swallows the error (FR-024), the default keeps reporting through
  `transientMessage`.

## `AppDelegate` (`NetworkTo/App/AppDelegate.swift`)

```swift
@MainActor final class AppDelegate: NSObject, UIApplicationDelegate {
    func attach(_ store: AppStore)          // called first thing in NetworkToApp's .task; flushes buffered route and token
    // UIApplicationDelegate: didFinishLaunching sets UNUserNotificationCenter.current().delegate = self
    // didRegisterForRemoteNotificationsWithDeviceToken → DeviceRegistration → store.receiveDeviceRegistration
    // didFailToRegisterForRemoteNotificationsWithError → os.Logger only
}
extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_:didReceive:) async               // default action only → store.handleNotificationRoute
    nonisolated func userNotificationCenter(_:willPresent:) async -> UNNotificationPresentationOptions
    // [.banner, .list, .sound] unless store.shouldPresentArrivingNotification returns false → []
}
```

## `NetworkToApp` wiring

- `@UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate`.
- `.task`: `appDelegate.attach(store)` first, then the existing restore and StoreKit steps,
  then `await store.registerForRemoteNotificationsIfAllowed()`.
- `.onChange(of: scenePhase)` on `.active`: restore the live session as today, then
  `await store.registerForRemoteNotificationsIfAllowed()` (which also refreshes the status on
  the mock backend so the Profile row stays current).

## Views

- `NTNotificationInviteCard(turnOn:notNow:)` in `Components.swift`: heading "When network.to will
  notify you", body "We’ll notify you only when an introduction is ready, when interest is
  mutual, when you receive a message, before a meeting, and when private feedback is due. You
  can change this anytime in iPhone Settings.", primary "Turn on notifications"
  (`NTPrimaryButtonStyle`), secondary "Not now" (`NTSecondaryButtonStyle`), `ntSurface()`,
  no symbol animation, `accessibilityElement(children: .contain)` with a label on the card and
  hints on both buttons.
- `TodayView`: renders the card first in the content stack when
  `store.shouldOfferNotificationInvite`; calls `store.didViewNotificationItem(.introduction(id))`
  whenever Today is the selected tab in the `.ready` phase.
- `IntroductionFlowView`: `onAppear` calls `didViewNotificationItem(.introduction(id))`.
- `MessagesView`: `NavigationStack(path: $store.messagesPath)`,
  `NavigationLink(value: MessagesDestination.conversation(id))`,
  `.navigationDestination(for: MessagesDestination.self) { _ in ConversationView() }`;
  `ConversationView.onAppear` keeps `openConversation()` and adds
  `didViewNotificationItem(.conversation(id))`.
- `ProfileView` Notifications row: subtitle from the status ("Not set up yet", "On · Managed in
  iPhone Settings", "Off · Turn on in iPhone Settings", "Managed in iPhone Settings" while
  unknown); tap presents the dialog while `.notDetermined`, otherwise opens
  `UIApplication.openNotificationSettingsURLString` and sets `transientMessage` to the fallback
  notice when the URL cannot be opened.
