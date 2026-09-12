# Data Model: iPhone Remote Notifications

**Feature**: 001-remote-notifications | **Date**: 2026-09-12

The backend model is unchanged. This feature adds phone-side value types, two `UserDefaults`
records, and navigation state on `AppStore`.

## Server-side entities (existing, unchanged)

| Entity | Where | Fields the client relies on | Notes |
|--------|-------|-----------------------------|-------|
| Phone registration | `public.device_tokens` | `token` (unique, `^[0-9a-f]{64,200}$`), `environment` (`sandbox` or `production`), `user_id`, `updated_at` | Written only through `register_device_token`; removed through `unregister_device_token`, `retire_device_token`, or cascade on deletion |
| Notification | `public.notification_events` + the APNs payload | `kind`, `introduction_id`, `conversation_id`, `meetup_id` | Payload copy is fixed per kind by `notificationContent` in `apns.ts` |

## Client value types (`NetworkTo/Services/NotificationRouting.swift`, Foundation only)

### `NotificationAuthorizationStatus`

`enum … : Equatable, Sendable { case unknown, notDetermined, denied, authorized }`

- `unknown`: not read yet (initial value; never triggers the invitation).
- `notDetermined`: the phone has never been asked (`canPrompt == true`).
- `denied`: the member declined or turned notifications off in Settings.
- `authorized`: alerts allowed (`allowsDelivery == true`); provisional and ephemeral map here
  although the app never requests them.

### `PushEnvironment`

`enum … : String, Sendable { case sandbox, production }`

- `rawValue` is exactly what `register_device_token(p_environment)` accepts.
- `static func parse(provisioningProfile: Data) -> PushEnvironment?` reads the embedded
  provisioning profile's `aps-environment` entitlement (`development` → `.sandbox`,
  `production` → `.production`).
- `static func resolve(isSimulator: Bool, profile: Data?) -> PushEnvironment?`: simulator →
  `nil`; no profile → `.production` (App Store install); otherwise the parsed value.
- `static func current(bundle: Bundle = .main) -> PushEnvironment?` applies `resolve` to the
  running process.

### `DeviceRegistration`

`struct … : Equatable, Sendable { let token: String; let environment: PushEnvironment }`

- `token` is lowercase hex; `init?(deviceToken: Data, environment:)` returns `nil` unless the
  formatted token matches the RPC rule (32 to 100 bytes).
- Persisted per member as `["token": …, "environment": …]`.

### `NotificationRoute`

`enum … : Equatable, Sendable { case introduction(UUID?); case conversation(UUID?, kind: Kind) }`

- `Kind: String` with the five raw values `introduction_ready`, `mutual_interest`,
  `new_message`, `meetup_reminder`, `feedback_due`.
- `init?(userInfo: [AnyHashable: Any])`: `kind` unknown or missing → `nil`; identifiers parsed
  with `UUID(uuidString:)`, malformed → `nil` id (the route still selects the tab).
- Carries no name, no copy, and no decision.

### `NotificationItem`

`enum … : Equatable, Sendable { case introduction(UUID); case conversation(UUID) }`

- `func matches(userInfo:) -> Bool` compares `introduction_id` or `conversation_id`
  case-insensitively; used to remove delivered notifications once the item is on screen.

### `NotificationInvitePolicy`

`static func shouldOffer(authorization:hasAuthenticated:hasCompletedOnboarding:canReceiveIntroductions:phase:hasDeclined:) -> Bool`

True only when the status is `.notDetermined`, the member is signed in with onboarding
complete and access to introductions, the phase is `.searching` or `.waiting`, and no "Not now"
is recorded.

### `MessagesDestination` (`NetworkTo/App/AppStore.swift`)

`enum … : Hashable, Sendable { case conversation(UUID) }` — the value type behind the Messages
navigation path.

## Store state (`AppStore`)

| Property | Type | Access | Changed by |
|----------|------|--------|------------|
| `notificationAuthorization` | `NotificationAuthorizationStatus` | `@Published private(set)` | `refreshNotificationAuthorization()`, `requestNotificationAuthorization()`, `registerForRemoteNotificationsIfAllowed()` |
| `hasDeclinedNotificationInvite` | `Bool` | `@Published private(set)` | `declineNotificationInvite()`, member change (reload), deletion (clear) |
| `messagesPath` | `[MessagesDestination]` | `@Published` (bound by `MessagesView`) | navigation, route application, sign-out, reset |
| `pendingNotificationRoute` | `NotificationRoute?` | `private(set)` | `handleNotificationRoute(_:)`, application, sign-out |
| `pendingDeviceRegistration` | `DeviceRegistration?` | `private(set)` | `receiveDeviceRegistration(_:)`, successful sync, sign-out |
| `registeredDeviceRegistration` | `DeviceRegistration?` | `private(set)` | successful sync (persisted per member), member change (reload), sign-out and deletion (cleared) |
| `signOutTask` | `Task<Void, Never>?` | `private(set)` | `signOut()` (tests await it) |

Derived: `shouldOfferNotificationInvite` (the policy applied to the store),
`isReadyForDeviceRegistration` (`isUsingLiveBackend && hasAuthenticated && hasCompletedOnboarding`).

## Phone memory (`UserDefaults`, keyed by `member.id`)

| Key | Value | Written | Cleared |
|-----|-------|---------|---------|
| `networkto.notifications.invite.declined.<memberID>` | `true` | "Not now" | after confirmed account deletion (lost with the app) |
| `networkto.notifications.registration.<memberID>` | `{ token, environment }` | successful `register_device_token` | sign-out (after the removal attempt), confirmed account deletion |

The member id is the profile id delivered by `bootstrap()` (the mock member id in
demonstration mode), so the memory is per member on this phone as FR-004 and FR-009 require.

## State transitions

```text
Permission:   unknown --refresh--> notDetermined | denied | authorized
              notDetermined --request (card or Profile row)--> authorized | denied
              (denied and authorized change only through iPhone Settings; re-read on activation)

Invitation:   hidden --(policy true)--> showing --Turn on--> hidden (status leaves notDetermined)
                                        showing --Not now--> hidden (declined recorded)
                                        showing --(status changes elsewhere)--> hidden (nothing recorded)

Registration: none --token--> pending --ready && RPC ok--> remembered (previous token removed if different)
              pending --RPC fails--> pending (retried on next activation)
              remembered --sign-out--> removal attempted (≤ 5 s) --> forgotten
              remembered --deletion confirmed--> forgotten

Route:        received --(restore not yet attempted, live)--> pending
              pending/received --(signed in, onboarded)--> applied: Today | Messages (+ conversation)
              pending/received --(not signed in or onboarding incomplete)--> discarded
```
