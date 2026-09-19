# Implementation Plan: Batch Matching

**Branch**: `005-batch-matching` | **Date**: 2026-09-19 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/005-batch-matching/spec.md`, decisions in
[discovery.md](discovery.md) section 9

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Replace the hourly one-pair-at-a-time matcher with one daily batch per city, entirely in
Postgres. Two migrations: the first adds the product-owned affinity registry between growth
areas and contribution areas (`private.growth_contribution_affinity`) with its first content;
the second adds the batch. The batch computes, per city, every eligible pair that clears the
quality floor (each member's contribution areas serve at least one of the other's growth
areas, in both directions), weights it by fit plus a bounded waiting bonus, selects pairs
greedily by weight with each member used at most once, re-validates each chosen pair, creates
the introductions with deterministic second-person explanations, and records per-city counts
in `private.matching_run_cities`. A mutual introduction counts as active only until its
expiry; "exceptional only" means a stronger floor and 28-day spacing. The hourly cron job is
replaced by `network-to-daily-matching` at 13:07 UTC. The selection step sits behind two
private functions (candidate pairs out, chosen pairs committed after re-validation) so an
exact solver can replace it later. No Edge Function is added, no client change, no new secret.
`README.md`, `docs/SUPABASE_BACKEND.md`, and the constitution's schedule line change in the
same pull request.

## Technical Context

**Language/Version**: PL/pgSQL and SQL on Postgres 17 (Supabase); TypeScript on Deno v2.5.2
only for the optional `generate-introductions` operations function's response

**Primary Dependencies**: none new (`pg_cron`, `pgcrypto`, pgTAP already present)

**Storage**: Postgres. New: `private.growth_contribution_affinity` (registry),
`private.matching_run_cities` (per-city run records), two text columns and one uuid column on
`public.introductions`. Existing: `profiles`, `networking_preferences`,
`meeting_preferences`, `introductions`, `introduction_responses`, `blocks`,
`private.memberships`, `private.matching_runs`

**Testing**: pgTAP (`supabase/tests/database/batch_matching.test.sql`, new; `schema`,
`production_behavior`, `introduction_privacy`, `launch_operations`, and `company_marks` tests
adjusted), `deno check` for the operations function, the Supabase workflow's validate job on
the pull request. Docker is not available in the authoring environment, so local runs use a
Postgres harness when one can be built and otherwise the workflow is the proof (recorded in
the pull request description as the constitution requires)

**Target Platform**: Supabase hosted project (staging, then production), unchanged iPhone app

**Project Type**: Supabase backend of a mobile app (existing layout)

**Performance Goals**: a city batch with 3,000 eligible members completes in under ten
minutes; pair generation is one set-based query per city over precomputed per-member arrays
(array overlap for the floor), with the loop confined to the greedy pass over pairs above the
floor

**Constraints**: no introduction below the floor (FR-004); one introduction per member per
batch (FR-002); deterministic given identical data (SC-008); nothing readable by a member
carries a relevance value (Principle II); every run recorded, nothing raised (Principle VI);
retention rule with proof for the new operational table; the advisory lock and `skipped`
record kept

**Scale/Scope**: up to a few thousand eligible members per city per batch (decision D2); two
migrations, one new pgTAP file, five adjusted pgTAP files, one Edge Function response change,
three documents, one constitution amendment

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Principles touched: I, II, III, IV, VI, VII, VIII.

- **I (one introduction, never a feed)**: matching stays server-side on the schedule, same
  normalized city, reciprocal (now a testable floor), meeting overlap required, cadence,
  pause, blocks, the 180-day rule, and one active introduction honoured; no quota; every
  introduction explains reciprocal value in plain language from the members' own words. The
  schedule changes from hourly to daily, which amends the Schedules line of the Product and
  Platform Constraints (MINOR, this pull request). PASS.
- **II (reciprocal interest is the only gate)**: the Pass rules and `respond_to_introduction`
  are untouched; nothing computed by the batch is written where a member can read it except
  the explanation texts; no score, ranking, or popularity signal exists; the run records hold
  counts only. PASS.
- **III (the outcome is a meeting)**: membership access still gates matching through
  `private.has_membership_access`; the mutual bound changes only future eligibility;
  conversations, meetups, feedback, and Connections are untouched. PASS.
- **IV (members own their data)**: gender absent; no new data about members; the registry is
  product data; Pass, Interested, feedback, and availability are not read by selection. PASS.
- **VI (the backend owns trust)**: new tables in `private` with revoke-then-grant (no grant);
  every new function `security definer` with empty `search_path`, fully qualified relations,
  and explicit revokes; the batch keeps the advisory lock, records `skipped`, records
  failures without raising; the new table has a retention rule with a pgTAP proof; the
  optional operations function still authenticates with its job secret. PASS.
- **VII (deterministic tests, CI-only deploys)**: every rule is a pgTAP assertion with
  privilege assertions for every new object and the cron job asserted scheduled exactly once;
  the new operational table has its retention proof; docs updated in the same pull request;
  deployment only through the workflow. PASS.
- **VIII (calm technology)**: see the Calm Technology check below. PASS.

Gate details required by the plan gate:

| Item | RLS / grants | Privilege assertions | Secret | Push payload | Idempotency | Retention |
|------|--------------|----------------------|--------|--------------|-------------|-----------|
| `private.growth_contribution_affinity` (new table) | private schema; `revoke all` from `public`, `anon`, `authenticated` | added: no client role may select | none | n/a | primary key `(growth_area, contribution_area)`; seed uses `on conflict do nothing` | product data, kept |
| `private.matching_run_cities` (new table) | private schema; `revoke all` from `public`, `anon`, `authenticated` | added: no client role may select | none | n/a | primary key `(run_id, city_key)` | deleted with its run after 180 days (`on delete cascade`), proven |
| `public.introductions.reciprocal_for_a`, `reciprocal_for_b`, `matching_run_id` (new columns) | existing participant select policy; text each reader is meant to see, no relevance value | existing RLS assertions kept | none | n/a | backfilled once | as introductions |
| `private.growth_service(text[], text[])`, `private.normalize_topic(text)`, `private.experience_band(text)`, `private.cadence_interval(text)`, `private.has_active_introduction(uuid, timestamptz)`, `private.wait_bonus(...)` (new helpers) | `security definer` where they read tables, empty `search_path`; revoked from every role | added for each | none | n/a | pure or read-only | n/a |
| `private.matching_eligible_members(timestamptz)`, `private.matching_candidate_pairs(text, timestamptz)`, `private.matching_pair_is_valid(uuid, uuid, timestamptz)`, `private.select_matching_pairs(...)`, `private.compose_introduction_copy(...)`, `private.commit_matching_pairs(...)` (new) | private; revoked from every role | added for each | none | `introduction_ready` per member on creation, unchanged payload `{"introduction_id"}` | commit re-validates each pair and the active-pair unique index refuses a duplicate | n/a |
| `private.run_matching_batch(integer)` (redefined; the integer is now the per-city cap) | revoked from every role | existing assertion kept | none | as above | advisory lock; `skipped` record | run records 180 days (existing) |
| `public.run_matching_now()` (new, replaces `public.generate_next_introduction()`) | execute revoked from `public`, `anon`, `authenticated`; granted to `service_role`; raises unless `auth.role() = 'service_role'` | added | `MATCHING_JOB_SECRET` unchanged on the optional function | as above | same lock | n/a |
| `public.get_current_introduction()` (redefined) | unchanged grants | existing assertions kept; new: `reason_for_them` comes from the reciprocal column | none | n/a | read | n/a |
| Cron `network-to-daily-matching` (`7 13 * * *`, replaces `network-to-hourly-matching`) | n/a | asserted scheduled exactly once; hourly job asserted absent; five jobs in total | none | n/a | one run per day, lock | n/a |

No new notification kind, surface, or secret.

### State matrix and offline states

No new surface. Today, the Introduction screen, Messages, and the notification tap routes
render exactly as before; only the explanation text content changes. The existing state
matrix in `docs/COMPONENT_STATE_SHEET.md` applies unchanged.

### Tests this plan adds

- pgTAP `supabase/tests/database/batch_matching.test.sql` (new): registry present, revoked,
  and covering every growth area; `growth_service` counts and choice of the explained area;
  floor in both directions (one-direction pair never introduced); meeting overlap with the
  flexible wildcard; explanations name the served growth area, the serving contribution
  area, the other member's contribution words, and their ambition, for both members;
  exceptional-only floor and 28-day spacing; mutual bound before and after expiry; passed
  introduction still counts toward cadence; cadence windows; the 180-day rule; blocks;
  membership; same city; fairness (equal fit → longer wait; stronger fit beats wait, with
  the bound); one introduction per member per batch; per-city counts by reason; commit
  drops an invalid pair; skipped under the lock; cron scheduled once and the hourly job gone;
  retention cascade; privileges for every new object; `run_matching_now` service-role only;
  two runs on identical data (savepoint) create the same pairs.
- Adjusted: `schema.test.sql` (daily job, new functions), `production_behavior.test.sql` and
  `introduction_privacy.test.sql` (call `private.run_matching_batch(1000)` instead of the
  removed `private.generate_one_introduction()`), `launch_operations.test.sql` (retention of
  the city records), `company_marks.test.sql` (job count stays five).
- Deno: `deno check` on the adjusted `generate-introductions` function (no `_shared` logic).

### Calm Technology check (Principle VIII)

- *Reduce or add attention?* Reduces: one predictable morning arrival, fewer weak
  introductions, no new screen or prompt.
- *Inform or alarm?* Informs: the explanation names the reason in the members' own words;
  nothing announces a batch, a wait, or a queue position.
- *Can it live in the periphery?* Yes: the same notification and the same screen.
- *Help two people meet, or keep them in the app?* Meet: a true reciprocal reason and a
  practical overlap are the whole output.
- *Fail quietly?* Yes: a failed or skipped run is recorded and alerts operations; a member
  sees only the searching state.
- *Is there a simpler way?* The floor and the registry are the minimum that make reciprocity
  real; the batch reuses the schedule, lock, run records, alerts, and retention; greedy
  selection in SQL instead of a solver service.
- *Would a thoughtful professional find it normal?* Yes.

## Project Structure

### Documentation (this feature)

```text
specs/005-batch-matching/
├── discovery.md         # current matcher, findings, options, decisions
├── spec.md
├── plan.md              # this file
├── research.md          # Phase 0: decisions with rationale and rejected alternatives
├── data-model.md        # Phase 1: tables, columns, eligibility, fit, weights, records
├── quickstart.md        # Phase 1: how to validate
├── contracts/
│   ├── database.md      # tables, functions, grants, read model, schedule, retention
│   └── copy.md          # explanation and meeting-context templates (member-facing copy)
├── checklists/requirements.md
└── tasks.md             # Phase 2 (/speckit-tasks)
```

### Source Code (repository root)

```text
supabase/
├── migrations/
│   ├── 20260919150000_growth_contribution_affinity.sql   # new: registry table, seed, growth_service
│   └── 20260919150100_batch_matching.sql                 # new: columns, run cities, helpers, batch, read model, cron, run_matching_now
├── functions/generate-introductions/index.ts             # edit: call run_matching_now, return run id and count
└── tests/database/
    ├── batch_matching.test.sql                           # new
    ├── schema.test.sql                                   # edit: daily job, new functions
    ├── production_behavior.test.sql                      # edit: batch instead of generate_one_introduction
    ├── introduction_privacy.test.sql                     # edit: same
    ├── launch_operations.test.sql                        # edit: retention of run cities
    └── company_marks.test.sql                            # unchanged assertion (five jobs) re-verified

docs/SUPABASE_BACKEND.md                                  # edit: schedules, matching section, operations function
README.md                                                 # edit: "daily matching"
.specify/memory/constitution.md                           # edit: Schedules line, registry constraint, version 1.6.0
```

**Structure Decision**: the existing layout. Everything is two migrations and tests; the only
code outside `supabase/` is documentation.

## Complexity Tracking

No constitution violations. Two design choices worth recording:

| Choice | Why | Simpler alternative rejected because |
|--------|-----|--------------------------------------|
| Two new explanation columns instead of reusing the two existing ones | The read model serves the same stored string to both members ("why you" for one, "why they" for the other), so second-person copy needs one text per reader per direction | Third-person neutral copy that reads in both slots addresses the member as "Alex" instead of "you", which the design philosophy and the UI spec's examples reject |
| The per-city cap keeps the existing `run_matching_batch(integer)` signature | The existing cron call, schema test, and operations habits keep working; the cap is a safety bound, not a quota | Dropping the argument changes an existing assertion and the operations command for no member-facing gain |

## Operator steps outside the repository

None. Both migrations deploy through the existing workflow; the cron change is inside the
migration; no secret is added. After release, the product owner may edit the registry only by
a further migration.
