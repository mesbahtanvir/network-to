# Data Model: No False Affordances

**Feature**: 004-no-false-affordances | **Date**: 2026-09-13

No backend data, client model, store property, or phone memory is added, changed, or
removed. The feature removes two pieces of view-local state:

| Removed | Where | Why |
|---------|-------|-----|
| `showPassFeedback` (`@State Bool`) and `PassFeedbackView` | `IntroductionFlowView` | The sheet recorded nothing. |
| "Verify a new work email" button action | `WorkVerificationView` | The flow does not exist. |

`AppStore.passIntroduction()`, `lookAgain()`, and the introduction response contract are
unchanged.
