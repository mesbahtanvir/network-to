# Backend Usage: iPhone Remote Notifications

The client calls two existing RPCs. Nothing is added or changed server-side.

## `public.register_device_token(p_token text, p_environment text)`

- Caller: `authenticated` only (`auth.uid()` must be set; otherwise "Authentication required").
- `p_token`: lowercase hex, `^[0-9a-f]{64,200}$` after trim and lowercase; anything else raises
  "Invalid device token".
- `p_environment`: `sandbox` or `production`; anything else raises "Invalid push environment".
- Effect: upsert on `token`; an existing row is reassigned to the caller and its `updated_at`
  refreshed. This is the "shared phone" and "last-confirmed time" behaviour the spec relies on.
- Client expectations: called once per token delivery while signed in with onboarding
  complete on the live backend; failures are swallowed and retried on the next activation.

## `public.unregister_device_token(p_token text)`

- Caller: `authenticated` only; deletes the row where `user_id = auth.uid()` and the token
  matches; a token owned by another member is untouched (no error).
- Client expectations: called before `signOut()` with the remembered token, bounded to 5
  seconds; called after a successful registration of a different token to remove the
  previous one. Never called after account deletion (the cascade removes every row).

## Delivery pipeline (unchanged, for reference)

- `private.dispatch_notification_delivery()` posts due events to `deliver-notifications`,
  which sends `apns-push-type: alert` payloads built by `apnsPayload` with
  `apns-collapse-id` and `thread-id` set per kind.
- `retire_device_token` removes tokens APNs reports as unregistered or bad; the app never
  needs to react to that.
- Events for members without a registered token are not attempted.

## Encoding in `SupabaseBackendService`

```swift
private struct DeviceTokenParameters: Encodable {
    let token: String
    let environment: String
    enum CodingKeys: String, CodingKey { case token = "p_token"; case environment = "p_environment" }
}
private struct DeviceTokenRemovalParameters: Encodable {
    let token: String
    enum CodingKeys: String, CodingKey { case token = "p_token" }
}
// client.rpc("register_device_token", params: …).execute()
// client.rpc("unregister_device_token", params: …).execute()
```
