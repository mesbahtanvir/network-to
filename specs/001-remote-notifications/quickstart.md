# Quickstart: iPhone Remote Notifications

## Build and unit tests

```sh
xcodebuild test -project NetworkTo.xcodeproj -scheme NetworkTo \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

The suite must pass with the four new test files. The hosted test run launches the app; no
system permission alert may appear (the prompt only follows a member's tap).

Validate the hand-edited project file on a Mac before opening it in Xcode:

```sh
plutil -lint NetworkTo.xcodeproj/project.pbxproj
xcodebuild -list -project NetworkTo.xcodeproj
```

## One-time developer-account step

Enable **Push Notifications** on the App ID `com.mesbahtanvir.networkto` (team `6Z4KNLU26A`).
With automatic signing, the first device build after this change registers the capability and
regenerates the profile when Xcode is signed in with an account allowed to edit identifiers
(`xcodebuild … -allowProvisioningUpdates` from the command line). Until then a device build logs
`no valid "aps-environment" entitlement string found` from
`didFailToRegisterForRemoteNotificationsWithError` and nothing is registered; the app shows
nothing.

Verify an exported build carries the right value:

```sh
codesign -d --entitlements :- Payload/NetworkTo.app | grep -A1 aps-environment
```

Development builds must show `development`; TestFlight and App Store exports must show
`production`.

## Simulator routing check (no backend needed)

Run the app with `--mock-backend`, complete onboarding, then push a payload that mirrors
`apnsPayload`:

```sh
cat > /tmp/new_message.apns <<'EOF'
{
  "Simulator Target Bundle": "com.mesbahtanvir.networkto",
  "aps": {
    "alert": { "title": "New message", "body": "Sarah sent you a message." },
    "sound": "default",
    "thread-id": "conversations",
    "interruption-level": "active"
  },
  "kind": "new_message",
  "conversation_id": "REPLACE-WITH-THE-OPEN-CONVERSATION-ID"
}
EOF
xcrun simctl push booted com.mesbahtanvir.networkto /tmp/new_message.apns
```

Expected: with the app on Today, the banner appears once; tapping it opens Messages with the
conversation pushed and the composer visible. With the conversation already open, no banner
appears. With the app force-quit, tapping the notification launches the app and lands on the
conversation after the standard loading state. Use `"kind": "introduction_ready"` to check the
Today route and an unknown kind to check that nothing routes.

Without a real conversation id (the mock conversation id changes per run), omit
`conversation_id`: the tap must still land on Messages with the only conversation pushed.

## Device checklist (staging backend with APNs secrets)

1. Fresh install, sign up, complete onboarding: the invitation card appears at the top of Today
   only when Today is searching or privately waiting; nothing appears during sign-in or
   onboarding.
2. "Turn on notifications" → the phone's dialog; Allow → `select environment, updated_at from
   public.device_tokens` shows one row with `sandbox` for a development build.
3. Relaunch and bring the app to the foreground: `updated_at` advances; no visible change.
4. Deny in the dialog → no second prompt on relaunch; Profile → Notifications opens iPhone
   Settings; enabling there and returning to the app registers the phone.
5. "Not now" → card gone; sign out and back in → card still gone; Profile → Notifications
   presents the dialog.
6. Create each kind of event for the member (a message from the other account, or an insert
   into `notification_events`): banner text matches `apns.ts`; tapping routes correctly with
   the app open, in the background, and force-quit.
7. Sign out online: the `device_tokens` row disappears within 5 seconds. Sign out in airplane
   mode: sign-out completes at once; the row remains until the next registration.
8. Delete the account: no row remains; reinstalling and signing up again shows the card again
   only if the phone's permission is still never-asked.
9. TestFlight build: `device_tokens.environment` is `production` and a notification arrives.
10. Accessibility: VoiceOver reaches the card first on Today; both buttons announce label and
    hint; the card survives the largest accessibility text size at 320 pt; Reduce Motion
    changes nothing because nothing animates.
