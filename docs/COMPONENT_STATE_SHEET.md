# network.to component and state sheet

Status: **Proposed**  
Version: 0.2  
Last updated: 2026-09-04  
Companion: `UI_DESIGN_SPEC.md`

This document defines the reusable SwiftUI-level components and states required to implement the V1 interface consistently. It does not replace Apple platform components where a native control already solves the problem.

## 1. Naming and implementation rules

- Product components use the `NT` prefix in Swift, such as `NTVerifiedCompanyLine`.
- Prefer composition around native `NavigationStack`, `TabView`, `Form`, `List`, `Button`, `TextField`, `SecureField`, `Toggle`, `Picker`, `Menu`, `Sheet`, and `Alert`.
- Never recreate native accessibility, focus, keyboard, or navigation behavior merely for visual styling.
- All components must support Dynamic Type, VoiceOver, light/dark appearance, Increased Contrast, Reduce Motion, and Reduce Transparency.
- Product color, type, spacing, radius, and motion values come from the design tokens in `UI_DESIGN_SPEC.md`.
- No component may introduce a feed, global people search, cold messaging, compatibility score, swipe response, or dating-style interaction.

## 2. Foundations

### 2.1 Semantic colours

| Swift token | Light | Dark | Meaning |
| --- | --- | --- | --- |
| `NTColor.background` | `#F8F4EE` | `#171815` | Warm paper canvas |
| `NTColor.surface` | `#FFFDF9` | `#20211D` | Content and sheets |
| `NTColor.surfaceSecondary` | `#EEE8DF` | `#292A25` | Quiet controls/context |
| `NTColor.textPrimary` | `#292821` | `#F5F0E8` | Primary content |
| `NTColor.textSecondary` | `#66665E` | `#BBB8AF` | Secondary content |
| `NTColor.separator` | `#E4DBD0` | `#3A3B35` | Soft structural boundary |
| `NTColor.accent` | `#526B57` | `#B7CEB9` | Selected and conversational emphasis |
| `NTColor.accentStrong` | `#354C3D` | `#BFD3C1` | Primary action |
| `NTColor.meetingContext` | `#BD7053` | `#DC967A` | Coffee and human momentum |
| `NTColor.success` | `#2E7350` | `#6BC18F` | Verified/mutual/complete |
| `NTColor.warning` | `#8A641D` | `#E0B55C` | Expiry/attention |
| `NTColor.destructive` | `#B42332` | `#FF7A88` | Safety/destructive action |
| `NTColor.companyMarkBacking` | `#F3EEE6` | `#F3EEE6` | Tile behind company marks and monograms (fixed in both appearances) |
| `NTColor.companyMarkGlyph` | `#354C3D` | `#354C3D` | Company monogram characters |

Meaning is always paired with text or a symbol. Colour is never the only state indicator.

### 2.2 Spacing

| Token | Value | Typical use |
| --- | --- | --- |
| `NTSpacing.xxs` | 4 pt | Icon/text micro-gap |
| `NTSpacing.xs` | 8 pt | Compact internal gap |
| `NTSpacing.sm` | 12 pt | Row internals |
| `NTSpacing.md` | 16 pt | Standard padding/list inset |
| `NTSpacing.lg` | 20 pt | Narrative screen inset |
| `NTSpacing.xl` | 24 pt | Section separation |
| `NTSpacing.xxl` | 32 pt | Major transition |
| `NTSpacing.xxxl` | 40 pt | Sparse hero separation |

### 2.3 Shape

| Token | Value | Use |
| --- | --- | --- |
| `NTRadius.control` | 12 pt continuous | Compact controls |
| `NTRadius.field` | 16 pt continuous | Fields and primary buttons |
| `NTRadius.context` | 18 pt continuous | Context/notice surface |
| `NTRadius.card` | 20 pt continuous | Reusable product surface |
| `NTRadius.hero` | 28 pt continuous | Today hero only |

### 2.4 Typography

Use native Dynamic Type styles. Product components may change weight but not freeze point sizes.

| Role | SwiftUI style | Weight |
| --- | --- | --- |
| Screen title | `.largeTitle` | Semibold |
| Person/outcome title | `.title` | Semibold |
| Section heading | `.title3` | Semibold |
| Row title | `.headline` | Semibold |
| Body | `.body` | Regular |
| Metadata | `.subheadline` | Regular |
| Verification/timing | `.caption` | Medium |

## 3. Navigation components

### `NTMainTabView`

Native `TabView` with exactly four destinations in this order:

1. Today — `sun.max`
2. Connections — `person.2`
3. Messages — `message`
4. Profile — `person.crop.circle`

States:

- selected;
- unselected;
- notification badge for unread mutual-only messages;
- accessibility label and value.

Constraints:

- No centre action, Explore, Search, Feed, or floating people action.
- Badge counts apply only to actionable unread items; never to encourage engagement.

### `NTNavigationHeader`

Native navigation title plus optional leading back action and one trailing action.

Variants:

- large title for tab roots;
- inline title for Introduction, Conversation, and settings;
- centred professional identity in Conversation.

## 4. Trust and professional identity

### `NTProfessionalIdentity`

Anatomy:

- optional monogram or post-mutual photo;
- real name;
- member-provided role;
- company name;
- `NTVerifiedCompanyLine`;
- optional city or context.

Variants:

- introduction: monogram only, no profile photo;
- message row: compact identity;
- connection row: compact identity plus connection context;
- profile: expanded identity.

States:

- verified affiliation;
- affiliation reverification required;
- unknown-company review pending;
- company changed.

### `NTVerifiedCompanyLine`

Anatomy:

- `checkmark.seal.fill`;
- `NTCompanyMark` (mark or company monogram) immediately before the company name;
- company name or “Work email verified”;
- disclosure action.

Disclosure text:

> Verified through access to a company email. This does not imply employer endorsement.

States:

- verified;
- pending review;
- reverification required;
- unverified/ineligible.

Accessibility:

- VoiceOver reads the complete meaning, not only “verified.”
- Seal is decorative when the adjacent text carries meaning.

### `NTCompanyMark`

Anatomy:

- square tile the height of the accompanying text line, `NTColor.companyMarkBacking`, 25% continuous radius, one-eighth inner padding;
- the company's published icon fitted inside, or the company monogram in `NTColor.companyMarkGlyph`.

Placement: inline in the text it accompanies (`CompanyMarkTile.text` and `NTRoleAndCompanyLine`), immediately before the company name, so long names wrap as ordinary text at every Dynamic Type size and at 320 pt.

States:

- mark (a served mark this phone holds);
- company monogram (no mark published, withheld, company not approved, affiliation not verified, not yet downloaded, offline, or failed).

There is no loading, error, or retry state and no animation when a monogram becomes a mark. A mark is fetched only from the project's own storage host, cached in the Caches directory, and cleared at sign-out and after confirmed account deletion.

Accessibility:

- decorative (`accessibilityHidden`); the company name and existing verification wording carry the meaning;
- monogram glyph on the tile 8.07:1; tile on the dark surface 14.02:1.

### `NTVisibilityLabel`

Compact text treatment used in onboarding review.

Variants:

- `Introduction` with `eye`;
- `Coarse only` with `mappin.and.ellipse`;
- `Only you` with `lock`;
- `Private` with `shield`.

The label describes who can access a field; it never behaves as an unexplained badge.

### `NTProfessionalTopic`

Short professional topic label used for scanning.

States:

- display only;
- selectable in onboarding;
- selected;
- unselected;
- custom topic;
- validation/maximum reached.

Constraints:

- Sentence case.
- Not styled as colourful social-interest badges.
- Selected state uses border, background, and accessibility value—not colour alone.

## 5. Onboarding controls

### `NTOnboardingProgressHeader`

Anatomy:

- native back button;
- “Step X of Y”;
- thin determinate progress bar;
- optional Skip only for clearly optional steps such as résumé enhancement.

States:

- first required step;
- intermediate;
- optional;
- final review.

### `NTLabeledField`

Wraps native field controls with:

- visible label;
- optional leading symbol;
- field;
- supporting or privacy text;
- validation message.

States:

- empty;
- focused;
- populated;
- invalid;
- disabled;
- loading/validating.

Validation is specific and actionable. Example: **Use a qualifying company email. Consumer email addresses are not eligible for V1.**

### `NTOTPField`

Native one-time-code field with `textContentType(.oneTimeCode)`.

States:

- empty;
- partial;
- complete;
- verifying;
- invalid;
- expired;
- resend cooldown.

Requirements:

- Supports paste and AutoFill.
- Does not force focus across six custom fields.
- Announces error without clearing the code unexpectedly.

### `NTChoiceRow`

Full-width choice with optional icon, title, explanation, and selection indicator.

Variants:

- single-select frequency;
- multiple-select meeting formats;
- private preference picker entry.

States:

- unselected;
- selected;
- disabled;
- validation required.

### `NTProfileReviewSection`

Anatomy:

- section title;
- `NTVisibilityLabel`;
- concise selected content;
- optional Edit action.

Required sections:

- Professional identity;
- Professional direction;
- Where you’re growing;
- What you can share;
- Meeting context;
- Introduction rhythm.

## 6. Introduction components

### `NTIntroductionReadyHero`

Used once on Today.

Anatomy:

- “New introduction” context;
- **We found someone you might want to meet.**;
- concise quality explanation;
- **View introduction** action.

States:

- new;
- seen but undecided;
- expired while unopened.

Constraints:

- No person preview queue.
- No competing content carousel.
- No countdown or artificial urgency.

### `NTReciprocalValueSection`

Required twice on the Introduction screen.

Variants:

- **Why you should meet** with `arrow.up.right`;
- **Why they may want to meet you** with `hand.raised`.

States:

- concise default;
- expanded accessibility layout;
- data unavailable error is not allowed when an introduction is presented—the introduction must not ship without a defensible explanation.

### `NTMeetingContextStrip`

Shows coarse practical overlap.

Examples:

- Both work near the city centre on Wednesdays.
- Both are available on the east side at lunch.
- Both prefer weekday coffee chats.

States:

- usual overlap;
- Available Today overlap;
- no location statement when it does not improve practicality.

Privacy:

- Never contains exact live coordinates.
- Never exposes another member’s raw availability settings.

### `NTIntroductionActions`

Two explicit buttons:

- secondary **Pass**;
- filled **Interested**.

States:

- enabled;
- submitting;
- submitted;
- offline retry;
- introduction expired.

Constraints:

- No swipe.
- No check/X pair.
- No heart.
- No confirmation that reveals the other person’s response.

### `NTPrivateWaitingState`

Anatomy:

- lock/shield symbol;
- **Your interest is private.**;
- mutual-gating explanation;
- neutral path back to Today.

Outcomes:

- still waiting;
- mutual interest notification;
- introduction expired;
- non-mutual outcome: **This introduction didn’t work out. We’ll keep looking for someone worthwhile.**

### `NTMutualInterestState`

Anatomy:

- restrained success symbol;
- **You’re both interested.**;
- professional identity;
- **Start conversation** action.

No confetti, compatibility score, romantic language, or popularity signal.

## 7. Available Today components

### `NTAvailableTodayControl`

Today-row states:

- off — **Open to a 1:1 coffee?**;
- configuring;
- active — broad area, time window, exact expiry;
- expiring soon;
- expired;
- unavailable due to paused account or incomplete settings.

Actions:

- Set;
- Change;
- Turn off.

### `NTAvailabilitySheet`

Native sheet containing:

- broad area single-select;
- broad time-window single-select;
- expiry disclosure;
- precise-location privacy disclosure;
- Cancel and Turn on.

Initial areas:

- Downtown / city centre;
- Central neighborhoods;
- West side;
- East side;
- Flexible within the city.

Initial windows:

- Lunch;
- Afternoon;
- After work.

States:

- valid selection;
- missing area;
- missing time;
- activating;
- activation failure;
- active confirmation.

## 8. Messaging components

### `NTConversationIdentityHeader`

Anatomy:

- back action;
- name;
- role and verified company with `NTCompanyMark` before the company name (one line; the row and connection detail carry the full wrapping text);
- conversation details/safety menu.

Shipped as the principal toolbar item of `ConversationView`; the navigation title keeps the counterpart's name for the back button and VoiceOver reads name, role, and company once.

### `NTIntroductionContextStrip`

Persistent concise context explaining why the conversation exists.

Example:

> Introduced for complementary experience in AI infrastructure and distributed systems.

The component is informational and collapsible only if Dynamic Type requires more room.

### `NTMessageBubble`

States:

- incoming;
- outgoing;
- sending;
- delivered if product needs delivery state;
- failed with retry;
- blocked/removed by safety policy.

V1 supports text only. No reactions, voice notes, disappearing content, stories, or group chat.

### `NTMessageComposer`

Native text field plus labelled Send action.

States:

- empty;
- focused;
- populated;
- sending;
- offline;
- conversation ended;
- blocked.

The composer does not exist before mutual interest.

### `NTCoffeePlanSummary`

Lightweight chat context inferred or confirmed from conversation.

Anatomy:

- coffee symbol;
- broad date/time;
- broad area;
- optional Edit/Confirm action if implemented.

It does not book a venue, reserve a table, or expose precise location automatically.

## 9. Feedback and Connection components

### `NTMeetupFeedbackChoice`

Four choices:

- Great connection;
- Good conversation;
- Didn’t really connect;
- Didn’t meet.

States:

- unselected;
- selected;
- submitting;
- submitted;
- error/retry.

Constraints:

- No stars.
- No public review.
- No visible reliability score.
- Private-use disclosure remains visible.

### `NTConnectionCreatedState`

Anatomy:

- restrained success treatment;
- **Connection created.**;
- explanation that the relationship became real through meeting;
- professional identity;
- meeting/introduction context;
- **View Connections** action.

### `NTConnectionRow`

Anatomy:

- professional identity;
- verified company;
- relationship context such as meeting date or introduction topic;
- disclosure indicator.

No follower, popularity, endorsement, or engagement metadata.

## 10. System and safety states

### `NTQualityWaitState`

Used when no candidate clears the quality threshold.

Copy:

> **We’re looking for someone worth introducing you to.**

Supporting content may show introduction frequency and Available Today. It must not fill the screen with events, articles, or people to browse.

### `NTNotificationInviteCard`

The single explanation before the phone's permission dialog. Shown at the top of Today only while Today is searching or waiting privately, the member can receive introductions, the phone has never been asked, and the member has not chosen **Not now** on this phone.

Anatomy:

- **When network.to will notify you**;
- one sentence naming the five reasons and one stating that delivery is managed in iPhone Settings;
- **Turn on notifications** (primary) and **Not now** (secondary), equal targets of at least 44 pt.

States:

- resting: card visible with both choices;
- in progress: the phone's dialog is open and the card is already gone;
- success: allowed; nothing is shown and the phone is registered silently;
- recoverable failure: registration failed; nothing is shown and it is retried on the next activation;
- terminal: declined in the dialog or **Not now**; the card is gone for this member on this phone;
- offline: the dialog works offline and registration is queued silently (a recorded deviation from the offline wording rule, because the member's own action completed on the phone).

Never a sheet, alert, badge, sound, or animation; never shown beside an undecided introduction or a mutual-interest action.

### `NTInlineNotice`

The single notice surface, rendered by `MainTabView` at the top of the screen from the store's one `notice`; a newer notice replaces the older. The feedback sheet renders the same component inline for its own refused submission.

Variants (the symbol, tint, and text always agree):

- success: `checkmark.circle.fill` in `success`; only after the backend confirms, or at once for a change kept only on the phone;
- information: `info.circle.fill` in `accent`; something worth knowing that asks nothing of the member (a failed refresh, a membership gate);
- error: `exclamationmark.circle.fill` in `destructive`; the member's own action that did not happen, named plainly ("Introduction preferences weren’t saved.").

Anatomy:

- semantic symbol;
- one sentence in `textPrimary`;
- for errors, **Retry** when the action can be repeated with the same values, and **Dismiss**; each target at least 44 pt.

States:

- success and information dismiss themselves after about two seconds;
- an error stays until dismissed, retried, or replaced; Retry runs the failed action once, and the action raises its own notice if it fails again;
- sign-out and account deletion clear the notice and its retry.

The text is announced to VoiceOver when the notice appears; the entrance honours Reduce Motion.

### `NTLoadingState`

Use native progress indication only when the wait is indeterminate and visible.

Rules:

- Avoid skeleton people cards because they imply a browseable queue.
- Preserve screen hierarchy while submitting interest or verification.
- Never loop decorative motion.

### `NTOfflineState`

Every action that reaches the backend states whether it was saved, queued, or not submitted, and offers retry:

- introduction responses roll back, re-enable the buttons, and raise the backend's message as an error;
- Available Today (set and clear), introduction and meeting preferences, unblock, block, remove Connection, and end conversation apply at once, restore the previous state when the save fails, and raise an error with **Retry**;
- a coffee plan and private feedback apply only after the backend confirms: the plan raises an error with **Retry**; the feedback sheet stays open with an inline error and **Retry**;
- profile saves keep the edited text on screen and raise an error with **Retry**;
- messages keep their per-message **Not sent · Retry**;
- work-email verification and reports keep their inline error in their sheet.

Nothing is queued for later delivery; a failed save is reported and retried by the member. An offline launch does not yet show the last snapshot (recorded in `docs/DESIGN_PHILOSOPHY.md`).

### `NTSafetyMenu`

Available from Conversation details and Connection detail.

Actions:

- Block;
- Report;
- End conversation or connection.

Block and Report require clear consequence text. Report categories follow the PRD. Romantic/sexual behavior is explicitly reportable because it violates the professional-only boundary.

## 11. Interaction-state matrix

| Surface | Resting | In progress | Success | Recoverable failure | Terminal/expired |
| --- | --- | --- | --- | --- | --- |
| Work email | Populated | Sending code | Code sent | Invalid/ineligible/domain review | Account ineligible |
| OTP | Complete | Verifying | Company verified | Invalid/expired/resend | Verification cancelled |
| Introduction | Undecided | Submitting response | Private waiting; ends only at expiry, mutual interest, or a block | Buttons return with the backend's message | Ended at expiry: one state, shown once, whatever ended it |
| Available Today | Off | Saving, shown active at once | Active until exact time | Restored to the previous state; "Availability wasn’t saved." with Retry | Expired/turned off |
| Preference and safety saves | Saved values | Saving, shown at once | Success notice after confirmation | Restored to the previous state; error notice with Retry | n/a |
| Coffee plan | Coordinating | Sending | Plan shown once saved | "Coffee plan wasn’t sent." with Retry | Conversation ended |
| Mutual interest | Notification ready | Opening chat | Conversation active | Retry loading conversation | Member restricted |
| Message | Draft | Sending | Sent | Failed/retry | Conversation ended/blocked |
| Meetup feedback | Unselected | Submitting; sheet stays open | Recorded/Connection created only after confirmation | Sheet stays open with "Feedback wasn’t submitted." and Retry | Dismissed/expired prompt |
| Refresh | Last snapshot | Refreshing | State replaced | "Couldn’t refresh right now." as information | Session invalid; sign-in shown |
| Notification invitation | Card with two choices | Phone dialog open | Allowed; card gone; silent registration | Registration retried silently on next activation | Declined or Not now; card gone |
| Tapped notification | Launch screen or current screen | Session restore and refresh | Today or the referenced conversation | Refresh failed; destination in last known state | Session invalid; sign-in shown; route discarded |

## 12. Accessibility contract

Every component must satisfy all of the following:

- 44 × 44 pt effective touch targets.
- Native focus order and keyboard behavior.
- Complete VoiceOver label, hint, and value where state is not obvious from visible text.
- Dynamic Type through the largest accessibility sizes without truncating introduction explanations.
- Increased Contrast preserves state boundaries.
- Reduce Transparency replaces material with an opaque semantic surface.
- Reduce Motion removes nonessential state animation.
- Semantic colour is paired with text or symbol.
- Errors use `accessibilityLiveRegion(.assertive)` or equivalent focused announcement only when action is required.
- Dynamic status such as availability expiry uses polite announcements and does not repeatedly interrupt.

## 13. Component lock checklist

| Area | Components defined | Visual prototype coverage | Status |
| --- | --- | --- | --- |
| Navigation | Main tabs, navigation header | Core-flow prototype | Proposed |
| Trust and identity | Identity, verification, visibility, topics | Both prototypes | Proposed |
| Onboarding | Progress, fields, OTP, choices, review | Onboarding prototype | Proposed |
| Introduction | Ready hero, reciprocity, context, actions, waiting, mutual | Core-flow prototype | Proposed |
| Available Today | Today control and configuration sheet | Core-flow prototype | Proposed |
| Messaging | Header, context, bubbles, composer, coffee plan | Core-flow prototype | Proposed |
| Feedback and Connection | Feedback choices, created state, connection row | Core-flow prototype | Proposed |
| System and safety | Wait, notices, loading, offline, safety menu | Specification only | Needs visual states |

The component system becomes locked only after the product owner approves the visual direction and the remaining system/safety states receive visual review.
