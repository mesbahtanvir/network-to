# Tasks: No False Affordances

**Input**: Design documents from `/specs/004-no-false-affordances/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: No new tests; the removed controls had no logic. The existing Pass tests and the iOS
workflow's Release compile are the gate (plan.md).

**Organization**: one story per removed control, then documents and governance.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2)
- Include exact file paths in descriptions

## Path Conventions

Mobile app: `NetworkTo/`, `docs/`, `.specify/memory/`.

---

## Phase 1: Setup

- [X] T001 Point `.specify/feature.json` at `specs/004-no-false-affordances` and write the spec, checklist, research, data model, contract, quickstart, and plan

---

## Phase 2: User Story 1 - A Pass Asks Nothing Further (Priority: P1) 🎯 MVP

- [X] T002 [US1] In `NetworkTo/Features/Introduction/IntroductionFlowView.swift` remove the `showPassFeedback` state, the "Share private feedback" button, the `.sheet` presenting `PassFeedbackView`, and the `PassFeedbackView` struct; keep the confirmation copy and Return to Today

**Checkpoint**: a Pass confirms with one action on both the introduction screen and Today

---

## Phase 3: User Story 2 - Work Verification Says Only What Exists (Priority: P2)

- [X] T003 [P] [US2] In `NetworkTo/Features/Profile/PreferenceViews.swift` remove the "Verify a new work email" button from `WorkVerificationView`, keeping the "Changing companies" text

**Checkpoint**: Work verification shows the company, the email, the Verified mark, and the two explanations only

---

## Phase 4: Polish & Cross-Cutting Concerns

- [X] T004 [P] Update `docs/UI_DESIGN_SPEC.md` (T-04 and P-05 rows, flow 6.2 Pass bullet) and `docs/DESIGN_PHILOSOPHY.md` (section 1 Pass sentence; section 2 rule that a control does what its label says)
- [X] T005 Amend `.specify/memory/constitution.md` to 1.5.0 (MINOR): Principle VIII gains the placeholder rule; the migration plan records the two removals; version line updated
- [ ] T006 Run the source check in `quickstart.md`, check constitution line lengths, commit, push, open the pull request, and confirm the iOS workflow is green on the head commit

---

## Dependencies & Execution Order

- T001 first; T002 and T003 in parallel; T004 and T005 in parallel after them; T006 last.

## Implementation Strategy

1. Remove the two controls; nothing else in the app changes.
2. Make the documents and the constitution describe the shipped screens.
3. Let the iOS workflow prove the compile.
