# Feature Specification: Batch Matching

**Feature Branch**: `005-batch-matching`

**Created**: 2026-09-19

**Status**: Draft

**Input**: User description: "Now let's do matching algorithms. We need to do batch matching: first figure out the current product, then figure out what the best matching algorithm should be, then figure out what architecture we should use." The current product, the findings, the options, and the product owner's decisions are recorded in [discovery.md](discovery.md).

## Clarifications

### Session 2026-09-19

- Q: When should matching run? → A: One batch per city per day at about nine in the morning local time, starting with one fixed hour for Toronto until a second city has members. A member who passes is eligible again at the next batch, subject to their cadence. The hourly schedule is retired (FR-001, User Story 3).
- Q: How many eligible members per city per batch should the design carry? → A: Up to a few thousand over the next year. The batch is designed so a stronger selection method can replace the selection step later without changing eligibility, explanations, or records (Assumptions).
- Q: How is the reciprocity vocabulary gap fixed? Growth areas and contribution areas are two different fixed lists sharing one term, so almost no pair clears the quality floor today. → A: A product-owned affinity registry between the two existing lists ships in this feature, backend only. Replacing both lists with one shared taxonomy in onboarding, profile editing, and the résumé drafter is its own later feature (FR-006, FR-007).
- Q: After mutual interest, how long does the introduction count as a member's one active introduction? → A: Until its seven-day expiry. A member in a live conversation may receive their next introduction after that, still subject to cadence. This also fixes the defect that excludes a member from matching for good after their first mutual introduction (FR-015, User Story 2).
- Q: How strict is the quality floor while density is low? → A: Reciprocal help is required in both directions. Early members may wait; the run records show how long (FR-004, FR-006).
- Q: What does "Exceptional introductions only" mean? → A: A stronger fit than the standard floor and at most one introduction every 28 days (FR-009, FR-017).
- Q: Should waiting time raise a member's priority? → A: Yes, bounded: it never admits a pair below the floor and never outweighs a clearly stronger fit (FR-019).
- Q: May matching learn from Pass history or meetup feedback? → A: Not in this feature. Run records are kept now; any such use needs its own constitution amendment first (FR-011).
- Q: How are explanations and text relevance produced? → A: Deterministically, from the members' own words and choices. No language model drafts an explanation or judges a pair. Text embeddings are the recorded upgrade path for topic and ambition similarity, behind the same relevance interface (FR-012 to FR-014).
- Q: Is the Available today same-day path part of this feature? → A: No, a follow-up. The batch is designed so the same selection can later run over members with a live availability (Assumptions).
- Q: Relationship mix and years of experience are stored but unused. → A: Both become the peer-fit component of relevance (FR-008).

## User Scenarios & Testing *(mandatory)*

The product promises one worthwhile same-city introduction at a time, with a plain explanation of why each person could help the other, and nothing at all when no such pair exists. Today the matcher cannot keep that promise. Growth areas and contribution areas are two different fixed lists that share a single term, so the reciprocity test that gates every introduction almost never passes and almost nobody is introduced. A member whose first introduction becomes mutual is never introduced again, because that introduction counts as active forever. Introductions are chosen one pair at a time, at any hour, and the explanations do not say what the pair was chosen for. Nothing is recorded about who was eligible and why they were not introduced, so the product's own success signals cannot be reviewed.

This feature makes matching a daily batch per city: every eligible pair in the city is considered together, only pairs where each member can help the other are ever introduced, a member who has waited longer is preferred when fit is comparable, each explanation names the specific reason, a mutual introduction stops blocking its members after it expires, and every run records what happened. No new surface, no new notification kind, and no change to what a member sees except better explanations that arrive at a predictable time.

Vocabulary: **Introduction**, **Interested**, **Pass**, **mutual interest**, **Connection**, **Meet**, **Available today**, **member**, **growth area** (what a member wants to develop), **contribution area** (what a member can share), **professional topic**.

### User Story 1 - Only Worthwhile Introductions Are Sent (Priority: P1)

A member receives an introduction only when the other person can share something the member wants to grow in, and the member can do the same for them. The introduction says so in plain language: which of the member's growth areas the other person serves, what that person offers in their own words, and what they are working toward. When no such pair exists in the member's city, Today keeps saying that nothing has been sent, and nothing is.

**Why this priority**: the reciprocity promise is the product. Today it is unreachable for almost every pair because the two vocabularies do not overlap, so the first job is to make a worthwhile introduction possible and to make its explanation true.

**Independent Test**: create two members in the same city whose contribution areas serve each other's growth areas through the affinity registry, with overlapping meeting preferences; run one batch; confirm one introduction exists whose two explanations name the served growth areas and quote each member's own ambition and contribution. Create a third member whom only one of them can help; confirm that member is never introduced to either. Create two members with no meeting overlap; confirm no introduction.

**Acceptance Scenarios**:

1. **Given** members A and B in the same city, where A's contribution areas serve at least one of B's growth areas and B's contribution areas serve at least one of A's, **When** the batch runs, **Then** one introduction is created between them and both receive the existing "introduction ready" notification.
2. **Given** A can help B but nothing B offers serves any of A's growth areas, **When** the batch runs, **Then** no introduction is created between them, however similar their topics, goals, or companies.
3. **Given** an introduction is created, **When** A reads "Why you should meet", **Then** it names one of A's growth areas, the contribution area of B that serves it, B's own words about what they can share, and B's own ambition, without any score, ranking, or "AI" wording.
4. **Given** the same introduction, **When** A reads "Why they may want to meet you", **Then** it names one of B's growth areas and the contribution area of A that serves it, in A's own words.
5. **Given** A and B serve each other but share no meeting area, format, or window, **When** the batch runs, **Then** no introduction is created. "Flexible within the city" counts as overlapping any area.
6. **Given** a growth area that no contribution area serves exactly (for example "Career transition"), **When** the affinity registry maps it to adjacent contribution areas, **Then** members who chose it can be introduced to members offering those areas, and the explanation still names both areas.
7. **Given** the affinity registry changes by a product decision, **When** the next batch runs, **Then** the new mapping applies from that batch and no existing introduction changes.
8. **Given** a member's frequency is "Exceptional introductions only", **When** a pair clears only the standard floor, **Then** no introduction is created for that member; **When** a pair clears the exceptional floor and at least 28 days have passed since their last introduction, **Then** it may be created.

---

### User Story 2 - One Introduction at a Time, Then the Next (Priority: P1)

A member who has had a mutual introduction, met or not, becomes eligible for their next introduction once that introduction expires, at their normal cadence. Their conversation and any Connection are untouched. A member who passed is eligible at the next batch once their cadence spacing has passed. A member waiting on an unanswered introduction is not introduced to anyone else until it expires.

**Why this priority**: today a first mutual introduction ends a member's use of the product. This is a defect in the shipped rules, not a new capability, and it must ship with the batch.

**Independent Test**: create a mutual introduction; run a batch before its expiry and confirm neither member is introduced to anyone; advance past the expiry and run again with eligible partners present; confirm each member receives a new introduction and the original conversation is unchanged.

**Acceptance Scenarios**:

1. **Given** A and B have a mutual introduction created less than seven days ago, **When** the batch runs, **Then** neither A nor B is introduced to anyone else.
2. **Given** that introduction is more than seven days old, **When** the batch runs and each has an eligible partner whose cadence spacing has passed, **Then** each receives a new introduction; their conversation, messages, meetup, and Connection are unchanged.
3. **Given** A passed on an introduction, **When** the next batch runs after A's cadence spacing has passed, **Then** A may receive a new introduction, while the other member keeps the original introduction as their active one until it expires, exactly as today.
4. **Given** A chose Interested and the other member has not answered, **When** the batch runs, **Then** A is not introduced to anyone else before the introduction expires.
5. **Given** A and B were introduced within the last 180 days, **When** the batch runs, **Then** they are never paired with each other again in that period.
6. **Given** A's frequency is weekly, twice a month, monthly, or exceptional only, **When** the batch runs, **Then** A receives an introduction only if at least 7, 14, 28, or 28 days have passed since A's last introduction was created; a paused member receives none.
7. **Given** A's free month or subscription has ended, **When** the batch runs, **Then** A receives no introduction while conversations and Connections remain usable, as today.
8. **Given** A blocked B, **When** the batch runs, **Then** A and B are never paired, and any pair computed before the block was recorded is dropped before creation.

---

### User Story 3 - A Daily Batch That Treats the City Fairly (Priority: P2)

Every morning, the product looks at everyone in a city who could receive an introduction, considers every pair that clears the floor, and introduces the pairs that serve the city best: stronger reciprocal fit first, and among comparable pairs, members who have waited longer. Each member receives at most one introduction per batch. Introductions arrive at a predictable, humane hour instead of any hour of the day or night.

**Why this priority**: the batch is what turns a set of good rules into a good experience across a city. It depends on User Story 1 for what "worthwhile" means and on User Story 2 for who is eligible.

**Independent Test**: create three eligible members A, B, and C where A serves and is served by both B and C, and B and C do not serve each other; confirm one batch creates exactly one introduction for A. Create the same again with B having waited four weeks and C one day, of equal fit; confirm A is introduced to B. Create the same with C a clearly stronger fit; confirm A is introduced to C.

**Acceptance Scenarios**:

1. **Given** A could be introduced to both B and C in one batch, **When** the batch runs, **Then** A receives exactly one introduction and the other member waits for a later batch.
2. **Given** two possible pairs of equal fit, one involving a member who has waited longer since their last introduction, **When** the batch runs and only one can be created, **Then** the pair with the longer-waiting member is created.
3. **Given** a pair of clearly stronger fit and a pair of weaker fit involving a longer-waiting member, **When** only one can be created, **Then** the stronger pair is created; waiting never outweighs a clearly stronger fit.
4. **Given** a member has waited any length of time, **When** their only possible pairs are below the floor, **Then** they receive nothing; waiting never admits a pair below the floor.
5. **Given** a city has fewer than two eligible members, **When** the batch runs, **Then** no introduction is created there and the run records that.
6. **Given** members in different cities, **When** the batch runs, **Then** no cross-city introduction is created, as today.
7. **Given** the scheduled hour arrives while a previous batch is still running, **When** the new run starts, **Then** it is recorded as skipped and nothing is created twice.
8. **Given** a member's eligibility changes between the moment pairs are considered and the moment introductions are created (a block, a pause, a lapsed membership, a new introduction), **When** the batch creates introductions, **Then** any pair that no longer satisfies every rule is dropped.
9. **Given** the batch creates introductions, **When** a member opens the app, **Then** Today shows the introduction exactly as it does today and each member has received one "introduction ready" notification for it.
10. **Given** the operations team runs matching by hand, **When** the manual action is used, **Then** it runs the same batch with the same rules and records the run in the same way.

---

### User Story 4 - Operations Can See Why (Priority: P3)

After each batch, the operations team can see, per city, how many members were eligible, how many were introduced, and why the rest were not: no other eligible member in the city, every candidate already introduced or blocked, no meeting overlap, or no pair above the floor. From that and the existing records they can review the product's success signals: median days from onboarding completion to first introduction, and the share of members with none after seven days.

**Why this priority**: the quality floor is deliberately strict; the only responsible way to keep it strict is to watch what it costs. This story is last because it adds nothing a member sees.

**Independent Test**: run a batch over a city with members in each unmatched situation; confirm the run record reports the counts per reason and the introductions created, and that the records are purged after 180 days.

**Acceptance Scenarios**:

1. **Given** a batch runs, **When** the operations team reads the run record, **Then** it shows, per city: eligible members, members with no eligible partner by reason, pairs above the floor, and introductions created.
2. **Given** a run fails, **When** the operations alert runs, **Then** the existing "matching run failed" alert posts once, as today.
3. **Given** no batch has run in 25 hours, **When** the operations alert runs, **Then** the existing "matching stalled" alert posts once, as today.
4. **Given** run records older than 180 days exist, **When** the daily retention job runs, **Then** they are removed, and the rule is proven by a test.
5. **Given** the run records and the existing member records, **When** the operations team reviews them, **Then** the median days from onboarding completion to first introduction and the share of members with no introduction after seven days can be computed without any other data.
6. **Given** any run record, **When** it is read, **Then** it contains counts only: no member's name, words, or identity.

---

### Edge Cases

- **A member changed city between batches**: they are considered only in their current city; an introduction created in the old city keeps its rules.
- **A member has only "Flexible within the city" as an area**: they overlap every other member's areas; format and window overlap are still required.
- **Two members serve each other through an adjacent mapping only**: they clear the standard floor, not the exceptional one.
- **The registry maps a growth area to nothing**: members who chose only that growth area cannot be introduced; the registry must cover every growth area before it ships.
- **An odd number of eligible members**: one member waits; nothing is sent to fill the gap.
- **A member completes onboarding at noon**: their first possible introduction is the next morning's batch.
- **A member passes at 9:30 in the morning**: their next possible introduction is the next batch after their cadence spacing has passed.
- **A member's cadence changes from weekly to exceptional only after an introduction**: the new spacing and floor apply from the next batch.
- **Daylight-saving change**: until a per-city time zone exists, the fixed hour shifts by one hour locally twice a year. Accepted for one city.
- **A mutual introduction expires while the members are arranging a coffee**: both become eligible for their next introduction at their cadence; nothing about the conversation changes, and no notification is sent about the expiry.
- **A batch creates zero introductions**: the run is recorded as completed with zero, and the stalled alert does not fire.
- **Demonstration mode on the phone**: unchanged; the mock backend keeps serving its fixed introduction.

## Requirements *(mandatory)*

### Functional Requirements

**Batch selection**

- **FR-001**: Matching MUST run as one batch per city per day at the scheduled hour, replacing the hourly schedule. Every run MUST be recorded, including runs that create nothing, and a run that starts while another is running MUST be recorded as skipped and MUST create nothing.
- **FR-002**: Within one batch each member MUST receive at most one introduction, and every introduction created MUST satisfy every existing rule: same normalized city, both members active with complete onboarding, both holding an active free month or verified subscription, neither paused, both members' cross-company and cross-industry consents, not blocked in either direction, no introduction between the two in the last 180 days, neither member holding an active introduction, and each member past their cadence spacing.
- **FR-003**: A batch MUST select the introductions for a city from all pairs that clear the floor in that city together, preferring stronger reciprocal fit, and preferring the pairs of a member who has waited longer since their last introduction when fit is comparable.
- **FR-004**: No pair below the quality floor MUST ever be introduced, whatever the members' waiting time, the number of unmatched members, or the size of the city. There MUST be no minimum or target number of introductions per batch.
- **FR-005**: The manual operations action MUST run the same batch with the same rules and records.

**Quality floor and reciprocal fit**

- **FR-006**: A pair clears the quality floor only if at least one of each member's contribution areas serves at least one of the other member's growth areas, in both directions, according to the affinity registry. Serving means the same term or a term the registry lists as adjacent.
- **FR-007**: The affinity registry MUST be product-owned, changed only by a recorded product decision, and MUST cover every growth area a member can choose, including "Career transition" and "Local tech ecosystem". A change MUST apply from the next batch and MUST NOT alter existing introductions.
- **FR-008**: Above the floor, the strength of fit MUST be determined only by: how many growth areas are served in each direction and whether by the same term or an adjacent one; shared networking goals; professional topics that are identical after normalizing case, spacing, and punctuation; peer fit, meaning how close the two members' experience bands are, read through the member's relationship mix; and whether the pair crosses companies and industries.
- **FR-009**: For a member whose frequency is "Exceptional introductions only", a pair MUST additionally serve at least one growth area in each direction by the same term (not adjacent) and share at least one networking goal, and MUST be at least 28 days after that member's last introduction.
- **FR-010**: Meeting practicality MUST remain a hard requirement: at least one shared meeting area, at least one shared format, and at least one shared window. "Flexible within the city" MUST count as overlapping every area.
- **FR-011**: Selection MUST NOT use gender, photos, Pass history, Interested history, meetup feedback, message content, live availability, or anything not listed in FR-002 to FR-010.

**Explanations**

- **FR-012**: "Why you should meet" MUST name a growth area the reader chose, the contribution area of the other member that serves it, the other member's own words about what they can share, and the other member's own ambition. "Why they may want to meet you" MUST name a growth area the other member chose and the contribution area of the reader that serves it, in the reader's own words. Both MUST be plain professional language in the canonical vocabulary, with no score, ranking, percentage, or AI wording, no exclamation points, and no inferred pronouns (the other member is named or referred to as "they").
- **FR-013**: The meeting context MUST name a shared format and a shared area and MUST NOT reveal live location or exact availability, as today.
- **FR-014**: Explanations MUST be assembled only from what the members wrote or chose and the registry; no explanation or relevance judgement MUST be produced by a language model.

**Cadence and active introductions**

- **FR-015**: A mutual introduction MUST count as each member's active introduction only until its expiry, seven days after creation. After that the member is eligible for a new introduction at their cadence; the conversation, its messages, meetups, feedback, and any Connection MUST be unchanged, and no notification MUST be sent about the expiry.
- **FR-016**: An offered introduction MUST count as active for a member until it expires or that member passes, as today, and a passed-on introduction MUST still count toward the passer's cadence spacing.
- **FR-017**: Cadence spacing MUST be measured from the creation of the member's most recent introduction: weekly 7 days, twice a month 14 days, monthly 28 days, exceptional only 28 days, paused never.
- **FR-018**: A member who passes MUST be eligible at the first batch after their cadence spacing has passed; the other member's introduction MUST be unchanged, per the private Pass rules.

**Fairness**

- **FR-019**: A member's waiting time, measured from their most recent introduction or from onboarding completion when they have none, MUST raise the preference of their pairs by a bounded amount: never enough to admit a pair below the floor, and never more than the difference between an adjacent-term match and a same-term match in one direction, so a clearly stronger fit always wins.

**Operations**

- **FR-020**: Every run MUST record, per city: eligible members; members with no eligible partner, counted by reason (no other eligible member in the city; every candidate blocked or introduced within 180 days; no meeting overlap; no pair above the floor); pairs above the floor; and introductions created. Records MUST contain counts only, never a member's identity or words.
- **FR-021**: Run records MUST be removed after 180 days by the existing daily retention job, and the rule MUST be proven by a test.
- **FR-022**: The existing operations alerts for a failed run and for no run in 25 hours MUST keep working with the daily schedule.
- **FR-023**: It MUST be possible to compute, from the run records and existing member records alone, the median days from onboarding completion to first introduction and the share of members with no introduction seven days after onboarding.

**Unchanged promises**

- **FR-024**: Reciprocal interest as the only gate, the private Pass, the seven-day expiry, the 180-day no-repeat rule, blocks, reports, and the single "introduction ready" notification per member per introduction MUST be unchanged.
- **FR-025**: No change on the phone MUST be required; Today and the Introduction screen render the explanations as received.
- **FR-026**: All new member-facing copy MUST use the canonical vocabulary and MUST NOT use match, compatibility, score, like, swipe, deck, streak, or artificial urgency.

### Key Entities *(include if feature involves data)*

- **Introduction**: unchanged record; it now also remembers which run created it. Its "mutual" status keeps its meaning; only how long it counts as active changes (FR-015).
- **Affinity registry**: product-owned pairs of a growth area and a contribution area that serves it, each marked as the same term or adjacent. Changed only by a recorded product decision.
- **Matching run**: the existing record of one scheduled or manual run (status, timing, failure), extended with one **city batch record** per city holding the counts in FR-020. Purged after 180 days.
- **Eligible pair**: a transient judgement made during a batch and never stored where a member can read it; no relevance value is ever shown or exposed to a member.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In tests, every pair whose members serve each other's growth areas through the registry, with meeting overlap and every eligibility rule met, is introduced by the next batch, and no pair with help in one direction only is ever introduced, in 100% of cases.
- **SC-002**: In tests, no member receives more than one introduction per batch and no introduction below the floor is created, across every synthetic city, in 100% of runs.
- **SC-003**: In tests, a member whose mutual introduction has expired receives a new introduction at the next batch when an eligible partner exists, and never before the expiry, in 100% of cases.
- **SC-004**: Every introduction created by the batch carries two explanations that name the served growth area and quote the other member's own ambition and contribution, verified by content for 100% of introductions in tests.
- **SC-005**: Introductions are created only by the daily batch or the manual operations action; zero are created at any other time.
- **SC-006**: For any past day, the operations team can state per city how many members were eligible, how many were introduced, and why the rest were not, from the run records alone.
- **SC-007**: A city batch with a few thousand eligible members completes well within the scheduled hour, so every introduction of a morning batch is available before members start their day.
- **SC-008**: With identical data, two runs of the batch create the same introductions, so every rule is verifiable by a deterministic test.

## Assumptions

- The scheduled hour is a fixed hour for Toronto (about nine in the morning local time) until a second city has members; a per-city time zone registry is added then, as its own change. The hour shifts by one hour locally across daylight-saving changes until that registry exists.
- The affinity registry's first content is the draft in [discovery.md](discovery.md) section 5, edited by the product owner in the implementation pull request before it lands; the product owner decides what serves "Career transition" and "Local tech ecosystem".
- Growth areas, contribution areas, goals, meeting preferences, and cadence choices keep their current lists and copy in onboarding and profile editing. Replacing the two lists with one shared taxonomy is a separate feature.
- The batch may process up to a few thousand eligible members per city; the selection step is designed so a stronger method can replace it later without changing eligibility, explanations, or run records.
- A member is eligible once onboarding is complete and their free month or subscription is active; nothing about membership changes.
- The demonstration backend on the phone keeps its fixed introduction; it never runs matching.
- Existing introductions, conversations, and Connections are untouched by the change; the first daily batch after release applies the new rules to everyone eligible at that time.
- No new notification kind, no new push copy, no new secret, and no new scheduled job beyond replacing the hourly matching schedule with the daily one.

**Out of scope**

- The same-day Available today path (a more frequent selection over members with a live availability). The Available today control keeps working as it does now.
- Learning from Pass history or meetup feedback in selection.
- Language-model explanations or relevance, and text embeddings.
- A shared growth and contribution taxonomy in onboarding, profile editing, and the résumé drafter.
- Any change to the Introduction screen, Today, notifications, or the Pass rules.

### Constitution Check

- **Principles touched**: I (matching stays server-side on the schedule, same city, reciprocal, cadence-aware, block-aware, 180-day rule, one active introduction; no quota; explanations in plain language; this feature tightens "reciprocal professional relevance" into a testable floor and changes the schedule from hourly to daily, which amends the Schedules line of the Product and Platform Constraints as a MINOR amendment in the implementation pull request), II (nothing a member can read reveals a one-sided decision; the Pass rules are unchanged; no score, ranking, or popularity signal exists or is exposed; relevance judgements are never stored where a member can read them), III (membership access still gates matching; the mutual bound affects only future matching; conversations and Connections are untouched), IV (gender is absent; no new data about members; the affinity registry is product data, not member data; Pass and feedback are not used), VI (the batch, the registry, and the run records stay backend-owned in the private area, with the advisory lock, recorded runs, and no raised errors; a new operational record adds a retention rule with proof), VII (every rule above is a deterministic backend test; the cron schedule is asserted scheduled exactly once; README and the backend document are updated in the same pull request), VIII (see the Calm Technology check).
- **One-sided decisions**: none revealed. Selection uses no Pass, Interested, or feedback data, and a run record holds counts only.
- **Retention**: the city batch records are purged after 180 days with the matching runs, proven by a test.
- **Refused surfaces**: none admitted. No tab, browse, search, score, rejection notification, gender field, group event, or messaging without mutual interest.
- **Calm Technology check (Principle VIII)**: *Reduce or add attention?* Reduces it: introductions arrive once a day at a predictable hour, and fewer weak ones are sent. *Inform or alarm?* Informs: the explanation says exactly why, in the members' own words; nothing announces a batch or a wait. *Can it live in the periphery?* Yes: the only member-facing change is better text on the existing screen and the existing notification. *Help two people meet, or keep them in the app?* Meet: a true reason to meet and a practical overlap are the whole output. *Fail quietly?* Yes: a failed or skipped run is recorded and alerts operations; a member sees nothing but the searching state. *Is there a simpler way?* The floor and the registry are the minimum that make reciprocity real; the batch reuses the existing schedule, lock, records, and alerts; no new function, secret, or surface. *Would a thoughtful professional find it normal?* Yes: one considered introduction on a weekday morning, explained plainly, is how a good connector behaves.
