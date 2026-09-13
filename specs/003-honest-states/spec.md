# Feature Specification: Honest States

**Feature Branch**: `003-honest-states`

**Created**: 2026-09-12

**Status**: Draft

**Input**: User description: "Clear the constitution's recorded follow-ups so the app never lies by timing or by glyph: a Pass must never be observable by the other member (today the introduction disappears or errors the moment the other person passes); notices must show what they are (errors currently appear with the success checkmark and vanish on their own); and every save must say what happened (availability, preference, meetup, feedback, and safety saves currently keep their optimistic state after a failure). No new surface, no new notification, no new data kept about members."

## Clarifications

### Session 2026-09-12

- Q: After the other member passes, how long does a member who chose Interested keep waiting, and how does that wait end? → A: Until the introduction's existing expiry (seven days after it was created). The wait ends with the same "This introduction didn't work out" state, at the same moment, as an introduction the other member never answered. Shortening or otherwise changing the expiry after a Pass was rejected because any change correlated with the Pass reveals it (FR-001 to FR-004, User Story 1).
- Q: May the member who passed receive a new introduction before the old one expires? → A: Yes, subject to the existing introduction cadence (weekly by default): their passed introduction no longer counts as their active introduction. The waiting member keeps it as their one active introduction until expiry (FR-005, User Story 1 scenario 5).
- Q: When private feedback fails to submit, should the app keep the optimistic outcome and retry in the background, or keep the feedback sheet open? → A: Keep the sheet open with an inline error and Retry; nothing is recorded, no Connection is created, and the sheet closes only when the backend confirms (FR-021, User Story 3 scenario 10).
- Q: Do all failures persist until dismissed? → A: Only failed member actions do. A refresh that fails, which no member action waits on, shows an information notice that dismisses itself (FR-013, FR-016, User Story 2 scenario 5).

## User Scenarios & Testing *(mandatory)*

The product promises that a private decision stays private and that the app tells the truth. Three places break that promise today. First, a Pass is observable: when one member passes, the other member's introduction disappears at the next refresh, or answering Interested fails with "Introduction is no longer open", so the timing announces the rejection the product says it never sends. Second, the single notice channel draws every message, including errors, with the success checkmark and removes it after two seconds, so a failed save looks like a confirmed one. Third, availability, preference, meetup, feedback, and safety saves change the screen before the backend confirms and keep that change after a failure, so the member believes something was saved when it was not. This feature fixes all three without adding a surface, a notification, or any data about members.

Vocabulary: **Introduction**, **Interested**, **Pass**, **Connection**, **Meet**, **Available today**, **member**, **notice** (the app's single message channel).

### User Story 1 - A Pass Is Never Observable (Priority: P1)

Two members receive the same introduction. One of them passes. Nothing the other member can see, receive, or time reveals it: their introduction stays open exactly as long as it would have if the other member had never answered, Interested still works and leads to the private waiting state, and the introduction ends at its own expiry with the same neutral "This introduction didn't work out" state an unanswered introduction ends with. The member who passed is done with that introduction at once and can be introduced to someone else at their normal cadence.

**Why this priority**: the product's core promise is that responses are private and that passing carries no social cost. An observable Pass is a rejection notification by another name. Everything else in this feature is about honesty; this is about the promise that makes members willing to answer at all.

**Independent Test**: with two test members holding the same introduction, have one pass, then confirm the other's introduction is unchanged, that Interested succeeds and shows the waiting state, that nothing arrives on their phone, and that the introduction ends at its expiry with the neutral ended state. Repeat with the other member never answering and confirm every observable detail, including timing, is identical. Confirm the member who passed can be introduced to a third compatible member before the old introduction expires.

**Acceptance Scenarios**:

1. **Given** members A and B hold an open introduction and B has not answered, **When** A passes, **Then** B's Today keeps showing the introduction with the same expiry, and Interested and Pass remain available to B.
2. **Given** A has passed, **When** B chooses Interested, **Then** B sees the private waiting state with no error, exactly as if A had not answered.
3. **Given** B chose Interested first, **When** A passes, **Then** B's waiting state is unchanged, nothing arrives on B's phone, and B's Today still shows "Your response is private".
4. **Given** A passed and B is waiting, **When** the introduction reaches its expiry, **Then** the next time B looks at Today it shows "This introduction didn't work out" with a Continue action, in the same copy and at the same moment as an introduction A never answered.
5. **Given** A passed, **When** A's Today refreshes, **Then** A no longer sees the introduction, and A is eligible for a new introduction at A's normal cadence without waiting for the old introduction to expire.
6. **Given** both members pass, **When** the second Pass is recorded, **Then** the introduction closes at once and neither member sees anything further.
7. **Given** both members choose Interested, **When** the second response is recorded, **Then** the conversation opens and both are notified of mutual interest exactly as today.
8. **Given** B chose Interested after A passed, **When** B uses the app at any time before the expiry, **Then** no copy, badge, notification, or timing differs from the case where A never answered.
9. **Given** B was waiting and the introduction has ended, **When** B opens the app days later, **Then** the ended state shows once; Continue returns Today to searching; if a new introduction already exists, Today shows the new introduction and no ended state.
10. **Given** an introduction ends before B answered it, **When** B next looks at Today, **Then** Today shows the searching state with no ended message.
11. **Given** either member blocks the other, **When** the introduction is read, **Then** it is hidden for both, as today.

---

### User Story 2 - Notices Mean What They Show (Priority: P2)

Every message the app shows through its single notice channel now carries its kind. A success shows the success symbol and goes away on its own. An error shows the error symbol, stays until the member dismisses it or a newer notice replaces it, and offers Retry when the failed action can be retried. Information shows the information symbol and goes away on its own. Nothing is ever shown with a symbol that contradicts it.

**Why this priority**: a wrong symbol is a lie in the periphery. Members skim notices; the glyph is what they read. It follows the private Pass because it fixes appearance, while the Pass fixes a promise.

**Independent Test**: make one save fail and one succeed in the demonstration build; confirm the error notice uses the error symbol, stays until Dismiss, and offers Retry, and that the success notice uses the success symbol and dismisses itself. Confirm a failed refresh shows an information notice that dismisses itself. Confirm VoiceOver announces each notice.

**Acceptance Scenarios**:

1. **Given** a save fails, **When** the notice appears, **Then** it shows the error symbol, plain text saying what was not saved, a Dismiss control, and a Retry control when the action can be retried; it stays until Dismiss, Retry, or a newer notice.
2. **Given** a save succeeds, **When** the notice appears, **Then** it shows the success symbol and dismisses itself after about two seconds.
3. **Given** the app has something to tell that is neither a success nor a failure of a member action (for example a refresh that could not complete), **When** the notice appears, **Then** it shows the information symbol and dismisses itself.
4. **Given** a notice is showing, **When** another notice is raised, **Then** the newer one replaces it; at most one notice is ever visible.
5. **Given** the app cannot refresh (offline, for example) on launch, on activation, or on pull to refresh, **When** the refresh fails, **Then** an information notice "Couldn’t refresh right now." appears and dismisses itself; no error persists.
6. **Given** VoiceOver is on, **When** a notice appears, **Then** it is announced, its controls are reachable, and each control is at least 44 by 44 points; with Reduce Motion on, the notice appears without sliding.
7. **Given** any success message that exists today (preferences saved, connection removed, member blocked or unblocked, conversation ended, report submitted, feedback saved, membership activated), **When** it appears, **Then** its wording is unchanged and it appears only after the backend has confirmed the action.

---

### User Story 3 - Every Save Says What Happened (Priority: P3)

When a save fails, the screen goes back to what was true before the member acted, the notice says the action was not saved, and Retry does it again. Nothing on screen claims a state the backend does not hold. Success messages appear only after confirmation. Private feedback, which decides whether a Connection exists, is not shown as done until it is done: the feedback sheet stays open with an inline error and Retry.

**Why this priority**: an optimistic screen that stays after a failure is the most common way the app lies. It is ordered last because each save is independently small once the notice channel can carry kinds and retries.

**Independent Test**: in the demonstration build, make saves fail and confirm, for each action below, that the previous state returns, the error notice names the action, and Retry completes it with the success notice once saves succeed again.

**Acceptance Scenarios**:

1. **Given** the member turns on Available today and the save fails, **When** the failure is known, **Then** the availability banner is gone (the previous availability, if any, is back), the notice reads "Availability wasn’t saved." with Retry, and Retry saves it and shows the banner.
2. **Given** the member turns off availability and the save fails, **Then** the availability is still shown and the notice offers Retry.
3. **Given** the member saves introduction preferences and the save fails, **Then** the previous preferences are back, the notice reads "Introduction preferences weren’t saved." with Retry, and "Introduction preferences saved" appears only after a successful save.
4. **Given** the member saves meeting preferences and the save fails, **Then** the same holds with "Meeting preferences weren’t saved." and "Meeting preferences saved".
5. **Given** the member unblocks someone and the save fails, **Then** the member stays in the blocked list and the notice offers Retry; the "was unblocked" message appears only after confirmation.
6. **Given** the member blocks someone (from a conversation or a Connection) and the save fails, **Then** the conversation or Connection is back exactly as it was, the blocked list does not contain them, and the notice offers Retry.
7. **Given** the member removes a Connection and the save fails, **Then** the Connection is back in the list and the notice offers Retry.
8. **Given** the member ends a conversation and the save fails, **Then** the conversation is open again and the notice offers Retry.
9. **Given** the member sends a coffee plan and the plan save fails, **Then** the meeting details are not shown and the notice offers Retry; the accompanying message keeps its own "Not sent · Retry" state.
10. **Given** the member submits private feedback and the save fails, **Then** the sheet stays open with an inline error and Retry, no Connection is created, the conversation status is unchanged, and the sheet closes only after the backend confirms.
11. **Given** the member edits their profile and the save fails, **Then** the edited text stays on screen, the notice reads "Profile changes weren’t saved." with Retry, and Retry saves the current text.
12. **Given** the member answers Interested or Pass and the response fails, **Then** the buttons are back (as today) and the notice is an error carrying the backend's message.
13. **Given** the phone is offline, **When** any of the saves above is attempted, **Then** the same rollback, error notice, and Retry apply; nothing is queued silently.

---

### Edge Cases

- **Both members pass within the same second**: the second Pass finds the first and closes the introduction; neither is waiting, so nothing is shown.
- **A member passes, then the other blocks them**: the introduction is hidden for both (existing block rule); the waiting member's ended state does not appear because the block already removed the introduction from their Today.
- **The waiting member reinstalls the app before the expiry**: the app forgets that it was waiting, so at expiry Today returns to searching without the ended message. Accepted: the message is a courtesy; the promise is that nothing reveals a Pass.
- **A new introduction arrives at the same refresh the old one ended**: Today shows the new introduction; the ended message is skipped.
- **The member taps Interested on an introduction that has already expired (stale screen)**: the backend refuses, the buttons return, the error notice carries the backend's message, and the next refresh removes the introduction.
- **Retry while offline**: the same failure, rollback, and notice; the member can retry again or dismiss.
- **Two failures in a row from different actions**: the newer error replaces the older; only the newer Retry is offered. The older action stays rolled back; the member repeats it by hand.
- **A notice is showing when the member switches tabs or backgrounds the app**: an error stays; a success or information notice continues its own dismissal.
- **Sign-out while an error notice is showing**: the notice is cleared with the session.
- **Demonstration mode**: saves succeed by default; the failure paths are exercised through the mock backend's named failure trigger in tests and previews.

## Requirements *(mandatory)*

### Functional Requirements

**A Pass is never observable**

- **FR-001**: Recording a Pass MUST NOT change anything the other member can read about the introduction: it MUST stay open for them, with its original expiry, until the introduction expires or they respond.
- **FR-002**: An Interested response recorded after the other member passed MUST succeed and MUST return the same waiting outcome as an Interested response recorded while the other member has not answered. The introduction MUST stay open for the interested member until its expiry.
- **FR-003**: An introduction MUST end for a waiting member only through its expiry (the existing seven days from creation), through mutual interest, or through a block; never at the moment of the other member's Pass. The expiry MUST NOT be shortened, extended, or otherwise changed because of a Pass.
- **FR-004**: The app MUST show a waiting member whose introduction has ended the same "This introduction didn't work out" state, with the same copy and at the same moment, whether the other member passed or never answered. The state MUST be shown once, dismissed by Continue, and skipped when a new introduction already exists.
- **FR-005**: A member who passed MUST NOT see the introduction again, and it MUST NOT count as their active introduction: they are eligible for a new introduction at their normal cadence without waiting for the old one to expire. It MUST still count as the waiting member's one active introduction until expiry.
- **FR-006**: When both members have passed, the introduction MUST close at once.
- **FR-007**: Mutual interest, its conversation, and its notifications MUST be unchanged.
- **FR-008**: Nothing sent to a phone, shown in the app, or returned by the backend MUST differ between a passed and an unanswered introduction, including notification kinds, badges, copy, and timing.
- **FR-009**: The member who passed MUST NOT receive any notification about that introduction; the waiting member MUST NOT receive any notification at the expiry.

**Notices mean what they show**

- **FR-010**: Every notice MUST carry a kind: success, information, or error. The symbol and colour MUST match the kind and MUST NOT be the only indicator (the text carries the meaning).
- **FR-011**: A success or information notice MUST dismiss itself after about two seconds; an error notice MUST stay until the member dismisses it, retries, or a newer notice replaces it.
- **FR-012**: An error notice MUST offer a Dismiss control and MUST offer a Retry control when the failed action can be repeated; both MUST be at least 44 by 44 points and MUST be reachable by VoiceOver.
- **FR-013**: A refresh that fails MUST produce an information notice ("Couldn’t refresh right now."), never an error notice, because no member action waits on it.
- **FR-014**: At most one notice MUST be visible; a newer notice replaces the older.
- **FR-015**: A notice MUST be announced to VoiceOver when it appears, MUST honour Reduce Motion, and MUST use only the design tokens.
- **FR-016**: Existing success wordings MUST be kept; a success notice MUST appear only after the backend confirms the action (or at once for a purely local change, such as safety settings kept on the phone).

**Every save says what happened**

- **FR-017**: Availability (set and clear), introduction preferences, meeting preferences, unblock, block, remove Connection, end conversation, and coffee plan saves MUST restore the previous state when the save fails and MUST raise an error notice naming the action with Retry.
- **FR-018**: Retry MUST repeat the failed action with the same values; on success the state and the success notice MUST be exactly what a first-time success produces.
- **FR-019**: Profile saves MUST keep the member's edited text on screen after a failure and raise "Profile changes weren’t saved." with Retry; Retry MUST save the text as it is at that moment.
- **FR-020**: Introduction responses MUST keep their existing rollback and MUST raise the error kind with the backend's message.
- **FR-021**: Private feedback MUST NOT be applied until the backend confirms: the sheet MUST stay open on failure with an inline error and Retry, and no Connection, phase change, or tab change MUST happen before confirmation.
- **FR-022**: A coffee plan's meeting details MUST appear only after the plan is saved; the accompanying message keeps its own "Not sent · Retry" state.
- **FR-023**: Sign-out MUST clear any notice and any pending retry.
- **FR-024**: Failures MUST be raised through the store, never by a view keeping its own copy of the outcome, except the feedback sheet's inline error, which is local to the sheet by design.
- **FR-025**: The demonstration backend MUST provide a named failure trigger so every rollback and retry path is covered by deterministic tests.

**Quality**

- **FR-026**: Every surface this feature touches MUST meet the accessibility contract (VoiceOver label, hint, and value; Dynamic Type; 44 by 44 points; WCAG AA contrast in light and dark; Reduce Motion honoured; colour never the sole indicator; layout intact at 320 points).
- **FR-027**: All copy MUST use the canonical vocabulary and MUST NOT use match, compatibility, score, like, swipe, deck, streak, or urgency.

### Key Entities *(include if feature involves data)*

- **Introduction**: unchanged record. Its status now means: `offered` while at least one member has not passed and it has not expired; `mutual` after both chose Interested; `closed` only when both passed or on the existing safety paths; `expired` after its expiry. A member's own Pass hides it from that member only.
- **Introduction response**: unchanged record of one member's decision. A Pass no longer changes the introduction for the other member.
- **Notice**: the app's single message with a kind (success, information, error), text, and whether Retry is available. Never stored, never sent anywhere.
- **Pending retry**: the last failed member action, kept only until it is retried, dismissed, replaced, or the session ends.
- **Waited introduction**: the identifier of the introduction the member chose Interested on, kept on the phone per member so the ended state can be shown once at expiry; cleared by Continue, by a new introduction, by mutual interest, or with the account.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In backend tests, every value a member can read about an introduction (status, expiry, presence, waiting outcome, notifications) is identical between "the other member passed" and "the other member never answered" at every moment before the expiry, in 100% of cases.
- **SC-002**: A member who passed can be paired again before the old introduction's expiry, and a waiting member cannot, in 100% of matching test cases.
- **SC-003**: Zero notices are rendered with a symbol of a different kind than the notice, and zero error notices dismiss themselves, across the test suite and a manual pass of every notice-raising action.
- **SC-004**: For every save listed in FR-017, FR-019, and FR-021, a forced failure restores the previous state and offers Retry, and Retry produces the first-time success state, in 100% of test runs.
- **SC-005**: Zero success notices appear before the backend confirms the action (measured in tests by asserting the notice is absent until the mock completes).
- **SC-006**: Every notice passes the accessibility contract (announcement, control targets, Reduce Motion) before merge.

## Assumptions

- The expiry of seven days from creation already exists and is enforced by the matching run and the retention job; it is not changed. All introduction cadences are at least seven days, so holding a passed-on introduction until expiry costs the waiting member nothing compared with the unanswered case, and the member who passed gains nothing they would not have at their cadence anyway.
- The ended state is a phone-side courtesy: the phone remembers the introduction it was waiting on; if that memory is lost (reinstall), Today returns to searching quietly. Reporting "ended because the other passed" is never done, anywhere.
- Notices remain one channel owned by the store; no notice history, no stacking, no inbox.
- Message sending keeps its per-message "Not sent · Retry" state, which already satisfies the offline rule; reports keep their inline error in the report sheet.
- Safety settings kept only on the phone keep their immediate success notice.
- A refresh failure is informational because foreground refresh is the recovery path and no member action waits on it (constitution Principle V).
- No new operational data: no table, column, notification kind, or secret. The introduction status vocabulary keeps its four values with clarified meaning.

**Out of scope**

- Caching the last snapshot for an offline launch (the design philosophy notes it as not yet done; separate feature).
- Queuing saves for later delivery; every failed save is reported and retried by the member.
- Changing the introduction expiry, the cadence rules, or the matching quality rules.
- Any new notification, badge, sound, or notice history.

### Constitution Check

- **Principles touched**: I (Today still shows one thing; the ended state is one card with one action; no feed), II (a Pass is now unobservable by the other member; mutual interest remains the only gate; nothing reveals a one-sided decision by copy, presence, or timing), III (unchanged), IV (no new data about members; the phone keeps only the identifier of the introduction it waited on, per member, cleared with the account; no notification is added), V (the single notice channel gains a kind and a Retry; optimistic transitions roll back on failure as the principle requires; the state matrix gains honest offline and failure rows; `NT` component with tokens), VI (the backend keeps enforcing who can read an introduction; the read model hides a member's own Pass; the response RPC stays idempotent per member), VII (pgTAP for every backend rule, XCTest for every rollback, retry, and notice kind, deterministic failure trigger in the mock), VIII (calm: fewer lies, no new attention; failures are quiet but honest; the ended state appears once and asks for one tap).
- **One-sided decisions**: this feature exists to hide one. After it, the only observable outcomes of an introduction are mutual interest, expiry, and a block.
- **Retention**: no new operational table. Introductions and responses keep their existing rules. The phone-side waited-introduction identifier is cleared by Continue, a new introduction, mutual interest, or account deletion.
- **Refused surfaces**: none admitted.
- **Calm Technology check (Principle VIII)**: *Reduce or add attention?* Reduces it: no rejection moment exists any more, and errors stop pretending to be successes. *Inform or alarm?* Informs: an error says what was not saved and offers one retry; no red flashes, no modal. *Can it live in the periphery?* Yes: the notice is the existing banner; the ended state is one card on Today. *Help two people meet, or keep them in the app?* Neutral; it removes a reason to distrust the product. *Fail quietly?* Yes: rollbacks are silent, refresh failures are informational, and only a member's own failed action persists until they act. *Is there a simpler way?* The expiry mechanism already exists; hiding the Pass is a change of what the read model shows, not new machinery; notices reuse the existing channel. *Would a thoughtful professional find it normal?* Yes: not being told someone passed on you, and being told plainly when something was not saved, is how considerate tools behave.
