# Implementation Plan: No False Affordances

**Branch**: `004-no-false-affordances` | **Date**: 2026-09-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/004-no-false-affordances/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Remove two controls that promise what the product does not do: the "Share private feedback"
link and its sheet after a Pass (which claimed to save a reason that was never recorded), and
the "Verify a new work email" button on Work verification (which answered with a developer
placeholder). The Pass confirmation keeps its private-Pass copy and one action; Work
verification keeps its explanatory text. Documents and the constitution describe the shipped
behaviour, and the design philosophy gains the rule that a control does what its label says.
No store, model, backend, or test logic changes.

## Technical Context

**Language/Version**: Swift 6 (SwiftUI, iOS 17+, strict concurrency complete)

**Primary Dependencies**: none new

**Storage**: none

**Testing**: existing XCTest suites (passing behaviour is covered by `AppStoreTests` and
`introduction_privacy.test.sql`); the iOS workflow's unit tests and Release compile on the PR

**Target Platform**: iPhone iOS 17.0+

**Project Type**: Mobile app (existing layout)

**Performance Goals**: n/a

**Constraints**: no new data about members (FR-006); the Pass flow's behaviour is unchanged
(FR-003); canonical vocabulary (FR-008)

**Scale/Scope**: 2 edited Swift files, 2 documents, constitution amendment 1.5.0

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Principles touched: I, II, IV, V, VIII.

- **I (one introduction, never a feed)**: the Pass confirmation keeps one action; nothing is
  added to Today or Profile. PASS.
- **II (reciprocal interest is the only gate)**: the Pass response is recorded exactly as
  before and stays unobservable; a place where a member elaborated a decision for nobody is
  removed. PASS.
- **IV (members own their data)**: no data is collected; a thought the product never used is
  no longer asked for. PASS.
- **V (native, accessible, single store)**: the store is untouched; two views lose a control;
  no notice is raised by a removed control; remaining controls keep tokens and 44 pt targets.
  PASS.
- **VII (deterministic tests, CI-only deploys)**: there is no new behaviour to protect; the
  existing Pass tests stay green and the iOS workflow must be green on the head commit. PASS.
- **VIII (calm technology)**: see the check below. PASS.

Gate details required by the plan gate: no new table, RPC, Edge Function, notification,
scheduled job, or secret. No RLS, grant, privilege assertion, push payload, idempotency key,
or retention rule changes.

### State matrix and offline states

| Surface | Resting | In progress | Success | Recoverable failure | Terminal | Offline |
|---------|---------|-------------|---------|---------------------|----------|---------|
| Pass confirmation (introduction screen and Today) | "Thanks for deciding", private-Pass sentence, Return to Today | n/a (nothing is called) | Today returns to searching | Unchanged: a failed Pass response returns the buttons with the backend's message (feature 003) | n/a | Same as failure |
| Work verification | Company, work email, Verified mark, two explanations | n/a | n/a | n/a | n/a | Reads local state only |

### Tests this plan adds

None. The removed controls had no logic; `AppStoreTests.testPassingNeverCreatesConversation`
and `introduction_privacy.test.sql` continue to cover passing. The source check in
`quickstart.md` and the iOS workflow's Release compile confirm the removal.

### Calm Technology check (Principle VIII)

- *Reduce or add attention?* Reduces: one fewer optional step, one fewer dead end.
- *Inform or alarm?* Informs; the remaining text is accurate.
- *Can it live in the periphery?* Nothing new is shown.
- *Help two people meet, or keep them in the app?* Neutral; a detour after a Pass is gone.
- *Fail quietly?* Nothing can fail.
- *Is there a simpler way?* This is the simplest honest state.
- *Would a thoughtful professional find it normal?* Yes.

## Project Structure

### Documentation (this feature)

```text
specs/004-no-false-affordances/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/client.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
NetworkTo/
├── Features/Introduction/IntroductionFlowView.swift   # edit: passed state loses the link, sheet, state, and PassFeedbackView
└── Features/Profile/PreferenceViews.swift             # edit: WorkVerificationView loses the button

docs/UI_DESIGN_SPEC.md, docs/DESIGN_PHILOSOPHY.md, .specify/memory/constitution.md   # edit
```

**Structure Decision**: the existing layout; removals only.

## Complexity Tracking

No constitution violations and no added complexity.

## Operator steps outside the repository

None.
