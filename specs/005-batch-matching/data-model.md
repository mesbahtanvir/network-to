# Data Model: Batch Matching

**Feature**: 005-batch-matching | **Date**: 2026-09-19

## New tables (private schema)

### `private.growth_contribution_affinity`

| Column | Type | Rules |
|--------|------|-------|
| `growth_area` | text | one of the growth areas members can choose |
| `contribution_area` | text | one of the contribution areas members can choose |
| `strength` | text | `same` or `adjacent` |
| `created_at` | timestamptz | default `now()` |

Primary key `(growth_area, contribution_area)`. `revoke all` from `public`, `anon`,
`authenticated`. Product-owned; changed only by migration. Identical terms serve as `same`
whether or not a row exists.

First content (product owner edits in the pull request):

| Growth area | Served by (`adjacent` unless marked) |
|-------------|--------------------------------------|
| Applied AI products | AI infrastructure; Product strategy |
| Executive communication | Engineering leadership; Scaling teams; Fundraising; Go-to-market |
| Engineering leadership | Engineering leadership (`same`); Scaling teams |
| Platform strategy | Distributed systems; Developer tools; Product strategy |
| Product thinking | Product strategy; Go-to-market; Developer tools |
| Founder perspective | Fundraising; Go-to-market; Scaling teams |
| Career transition | Engineering leadership; Product strategy; Scaling teams |
| Local tech ecosystem | Fundraising; Go-to-market; Scaling teams |

### `private.matching_run_cities`

| Column | Type | Meaning |
|--------|------|---------|
| `run_id` | uuid | references `private.matching_runs(id)` on delete cascade |
| `city_key` | text | normalized city |
| `eligible_members` | integer | members eligible in the city at the run |
| `unmatched_no_peers` | integer | eligible members with no other eligible member in the city |
| `unmatched_all_excluded` | integer | every candidate excluded by a block, a repeat within 180 days, or a consent |
| `unmatched_no_meeting_overlap` | integer | candidates remained but none shared an area, format, and window |
| `unmatched_below_floor` | integer | candidates with meeting overlap remained but none cleared the floor |
| `unmatched_partners_taken` | integer | pairs above the floor existed but every partner was taken by another pair this batch |
| `pairs_above_floor` | integer | distinct pairs above the floor in the city |
| `pairs_dropped_at_commit` | integer | chosen pairs that failed re-validation |
| `introductions_created` | integer | introductions created in the city |
| `total_weight` | numeric | sum of the created pairs' weights (operations only) |
| `created_at` | timestamptz | default `now()` |

Primary key `(run_id, city_key)`; every count `>= 0`. `revoke all` from `public`, `anon`,
`authenticated`. Retention: removed with its run by the existing 180-day purge (cascade),
proven by pgTAP. A city with one eligible member gets a row with `unmatched_no_peers = 1`; a
city with none gets no row.

## Changed table

### `public.introductions`

| Column | Change |
|--------|--------|
| `reason_for_a`, `reason_for_b` | unchanged type; meaning fixed as "why this member should meet the other", written to that member |
| `reciprocal_for_a` | new, `text not null default ''`: "why the other may want to meet this member", written to member A |
| `reciprocal_for_b` | new, same for member B |
| `matching_run_id` | new, `uuid null`, no foreign key (runs are purged; introductions are not) |

Backfill once: `reciprocal_for_a = reason_for_b`, `reciprocal_for_b = reason_for_a` for every
existing row, so open introductions display exactly as before. Existing grants and the
participant select policy are unchanged; no column carries a relevance value.

## Existing tables read by the batch

`profiles` (city_key, growth_areas, contribution_areas, topics, years_experience,
company_domain, industry, name, contribution, help_formats, professional_ambition,
onboarding_complete, is_active), `networking_preferences` (frequency, goals,
relationship_mix, cross_company, cross_industry), `meeting_preferences` (areas, formats,
windows), `introductions` (status, expires_at, created_at, members), `introduction_responses`
(through `private.introduction_passed_by`), `blocks`, `private.memberships`
(`trial_started_at`, access through `private.has_membership_access`).

## Eligibility (per member, at `p_now`)

A member is eligible when all hold:

1. `is_active` and `onboarding_complete`, `city_key <> ''`.
2. `private.has_membership_access(id, p_now)`.
3. `frequency <> 'paused'`.
4. `not private.has_active_introduction(id, p_now)`: no introduction with `expires_at > p_now`
   that is `offered` and not passed on by the member, or `mutual`.
5. No introduction involving the member created after `p_now - private.cadence_interval(frequency)`
   (weekly 7 days, twice_monthly 14, monthly 28, exceptional_only 28).

Derived per member: `wait_days = greatest(0, (p_now - coalesce(last_introduction_created_at,
trial_started_at)) in days)`, `wait_bonus = 0.15 × least(28, wait_days) / 28`,
`serves_same` and `serves_adjacent` (the growth areas the member's contribution areas serve,
from identity and the registry), `topics_norm` (normalized topics), `band`
(`private.experience_band(years_experience)`), `flexible` (areas contain "Flexible within
the city"), `exceptional` (`frequency = 'exceptional_only'`).

## Pair rules (both members eligible, same `city_key`, `member_a < member_b`)

1. Not blocked in either direction (`private.users_blocked`).
2. No introduction between them created in the last 180 days.
3. Consents: `cross_company` of both or same company; `cross_industry` of both or same industry.
4. Meeting overlap: (`flexible` of either or `areas && areas`) and `formats && formats` and
   `windows && windows`.
5. Floor: `growth_service(A.contribution, B.growth)` serves at least one and
   `growth_service(B.contribution, A.growth)` serves at least one.
6. Exceptional: if either member is `exceptional`, both directions have `same_count >= 1`
   and the members share at least one goal.

## Fit and weight

See research section 3 for the table. `weight = fit + wait_bonus_a + wait_bonus_b`. Ordering
for selection and for determinism: `weight desc, greatest(wait_a, wait_b) desc, member_a,
member_b`.

## Selection state (temporary, per run and city)

| Temporary table | Columns |
|-----------------|---------|
| `matching_members` | one row per eligible member with the derived fields above (primary key `user_id`) |
| `matching_pairs` | one row per pair passing rules 1 to 3, with flags `meets`, `above_floor`, the fit components, `weight`, and the explanation inputs (served growth area and serving contribution area in each direction) |
| `matching_taken` | members used by a chosen pair (primary key `user_id`) |

Nothing from these tables is written anywhere a member can read.

## Explanation inputs

For each direction the chosen served growth area is the first of the reader's growth areas
(in the reader's order) served by a `same` term, else the first served by an `adjacent` term;
the serving contribution area is the first of the other member's contribution areas (in
their order) that serves it. Templates: [contracts/copy.md](contracts/copy.md).

## State transitions

```text
Introduction status: unchanged (offered → mutual | closed | expired). New: a mutual
introduction stops counting as active at expires_at with no status change.

Matching run: running → completed | failed | skipped (unchanged). Each completed run has
zero or more city records.

Schedule: network-to-hourly-matching (removed) → network-to-daily-matching, 13:07 UTC.
```
