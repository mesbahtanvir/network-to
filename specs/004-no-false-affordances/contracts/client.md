# Client Contracts: No False Affordances

## Removed surfaces

- `IntroductionFlowView.passed`: the "Share private feedback" link and the
  `PassFeedbackView` sheet are removed. The state keeps `NTEmptyState` ("Thanks for deciding",
  "Your pass is private. We’ll keep looking for someone worthwhile.") and one primary action,
  **Return to Today**, which dismisses to Today.
- `WorkVerificationView`: the "Verify a new work email" button is removed. The "Changing
  companies" section keeps its explanatory text.

## Unchanged

- `AppStore.passIntroduction()`, `AppStore.lookAgain()`, `TodayView.passedState`.
- The notice channel; no notice is raised by either screen after this change.
- No `BackendService` requirement changes; no migration.
