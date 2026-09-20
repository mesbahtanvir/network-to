# Tasks: Batch Matching

**Input**: Design documents from `/specs/005-batch-matching/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Required by the constitution (Principle VII): pgTAP tasks land in the same change as
the behaviour they protect. No iOS test is needed because no client code changes.

**Organization**: the registry and the helpers are foundational; Story 1 is the floor, the
fit, and the explanations; Story 2 is the mutual bound and cadence; Story 3 is the daily batch
and fairness; Story 4 is the run records. Most backend tasks edit the same migration file in
sequence, so they are ordered, not parallel.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4)
- Include exact file paths in descriptions

## Path Conventions

Supabase backend: `supabase/migrations/`, `supabase/tests/database/`, `supabase/functions/`;
documents in `docs/`, `README.md`, `.specify/memory/constitution.md`.

---

## Phase 1: Setup

- [X] T001 Build a local verification harness in the session scratchpad (not committed): a throwaway Postgres cluster with pgTAP and stub `auth`, `cron`, `net`, `vault`, `storage`, and `extensions` objects, applying `supabase/migrations/*.sql` in order and running each `supabase/tests/database/*.test.sql`; if pgTAP or the stubs cannot be provided, record in the pull request that the workflow validate job is the proof

---

## Phase 2: Foundational

**Purpose**: the registry and the pure helpers every story reads

- [X] T002 Create `supabase/migrations/20260919150000_growth_contribution_affinity.sql`: opening comment (product-owned registry, edited only by migration, no operator step); `private.growth_contribution_affinity (growth_area text, contribution_area text, strength text check (strength in ('same', 'adjacent')), created_at timestamptz default now(), primary key (growth_area, contribution_area))` with `revoke all` from `public`, `anon`, `authenticated`; the seed from data-model.md with `on conflict do nothing`; `private.growth_service(p_growth text[], p_contribution text[]) returns table (same_count integer, adjacent_count integer, served_growth_area text, serving_contribution_area text)` per contracts/database.md (identity always serves as `same`; explained pair per data-model.md; zeros and nulls on empty input), revoked from every role
- [X] T003 Create `supabase/migrations/20260919150100_batch_matching.sql` with the opening comment (daily batch replaces the hourly job, no operator step) and the schema part: `alter table public.introductions add column reciprocal_for_a text not null default ''`, `reciprocal_for_b text not null default ''`, `matching_run_id uuid`; the backfill `reciprocal_for_a = reason_for_b, reciprocal_for_b = reason_for_a` for rows where both new columns are empty; `private.matching_run_cities` per data-model.md (`run_id uuid references private.matching_runs(id) on delete cascade`, `city_key text`, the nine integer counts each `check (>= 0)`, `total_weight numeric not null default 0`, `created_at timestamptz default now()`, primary key `(run_id, city_key)`) with `revoke all` from `public`, `anon`, `authenticated`
- [X] T004 In `supabase/migrations/20260919150100_batch_matching.sql` add the helpers per contracts/database.md, each `set search_path = ''` and revoked from every role: `private.normalize_topic(text)` (immutable), `private.experience_band(text)` (immutable; "1–3 years" 1 … "15+ years" 5, hyphen or en dash, else null), `private.cadence_interval(text)` (immutable; weekly 7, twice_monthly 14, monthly 28, exceptional_only 28 days, else null), `private.lower_first_word(text)` (immutable), `private.has_active_introduction(uuid, timestamptz)` (stable, security definer: unexpired `offered` not passed on by the member, or unexpired `mutual`)

**Checkpoint**: both migrations apply cleanly on the harness; existing tests still pass except the assertions that name the removed hourly job and the old selection function

---

## Phase 3: User Story 1 - Only Worthwhile Introductions Are Sent (Priority: P1) 🎯 MVP

**Goal**: only pairs where each member serves the other are introduced, and the explanations name the reason in the members' own words

**Independent Test**: `supabase/tests/database/batch_matching.test.sql` scenarios for the floor, the flexible wildcard, the registry, and the explanation content

- [X] T005 [US1] In `supabase/migrations/20260919150100_batch_matching.sql` add `private.matching_eligible_members(p_now timestamptz)` returning one row per eligible member with the derived fields in data-model.md (city_key, name, company_domain, industry, growth_areas, contribution_areas, contribution, professional_ambition, help_formats, areas, formats, windows, goals, cross_company, cross_industry, exceptional, flexible, band, topics_norm, serves_same, serves_adjacent, wait_days, wait_bonus), applying eligibility rules 1 to 5 (`is_active`, `onboarding_complete`, non-empty city, `private.has_membership_access`, not paused, `not private.has_active_introduction`, cadence spacing from the most recent introduction)
- [X] T006 [US1] In the same migration add `private.matching_candidate_pairs(p_city_key text, p_now timestamptz)` returning `(member_a, member_b, meets boolean, above_floor boolean, weight numeric, same_ab, adjacent_ab, same_ba, adjacent_ba, goal_jaccard, shared_topics, band_distance, cross_company, cross_industry, served_growth_a, serving_contribution_b, served_growth_b, serving_contribution_a, wait_a, wait_b)`: pair rules 1 to 3 always (blocks, 180-day repeat, consents); `meets` per rule 4 with the flexible wildcard; `above_floor` per rules 5 and 6 (both directions served; exceptional members need `same` in both directions and a shared goal); fit and weight exactly as research.md section 3 (service capped at 2.0 per direction, 0.5 × Jaccard of goals, 0.2 × least(3, shared normalized topics), peer fit 0.4/0.2/0, perspective 0.2 + 0.2, wait bonus 0.15 × least(28, wait_days) / 28 per member)
- [X] T007 [US1] In the same migration add `private.compose_introduction_copy(...)` returning `(reason_for_a, reason_for_b, reciprocal_for_a, reciprocal_for_b, meeting_context)` per contracts/copy.md: first name, lower-cased area names through `private.lower_first_word`, first help format, quoted `contribution` and `professional_ambition` with sentences omitted when empty, meeting context with the first shared format and area (flexible handling), no exclamation points
- [X] T008 [US1] In the same migration add `private.matching_pair_is_valid(p_a uuid, p_b uuid, p_now timestamptz)` (both eligible, same city, pair rules 1 to 6 re-evaluated from the tables) and `private.commit_matching_pairs(p_run_id uuid, p_city_key text, p_pairs jsonb, p_now timestamptz) returns table (created integer, dropped integer, total_weight numeric)`: for each `{"a","b","weight"}` skip unless valid and neither member already introduced in this run, insert the introduction with `matching_run_id` and the composed copy, insert two `introduction_ready` events with `{"introduction_id": ...}`
- [X] T009 [US1] In the same migration redefine `public.get_current_introduction()` with `reason_for_them` read from `reciprocal_for_a` / `reciprocal_for_b` (everything else unchanged, including `company_mark`), restating the revoke from `public`, `anon` and the grant to `authenticated`
- [X] T010 [US1] Create `supabase/tests/database/batch_matching.test.sql` with the Toronto fixture through `auth.users` and assertions for: registry table present and revoked; registry covers every growth area; `growth_service` counts and explained pair; a serving pair is introduced by `private.run_matching_batch(1000)`; a one-direction pair is never introduced; no meeting overlap means no introduction; the flexible wildcard overlaps; both explanations name the served growth area, the serving contribution area, the quoted contribution and ambition; empty free text omits its sentence; no "!" and no forbidden words; `get_current_introduction` returns `reason_for_you` and `reason_for_them` from the right columns; existing rows keep their display after the backfill

**Checkpoint**: the floor and the explanations are proven on the harness

---

## Phase 4: User Story 2 - One Introduction at a Time, Then the Next (Priority: P1)

**Goal**: a mutual introduction stops blocking its members at its expiry; cadence, Pass, blocks, the 180-day rule, and membership keep their meaning

**Independent Test**: `batch_matching.test.sql` scenarios for the mutual bound before and after expiry, the passer's cadence, the waiting member, blocks, the 180-day rule, each cadence window, and lapsed membership

- [X] T011 [US2] In `supabase/tests/database/batch_matching.test.sql` add assertions: a `mutual` introduction younger than seven days blocks both members; older than seven days it blocks neither and the conversation is unchanged; a passed-on introduction frees the passer only after their cadence spacing; a waiting member with an unanswered introduction is not paired; a pair introduced 100 days ago is not paired again; a blocked pair is never paired and a block recorded between candidates and commit drops the pair; weekly, twice-monthly, monthly, and exceptional-only spacing; a paused member and a lapsed membership receive nothing

**Checkpoint**: eligibility rules proven

---

## Phase 5: User Story 3 - A Daily Batch That Treats the City Fairly (Priority: P2)

**Goal**: one batch per city per day, greedy by weight with bounded waiting priority, one introduction per member per batch, run on the daily schedule or on demand

**Independent Test**: `batch_matching.test.sql` scenarios for one-per-member, fairness ordering, the floor never crossed by waiting, the skipped run under the lock, determinism, the cron assertion, and the manual run

- [X] T012 [US3] In `supabase/migrations/20260919150100_batch_matching.sql` add `private.select_matching_pairs(p_city_key text, p_now timestamptz, p_limit integer) returns table (member_a uuid, member_b uuid, weight numeric)`: greedy over `matching_candidate_pairs` where `above_floor`, ordered `weight desc, greatest(wait_a, wait_b) desc, member_a, member_b`, each member at most once, at most `p_limit` pairs, no `random()`
- [X] T013 [US3] In the same migration drop `public.generate_next_introduction()` and `private.generate_one_introduction()`, redefine `private.run_matching_batch(p_limit integer)` (cap 1 to 5000 per city; advisory lock else a `skipped` run; expire `offered` past expiry; per city with at least one eligible member: select, commit, one `matching_run_cities` row; `completed` with the total or `failed` with the message; never raises), add `public.run_matching_now() returns jsonb` (service role only; revoke from `public`, `anon`, `authenticated`; grant to `service_role`), and replace the cron job: unschedule `network-to-hourly-matching`, schedule `network-to-daily-matching` at `7 13 * * *` running `select private.run_matching_batch(1000)`
- [X] T014 [P] [US3] Update `supabase/functions/generate-introductions/index.ts` to call `rest/v1/rpc/run_matching_now` and return its JSON (`run_id`, `status`, `introductions_created`); keep the `MATCHING_JOB_SECRET` check; `deno check` passes
- [X] T015 [US3] In `supabase/tests/database/batch_matching.test.sql` add assertions: a member with two possible partners receives exactly one introduction; equal fit prefers the longer-waiting member; a stronger fit beats a longer wait; waiting never admits a pair below the floor; a city with one eligible member creates nothing; no cross-city pair; a run started while the advisory lock is held is recorded `skipped` (use `pg_advisory_xact_lock` in a `dblink`-free way: take the lock in the test transaction, call the batch, expect `skipped`); two runs on identical data from a savepoint create the same pairs; `network-to-daily-matching` scheduled exactly once and `network-to-hourly-matching` absent; `run_matching_now` raises for `authenticated` and returns a run id for `service_role`

**Checkpoint**: the batch, the schedule, and fairness proven

---

## Phase 6: User Story 4 - Operations Can See Why (Priority: P3)

**Goal**: per-city counts by reason for every run, purged with the run

**Independent Test**: `batch_matching.test.sql` scenarios for the counts and the retention cascade

- [X] T016 [US4] In `private.run_matching_batch` (same migration) compute the per-city counts from the candidate stage flags: `eligible_members`; `unmatched_no_peers` (no other eligible member in the city); `unmatched_all_excluded` (every candidate failed rules 1 to 3); `unmatched_no_meeting_overlap` (candidates remained, none `meets`); `unmatched_below_floor` (some `meets`, none `above_floor`); `unmatched_partners_taken` (some `above_floor`, not selected); `pairs_above_floor`; `pairs_dropped_at_commit`; `introductions_created`; `total_weight`
- [X] T017 [US4] In `supabase/tests/database/batch_matching.test.sql` add assertions: a run over a city with members in each unmatched situation records the expected counts; a run creating nothing is `completed` with zero and the stalled alert does not fire; a failed run still becomes a pending alert; an old run with a city row is removed by `private.run_retention_maintenance()` together with its city row; `matching_run_cities` is revoked from `anon` and `authenticated`; a city row holds no member identifier

**Checkpoint**: operations records proven

---

## Phase 7: Polish & Cross-Cutting Concerns

- [X] T018 Adjust existing tests: `supabase/tests/database/schema.test.sql` (daily job present once, hourly job absent, new tables and functions exist; plan count), `supabase/tests/database/production_behavior.test.sql` and `supabase/tests/database/introduction_privacy.test.sql` (call `private.run_matching_batch(1000)` instead of `private.generate_one_introduction()`; give fixtures serving areas and meeting overlap; plan counts), `supabase/tests/database/launch_operations.test.sql` (retention of city rows; plan count), `supabase/tests/database/company_marks.test.sql` (five jobs assertion still holds)
- [X] T019 [P] Update `docs/SUPABASE_BACKEND.md` (schedules line: daily matching at 13:07 UTC; the matching paragraph: registry, floor, fit, wait bonus, one per member per batch, mutual bound, exceptional-only, explanations, run records and how to compute time to first introduction; the operations function returns the run; production status list) and `README.md` ("daily matching")
- [X] T020 [P] Amend `.specify/memory/constitution.md` to 1.6.0: Schedules line (daily matching at 13:07 UTC, per-city cap 1000), Product and Platform Constraints gains the affinity registry as product data changed by migration, Retention gains `matching_run_cities` (with its run), Last Amended 2026-09-20, version note in the migration plan paragraph
- [X] T021 Run the harness over all migrations and tests, `deno check supabase/functions/*/index.ts supabase/functions/_shared/*.ts`, and `deno test supabase/functions` where Deno is available; commit; push; update the pull request description with what ran

---

## Dependencies & Execution Order

- T001 first (verification for everything after).
- T002 → T003 → T004 (foundation, in file order).
- T005 → T006 → T007 → T008 → T009 → T010 (US1, same migration file then its test).
- T011 after T010 (extends the same test file).
- T012 → T013 → T015 (US3 in file order); T014 in parallel with any of them.
- T016 inside T013's function, then T017.
- T018 after T013 (the hourly job and old function are gone); T019 and T020 in parallel with each other after T013; T021 last.

## Implementation Strategy

Build the foundation and Story 1 first and prove them on the harness (the floor and the
explanations are the product's promise). Story 2 is mostly assertions over the helpers built in
Phase 2. Story 3 turns the pieces into the daily batch and retires the hourly job; Story 4
records what happened. One pull request carries all of it with the docs and the constitution
amendment, as the constitution requires.
