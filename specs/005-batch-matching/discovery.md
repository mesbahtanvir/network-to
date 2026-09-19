# Discovery: Batch Matching

**Feature**: `005-batch-matching` (pre-spec discovery; the spec is written after the product owner
section 9)

**Created**: 2026-09-13

**Status**: Discovery with decisions recorded (section 9). Nothing here changes shipped behaviour. `README.md` and
`docs/SUPABASE_BACKEND.md` continue to describe the current matcher until a feature ships.

**Constitution**: Principles I, II, III, IV (gender), VI, VII, VIII are touched by any change to
matching. Section 8 lists which choices below stay inside the constitution and which would
need an amendment first.

## 1. The product, as matching sees it

network.to introduces two members in the same normalized city, one introduction at a time,
with a plain-language explanation of reciprocal professional value, and steps back once both
choose Interested and a 1:1 coffee is arranged. The member we build for is the newcomer
builder: new to a big North American city, working at a listed technology company, with a
concrete goal such as founding a company or changing specialty, who wants a few genuine
relationships built slowly and in person (`docs/PRODUCT_DEFINITION.md`).

The rules that bind the matcher (constitution Principle I, III, IV):

- Server-side, on the schedule; the client never generates introductions.
- Same normalized city only.
- Reciprocal professional relevance and overlapping meeting preferences are required.
- Honour each member's cadence (weekly, twice a month, monthly, exceptional only, paused),
  blocks, the 180-day no-repeat rule, and one active introduction per member.
- Both members must hold an active free month or a verified subscription.
- No introduction quota: sending nothing is required over sending below the quality threshold.
- No compatibility score, ranking, or popularity signal is computed for display; the ranking
  machinery stays invisible and relevance is explained in plain professional language.
- Gender is never collected or used.
- A Pass is unobservable by the other member and frees the member who passed for a new
  introduction at their cadence.

The product measures itself by real-world outcomes (`docs/PRODUCT_DEFINITION.md`, Success
signals): median days from onboarding completion to first introduction and the share of
members with none after seven days, the share of mutual introductions that lead to a recorded
meeting, feedback recorded within seven days, and connections still present after 90 days.
None is driven by lowering the quality threshold.

### What members give the matcher

| Source | Field | Shape | Used by matching today |
| --- | --- | --- | --- |
| `profiles` | `city_key` | generated, normalized | yes, hard filter |
| `profiles` | `company_domain`, `industry` | copied server-side from the registry | yes, consent filter and bonus |
| `profiles` | `topics` | free text, at most 12 (résumé draft emits at most 8) | yes, exact overlap |
| `profiles` | `growth_areas` | fixed list of 8, at most 4 chosen | yes, reciprocity |
| `profiles` | `contribution_areas` | fixed list of 8, at most 4 chosen (résumé draft uses the same list) | yes, reciprocity |
| `profiles` | `professional_ambition`, `current_focus` | member-authored prose | copy only |
| `profiles` | `growth_interest`, `contribution`, `contribution_boundaries`, `bio`, `role_scope` | member-authored prose | no |
| `profiles` | `years_experience` | fixed list of 5 bands | no |
| `profiles` | `help_formats` | fixed list of 4 | no |
| `networking_preferences` | `frequency` | 5 values | yes, cadence and pause |
| `networking_preferences` | `goals` | fixed list of 6 | yes, overlap count |
| `networking_preferences` | `relationship_mix` | one value exists in the UI | no |
| `networking_preferences` | `cross_company`, `cross_industry` | booleans | yes, consent filter |
| `meeting_preferences` | `areas`, `formats`, `windows` | fixed lists (5, 3, 3) | yes, hard overlap |
| `availabilities` | `area`, `time_window`, `expires_at` | Available today | no |
| `introduction_responses` | `decision` | interested or pass | only for the active-introduction rule |
| `meetup_feedback` | `outcome`, `stay_connected` | four fixed outcomes | no |
| `blocks` | pair | | yes, hard filter |
| `private.memberships` | access | | yes, hard filter |

## 2. How matching works today

Schedule and shell (`supabase/migrations/20260905000600_production_hardening.sql`):

- `pg_cron` job `network-to-hourly-matching` runs `private.run_matching_batch(25)` at minute 7
  of every hour.
- The batch takes an advisory lock (records `skipped` when held), expires `offered`
  introductions past `expires_at`, then calls `private.generate_one_introduction()` up to 25
  times, stopping at the first null. Every run is recorded in `private.matching_runs` with a
  count; failures are recorded, not raised. Operations alerts fire for a failed run and for no
  run in 25 hours. Runs are purged after 180 days.
- `generate-introductions` is a manual Edge Function that calls the same selection once; it is
  not deployed.

Selection (`private.generate_one_introduction()`, last redefined in
`supabase/migrations/20260912130000_private_pass.sql`):

1. Self-join `profiles` on `p1.id < p2.id and p1.city_key = p2.city_key`, joined to both
   members' networking preferences, meeting preferences, and memberships.
2. Hard filters: both active and onboarding complete; a non-empty city; membership access;
   neither paused; the cross-company and cross-industry consents of both; not blocked; no
   introduction between the pair in 180 days; neither has an active introduction (`offered` or
   `mutual`, except one the member has passed on); each member's last introduction is older
   than their cadence window (7, 14, 28, or 90 days).
3. Quality floor: `reciprocal_score >= 1` and at least one shared area, format, and window.
   `reciprocal_score` is the count of A's contribution areas that appear in B's growth areas
   plus the reverse.
4. Score: `reciprocal_score * 5 + topic_overlap * 2 + goal_overlap + cross_company + cross_industry`.
5. Order by score, then the pair whose members were introduced least recently, then random;
   take one.
6. Insert the introduction with templated copy ("{name} is working toward {ambition}. Their
   experience connects with your current focus: {focus}" and "You are both in the same city
   and prefer {format} around {area}.") and one `introduction_ready` event per member.

This is a greedy, one-pair-at-a-time selection. Each of the up to 25 iterations recomputes
the whole candidate set for every city.

## 3. Findings

Ordered by how much they change what members experience.

**F1. The reciprocity vocabulary cannot overlap, so the quality floor is almost unreachable.**
Growth areas are "Applied AI products", "Executive communication", "Engineering leadership",
"Platform strategy", "Product thinking", "Founder perspective", "Career transition", "Local tech
ecosystem". Contribution areas are "Distributed systems", "AI infrastructure", "Developer
tools", "Product strategy", "Engineering leadership", "Scaling teams", "Fundraising",
"Go-to-market" (`NetworkTo/Features/Onboarding/OnboardingView.swift`, mirrored in
`ProfileView.swift` and in the `process-resume` schema). The two lists share exactly one string,
"Engineering leadership". `reciprocal_score` is an exact overlap between one member's
contribution areas and the other's growth areas, so it can only be non-zero when one member
wants to grow in engineering leadership and the other offers it. Every other pair fails the
floor and is never introduced, whatever else they share. The demonstration pair in
`Models.swift` (Alex and Sarah) clears the floor only through that one term.

**F2. After a first mutual introduction a member is excluded from matching for good.** The
active-introduction filter treats `mutual` as active with no time bound, and nothing ever
changes an introduction's status after `mutual`: expiry updates only `offered`,
`end_conversation` and `block_member` update `conversations`, and the meetup follow-ups never
touch `introductions`. Meanwhile `get_current_introduction` stops returning the introduction
seven days after creation, so the member's Today shows "Looking beyond your usual circle"
while the backend can never produce a second introduction for them. This affects every member
whose first introduction succeeds.

**F3. Greedy single-pair selection is not batch matching.** Taking the global best pair, then
the next, consumes the most compatible members first and leaves members with rarer profiles
to whoever is left; it does not consider whether a different pairing would have served more
members above the floor. It also recomputes the full quadratic candidate set per iteration,
which is fine at hundreds of members per city and increasingly wasteful beyond that.

**F4. Topics are free text compared exactly.** "ML infrastructure" and "AI infrastructure"
do not overlap, so `topic_score` is usually zero and topics contribute little.

**F5. "Flexible within the city" is not a wildcard.** Area overlap needs a literal shared
string, so a member who chose only "Flexible within the city" never overlaps a member who chose
only "West side", though the flexible member meant to accept any area.

**F6. Available today is never read by matching.** The same-day loop ("Available today →
introduction → coffee within hours") is a product promise in `docs/UI_DESIGN_SPEC.md`, but
`availabilities` is only written by the client and purged daily.

**F7. Signals members provide are unused.** `relationship_mix`, `years_experience`,
`help_formats`, `growth_interest`, `contribution`, and `bio` never influence selection or copy.
Outcomes (`introduction_responses.decision`, `meetup_feedback.outcome`) are never used to learn.
`introduction_responses.private_feedback` exists but nothing writes it (a Pass collects no
reason by design).

**F8. "Exceptional introductions only" is a 90-day spacing, not a higher bar.** The member
asked for fewer, better introductions; today they get the same threshold, less often.

**F9. Explanations do not say what the matcher rewarded.** The copy names the other member's
ambition and the reader's own focus, which are true but not the reciprocal reason the pair was
chosen for. The UI spec's example ("Her perspective could help you understand how frontier AI
infrastructure teams operate") names the specific value; today's template cannot.

**F10. Runs record counts only.** There is no record per city of eligible members, why the
unmatched were unmatched (nobody in their city, no meeting overlap, below the floor, cadence),
or how far the floor was from being met. Time to first introduction and the share of members
with none after seven days cannot be reviewed from the data the matcher keeps.

**F11. Introductions arrive at any hour.** An hourly run offers an introduction the moment a
member becomes eligible and a partner exists, which can be 3 a.m. locally. A batch at a fixed
local time is calmer and matches "one good introduction a week is plenty".

Everything else checked holds: the advisory lock and `skipped` record, the failure record
instead of a raise, the membership check, the block check on the pairing path, the 180-day
rule, the pass semantics, and the retention rule.

## 4. The batch matching problem

For one city `c` at batch time `t`:

- **Eligible members** `V`: active, onboarding complete, membership access, not paused, no
  active introduction (an `offered` one not passed by them, or a `mutual` one within the
  window decided in D4), and their last introduction older than their cadence
  window.
- **Eligible pairs** `E`: both in `V`, not blocked either way, no introduction in 180 days,
  both consents satisfied, meeting overlap (areas with "Flexible within the city" as a
  wildcard, at least one shared format, at least one shared window), and relevance
  `q(u, v) >= τ` where `τ` is the quality floor.
- **Weight** `w(u, v) = q(u, v) + λ · (wait(u) + wait(v))`, where `wait` is the member's time
  since their last introduction (or since onboarding completion), normalized and capped, and
  `λ` is small enough that no pair below the floor can ever be chosen and a clearly better
  pair still wins over a slightly longer wait.
- **Choose** a matching `M ⊆ E` (each member in at most one pair) maximizing `Σ w`.
- **Create** one introduction per pair in `M`, with copy built from the same components that
  produced `q`. Members not in `M` keep the searching state until the next batch.

This is maximum-weight matching in a general (non-bipartite) graph, because members are not
two sides of a market. The floor is a constraint, never relaxed by the algorithm. Cardinality
is not maximized: the product forbids a quota, so the batch never adds a pair to raise the
count. In practice a maximum-weight matching over positive weights still pairs most members
who have any eligible partner.

The floor decides quality. The algorithm decides who, among pairs that already clear the
floor, is introduced this batch. F1 shows that today the floor is the binding problem; a
better algorithm over the current relevance model would change very little.

## 5. Relevance: what makes an introduction worthwhile

Proposed components, each in `[0, 1]`, all computable from existing fields, each mapped to a
sentence so the copy says exactly what was rewarded:

- **Reciprocal help** (the core, required in both directions): how well A's contribution
  areas serve B's growth areas and the reverse. Because the two lists differ (F1), the mapping
  is a product-owned affinity table between growth areas and contribution areas (exact
  match 1.0, curated adjacent match lower), edited by migration like the company registry. A
  first draft to edit: Applied AI products ← AI infrastructure, Product strategy; Executive
  communication ← Engineering leadership, Scaling teams, Fundraising, Go-to-market;
  Engineering leadership ← Engineering leadership, Scaling teams; Platform strategy ←
  Distributed systems, Developer tools, Product strategy; Product thinking ← Product strategy,
  Go-to-market, Developer tools; Founder perspective ← Fundraising, Go-to-market, Scaling
  teams. "Career transition" and "Local tech ecosystem" have no natural contribution area and
  need a product decision (decision D3).
- **Shared direction**: overlap of the six networking goals (Jaccard).
- **Topic affinity**: normalized-token overlap of topics as a weak signal (fixes the worst of
  F4); the upgrade path is text embeddings (section 8).
- **Peer fit**: distance between `years_experience` bands, read through `relationship_mix`
  ("Peers and adjacent leaders" means within about one band is ideal).
- **Perspective**: cross-company and cross-industry, as today.
- **Meeting practicality**: a hard filter, not a score, with the flexible wildcard (F5).

Floor `τ`: reciprocal help above zero in both directions (decision D5). The other
components rank pairs above the floor; they never admit one.

Explanations ("Why you should meet", "Why they may want to meet you") are assembled from the
components that fired, in the members' own words: the growth area the reader chose, the
contribution area the other member chose, the other member's own ambition sentence, and
their `contribution` sentence. For example: "You want to grow in platform strategy. Maya has
led product strategy for a developer platform and offers to compare approaches. She is working
toward: {Maya's ambition}." Deterministic copy can be tested and never invents a claim.

## 6. Algorithm options

| Option | Quality of result | Cost | Fit |
| --- | --- | --- | --- |
| A. Greedy by weight over the whole eligible edge set, once per batch | At least half the optimal total weight; usually far closer when the floor filters heavily | One SQL pass per city plus a loop over sorted edges | Fits Principle VIII (minimum technology); fully testable with pgTAP; fixes F3's recomputation and adds the wait term |
| B. Exact maximum-weight matching (Edmonds' blossom) | Optimal for the stated objective | Needs a general-purpose language: a Deno Edge Function with a pure `_shared/matching.ts` and tests; SQL still owns eligibility and the commit | Consistent with `deliver-notifications` (cron → `pg_net` → function → service-role RPC); more moving parts and a new Vault secret |
| C. Stable roommates (Irving) | Stability with respect to preference lists | A stable matching may not exist; preferences here are symmetric scores | Poor fit: reciprocal interest is already the acceptance step |
| D. Per-member top-k candidates, then A or B on the sparse graph | Same as A or B | Keeps cost near-linear in members when a city has tens of thousands | Only needed at a scale far beyond the first cities |

Recommendation: A first, on the new relevance model, with per-run diagnostics that also
record the total weight chosen. If diagnostics show eligible members left unmatched whose
partners were consumed by marginally better pairs, upgrade the selection step to B behind the
same two RPCs (one that returns weighted eligible pairs per city, one that commits chosen
pairs after re-validating them). The relevance model and the floor matter far more than the
gap between A and B at the density of a first city.

## 7. Architecture options

**Option 1. Postgres-only batch (recommended first).** One redefined `private.run_matching_batch()`:
expire, then for each city with at least two eligible members compute eligible pairs and
weights into a temporary table in one pass, apply the floor, select greedily in weight order
with each member used at most once, insert introductions and events, and record per-city
diagnostics. The schedule changes from hourly to the cadence decided in D1 (per-city local
time needs a small city registry with a time zone, or a single UTC hour to start). No new
secret, no new function, no client change. The `generate-introductions` operations function
keeps working by calling the batch.

**Option 2. Postgres prepares, an Edge Function solves, Postgres commits.** `pg_cron` calls
`private.dispatch_matching()`, which posts through `pg_net` to a `run-matching` function with
a `matching_job_secret` from Vault (the notification pattern). The function calls a
service-role RPC that returns the weighted eligible pairs for one city, runs exact matching in
`_shared/matching.ts` (unit-tested), and calls a second RPC that re-validates each pair inside
the database and creates the introductions idempotently by run id. Without the Vault secret
the dispatcher stays idle and the stalled-matching alert fires, as the constitution requires
for missing configuration.

**Option 3. Option 1 with Option 2 as an upgrade.** Build the two RPCs from the start (pairs
out, chosen pairs in) and let the batch call the greedy selector in SQL; the function can take
over selection later without changing eligibility, commit, or diagnostics. This is the
recommendation: it is Option 1 today with the seam Option 2 needs.

Data changes under any option:

- `private.growth_contribution_affinity` (growth area, contribution area, weight), product-owned,
  edited by migration.
- `private.matching_run_cities` (run id, `city_key`, eligible members, eligible pairs, pairs
  above the floor, introductions created, total weight, counts of unmatched members by reason)
  with the same 180-day retention as `matching_runs` and a pgTAP proof.
- `introductions.matching_run_id` (nullable) for traceability. Relevance components stay in the
  private schema if kept at all; nothing resembling a score is ever readable by a client.
- A `private.introduction_is_active(introduction, member, now)` helper that gives `mutual` a
  bound (F2), decided in D4.
- Cadence semantics for `exceptional_only` (F8), decided in D6.

Tests: pgTAP for each rule (one introduction per member per batch, higher weight wins, the
floor is never crossed, wait raises priority without crossing the floor, cadence, blocks, the
180-day rule, pass semantics, the flexible wildcard, membership access, same city, the `mutual`
bound, run diagnostics, retention, privilege assertions, cron scheduled once); Deno tests for
`_shared/matching.ts` if Option 2 is built; no iOS change unless copy structure changes.

## 8. Constitution touchpoints

Stays inside the constitution: everything in sections 4 to 7 as written. Matching remains
server-side on a schedule, same city, reciprocal, cadence-aware, block-aware, no quota, no
displayed score, gender absent. A schedule change updates the "Schedules" line of Product and
Platform Constraints and the docs in the same PR.

Needs a product decision but no amendment: the affinity table (a registry like companies),
the `mutual` bound, the meaning of exceptional only, batch timing, using stored preferences.

Would need an amendment first:

- LLM-drafted explanations or LLM-judged relevance. "AI: the DeepSeek Responses API MUST be
  called only from the rate-limited `process-resume` function" (Product and Platform
  Constraints), and the privacy review covers résumé text only. Sending two members' profiles
  to a provider is a new disclosure.
- Text embeddings for topic and ambition affinity. Supabase's built-in edge model (`gte-small`
  through `Supabase.ai.Session`) runs inside the project's own runtime with no third-party
  call, so it is not the DeepSeek rule, but it is "AI in matching" and should be recorded in
  the constraints as a MINOR amendment if adopted. It is the natural upgrade path once the
  deterministic model is instrumented.
- Using Pass history or meetup feedback as a private ranking signal. Not forbidden (only
  displayed scores are), but it is a new use of private data and belongs in the constitution
  and the member-facing privacy labels before it ships.

## 9. Decisions (product owner, 2026-09-19)

Every question in the first version of this document was answered by the product owner on
2026-09-19; the decisions below are what the spec is written from.

- **D1. Batch timing.** One batch per city per day at about nine in the morning local time.
  Until a second city has members, one fixed UTC hour for Toronto; a city time-zone registry
  follows when needed. A member who passes is eligible again at the next batch, subject to
  their cadence. The hourly schedule is retired.
- **D2. Scale.** At most a few thousand eligible members per city per batch over the next
  year. Postgres-only batch with greedy selection, built behind the two-RPC seam (weighted
  pairs out, chosen pairs in) so an exact solver can replace selection later.
- **D3. Vocabulary.** A product-owned affinity table between the existing growth areas and
  contribution areas ships in this feature, backend only. Replacing both lists with one shared
  taxonomy in onboarding, profile editing, and the résumé drafter is its own later feature.
  "Career transition" and "Local tech ecosystem" are mapped in the table with the product
  owner's edits before the migration lands.
- **D4. After mutual interest.** A mutual introduction counts as a member's active
  introduction until its seven-day expiry. A member in a live conversation may receive their
  next introduction after that, still subject to cadence.
- **D5. Floor strictness.** Reciprocal help is required in both directions. Early members may
  wait; the diagnostics show how long.
- **D6. Exceptional only.** A higher floor and at most one introduction every 28 days.
- **D7. Fairness.** Waiting time raises priority within the floor, bounded, never crossing it.
- **D8. Learning from outcomes.** Not in this feature. Diagnostics are recorded now; any use
  of Pass history or meetup feedback in ranking needs its own constitution amendment.
- **D9. AI.** Explanations are deterministic, assembled from the members' own words and the
  components that fired. No amendment. Embeddings are the recorded upgrade path for topic and
  ambition affinity, behind the same relevance interface.
- **D10. Available today.** A follow-up feature. The batch is designed so the same selection
  can run over the availability subgraph later.
- **D11. Unused preferences.** Experience band distance, read through relationship mix, becomes
  the peer-fit component.

## 10. Sequence after the answers

1. `/speckit-specify` for `005-batch-matching` from this discovery and the decisions, including
   the Calm Technology check and the retention rule for `matching_run_cities`.
2. `/speckit-clarify` for anything still open, `/speckit-plan`, `/speckit-tasks`.
3. Implement as one migration per concern (affinity registry; batch selection and
   diagnostics; the `mutual` bound and cadence semantics; schedule change), each with pgTAP,
   then update `docs/SUPABASE_BACKEND.md`, `README.md`, and the constitution's schedule line
   in the same PR.
