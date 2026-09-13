# Feature Specification: No False Affordances

**Feature Branch**: `004-no-false-affordances`

**Created**: 2026-09-13

**Status**: Draft

**Input**: User description: "Two controls in the app promise something the product does not do. After a Pass, a 'Share private feedback' link opens a sheet that ends with 'Feedback saved privately' although nothing is recorded anywhere. On the Work verification screen, a 'Verify a new work email' button shows a developer placeholder message and does nothing. Remove both until the product actually records pass reasons or reverifies a changed company; keep the honest text around them."

## Clarifications

### Session 2026-09-13

- Q: Should the Pass feedback sheet record reasons privately, keep its copy honest, or go away? → A: Remove the sheet. A Pass confirms and returns to Today with no feedback step; no new member data; the step can return as its own feature when matching can use it (User Story 1).
- Q: Should the "Verify a new work email" button become a real reverification flow or go away? → A: Remove the button and keep the explanatory text about changing companies; reverification returns as its own feature when it exists (User Story 2).

## User Scenarios & Testing *(mandatory)*

The product's promise is that the app tells the truth. Two places break it with controls rather than words. After a Pass, the confirmation invites the member to "Share private feedback"; the sheet collects a reason and says "Feedback saved privately", but nothing is saved, so the member has spent a thought and been thanked for a record that does not exist. On the Work verification screen, "Verify a new work email" answers a tap with "Company reverification flow is ready for backend connection", a sentence written for a developer. This feature removes both controls and leaves only what is true: a Pass confirms once and asks nothing further; the verification screen shows the verified company and explains what happens when a member changes companies.

Vocabulary: **Introduction**, **Pass**, **Verified**, **member**, **notice**.

### User Story 1 - A Pass Asks Nothing Further (Priority: P1)

A member passes on an introduction. The confirmation says the Pass is private and offers one action, back to Today. Nothing invites a reason, nothing claims a record, and nothing about the member's decision is kept beyond the Pass itself.

**Why this priority**: the Pass is the moment the product most needs to be believed. Thanking a member for feedback that was thrown away is a small lie at exactly the wrong time, and it collects a thought the product never uses.

**Independent Test**: in the demonstration build, pass on the introduction; confirm the confirmation shows the private-Pass copy and a single Return to Today action, that no sheet, reason list, or "saved" notice can be reached, and that Today returns to searching.

**Acceptance Scenarios**:

1. **Given** an introduction is open, **When** the member taps Pass and confirms, **Then** the confirmation shows "Thanks for deciding", the private-Pass sentence, and one action, Return to Today.
2. **Given** the Pass confirmation is shown, **When** the member looks for a way to give a reason, **Then** there is none; no sheet exists.
3. **Given** the member returns to Today, **Then** Today shows the searching state as before, and no notice about feedback appears.
4. **Given** the change ships, **Then** no copy anywhere in the app claims that pass feedback is saved.

---

### User Story 2 - Work Verification Says Only What Exists (Priority: P2)

A member opens Work verification from Profile. The screen shows the verified company, the work email, and the Verified mark, explains that verification means control of a company email, and explains what changing companies means. There is no control that promises a flow the product does not have.

**Why this priority**: a button that answers with a developer's sentence tells the member the product is unfinished and that its promises may not hold. The text alone is honest and complete for today's product.

**Independent Test**: open Profile, then Work verification; confirm the screen shows the company, the email, the Verified mark, the two explanatory texts, and no button; confirm no notice appears.

**Acceptance Scenarios**:

1. **Given** a signed-in member, **When** they open Work verification, **Then** they see the company, the work email, the Verified mark, and the two explanations.
2. **Given** Work verification is open, **When** the member looks for a way to verify a new email, **Then** there is no control, and the "Changing companies" text still explains that a new company must be verified before its badge appears.
3. **Given** the change ships, **Then** the developer sentence "Company reverification flow is ready for backend connection" appears nowhere in the app.

---

### Edge Cases

- A member mid-way through the old feedback sheet when the update installs: the sheet no longer exists on next launch; nothing was ever recorded, so nothing is lost.
- The demonstration build's previews that show the passed state show the confirmation with one action.
- The Work verification screen for a member whose company changed later is out of scope; the product does not detect that today and the screen does not claim to.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The Pass confirmation MUST show the private-Pass copy and exactly one action, Return to Today, on both the introduction screen and Today.
- **FR-002**: The app MUST NOT offer a pass-reason sheet, list, field, or link anywhere, and MUST NOT show any notice claiming pass feedback was saved.
- **FR-003**: Passing MUST keep its existing behaviour: the response is recorded once, is never observable by the other member, and Today returns to searching.
- **FR-004**: The Work verification screen MUST show the verified company, the work email, the Verified mark, the verification explanation, and the "Changing companies" explanation.
- **FR-005**: The Work verification screen MUST NOT show a control for reverifying or changing the work email, and the developer placeholder sentence MUST NOT appear anywhere in the app.
- **FR-006**: No new data about members is collected or stored by this feature, and nothing is removed from the backend.
- **FR-007**: `docs/UI_DESIGN_SPEC.md` and `docs/DESIGN_PHILOSOPHY.md` MUST describe the Pass confirmation and the Work verification screen as shipped; the design philosophy MUST state that a control does what its label says and that a placeholder for a flow that does not exist is removed, not shipped.
- **FR-008**: All remaining copy on both screens MUST use the canonical vocabulary.

### Key Entities *(include if feature involves data)*

None. No data is added, changed, or removed.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Zero controls in the app lead to a placeholder message or to a claim of a record that does not exist, verified by a search of the app's source for the two removed strings and by a manual pass of both screens.
- **SC-002**: The Pass flow keeps every existing test green (passing never creates a conversation; a Pass is unobservable by the other member).
- **SC-003**: The iOS workflow (unit tests and Release compile) is green on the pull request's head commit.
- **SC-004**: The design philosophy and the UI specification describe both screens exactly as shipped.

## Assumptions

- Pass reasons are not used by matching today and no backend endpoint accepts them; removing the sheet loses nothing.
- Changing companies is rare for the launch audience; explaining it in text is honest and sufficient until a reverification flow exists.
- The identity-row and profile states that mention "reverification required" in the design documents describe a future flow and stay as design notes; they are not shipped controls.

**Out of scope**

- Recording pass reasons (would add new member data and needs a retention rule and a Principle IV amendment).
- A reverification flow for a changed work email (its own feature: magic link to the new email, domain check, company update, badge change).
- Detecting a changed affiliation server-side.

### Constitution Check

- **Principles touched**: I (Today and the introduction keep one decision and one action; nothing is added), II (a Pass records one response and reveals nothing; removing the reason sheet removes a place where a decision could have been elaborated), IV (no new data; a thought the product never used is no longer collected), V (the single store is unchanged; two views lose a control each; no notice is raised by a removed control), VIII (see the Calm Technology check).
- **One-sided decisions**: none revealed; the Pass stays unobservable by the other member.
- **Retention**: no new operational data.
- **Refused surfaces**: none admitted.
- **Calm Technology check (Principle VIII)**: *Reduce or add attention?* Reduces: one fewer optional step after a decision, one fewer dead end in settings. *Inform or alarm?* Informs: the remaining text says what verification means and what changing companies means. *Can it live in the periphery?* Yes: nothing new is shown. *Help two people meet, or keep them in the app?* Neutral; it removes a detour after a Pass. *Fail quietly?* Nothing can fail; nothing is called. *Is there a simpler way?* This is the simplest honest state: remove what is not true. *Would a thoughtful professional find it normal?* Yes: being thanked for a decision and moved on is normal; being thanked for feedback nobody keeps is not.
