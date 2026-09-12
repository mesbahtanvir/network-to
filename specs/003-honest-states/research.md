# Research: Honest States

**Feature**: 003-honest-states | **Date**: 2026-09-12

## 1. How a Pass leaks today

**Finding**: `respond_to_introduction` sets `status = 'closed'` on any Pass. The other member's
`get_current_introduction` only returns `offered` or `mutual` rows, so their introduction
vanishes at the next refresh; if they tap Interested first, the RPC raises "Introduction is
no longer open". The mock backend's `.notMutual` state ("This introduction didn't work out")
is what the constitution's migration plan describes; the live leak is by disappearance and by
error, at the exact moment of the Pass.

**Decision**: a Pass records the response and changes nothing the other member can read. The
introduction stays `offered` with its original `expires_at`; it becomes `closed` only when both
members have passed; it becomes `expired` at its expiry through the existing matching-run and
retention updates; `mutual` is unchanged. The read model hides an introduction from a member
who passed on it (`private.introduction_passed_by`). An Interested response after a Pass
returns `waiting`.

**Rejected**: shortening the expiry after a Pass (any change correlated with the Pass is
observable); returning `not_mutual` to the interested member with delayed display (still a
per-member signal the client would have to hide); a random early close (statistically
observable and needlessly complex).

## 2. What the passer sees and when they can be matched again

**Decision**: the passer's own Pass hides the introduction from them immediately (their
Today returns to searching after "Thanks for deciding"). In matching, an introduction counts as
a member's active introduction only if its status is `offered` or `mutual` and that member has
not passed on it, so the passer is eligible again at their cadence. The cadence rule
(`created_at` within the frequency window) is unchanged, so with a weekly cadence the passer
is eligible seven days after the introduction was created, which coincides with its expiry.
The waiting member keeps it as their active introduction until then.

**Rejected**: letting the waiting member receive a second introduction while waiting (breaks
"one introduction at a time" and would itself reveal the Pass).

## 3. The ended state on the phone

**Decision**: the store remembers the id of the introduction it chose Interested on, per member,
in `UserDefaults` (`networkto.introduction.waited.<memberID>`). When a refresh returns no
introduction and the memory is set, the phase becomes `.notMutual` (the existing ended state,
shown once until Continue). When a refresh returns a different introduction, the memory is
cleared and the new introduction shows. Mutual interest clears it; account deletion clears it.
Nothing about the reason for the end is known to the phone.

**Rejected**: a backend "last outcome" read model (new state and an acknowledgement RPC for a
courtesy); showing the ended card before a new introduction (two steps where one is the
useful one).

## 4. Notice model

**Decision**: `AppNotice { id, kind (success | information | error), text, canRetry }` owned by
`AppStore` as `notice`. Success and information dismiss themselves after about two seconds
(`MainTabView` keeps the timer); errors persist until Dismiss, Retry, or replacement. The
store keeps the pending retry as a `@MainActor` closure captured weakly; `retryFailedAction()`
runs it and clears it. `NTInlineNotice` renders the kind with `NTColor.success`, `NTColor.accent`,
and `NTColor.destructive`, announces itself through `AccessibilityNotification.Announcement`,
and honours Reduce Motion by dropping the slide transition. Refresh failures are information.

**Rejected**: a queue of notices (the constitution's single channel); an `Equatable` enum of
retryable actions (every save would need a case; the closure keeps each action's retry next
to its rollback); a persistent error for refresh failures (nagging with nothing to do).

## 5. Rollback and retry pattern

**Decision**: one private helper on the store runs an optimistic save: capture the previous
state, apply the change, run the backend call, on success raise the success notice (if any),
on failure restore the previous state and raise the error notice with a retry that calls the
same store method with the same values. Snapshots cover every field the action touched
(`block` touches the blocked list, the Connections list, the conversation flags, and the
phase). Coffee plans and private feedback are pessimistic because their success changes what
the other member sees or creates a Connection; the plan's details appear after confirmation
and the feedback sheet closes after confirmation. Profile saves keep the member's text and
retry with the current text.

**Rejected**: queuing failed saves for later delivery (silent state the member cannot see;
out of scope by the spec); rolling back profile edits (loses typed work).

## 6. Test strategy

**Decision**: the mock backend gets explicit save implementations behind `setSavesFail(_:)`,
a named failure trigger, plus an `introductionAvailable` flag so a snapshot without an
introduction can be served for the ended-state tests. Store tests await the store's async
entry points or poll with the existing `eventually` helper for fire-and-forget saves. The
backend rules are covered by a dedicated pgTAP file that mirrors the matching fixture in
`production_behavior.test.sql` (three Toronto members created through `auth.users`).

**Rejected**: driving failures by special input values for every save (a flag is one trigger
for all saves; message sending keeps its "fail" body trigger).

## Risks carried into implementation

- `generate_one_introduction` is redefined in full; a copy error would change matching
  quality. The pgTAP file asserts the passer/waiting rule and the existing matching test still
  runs.
- The waited-introduction memory is a courtesy; a reinstall loses it and Today returns to
  searching without the ended message (accepted in the spec).
- Persisting error notices changes what the hosted test run shows if a refresh fails; refresh
  failures are information notices, so nothing persists in CI.
