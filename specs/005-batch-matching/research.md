# Research: Batch Matching

**Feature**: 005-batch-matching | **Date**: 2026-09-19

Every decision below implements a decision the product owner took on 2026-09-19
([discovery.md](discovery.md) section 9). Nothing is left as NEEDS CLARIFICATION.

## 1. Selection: greedy by weight in SQL, behind a solver seam

**Decision**: per city, compute every pair above the floor with its weight into a temporary
table, then walk the pairs in descending weight (ties broken by the longer wait, then member
ids) and take a pair whenever neither member has been taken. Members and taken pairs live in
temporary tables with primary keys so each check is an index lookup. The candidate query and
the commit step are separate private functions (`matching_candidate_pairs`,
`commit_matching_pairs`) so a future exact solver (Edmonds' blossom in a Deno function) can
consume the same candidates and commit through the same re-validation without touching
eligibility, copy, or records.

**Rationale**: decision D2 bounds a city at a few thousand eligible members, where greedy
selection over a floor-filtered edge set is within a few percent of optimal in practice and
never below half. Postgres-only keeps Principle VIII's minimum technology and Principle VI's
single trust boundary; no secret, no `pg_net` call, no function to be down.

**Rejected**: exact maximum-weight matching now (a second runtime and a Vault secret for a
gain the diagnostics cannot yet justify); stable roommates (may have no solution; preferences
here are symmetric scores); maximizing the number of introductions (a quota by another name).

## 2. The floor and the registry

**Decision**: `private.growth_contribution_affinity(growth_area, contribution_area, strength)`
with `strength in ('same', 'adjacent')`. A contribution area serves a growth area when the two
terms are identical after trimming and case folding (always `same`, registry row or not) or
when the registry lists the pair. The floor is at least one served growth area in each
direction. The first content is the discovery draft with two additions for the areas no
contribution serves exactly: "Career transition" ← Engineering leadership, Product strategy,
Scaling teams; "Local tech ecosystem" ← Fundraising, Go-to-market, Scaling teams. The
product owner edits the seed in the pull request; the registry changes only by migration.

**Rationale**: identical terms serving without a row means the fixtures that use one term on
both sides keep working and a future shared taxonomy needs no registry rows. The table is
small (about 25 rows) and readable by the product owner in the SQL editor.

**Rejected**: free-text similarity for the floor (opaque, not product-owned); requiring an
onboarding change first (decision D3 defers the taxonomy).

## 3. Fit and weight

**Decision** (per pair A, B):

| Component | Definition | Range |
|-----------|------------|-------|
| service A→B | `least(2.0, 1.0 × same_count + 0.6 × adjacent_count)` of A's contribution areas serving B's growth areas | 0 to 2.0 |
| service B→A | the same the other way | 0 to 2.0 |
| shared direction | `0.5 × Jaccard(goals_A, goals_B)` | 0 to 0.5 |
| topics | `0.2 × least(3, shared normalized topics)` | 0 to 0.6 |
| peer fit | experience band distance 0 or 1 → 0.4; 2 → 0.2; otherwise or unknown → 0 | 0 to 0.4 |
| perspective | 0.2 if different companies, 0.2 if different industries | 0 to 0.4 |
| **fit** | sum | 0.6 to 5.9 above the floor |
| wait bonus | per member `0.15 × least(28, wait_days) / 28`; wait measured from the member's most recent introduction, else from `trial_started_at` (onboarding completion) | 0 to 0.3 per pair |
| **weight** | fit + wait bonus of both members | |

Exceptional-only floor for a member with that frequency: `same_count ≥ 1` in both directions
and at least one shared goal.

**Rationale**: the same-versus-adjacent gap in one direction is 0.4, so the largest possible
pair bonus (0.3) can reorder pairs of comparable fit but never beats one stronger match
(FR-019). The cap of 2.0 per direction stops a member with many areas from dominating.
Relationship mix has one value today ("Peers and adjacent leaders"), so peer fit reads band
distance directly; a future value changes only this mapping. Topic normalization is case
folding, non-alphanumerics to single spaces, trimming; no stemming, so "AI infrastructure"
and "ML infrastructure" stay different (embeddings are the recorded upgrade path).

**Rejected**: a multiplicative or learned model (unexplainable, and decision D8 defers
learning); using the fit numbers in copy (Principle II).

## 4. Explanations addressed to the reader

**Finding**: `get_current_introduction` returns `reason_for_you` and `reason_for_them` by
picking `reason_for_a` or `reason_for_b` according to who is asking, so one stored string is
read as "why you should meet" by one member and as "why they may want to meet you" by the
other. Second-person copy cannot be correct in both slots.

**Decision**: keep `reason_for_a` and `reason_for_b` as "why this member should meet the
other", written to that member, and add `reciprocal_for_a` and `reciprocal_for_b` as "why the
other may want to meet this member", also written to that member. The read model returns
`reason_for_you` from the first pair and `reason_for_them` from the second. Existing rows are
backfilled so their display is unchanged. The conversation read model's `introduction_reason`
already shows the caller's own "why you should meet" text and needs no change. Templates are
in [contracts/copy.md](contracts/copy.md); every piece comes from what the members chose or
wrote; empty pieces are omitted; the other member is named by first name or "they".

**Rejected**: neutral third-person copy (addresses the reader by name); four keys in the read
model (client change for no gain).

## 5. Active introductions, cadence, and the mutual bound

**Decision**: `private.has_active_introduction(member, now)` is true when an introduction with
`expires_at > now` involves the member and either is `offered` and the member has not passed
on it, or is `mutual`. No status transition is added; `mutual` keeps meaning "both chose
Interested". Cadence spacing is measured from the member's most recent introduction of any
status: weekly 7, twice a month 14, monthly 28, exceptional only 28 (from 90), paused never.

**Rationale**: the bound is time-based so nothing about a conversation changes at expiry and
no notification is sent (FR-015); `expires_at` is already set on every introduction.

**Rejected**: closing a mutual introduction at expiry (a status change a client could notice;
`get_current_introduction` already stops returning it by time); measuring cadence from the
last Interested response (rewards passing).

## 6. Run records and reasons

**Decision**: `private.matching_run_cities` holds, per run and city: eligible members; members
unmatched by reason (no other eligible member; every candidate excluded by a block, a repeat
within 180 days, or a consent; no meeting overlap; no pair above the floor; every partner
taken by another pair this batch); pairs above the floor; pairs dropped at commit;
introductions created; total weight. Reasons are computed per member from stage flags on the
pair table: a member's reason is the first stage at which they have zero candidates. The
row cascades from `matching_runs`, so the existing 180-day purge covers it; a pgTAP assertion
proves it.

**Rationale**: FR-020 and FR-023; counts only, so the record can never identify a member.

**Rejected**: a per-member table (identifies members, needs its own retention and privacy
labels); computing time to first introduction in the batch (derivable from `memberships` and
`introductions` in a query; documented in `docs/SUPABASE_BACKEND.md`).

## 7. Schedule and the operations path

**Decision**: cron `network-to-daily-matching` at `7 13 * * *` (13:07 UTC: 9:07 in Toronto
during daylight time, 8:07 otherwise), running `private.run_matching_batch(1000)` where the
argument is now the per-city cap (a safety bound, never a target). The hourly job is
unscheduled in the migration. `public.generate_next_introduction()` and
`private.generate_one_introduction()` are dropped; `public.run_matching_now()` (service role)
runs the same batch on demand and returns `{run_id, introductions_created, status}`; the
optional `generate-introductions` function calls it and returns that JSON.

**Rationale**: decision D1; the 25-hour stalled alert still works with one run a day; the
run-now path keeps FR-005 without a second code path.

**Rejected**: per-city local hours now (needs a time-zone registry; decision D1 defers it);
keeping the hourly job disabled as a fallback (two schedules to reason about).

## 8. Performance

**Decision**: per city, one set-based query builds a per-member temporary table with
precomputed arrays: the growth areas served by the member's contributions (`same` and
`adjacent` sets), normalized topics, goals, experience band, a `flexible` flag, and the wait
bonus. The pair query self-joins on `member_a < member_b`, applies the pair rules, and tests
the floor with array overlap (`&&`) before computing counts for the surviving pairs. The
greedy pass iterates only pairs above the floor.

**Rationale**: 3,000 members give 4.5 million pair checks, each an array overlap on short
arrays; that is seconds to a few minutes in Postgres, well inside SC-007. Existing indexes
(`profiles_active_city_key_idx`, `introductions_member_a_idx`, `introductions_member_b_idx`,
the blocks primary key) cover the eligibility and repeat checks.

**Rejected**: per-pair helper function calls for the floor (millions of function calls);
top-k sparsification (not needed at decision D2's scale; noted as the next step if it is).

## 9. Determinism and tests

**Decision**: no `random()` anywhere; ties break by weight, then the greater of the two wait
values, then `member_a`, `member_b`. The pgTAP file runs the batch twice on identical data
using a savepoint and asserts the same pairs. Fixtures follow `introduction_privacy.test.sql`:
members created through `auth.users` so the triggers create profiles, preferences, and (on
completing onboarding) memberships; profile arrays and preferences set by update.

**Rationale**: SC-008; the constitution forbids randomness in fixtures and the existing
matcher's `random()` tie-break made a failure irreproducible.

## 10. Local verification

**Finding**: the authoring environment has no Docker daemon and no Supabase CLI; Postgres 16
binaries and `psql` exist, without pgTAP.

**Decision**: implementation attempts a local harness (a throwaway Postgres cluster with stub
`auth`, `cron`, `net`, and `vault` objects and pgTAP, applying all migrations then the test
files). If the harness cannot be built in the environment, the pull request's validate job
is the proof and the pull request description says so, per Principle VII.

## Risks carried into implementation

- The registry seed is a product decision; the wrong mapping introduces the wrong people.
  The pull request asks the product owner to review the seed table explicitly.
- `run_matching_batch` is redefined in full; the adjusted existing tests and the new file must
  both pass before merge.
- Copy quality depends on members' free text (`contribution`, `professional_ambition`); the
  templates omit empty pieces and quote text verbatim, so a poorly written ambition is shown
  as written. Accepted: the words are the member's own, as the design philosophy requires.
- The daily hour is UTC-fixed; a second city needs the time-zone registry before its members
  arrive.
