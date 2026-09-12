# Data Model: Honest States

**Feature**: 003-honest-states | **Date**: 2026-09-12

## Backend (existing tables, clarified semantics)

### `public.introductions.status`

| Value | Meaning after this feature |
|-------|----------------------------|
| `offered` | Open for at least one member. A member who passed no longer sees it; the other member sees it unchanged until `expires_at`. |
| `mutual` | Both chose Interested; a conversation exists. Unchanged. |
| `closed` | Both members passed, or an existing safety path closed it. Never set by a single Pass. |
| `expired` | `expires_at` passed while `offered`; set by the matching run and the retention job. Unchanged. |

### `public.introduction_responses`

Unchanged: one row per member per introduction (`decision` `interested` or `pass`). A Pass
row is what hides the introduction from its author and frees them for matching.

### `private.introduction_passed_by(introduction uuid, member uuid) → boolean`

`exists` on the responses table for `decision = 'pass'`. Private, revoked from every role,
used by the read model, the response RPC, and matching.

### Read model `public.get_current_introduction()`

Adds `and not private.introduction_passed_by(i.id, caller)` to the existing filter. Fields are
unchanged (`status`, `expires_at`, `your_response`, `person`, reasons, `meeting_context`).

## Client value types

### `AppNotice` (`NetworkTo/Models/Models.swift`)

```swift
struct AppNotice: Equatable, Sendable, Identifiable {
    enum Kind: Sendable { case success, information, error }
    let id: UUID
    let kind: Kind
    let text: String
    let canRetry: Bool
    var persists: Bool { kind == .error }
}
```

## Store state (`AppStore`)

| Property | Type | Access | Changed by |
|----------|------|--------|------------|
| `notice` | `AppNotice?` | `@Published private(set)` | `presentSuccess`, `presentInformation`, `presentError`, `dismissNotice`, `retryFailedAction`, `signOut`, `MainTabView`'s auto-dismiss via `dismissNotice(id:)` |
| `pendingRetry` | `(@MainActor () -> Void)?` | `private` | `presentError(_:retry:)`, `retryFailedAction`, `dismissNotice`, `signOut` |
| `waitedIntroductionID` | `UUID?` | `private(set)` | `respondInterested` (waiting result), refresh (`waitingForReciprocalInterest`), `lookAgain`, a new introduction, mutual interest, deletion |

`transientMessage` is removed.

## Phone memory (`UserDefaults`, keyed by `member.id`)

| Key | Value | Written | Cleared |
|-----|-------|---------|---------|
| `networkto.introduction.waited.<memberID>` | introduction id | when the member's Interested response is recorded or a refresh reports waiting | Continue (`lookAgain`), a different introduction arriving, mutual interest, account deletion |

## State transitions

```text
Introduction (backend):
  offered --A passes--> offered (hidden from A; B unchanged)
  offered --A passes, B had passed--> closed
  offered --B interested after A passed--> offered, B waiting (RPC: waiting)
  offered --both interested--> mutual (+ conversation, + mutual_interest events)
  offered --expires_at reached--> expired (matching run / retention)

Phone (member B waiting):
  waiting --refresh: introduction absent, memory set--> ended (.notMutual) --Continue--> searching
  waiting --refresh: different introduction--> ready (memory cleared)
  waiting --refresh: conversation--> conversation (memory cleared)

Notice:
  none --success/information--> shown --~2 s--> none
  none --error(retry?)--> shown --Dismiss--> none
                                 --Retry--> action runs again --> success or a fresh error
                                 --newer notice--> replaced

Save (optimistic):
  previous --apply--> optimistic --confirmed--> optimistic (+ success notice)
                                  --failed--> previous (+ error notice with Retry)
Save (pessimistic: coffee plan, feedback):
  previous --confirmed--> applied
           --failed--> previous (+ error; feedback: inline in the sheet)
```
