# Notification Payload Contract (consumed by the client)

Produced by `supabase/functions/_shared/apns.ts` (`notificationContent` + `apnsPayload`); the
client reads it and never rewrites it.

```json
{
  "aps": {
    "alert": { "title": "New message", "body": "Sarah sent you a message." },
    "sound": "default",
    "thread-id": "<conversation uuid>",
    "interruption-level": "active"
  },
  "kind": "new_message",
  "conversation_id": "<uuid>",
  "introduction_id": "<uuid, when known>",
  "meetup_id": "<uuid, when known>"
}
```

Headers set by the backend: `apns-push-type: alert`, `apns-topic: com.mesbahtanvir.networkto`,
`apns-collapse-id` per kind and item. The client relies on them for grouping and replacement
and adds nothing.

## Routing table

| `kind` | Route | Destination | Identifier used |
|--------|-------|-------------|-----------------|
| `introduction_ready` | `.introduction(introduction_id)` | Today (ready state shows the introduction) | `introduction_id` (optional) |
| `mutual_interest` | `.conversation(conversation_id, kind: .mutualInterest)` | Messages, conversation pushed | `conversation_id` (may be absent; the only conversation is opened) |
| `new_message` | `.conversation(conversation_id, kind: .newMessage)` | Messages, conversation pushed | `conversation_id` |
| `meetup_reminder` | `.conversation(conversation_id, kind: .meetupReminder)` | Messages, conversation pushed (meetup details inside) | `conversation_id`; `meetup_id` parsed but unused |
| `feedback_due` | `.conversation(conversation_id, kind: .feedbackDue)` | Messages, conversation pushed (feedback prompt inside) | `conversation_id`; `meetup_id` parsed but unused |
| anything else | `nil` | ignored | n/a |

Malformed identifiers produce a route with a `nil` id that still selects the destination tab.

## Presentation while the app is open

| Member is viewing | Arriving kind | Presentation |
|-------------------|---------------|--------------|
| Today (any state) | `introduction_ready` | none (`[]`); silent refresh |
| Messages with the referenced conversation pushed | `mutual_interest`, `new_message`, `meetup_reminder`, `feedback_due` with a matching `conversation_id` | none (`[]`); silent refresh |
| anything else | any of the five | `[.banner, .list, .sound]`; silent refresh |
| any | unknown kind | `[.banner, .list, .sound]` (the phone shows whatever the backend sent; the app never routes it) |

## Delivered-notification clearing

| Member views | Removed from the phone's list |
|--------------|------------------------------|
| Today in the ready state, or `IntroductionFlowView` | delivered notifications whose `introduction_id` equals the current introduction's id |
| `ConversationView` for conversation C | delivered notifications whose `conversation_id` equals C's id |

Matching is case-insensitive on the UUID string. Only identifiers are compared; the app never
reads the alert text.
