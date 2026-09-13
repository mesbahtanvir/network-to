# network.to UI design specification

Status: **Implemented UI — product direction extended beyond PRD V1**  
Version: 0.5  
Last updated: 2026-09-08  
Source: `professional_network_prd_v1.md`, version 1.0 — Final V1 Product Direction

This document translates the PRD into an implementation-ready iOS interface contract. Product behavior that the PRD defines as foundational is not presented here as an optional design choice.

## 1. Product definition

`network.to` is an iOS-first professional connection network for ambitious, verified technology professionals across North American cities. It helps members move toward meaningful professional goals by forming high-quality local relationships beyond their usual company or industry circle.

The product makes selective, reciprocal introductions between people in the same city whose ambition, experience, direction, and perspective can help one another progress—and for whom an in-person 1:1 meeting is practical. Cross-company and adjacent-industry connections intentionally increase the range of lessons available to each member. Each person responds independently. Mutual interest opens a simple private conversation whose purpose is to coordinate a coffee chat or comparable real-world meeting.

The product succeeds when members leave the app, build a genuine professional relationship, and gain useful momentum toward what they are trying to achieve.

### Core promise

> **Move toward your goals through people worth knowing.**

### Core loop

`Professional direction + reciprocal value → Selective introduction → Independent response → Mutual interest → Private chat → 1:1 meetup → Feedback → Connection`

### Same-day signature loop

`Available today → Work area + time window → High-quality introduction → Mutual interest → Chat → Coffee within hours`

## 2. Non-negotiable product constraints

These rules come directly from the PRD and govern every interface decision.

- No events product or event-discovery surface.
- No Explore tab, Search tab, Feed tab, or global people directory.
- No cold outreach or unsolicited direct messages.
- No browsing company employee lists or nearby people.
- No follower counts, likes, public ratings, endorsements, or popularity signals.
- No swipe deck, compatibility percentage, hearts, “match,” or dating-oriented presentation.
- No artificial introduction quota. Sending nothing is preferable to sending a weak introduction.
- Professional affiliation is verified through a qualifying work email.
- An introduction response remains private unless both people choose **Interested**.
- Passing is easy, private, and socially inexpensive.
- Mutual interest is required before messaging opens.
- Messaging is intentionally simple and exists to coordinate an in-person meeting.
- Location is coarse and temporary; there is no continuous location tracking.
- Matching stays inside the member’s city even as the network operates across North America.
- Gender is not collected, exposed, or used as an introduction eligibility or ranking signal. The network is never partitioned into gender-based pools.
- Safety is supported through verified membership, professional-only standards, reporting, blocking, and ending conversations.
- A member’s existing network survives company changes.
- Notifications are scarce and tied to meaningful professional interaction.
- AI and ranking machinery remain invisible; the interface explains professional relevance in plain language.

## 3. Experience principles

### Calm, selective, and finite

Today presents one meaningful state—not a stream of people. There is no infinite scroll and no reason to remain in the app after the next real-world action is clear.

### Professional substance before appearance

Role, verified company, professional ambition, expertise, growth direction, reciprocal value, and practical meeting context dominate the interface. Photography is absent from the introduction decision in the proposed V1 direction to avoid dating-style judgment.

### Reciprocity made legible

Every introduction answers two separate questions:

1. Why could knowing this person help me?
2. Why could knowing me help them?

Neither explanation may reduce one member to access, status, mentorship, or a referral opportunity.

### Trust without theatre

Verification is visible and precisely described. It confirms control of a company email; it does not imply employer endorsement or identity verification beyond that fact.

### User control without people shopping

Members control their own goals, expertise, availability, frequency, location context, and private constraints. They do not control the system by filtering and browsing strangers.

### Perspective beyond the familiar

Cross-company and adjacent-industry introductions are a core source of value. They should help relevant experience travel across organizational boundaries without sacrificing professional relevance, reciprocity, or introduction quality.

### Rejection without social cost

**Pass** is visually available, neutral, and not punitive. The other member never receives a rejection notification.

### In-person momentum

After mutual interest, the hierarchy shifts immediately toward coordinating a short 1:1 meeting. Chat is a utility, not a destination.

## 4. Main information architecture

The bottom navigation is fixed by the PRD.

| Tab | Purpose | Primary states |
| --- | --- | --- |
| **Today** | Show the current introduction or the single most useful next action | Searching, introduction ready, response pending, mutual interest, meetup context, Available Today |
| **Connections** | Preserve relationships that progressed beyond a recommendation | Connections list, connection detail, empty state |
| **Messages** | Coordinate meetings after mutual interest | Conversation list, conversation, empty state |
| **Profile** | Maintain professional context, preferences, availability, privacy, and account settings | Profile, editing, verification, preferences, safety |

There is no separate notification centre in V1. A tapped notification opens Today (introduction ready) or the referenced conversation in Messages (mutual interest, new message, meeting reminder, feedback due). Permission is asked once, from a card at the top of Today after onboarding; delivery preferences stay in iPhone Settings.

## 5. Screen inventory

### 5.1 Authentication, verification, and account context

| ID | Screen | Purpose | Required states |
| --- | --- | --- | --- |
| A-01 | Welcome | State the promise and offer Create account or Sign in | Default |
| A-02 | Work email | Collect the company email for the selected intent | Empty, invalid, consumer email rejected, submitted |
| A-03 | Verify email | Enter a six-digit OTP with native one-time-code AutoFill | Waiting, invalid code, expired code, resend cooldown |
| O-01 | Context introduction | Explain why professional substance improves reciprocal introductions | Verified, ready |
| O-01A | Résumé processing | Show real local-reading, privacy-protection, drafting, and ready stages without implying the PDF is uploaded | Reading, protecting, drafting, ready, failed |
| O-01B | Résumé draft review | Let the member remove any inferred field, expertise topic, education detail, or job before applying the draft | Complete draft, sparse draft, item removed, continue manually |
| O-02 | Professional identity | Capture real name, role, verified company, and city | Empty, partial, complete |
| O-03 | Professional context | Capture role scope, current focus, and experience | Empty, partial, validation, complete |
| O-04 | Professional direction | Capture what the member wants to achieve, their growth areas, and the perspective useful now | Empty, selected, detailed, complete |
| O-05 | Contribution context | Capture lived experience, help formats, and boundaries | Empty, reciprocal examples, complete |
| O-06 | Meeting context | Capture broad within-city area and usual availability | Area, time windows, validation |
| O-07 | Profile review | Let the member review what is shared and how it supports introductions | Complete, missing required field |

Account context is progressive. O-02 through O-06 use short, focused steps and remain editable later; the flow must never resemble a long résumé form.

### 5.2 Today and introduction lifecycle

| ID | Screen | Purpose | Required states |
| --- | --- | --- | --- |
| T-01 | Today — searching | Communicate that quality takes time | Active search, profile needs work, paused, notification invitation |
| T-02 | Today — introduction ready | Announce one new introduction without showing a feed | New, seen |
| T-03 | Introduction | Explain identity, reciprocal value, trust, and practical meeting context | Default, Available Today context |
| T-04 | Pass confirmation | Make passing clear but inexpensive | Default: the private-Pass sentence and one action, Return to Today; nothing further is asked |
| T-05 | Interested — waiting | Confirm the private response without implying rejection | Waiting, ended at its expiry (one state, shown once, whatever ended it), notification invitation |
| T-06 | Mutual interest | Celebrate lightly and open the conversation | Default |
| T-07 | Available Today | Set temporary area and broad time window | Off, configuring, active, expiring, expired |
| T-08 | Upcoming meetup | Show the meeting context when one is known from conversation | Proposed, upcoming, changed |

### 5.3 Messaging and meetup

| ID | Screen | Purpose | Required states |
| --- | --- | --- | --- |
| M-01 | Messages | List conversations created by mutual introductions | Populated, empty, unread |
| M-02 | Conversation | Coordinate a 1:1 meeting using simple text | Active, sending, failed message, blocked, ended |
| M-03 | Conversation details | Show professional context and safety controls | Active, blocked, reported |
| M-04 | Meetup check-in | Ask whether the members met | Due, snoozed, answered |
| M-05 | Meetup feedback | Collect private outcome and connection preference | Great, good, weak, did not meet, optional note |

V1 does not require calendar booking, café discovery, voice notes, group chat, reactions, or media-heavy messaging.

### 5.4 Connections

| ID | Screen | Purpose | Required states |
| --- | --- | --- | --- |
| C-01 | Connections | Show the meaningful network created through the product | Populated, empty |
| C-02 | Connection detail | Preserve identity, professional context, introduction origin, and conversation access | Active, ended |

A person should become a **Connection** only after the relationship progressed beyond recommendation—preferably after confirmed meetup feedback.

### 5.5 Profile, preferences, and safety

| ID | Screen | Purpose | Required states |
| --- | --- | --- | --- |
| P-01 | Profile | Preview professional identity and reach editing/settings | Complete, incomplete, affiliation needs reverification |
| P-02 | Edit profile | Maintain role, bio, history, professional ambition, growth, and contribution | Editing, saved, validation |
| P-03 | Introduction preferences | Maintain frequency, goals, and professional preferences | Weekly default, alternatives, paused |
| P-04 | Meeting preferences | Maintain work areas, formats, and usual availability | Default, customized |
| P-05 | Work verification | Show the verified company and explain changing companies | Verified; the reverification flow is not built and no control claims it |
| P-06 | Privacy and safety | Explain inclusive introduction design and maintain blocked members and community standards | Default, blocked member present |
| P-07 | Notification settings handoff | Reflect the phone's permission status; present the phone's dialog while it has never been asked, otherwise open the app-specific notification page in iPhone Settings; do not recreate delivery controls in-app | Never asked, on, off, native Settings available, unavailable fallback |
| P-08 | Account | Support sign-out and account deletion | Default, destructive confirmation |

## 6. Core flows

### 6.1 Join and establish trust

`Welcome → Create account → Work email → Verify → Context introduction → Optional résumé processing → Remove/confirm inferred details → First incomplete context step → Member-authored ambition → Contribution confirmation → Meeting preferences → Profile review → Today`

Returning members follow `Welcome → Sign in → Work email → Verify → Today`.

- Consumer email domains are rejected with a direct explanation.
- Unknown company domains enter review; the UI must not pretend that validation is instant.
- Introduction-visible and private fields are visibly distinguished during setup.
- Optional résumé extraction prefills only supported facts: identity, role scope, explicit current/latest-role focus, experience range, expertise, work history, education, and demonstrated experience. The PDF remains on-device and contact details are redacted before bounded text is processed.
- The draft remains separate from the profile until confirmation. Every inferred item has a direct remove action, and the member can discard the draft entirely.
- Résumé users skip factual screens that are already complete. Professional ambition remains required and member-authored; growth themes, immediate perspective, help format, and contribution boundaries can be confirmed or added with low-input controls.

### 6.2 Weekly introduction

`Today → Introduction → Pass / Interested`

If **Pass**:

`Pass → Neutral confirmation → Today searching`

- A Pass is private. The introduction stays open for the other member with its original expiry, the member who passed never sees it again, and they may receive a new introduction at their normal cadence. The confirmation asks nothing further: no reason, no feedback step.

If **Interested**:

`Interested → Private waiting state`

- The waiting state never says or implies that the other person has rejected the member.
- The wait ends only at the introduction's expiry (seven days from creation), through mutual interest, or through a block. The other member's Pass changes nothing the waiting member can see: not the copy, not the expiry, not the timing.
- If the introduction does not become mutual, use: **This introduction didn’t work out. We’ll keep looking for someone worthwhile.** It appears once, at the same moment whether the other member passed or never answered, and **Continue** returns to Today searching.

### 6.3 Mutual interest to coffee

`Mutual interest → Conversation → Agree on time/place → Meetup check-in → Feedback → Connection`

- Mutual interest is the first moment either member learns that interest was reciprocal.
- The conversation header preserves the professional reason for the introduction.
- Product prompts may suggest meeting for coffee but do not auto-book or expose precise location.
- The desired terminal action is an in-person conversation, not prolonged in-app chat.

### 6.4 Available Today

`Today → Available today → Choose broad area → Choose Lunch/Afternoon/After work → Confirm expiry → Today active state`

- Availability expires automatically at the displayed time.
- Area choices are portable within-city regions such as Downtown / city centre, Central neighborhoods, East side, West side, and Flexible within the city.
- The other member sees practical overlap only when an introduction is created, not the member’s live location.

### 6.5 Post-meetup feedback

`How did it go? → Outcome → Stay connected? → Connection created / Conversation retained without connection`

- Feedback is private.
- There are no stars, public reviews, or visible reliability scores.
- “Didn’t meet” is not treated as a moral failure; repeated no-shows may affect internal trust signals only.

## 7. The Introduction screen

This is the most important decision surface in V1. It is a full screen, not a card in a swipe deck.

### Hierarchy

1. **Introduction** label and freshness.
2. Real name.
3. Role and verified company treatment.
4. Compact professional topics.
5. **Why you should meet** explanation.
6. **Why they may want to meet you** explanation.
7. Practical meeting context, such as shared downtown availability.
8. Trust/privacy clarification where needed.
9. **Pass** and **Interested** actions.

### Photography policy

Adopted 2026-09-11 (`docs/PRODUCT_DEFINITION.md`, `docs/DESIGN_PHILOSOPHY.md`): no profile photo appears before mutual interest. The introduction decision screen uses the name monogram for the person and the company mark for the verified company. This keeps professional substance dominant and materially reduces dating-style visual judgment.

After mutual interest, an optional small profile photo may appear in chat and connection detail if product testing shows that it improves meeting trust. This remains a design decision to validate.

### Action treatment

- **Interested** is the single filled action.
- **Pass** is a clearly labeled secondary action with equal touch accessibility but lower visual emphasis.
- Actions are buttons, never swipe gestures.
- No action uses a heart, check/X dating pair, or celebratory language before mutuality.

### Example content structure

**Sarah Chen**  
**Staff Software Engineer at Northstar AI** · Verified company

ML infrastructure · Distributed systems · AI systems

**Why you should meet**  
Sarah builds large-scale inference systems. Her perspective could help you understand how frontier AI infrastructure teams operate.

**Why Sarah may want to meet you**  
Your experience running distributed systems at global scale could be useful as her team grows its platform.

**Easy to meet this week**  
You both live in Toronto and prefer weekday coffee chats near the city centre.

## 8. Today states

Today is intentionally sparse. It never becomes a candidate queue.

### Looking for someone worthwhile

Use when there is no introduction above the quality threshold.

- Reassure the member that silence is a quality feature.
- Show introduction frequency and pause state.
- Offer **Available today** as a low-pressure optional action.
- Do not add generic content, profile browsing, events, or engagement filler.

### Introduction ready

- One composed announcement and one action: **View introduction**.
- Do not preview multiple people or encourage comparison shopping.

### Waiting privately

- Confirm: **Your interest is private.**
- Explain that the conversation opens only if interest is mutual.
- Preserve an easy path to Today without a countdown or pressure mechanic.

### Mutual interest

- Use restrained positive feedback: **You’re both interested.**
- State the next useful action: **Start a conversation and find a time for coffee.**
- Open the conversation with shared introduction context visible.

### Available Today active

- Show broad area, time window, and automatic expiry.
- Provide **Change** and **Turn off**.
- Never display a map of nearby members.

### Notification invitation

Shown once, at the top of Today, only in the searching or waiting-privately state, only while the phone has never been asked, and never again after **Not now**. It names the five reasons for a notification, says delivery is managed in iPhone Settings, and offers **Turn on notifications** and **Not now**. It is a card, not a sheet or alert; Today stays usable beneath it, and it never appears beside an undecided introduction.

## 9. Messaging design

Messaging is a practical coordination tool.

- Conversation title: member name, role, and verified company.
- Persistent context strip: concise reason for the introduction.
- Standard text messages and timestamps.
- Empty conversation suggests a professional opener tied to the introduction, but conversation starters are not required for V1.
- Optional system prompt: **If it feels useful, suggest a short coffee chat.**
- Safety menu contains Block, Report, and End conversation.
- No typing games, reactions, read-pressure mechanics, voice notes, stories, or public activity.
- No message can be sent before mutual interest.

## 10. Visual direction

### Brand expression

**Warm clarity. Human intention. Quiet trust.**

The interface should feel like being thoughtfully introduced by someone who knows both people—not like using HR, CRM, or enterprise networking software. Native iOS structure keeps interaction familiar. Warm paper surfaces, botanical greens, a restrained clay accent, generous spacing, and conversational copy make the experience personal without becoming casual or romantic.

### Colour tokens

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `background` | `#F8F4EE` | `#171815` | Warm paper canvas |
| `surface` | `#FFFDF9` | `#20211D` | Content and sheets |
| `surface-secondary` | `#EEE8DF` | `#292A25` | Quiet controls and context |
| `text-primary` | `#292821` | `#F5F0E8` | Primary content |
| `text-secondary` | `#66665E` | `#BBB8AF` | Metadata and explanations |
| `separator` | `#E4DBD0` | `#3A3B35` | Soft structural boundaries |
| `accent` | `#526B57` | `#B7CEB9` | Interested, selected, and conversational emphasis |
| `accent-strong` | `#354C3D` | `#BFD3C1` | Primary actions |
| `warm-context` | `#BD7053` | `#DC967A` | Coffee, meeting, and human-momentum accent |
| `success` | `#2E7350` | `#6BC18F` | Mutual interest and confirmed states |
| `warning` | `#8A641D` | `#E0B55C` | Expiry or work-email attention |
| `destructive` | `#B42332` | `#FF7A88` | Safety and account actions |
| `company-mark-backing` | `#F3EEE6` | `#F3EEE6` | Opaque tile behind every company mark and company monogram, the same in both appearances |
| `company-mark-glyph` | `#354C3D` | `#354C3D` | Company monogram characters on the mark tile |

Botanical green carries primary action and quiet trust. Clay appears around coffee, introductions, and moments of human momentum. Verification stays visually secondary: trust should be present, not the personality of the product.

### Anti-corporate guardrails

- Lead with the person and the reason to meet; company verification is supporting context.
- Use one clear action per moment rather than dashboard-style toolbars or administrative controls.
- Prefer continuous mobile pages and soft context surfaces over grids of bordered cards.
- Write conversationally. Avoid phrases that sound like compliance, recruiting, CRM, or performance management.
- Keep charts, scores, follower counts, status dashboards, and productivity metaphors out of the member experience.
- Use clay only for meeting momentum and botanical green for action; never flood every trust state with branded colour.
- Preserve generous empty space. A quiet Today screen is intentional, not an invitation to add feed content.

### Typography

Use San Francisco through SwiftUI Dynamic Type styles. No custom font is required for V1.

| Role | SwiftUI style | Weight |
| --- | --- | --- |
| Primary screen title | `.largeTitle` | Semibold |
| Person name / outcome | `.title` | Semibold |
| Section heading | `.title3` | Semibold |
| Row title | `.headline` | Semibold |
| Explanatory body | `.body` | Regular |
| Professional metadata | `.subheadline` | Regular |
| Verification / timing | `.caption` | Medium |

Introduction explanations must remain readable at large accessibility sizes; content reflows vertically rather than truncating.

### Spacing and shape

- 4-pt base spacing system: `4, 8, 12, 16, 20, 24, 32, 40`.
- Compact iPhone horizontal inset: 20 pt for narrative screens, 16 pt for lists.
- Controls: 12–16 pt continuous radius.
- Context surfaces: 18–20 pt continuous radius.
- Sheets use native presentation corners and detents.
- Use separators before shadows. Reserve shadow for transient sheets or floating controls only.
- Minimum effective touch target: 44 × 44 pt.

### Iconography

Use SF Symbols in monochrome or hierarchical rendering.

- Today: `sun.max`
- Connections: `person.2`
- Messages: `message`
- Profile: `person.crop.circle`
- Verified company: `checkmark.seal.fill`
- Available today: `clock.badge.checkmark`
- Location context: `mappin.and.ellipse`
- Professional relevance: `arrow.left.arrow.right`
- Growth: `arrow.up.right`
- Contribution: `hand.raised`
- Safety: `shield`

Avoid sparkles as a generic AI signifier and never use hearts for interest.

### Motion and haptics

- Use system navigation and sheet transitions.
- **Interested** uses a light confirmation haptic and a short state transition.
- Mutual interest may use a restrained success transition without confetti.
- Available Today activation uses a subtle control-state transition.
- No looping, pulsing, countdown, or attention-demanding animation.
- Respect Reduce Motion and Reduce Transparency.

## 11. Component inventory

### Verified company line

Verification seal, then the company mark (or company monogram) immediately before the company name, then **Work email verified**. A disclosure explains exactly what verification means. The mark and monogram are decorative; the company name stays the accessible text.

### Company mark

A square tile the height of the text line it sits in, drawn on `company-mark-backing` with one-eighth inner padding and a 25% continuous corner radius, holding the company's own published icon fitted without distortion or recolouring. When no mark is available (none published, withheld, not approved, not yet downloaded, offline, or failed) the same tile shows the company monogram in `company-mark-glyph`: at most two uppercase characters from the first letter or digit of the first two words of the company name, skipping punctuation-only words and "and", "of", "the". A mark replaces a monogram on the next redraw with no animation. Marks appear beside the verified company name on the introduction and mutual-interest identity rows, in conversation rows and the conversation header, in connection rows and detail, and on the member's own profile identity row; never in onboarding, the Edit profile Company field, the "Work email verified" settings row, or beside typed experience history.

### Notification invitation

A card at the top of Today with the heading **When network.to will notify you**, one sentence naming the five reasons and one stating that delivery is managed in iPhone Settings, then **Turn on notifications** (filled) and **Not now** (secondary) with equal targets. No symbol, no motion, no countdown. Shown until answered; **Not now** is remembered per member on the phone and cleared only after account deletion. Implemented as `NTNotificationInviteCard`.

### Professional topic label

Short structured topic text with subdued background. Topics support scanning but never resemble dating-interest badges or gamified skill chips.

### Reciprocal value section

Two clearly titled narrative blocks:

- **Why you should meet**
- **Why they may want to meet you**

This is a core component, not optional descriptive copy.

### Meeting context strip

Broad overlap such as **Both near the city centre on Wednesdays** or **Both available on the east side at lunch**. No exact live position is shown.

### Available Today control

An explicit toggle/action with area, broad time window, and visible expiry. It automatically returns to off.

### Introduction actions

One secondary **Pass** button and one filled **Interested** button. Both have text labels and equal accessible hit areas.

### Private waiting state

A finite confirmation state that explains mutual gating and avoids status checking pressure. It ends only at the introduction's expiry, at mutual interest, or at a block, never at the moment of the other member's Pass.

### Notices

One notice at a time, at the top of the screen, with a kind that its symbol, tint, and text all agree on. Success (checkmark) and information (info) leave on their own after about two seconds. An error (exclamation) names the action that did not happen ("Availability wasn’t saved.") and stays until the member dismisses it, retries it, or a newer notice replaces it; Retry repeats the action with the same values. A success notice appears only after the backend confirms the action, or at once for a change kept only on the phone. A refresh that fails is information, never an error, because no member action waits on it.

### Professional identity row

Name, role, verified company with its company mark, and last relevant context. Use in Messages and Connections; do not add follower counts or public activity.

### Conversation context strip

Shows why the system introduced the two members and keeps the professional purpose visible while they coordinate.

### Meetup feedback control

Four plain-language choices: **Great connection**, **Good conversation**, **Didn’t really connect**, **Didn’t meet**. It is private and does not use stars.

### Empty state

One truthful explanation and, when useful, one action. Today must be comfortable saying that no worthwhile introduction is ready.

## 12. Content design

### Required terminology

This is the single canonical vocabulary; the constitution and the product definition refer to it.

Use:

- Introduction
- Interested
- Pass
- Mutual interest
- Conversation
- Connection
- Meet
- Member (never user)
- Professional topic
- Available today
- Why you should meet
- Why they may want to meet you
- Verified company / Work email verified
- Company mark and company monogram

Avoid:

- Match, matched, compatibility, or score
- Like, liked you, admirer, or popular
- Swipe or deck
- Nearby people
- Networking streak
- AI-powered / AI match

### Voice

- Ambitious without hype.
- Warm without becoming casual or romantic.
- Clear about privacy and mutual consent.
- Honest when no introduction is available.
- Neutral about passes, timing, and failed coordination.
- Specific about professional relevance.

### Core copy proposals

| State | Copy |
| --- | --- |
| Welcome | **Move toward your goals through people worth knowing.** |
| No introduction | **We’re looking for someone worth introducing you to.** |
| Introduction ready | **We found someone you might want to meet.** |
| Interest recorded | **Your interest is private. We’ll let you know only if it’s mutual.** |
| Mutual interest | **You’re both interested.** |
| Non-mutual outcome | **This introduction didn’t work out. We’ll keep looking for someone worthwhile.** |
| Available Today | **Open to a coffee today?** |
| Meetup prompt | **Did you meet?** |
| Feedback | **How did it go?** |

## 13. Privacy, trust, and safety UI

- Introduction, coarse-only, only-you, and private fields are labeled wherever the distinction matters.
- Gender is not requested, stored, exposed, or used to determine introduction eligibility or ranking.
- The product does not offer gender-based introduction pools; safety controls apply consistently to every member.
- Introduction responses are inaccessible to the other member until mutuality is established.
- Work-email verification disclosure says: **Verified through access to a company email. This does not imply employer endorsement.**
- Precise location is never required for matching or shown to another member.
- Block immediately prevents future introductions and conversation access as defined by policy.
- Report categories include harassment, spam, fraud/misrepresentation, inappropriate behavior, romantic/sexual behavior, discrimination, threatening behavior, and other safety concerns.
- Blocking and reporting are accessible from conversation and connection detail without being visually dominant in normal use.
- Account deletion requires a destructive confirmation that explains the effect on messages and retained safety records.

## 14. Accessibility and quality gates

- Support Dynamic Type through the largest accessibility sizes.
- Preserve complete introduction explanations without truncation.
- Meet WCAG AA contrast for text and controls.
- Provide full VoiceOver support for professional context, verification, response privacy, and meeting overlap.
- Do not communicate response, verification, availability, or feedback state through color alone.
- Respect Reduce Motion, Reduce Transparency, Bold Text, and Increased Contrast.
- Maintain 44 × 44 pt touch targets.
- Test keyboard behavior for all form screens where external keyboards may be used.
- Use plain, localizable date/time language and reveal exact expiry for Available Today.
- Test light mode, dark mode, high contrast, 320-pt compact width, and the largest supported iPhone width.
- Test empty, loading, offline, OTP error, unknown company, non-mutual, expired introduction, blocked, reported, failed message, no-show, and affiliation-change states.

## 15. Design lock checklist

The product direction is fixed by the PRD. The UI becomes **Locked 1.0** when the following visual and interaction decisions are approved and represented in high-fidelity screens.

| Decision | Proposed choice | Status |
| --- | --- | --- |
| Main navigation | Today, Connections, Messages, Profile | PRD locked |
| Introduction model | One full-screen introduction; no browse/swipe | PRD locked |
| Response actions | Pass and Interested; independent and private | PRD locked |
| Messaging gate | Mutual interest only | PRD locked |
| Primary outcome | In-person 1:1 coffee or comparable meeting | PRD locked |
| Available Today | Broad area + time window + automatic expiry | PRD locked |
| Visual character | Warm clarity; human intention; quiet trust; native iOS | Revised in all prototypes; awaiting approval |
| Colour system | Warm paper, botanical green, restrained clay meeting accent | Revised in all prototypes; awaiting approval |
| Introduction photography | No photo before mutual interest | Adopted 2026-09-11 (PRODUCT_DEFINITION.md) |
| Introduction hierarchy | Identity → reciprocal value → practical overlap → actions | Proposed |
| Today state designs | Section 8 | Proposed |
| Screen inventory | Section 5 | Proposed |
| Component states | Section 11 | Proposed |
| Accessibility gates | Section 14 | Proposed |

### Required lock artifacts

1. This specification updated to `Status: Locked`, version `1.0`, with approval date.
2. High-fidelity screens for every state of Today and Introduction.
3. High-fidelity onboarding flow covering work-email verification and professional context.
4. Click-through prototype from introduction through mutual chat, meetup feedback, and Connection.
5. Component/state sheet covering verification, availability, reciprocal value, response actions, messaging, and feedback.
6. Light/dark and accessibility review of all P0 screens.

### Current artifact status

| Artifact | Current evidence | Status |
| --- | --- | --- |
| UI specification | PRD-aligned screen inventory, flows, warm visual system, content, privacy, and accessibility rules | Proposed; awaiting final approval |
| Today and Introduction | Warm mobile-native treatment across Today, Available Today, Introduction, Pass, private waiting, and mutual-interest states | Revised and interaction-tested |
| Progressive onboarding | Warmer first-run story with visually secondary verification and complete professional-context flow | Revised and interaction-tested |
| Introduction-to-Connection flow | Interactive interest gating, mutual-only messaging, coffee coordination, feedback, and post-meetup Connection | Revised and interaction-tested |
| Component/state sheet | Warm semantic tokens across trust, introduction, availability, messaging, feedback, and safety states | Revised and interaction-tested |
| Design-level accessibility review | `ACCESSIBILITY_REVIEW.md`: semantic, keyboard, contrast, motion, dark appearance, and 320-pt checks | Passed; native SwiftUI runtime audit remains an implementation gate |

### Remaining product-owner design decisions

1. Approve or redirect the revised warm-paper, botanical-green, and clay visual execution.
2. Choose the final product name and logotype treatment if `network.to` is a repository name rather than the customer-facing brand.

Language rule: use **meet** for the general relationship outcome and **coffee** when describing the concrete in-person format, availability, or plan.
