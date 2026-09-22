# Database Contracts: Batch Matching

Two migrations. Every function is `security definer` with `set search_path = ''`, fully
qualified relations, and an explicit `revoke all ... from public, anon, authenticated,
service_role` unless a grant is stated.

## Migration 1: `supabase/migrations/20260919150000_growth_contribution_affinity.sql`

Opens with a comment stating intent (product-owned registry, edited only by migration) and
that no operator step exists.

- `create table private.growth_contribution_affinity (...)` as in data-model.md; `revoke all`
  from `public`, `anon`, `authenticated`.
- Seed with `insert ... on conflict do nothing` (re-runnable).
- `private.growth_service(p_growth text[], p_contribution text[]) returns private.growth_service_result`
  (a composite of `same_count`, `adjacent_count`, `served_growth_area`, `serving_contribution_area`):
  `language sql stable security definer`, so a pair query can guard the call with a CASE. For each growth area (in order) the best serving contribution area
  (identity → `same`; registry row → its strength); counts by strength; the explained pair
  per data-model.md. Empty or null arrays return zeros and nulls.

## Migration 2: `supabase/migrations/20260919150100_batch_matching.sql`

Opens with a comment stating intent and that the hourly job is replaced by the daily one with
no operator step.

### Columns and backfill

```sql
alter table public.introductions
  add column if not exists reciprocal_for_a text not null default '',
  add column if not exists reciprocal_for_b text not null default '',
  add column if not exists matching_run_id uuid;
-- and private.matching_runs.requested_limit is re-bounded to 1..5000 (it is now a per-city cap)
update public.introductions set reciprocal_for_a = reason_for_b, reciprocal_for_b = reason_for_a
  where reciprocal_for_a = '' and reciprocal_for_b = '';
```

### `private.matching_run_cities`

As in data-model.md, with `references private.matching_runs(id) on delete cascade` and
`check (... >= 0)` on every count; `revoke all` from `public`, `anon`, `authenticated`.

### Helpers

| Function | Returns | Behaviour |
|----------|---------|-----------|
| `private.normalize_topic(text)` | text | `immutable`; lower-case, non-alphanumerics to one space, trimmed |
| `private.experience_band(text)` | integer | `immutable`; "1–3 years" 1, "4–6 years" 2, "7–9 years" 3, "10–15 years" 4, "15+ years" 5 (hyphen or en dash), else null |
| `private.cadence_interval(text)` | interval | `immutable`; weekly 7 days, twice_monthly 14, monthly 28, exceptional_only 28, else null |
| `private.has_active_introduction(uuid, timestamptz)` | boolean | `stable`; an unexpired `offered` introduction not passed on by the member, or an unexpired `mutual` one |
| `private.lower_first_word(text)` | text | `immutable`; lower-cases the first character when the second is a lower-case letter ("Platform strategy" → "platform strategy", "AI infrastructure" unchanged) |

### Batch functions

| Function | Returns | Behaviour |
|----------|---------|-----------|
| `private.matching_eligible_members(p_now timestamptz, p_member uuid default null)` | table of member rows with the derived fields in data-model.md | eligibility rules 1 to 5; with `p_member` only that member is evaluated |
| `private.matching_candidate_pairs(p_city_key text, p_now timestamptz, p_member_a uuid default null, p_member_b uuid default null)` | table `(member_a, member_b, stage smallint, weight numeric, same_to_a, adjacent_to_a, same_to_b, adjacent_to_b, goal_jaccard, shared_topics, band_distance, crosses_company, crosses_industry, served_growth_a, serving_contribution_b, served_growth_b, serving_contribution_a, wait_a, wait_b)` | every pair of eligible members in the city with its stage: 0 excluded by rules 1 to 3, 1 no meeting overlap, 2 below the floor, 3 above it; weight and explanation inputs only at stage 3. With both members set, only that pair, which is how commit re-validates. The "candidates out" seam |
| `private.matching_pair_is_valid(p_a uuid, p_b uuid, p_now timestamptz)` | boolean | the pair reaches stage 3 when re-evaluated from the tables |
| `private.select_matching_pairs(p_city_key text, p_now timestamptz, p_limit integer)` | table `(member_a, member_b, weight numeric)` | materializes the city's stage-3 pairs in `pg_temp.matching_batch_pairs`, then greedy in `weight desc, greatest(wait_a, wait_b) desc, member_a, member_b` order, each member at most once, at most `p_limit` pairs, no `random()` |
| `private.compose_introduction_copy(p_a uuid, p_b uuid, p_served_growth_a text, p_serving_contribution_b text, p_served_growth_b text, p_serving_contribution_a text)` | table `(reason_for_a, reason_for_b, reciprocal_for_a, reciprocal_for_b, meeting_context)` | reads names, help formats, words, ambitions, and meeting preferences from the tables; contracts/copy.md |
| `private.commit_matching_pairs(p_run_id uuid, p_city_key text, p_pairs jsonb, p_now timestamptz)` | table `(created integer, dropped integer, total_weight numeric)` | for each `{"a": uuid, "b": uuid, "weight": n}`: re-evaluate the pair through `matching_candidate_pairs`; drop it unless it is at stage 3 (a member already introduced in this run is no longer eligible, so the pair drops); insert the introduction with `matching_run_id` and the composed copy, plus two `introduction_ready` events (`{"introduction_id": ...}`); the active-pair unique index is the last guard. The "chosen pairs in" seam |
| `private.execute_matching_batch(p_limit integer)` | table `(run_id, status, introductions_created)` | `p_limit` between 1 and 5000 is the per-city cap; advisory lock else `skipped`; expire `offered` past expiry; for each city with at least one eligible member: one pass over `matching_candidate_pairs` for each member's furthest stage, then selection, commit, and one `matching_run_cities` row; run `completed` with the total or `failed` with the message; never raises. Run timestamps use `clock_timestamp()` |
| `private.run_matching_batch(p_limit integer default 1000)` | integer | calls `execute_matching_batch` and returns the count; the cron entry point, signature unchanged |
| `public.run_matching_now()` | jsonb `{"run_id", "status", "introductions_created"}` | raises unless `auth.role()` is `service_role`; calls `private.execute_matching_batch(1000)`. Execute revoked from `public`, `anon`, `authenticated`; granted to `service_role` |

Dropped: `public.generate_next_introduction()`, `private.generate_one_introduction()`.

### Read model

`public.get_current_introduction()` is redefined with the same body except:

```sql
'reason_for_you',  case when i.member_a = caller then i.reason_for_a     else i.reason_for_b     end,
'reason_for_them', case when i.member_a = caller then i.reciprocal_for_a else i.reciprocal_for_b end,
```

Grants unchanged. `public.get_conversations()` is unchanged (`introduction_reason` is the
caller's "why you should meet").

### Schedule

```sql
-- unschedule 'network-to-hourly-matching' if present, then:
select cron.schedule('network-to-daily-matching', '7 13 * * *', 'select private.run_matching_batch(1000)');
```

Five `network-to-` jobs in total, as before.

### Retention

No change to `private.run_retention_maintenance()`: deleting a run older than 180 days
cascades to its city records. pgTAP inserts an old run with a city row, runs retention, and
asserts both are gone.

### Alerts

No change: `matching_run_failed` and `matching_stalled` (25 hours) keep working.

## Edge Function: `supabase/functions/generate-introductions/index.ts`

Calls `rest/v1/rpc/run_matching_now` instead of `generate_next_introduction` and returns the
function's JSON (`run_id`, `status`, `introductions_created`). Still protected by
`MATCHING_JOB_SECRET`; still not deployed by default.

## pgTAP: `supabase/tests/database/batch_matching.test.sql`

Fixture: Toronto members created through `auth.users` (profiles and preferences by trigger;
onboarding completed by update, which starts the free month), with growth and contribution
arrays, goals, topics, experience bands, meeting preferences, frequencies, and memberships set
per scenario; an Austin member; introductions inserted with chosen `created_at` and
`expires_at`. Runs `private.run_matching_batch(1000)` and asserts the plan's test list.
Two-run determinism through `savepoint` / `rollback to savepoint`.

Adjusted files: `schema.test.sql` (daily job present once, hourly absent, the old functions
gone, new tables and functions exist), `production_behavior.test.sql` and
`introduction_privacy.test.sql` (call the batch). `launch_operations.test.sql` and
`company_marks.test.sql` pass unchanged; the retention cascade is proven in the new file.
Scenarios are separated by pausing every member so far rather than by savepoints, which
would roll back pgTAP's own bookkeeping; the skipped-run path cannot be exercised from one
session because advisory locks are re-entrant.
