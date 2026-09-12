# Implementation Plan: iPhone Remote Notifications

**Branch**: `001-remote-notifications` | **Date**: 2026-09-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/001-remote-notifications/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Add the phone side of the notification pipeline the backend already runs: ask for permission
once, from a calm card at the top of Today that appears only after onboarding while Today is
searching or privately waiting; register the phone's APNs token with the member's account
through the existing `register_device_token` RPC (sandbox or production, read from the
embedded provisioning profile); re-register on every activation; remove the registration before
sign-out (bounded to 5 seconds) and forget it after account deletion; open Today or the
referenced conversation when one of the five notification kinds is tapped, in every app state;
suppress the banner when the member is already on the destination; clear delivered
notifications about an item once it is on screen; and keep every delivery preference in iPhone
Settings through the existing Profile row. No backend change, no new secret, no new push
payload, no new scheduled job.

## Technical Context

**Language/Version**: Swift 6 (SwiftUI, iOS 17+, `SWIFT_STRICT_CONCURRENCY = complete`)

**Primary Dependencies**: UserNotifications and UIKit (system frameworks, auto-linked),
`supabase-swift` (already present) for the two RPC calls; no new package

**Storage**: on the phone, `UserDefaults` keys scoped to the member id for the "Not now" choice
and the last registered token; server-side the existing `public.device_tokens` and
`public.notification_events` tables, unchanged

**Testing**: XCTest on the `NetworkToTests` target with `MockBackendService` and a new
`MockNotificationCenterClient`; the pgTAP and Deno suites are unchanged (the backend is not
touched) and keep covering `register_device_token`, `unregister_device_token`, and the payload
builder; manual device and simulator checks listed in quickstart.md

**Target Platform**: iPhone, iOS 17.0+; physical device for APNs tokens (the simulator can only
replay payloads with `simctl push`)

**Project Type**: Mobile app (existing `NetworkTo/` layout) using the existing Supabase backend

**Performance Goals**: registration RPC issued once per activation (SC-002: within 60 s of
allowing); tap routing lands on the destination without waiting on the network when the app is
warm and after the single restore-and-refresh on cold launch (SC-003: 5 s); sign-out never
waits more than 5 s on the removal (SC-012)

**Constraints**: no prompt at launch, sign-in, or onboarding (FR-001); `[.alert, .sound]` only
(FR-005); no registration on the mock backend, when signed out, or before onboarding (FR-011);
no in-app notice for any registration or refresh failure (FR-008, FR-024); no icon badge, no
notification centre, no in-app toggles (FR-028, FR-030); `AppStore` stays the single owner of
rendered state (Principle V); nothing in the iOS target holds a secret

**Scale/Scope**: 3 new Swift source files, 1 entitlements file, 9 edited Swift files, 4 new
test files, project file registration, 5 documentation files

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Principles touched: I, II, III, IV, V, VI, VII, VIII.

- **I (one introduction, never a feed)**: four tabs unchanged; no notification centre; the
  Messages badge keeps counting the unread mutual-only conversation and nothing else gains a
  badge; the invitation card never appears beside an undecided introduction or a
  mutual-interest action (policy in `NotificationInvitePolicy`). PASS.
- **II (reciprocal interest is the only gate)**: the app only reacts to the five kinds the
  backend already deems safe; a tap only selects a tab and pushes the conversation the member
  can already open (`canMessage`); it never records Interested or Pass and never marks a
  message read before `ConversationView` appears. PASS.
- **III (in-person outcome)**: meeting reminders and feedback-due notifications open the
  conversation whose meetup details or feedback prompt they concern. PASS.
- **IV (members own their data)**: exactly the five kinds, parsed from `kind`; unknown kinds are
  ignored; payload identifiers only; delivery preferences stay in iPhone Settings (the Profile
  row opens them or presents the phone's dialog when never asked); the token is removed before
  `signOut()` and forgotten after confirmed deletion; the phone-side memory is one Bool and one
  token per member. PASS.
- **V (native, accessible, single store)**: `AppStore` gains the notification state
  (`notificationAuthorization`, `hasDeclinedNotificationInvite`, `messagesPath`, pending route
  and registration) as `private(set)` or store-owned properties changed only through guarded
  methods; the OS boundary is a `NotificationCenterClient` protocol injected through
  `AppStore.init` with a system default, so the store stays Foundation-only and tests inject a
  double; `BackendService` gains two requirements with no-op defaults; behaviour branches on
  `isLive`; the new `NTNotificationInviteCard` uses `NTColor`, `NTSpacing`, `NTRadius`, and
  Dynamic Type; the system permission dialog, banner, sound, grouping, and Settings page are
  used as they are; the state matrix below covers every new surface. PASS.
- **VI (backend owns trust)**: no backend change. The two RPCs already require `auth.uid()`,
  validate the token and environment, and are granted to `authenticated` only; the client
  cannot register for anyone else or see another member's registration. PASS.
- **VII (deterministic tests, CI-only deploys)**: XCTest files listed below; nothing deploys.
  Because no CI builds the app, the PR records the Xcode test pass before merge. PASS.
- **VIII (calm technology)**: see the Calm Technology check below. PASS.

Gate details required by the plan gate:

| Item | RLS / grants | Privilege assertions | Secret | Push payload | Idempotency | Retention |
|------|--------------|----------------------|--------|--------------|-------------|-----------|
| `register_device_token(p_token, p_environment)` (existing, now called) | `security definer`, empty `search_path`; execute revoked from `public`, `anon`; granted to `authenticated` | already asserted in `schema.test.sql` and `production_behavior.test.sql` | none | n/a | upsert on `token`; repeat calls refresh `updated_at` and reassign `user_id` | row removed on sign-out, by `retire_device_token`, or by cascade on deletion |
| `unregister_device_token(p_token)` (existing, now called) | as above | as above | none | n/a | delete filtered on `auth.uid()`; repeat calls are no-ops | n/a |
| Notification payload consumed by the client | n/a (produced by `deliver-notifications`, unchanged) | Deno tests for `apnsPayload` unchanged | APNs key stays a function secret; nothing in iOS | unchanged: `aps.alert`, `sound`, `thread-id`, `interruption-level: active`, top-level `kind`, `introduction_id`, `conversation_id`, `meetup_id` | `apns-collapse-id` set by the backend; the client does not group | events purged after 90 days (existing) |
| `aps-environment` entitlement (`NetworkTo/NetworkTo.entitlements`) | n/a | n/a | none (the entitlement is not a secret; Apple rewrites it to `production` for TestFlight and App Store exports) | n/a | n/a | n/a |
| Phone memory: `networkto.notifications.invite.declined.<memberID>` (Bool) and `networkto.notifications.registration.<memberID>` (token, environment) | device-local `UserDefaults`; never sent anywhere | n/a | none | n/a | overwrite | declined choice cleared after confirmed deletion; registration cleared on sign-out and after deletion; both lost with the app |

No new table, Edge Function, scheduled job, or push kind. No constitution amendment is needed:
Principle IV already lists the five kinds and "delivery preferences MUST live in native iPhone
Settings", and the Product and Platform Constraints do not change.

### State matrix and offline states

| Surface | Resting | In progress | Success | Recoverable failure | Terminal | Offline |
|---------|---------|-------------|---------|---------------------|----------|---------|
| Notification invitation card (Today) | Card with heading, five reasons, "Turn on notifications", "Not now" | Phone dialog open (card already dismissed because status leaves never-asked) | Allowed: card gone, no confirmation; registration runs silently | Registration failed: nothing shown, retried on next activation | Declined in the dialog or "Not now": card gone for this member on this phone | Dialog works offline; registration queued (token buffered) and sent on the next activation with connectivity; nothing shown (recorded deviation, spec FR-006) |
| Profile "Notifications" row | Subtitle reflects status: "Not set up yet" / "On · Managed in iPhone Settings" / "Off · Turn on in iPhone Settings" / "Managed in iPhone Settings" while unknown | Dialog open (never asked) or Settings opening | Settings page opened or permission decided | Settings page cannot open: one `transientMessage` "Notifications are managed in iPhone Settings under network.to" | n/a | Same as resting; no network involved |
| Tapped notification (cold launch) | Launch screen | Session restore and refresh (existing loading state) | Today in its current state or Messages with the conversation pushed | Refresh fails: destination tab shown in its last known state, existing offline notice from the refresh path, no notification-specific error | Session invalid: sign-in screen, route discarded; onboarding incomplete: onboarding, route discarded | Destination tab shown; updates in place when a later refresh succeeds |
| Tapped notification (warm) | Current screen | Tab switch and push happen at once | As above | Item absent: destination tab's current state, no error | As above | As above |
| Arrival while open | Current screen | Silent refresh | Content updated in place; banner suppressed on the destination, standard banner elsewhere | Silent refresh fails: nothing shown | n/a | Banner shown by the phone; nothing shown by the app |
| Registration (invisible) | No token | `registerForRemoteNotifications()` issued | Row upserted; previous token removed when it differs | RPC failed: token kept pending, retried on the next activation | Simulator or no environment: nothing registered | Token buffered until the next activation with connectivity |
| Sign-out | Signed in | Removal in flight (≤ 5 s) while the UI already shows sign-in | Row removed, session ended | Removal times out or fails: session still ended, registration forgotten | n/a | Same as failure |

### Tests this plan adds

- `NetworkToTests/NotificationRoutingTests.swift`: `DeviceRegistration` hex formatting and
  validation, `PushEnvironment.parse` and `resolve`, `NotificationRoute(userInfo:)` for all five
  kinds and the unknown and malformed cases, `NotificationItem.matches(userInfo:)`,
  `NotificationInvitePolicy.shouldOffer` table.
- `NetworkToTests/NotificationStoreTests.swift`: authorization refresh and request through the
  mock client (prompt only when never asked, never twice), invitation visibility for every
  phase, "Not now" persistence across store instances and its clearing after deletion,
  registration triggered only when allowed and ready.
- `NetworkToTests/NotificationRegistrationTests.swift`: token buffered before readiness and
  registered once with the expected hex and environment; repeat token re-registered (refresh);
  changed token registers the new one and removes the old; failure keeps the token pending and
  sets no `transientMessage`; sign-out removes the token before `signOut` and forgets it;
  deletion clears the memory; route handling for every kind, the discard cases, the
  `isViewingDestination` and presentation decisions, and the coalesced refresh.
- `NetworkToTests/NotificationTestDoubles.swift`: `MockNotificationCenterClient`.
- `MockBackendService` records registered and unregistered tokens and an ordered event log.
- Existing pgTAP (`schema.test.sql`, `production_behavior.test.sql`, `launch_operations.test.sql`)
  and Deno (`apns_test.ts`) coverage is unchanged and remains the contract the client relies on.

### Calm Technology check (Principle VIII)

- *Reduce or add attention?* Reduces it: the member learns of the five moments without opening
  the app. The only added surface is one card, shown once until answered, never beside an
  introduction, never repeated on the app's initiative.
- *Inform or alarm?* Informs: fixed copy with a neutral heading; the phone's standard banner at
  most once; no sound, haptic, or animation of the app's own; no banner when the member is
  already on the destination.
- *Can it live in the periphery?* Yes: notifications stay on the lock screen and in the phone's
  list, grouped and replaced there by the backend, and are cleared once the item is on screen.
  Inside the app only the existing Messages badge changes; no icon badge; no notification
  centre.
- *Help two people meet, or keep them in the app?* Every kind moves a member toward or through
  an in-person meeting. No streak, check-in, inactivity, expiry, or marketing notification.
- *Fail quietly?* Yes: a failed registration, a failed silent refresh, an expired or ended item,
  an unknown kind, an offline cold launch, and a sign-out that cannot confirm removal all
  produce no error and block nothing; foreground refresh remains the recovery path.
- *Is there a simpler way?* The phone's dialog, banner, sound, grouping, Settings page, and Focus
  handling are reused; the store adds the minimum state the single ask and routing need.
- *Would a thoughtful professional find it normal?* Yes: told once, after onboarding, what a tool
  will notify about, then managing it in iPhone Settings like every other app.

## Project Structure

### Documentation (this feature)

```text
specs/001-remote-notifications/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   ├── client.md        # Swift types, store API, view composition
│   ├── backend-usage.md # The two RPCs the client calls and what it expects
│   └── notification-payload.md  # Payload keys consumed, routing and presentation rules
├── checklists/requirements.md
└── tasks.md             # Phase 2 output (/speckit-tasks)
```

### Source Code (repository root)

```text
NetworkTo/
├── NetworkTo.entitlements                   # new: aps-environment = development
├── App/
│   ├── AppDelegate.swift                    # new: UIApplicationDelegate + UNUserNotificationCenterDelegate
│   ├── AppStore.swift                       # edit: notification state and methods (// MARK: - Notifications), coalesced refresh, sign-out, deletion
│   ├── NetworkToApp.swift                   # edit: delegate adaptor, attach, activation hooks
│   └── MainTabView.swift                    # unchanged (badge already derived from state)
├── Services/
│   ├── NotificationRouting.swift            # new: Foundation-only value types and policies
│   ├── NotificationCenterClient.swift       # new: protocol + SystemNotificationCenterClient (UserNotifications, UIKit)
│   ├── BackendService.swift                 # edit: registerDeviceToken / unregisterDeviceToken with no-op defaults
│   ├── SupabaseBackendService.swift         # edit: the two RPC calls
│   └── MockBackendService.swift             # edit: recording implementations
├── DesignSystem/
│   └── Components.swift                     # edit: NTNotificationInviteCard
└── Features/
    ├── Today/TodayView.swift                # edit: invitation card, delivered-notification clearing
    ├── Introduction/IntroductionFlowView.swift  # edit: delivered-notification clearing on appear
    ├── Messages/MessagesView.swift          # edit: NavigationStack(path:), value link, destination, clearing
    └── Profile/ProfileView.swift            # edit: status-aware Notifications row with fallback notice

NetworkToTests/
├── NotificationRoutingTests.swift           # new
├── NotificationStoreTests.swift             # new
├── NotificationRegistrationTests.swift      # new
└── NotificationTestDoubles.swift            # new

NetworkTo.xcodeproj/project.pbxproj          # edit: file references, build files, groups, Sources phases, CODE_SIGN_ENTITLEMENTS
docs/                                        # edit: SUPABASE_BACKEND.md, UI_DESIGN_SPEC.md, COMPONENT_STATE_SHEET.md, ACCESSIBILITY_REVIEW.md; README.md
```

**Structure Decision**: the existing single-app layout. Foundation-only logic lives in
`Services/NotificationRouting.swift` so it is unit-tested without UIKit; the only files that
import UserNotifications are `AppDelegate.swift` and `NotificationCenterClient.swift`. The
notification methods live inside `AppStore.swift` (a `// MARK: - Notifications` section) rather
than a separate extension file, because the state they change is `private(set)` and Swift
limits those setters to the declaring file.

## Complexity Tracking

No constitution violations to justify. The earlier idea of a second `NotificationStore`
(mirroring `SubscriptionStore`) was rejected during research because Principle V names one
`AppStore` as the owner of rendered state; the OS boundary is injected instead.

## Phase 0: Research

See [research.md](research.md). Seven unknowns were resolved: when and how to ask (policy and
card), token registration and its buffering, APNs environment detection, tap routing and the
navigation model, Swift 6 concurrency at the delegate boundary, project-file wiring
(entitlements and the hand-maintained pbxproj), and the test strategy.

## Phase 1: Design

See [data-model.md](data-model.md), [contracts/](contracts/), and [quickstart.md](quickstart.md).
Re-check of the Constitution Check after design: unchanged, PASS.

## Operator steps outside the repository

- Enable Push Notifications on App ID `com.mesbahtanvir.networkto` in the Apple Developer
  account (automatic signing does this on the first device build once the entitlement exists,
  when Xcode is signed in with an account allowed to edit identifiers).
- The APNs key, function secrets, and Vault secrets listed in `docs/SUPABASE_BACKEND.md`
  remain the launch dependencies for end-to-end delivery; registration works before they exist.
