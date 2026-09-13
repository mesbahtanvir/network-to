# Research: No False Affordances

**Feature**: 004-no-false-affordances | **Date**: 2026-09-13

## 1. The pass feedback sheet

**Finding**: `IntroductionFlowView`'s passed state offers "Share private feedback", which
presents `PassFeedbackView`: five fixed reasons, Skip, and Submit. Submit raises the success
notice "Feedback saved privately" and dismisses. No store method, backend call, table, or RPC
receives the reason; nothing is recorded on the phone either. Today's own passed state
(`TodayView.passedState`) never offered the sheet, so the two surfaces already disagreed.

**Decision** (product owner, 2026-09-13): remove the link, the sheet, and its view state. A Pass
confirms once with one action. Recording pass reasons would add data about members' decisions
and needs a retention rule and a Principle IV amendment; it is a separate feature if matching
ever uses it.

**Rejected**: keeping the sheet with honest copy (a step that leads nowhere is still a step);
recording reasons now (new member data without a consumer).

## 2. The reverification button

**Finding**: `WorkVerificationView` shows "Verify a new work email", whose action raises the
information notice "Company reverification flow is ready for backend connection". No flow
exists on the client or the backend. The surrounding text (verification means control of a
company email; a new company must be verified before its badge appears) is accurate.

**Decision** (product owner, 2026-09-13): remove the button, keep the text. Reverification is a
feature of its own: a magic link to the new address, the domain hook, a company update, and
the badge change, with pgTAP for the trust rules.

**Rejected**: leaving the button as a signpost (a control must do what its label says).

## 3. Governance

**Finding**: `docs/DESIGN_PHILOSOPHY.md` says a Pass "may invite optional private feedback
afterwards". The constitution makes that document's concrete rules part of the constitution
for versioning, so changing the sentence is an amendment.

**Decision**: amend to 1.5.0 (MINOR): the Pass confirms once and asks nothing further, and the
philosophy gains the rule that a control does what its label says and a placeholder for a
flow that does not exist is removed rather than shipped. Nothing loosens.

## Risks carried into implementation

- None functional: two views lose a control each; the store, models, backend, and tests are
  untouched. The iOS workflow's compile is the check that nothing referenced the removed view.
