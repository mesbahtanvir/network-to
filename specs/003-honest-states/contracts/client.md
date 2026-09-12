# Client Contracts: Honest States

## Notices (`AppStore`)

```swift
@Published private(set) var notice: AppNotice?

func presentSuccess(_ text: String)                       // auto-dismisses (~2 s)
func presentInformation(_ text: String)                   // auto-dismisses (~2 s)
func presentError(_ text: String, retry: (@MainActor () -> Void)? = nil)   // persists
func dismissNotice()                                      // clears the notice and any pending retry
func dismissNotice(id: UUID)                              // used by the auto-dismiss timer; no-op if replaced
func retryFailedAction()                                  // runs the pending retry once and clears the notice
```

Rules: one notice at a time (a newer replaces the older and drops the older retry);
`signOut()` and `deleteAccount()` clear the notice and the retry; `transientMessage` no longer
exists. Views raise notices only through these methods.

## `NTInlineNotice` (`NetworkTo/DesignSystem/Components.swift`)

`NTInlineNotice(notice:dismiss:retry:)`: symbol and tint by kind (`checkmark.circle.fill` /
`NTColor.success`, `info.circle.fill` / `NTColor.accent`, `exclamationmark.circle.fill` /
`NTColor.destructive`), the text in `NTColor.textPrimary`, and for errors a Retry button
(when `retry` is given) and a Dismiss button, each at least 44 pt. The view announces the
text through `AccessibilityNotification.Announcement` on appear. `MainTabView` renders it
in the existing top overlay, animates only when Reduce Motion is off, and starts the
auto-dismiss timer only for non-persisting notices.

## Saves (`AppStore`)

Every method below keeps its signature unless noted; each captures the previous state,
applies the change, and on failure restores it and raises the error with a retry that calls
the same method with the same values.

| Method | Failure notice | Success notice (after confirmation) |
|--------|----------------|--------------------------------------|
| `setAvailability(area:window:)` | "Availability wasn’t saved." | none (banner is the confirmation) |
| `clearAvailability()` | "Availability wasn’t saved." | none |
| `saveNetworkingPreferences(_:)` | "Introduction preferences weren’t saved." | "Introduction preferences saved" |
| `saveMeetingPreferences(_:)` | "Meeting preferences weren’t saved." | "Meeting preferences saved" |
| `unblock(_:)` | "<name> wasn’t unblocked." | "<name> was unblocked" |
| `block(_:)`, `blockCurrentPerson()` | "<name> wasn’t blocked." | "<name> was blocked" |
| `removeConnection(_:)` | "Connection wasn’t removed." | "Connection removed" |
| `endCurrentConversation()` | "Conversation wasn’t ended." | "Conversation ended" |
| `planMeetup(detail:)` (pessimistic) | "Coffee plan wasn’t sent." | none (details appear) |
| `updateMemberContext(...)`, `applyResumeSuggestions(_:)` (edits kept) | "Profile changes weren’t saved." | none |
| `recordFeedback(_:stayConnected:) async -> Bool` (pessimistic) | returns `false`; the sheet shows "Feedback wasn’t submitted." with Retry | none; state applied on `true` |
| `respondInterested()`, `passIntroduction()` | backend message (no retry; buttons return) | none |
| `submitReport(category:note:)` | throws (sheet shows it) | "Report submitted privately" |
| `saveSafetyPreferences(_:)` (local) | n/a | "Safety settings saved" at once |
| `refreshFromBackend()` | information "Couldn’t refresh right now." | none |

`MockBackendService` gains `setSavesFail(_ value: Bool)` (every save method throws
`MockServiceError.requestFailed` while set) and `init(latency:isLive:hasSession:introductionAvailable:)`
where `introductionAvailable: false` serves a snapshot without an introduction.

## Ended introduction (`AppStore`)

```swift
private(set) var waitedIntroductionID: UUID?
```

- `respondInterested()` remembers the introduction id when the backend answers `waiting`; a
  refresh that reports `waitingForReciprocalInterest` remembers the current id.
- A refresh with no conversation and no introduction while the memory is set sets
  `phase = .notMutual` (the existing ended state); `lookAgain()` clears the memory and
  returns to `.searching`.
- A refresh with a different introduction, or a conversation, clears the memory.
- `deleteAccount()` clears it with the other member memory.

## Views

- `MainTabView`: overlay renders `NTInlineNotice`; auto-dismiss only when `!notice.persists`.
- `MessagesView` feedback sheet: Submit becomes async; on `false` it shows an inline
  `NTInlineNotice`-styled error row "Feedback wasn’t submitted." and the button reads
  "Retry"; the sheet closes only on `true`.
- `MembershipView`, `ProfileView`, `PreferenceViews`, `IntroductionFlowView`: replace direct
  `transientMessage` writes with `presentSuccess` / `presentInformation`.
- `TodayView` and `IntroductionFlowView`: the ended state's copy is unchanged.
