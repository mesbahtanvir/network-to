-- Batch matching (feature 005), part two of two: one daily batch per city replaces the hourly
-- one-pair-at-a-time selection.
--
-- Each morning the batch considers every eligible member of a city together, keeps only the
-- pairs in which each member's contribution areas serve at least one of the other's growth
-- areas (the quality floor, through private.growth_contribution_affinity), weighs them by fit
-- plus a bounded waiting bonus, chooses pairs greedily so that each member receives at most
-- one introduction, re-validates every pair as it is created, writes both explanations to
-- their reader, and records per-city counts in private.matching_run_cities. A mutual
-- introduction counts as a member's active introduction only until its expiry. "Exceptional
-- introductions only" means a stronger floor and 28-day spacing. Selection sits behind
-- private.matching_candidate_pairs (candidates out) and private.commit_matching_pairs (chosen
-- pairs in) so a stronger selector can replace private.select_matching_pairs later.
--
-- The cron job network-to-hourly-matching is replaced by network-to-daily-matching at 13:07
-- UTC (9:07 in Toronto during daylight time). No secret, no operator step; re-runnable.

-- ---------------------------------------------------------------------------------------
-- Introductions: one explanation per reader per direction, and the run that created it.
-- ---------------------------------------------------------------------------------------

alter table public.introductions
  add column if not exists reciprocal_for_a text not null default '',
  add column if not exists reciprocal_for_b text not null default '',
  add column if not exists matching_run_id uuid;

update public.introductions
set reciprocal_for_a = reason_for_b, reciprocal_for_b = reason_for_a
where reciprocal_for_a = '' and reciprocal_for_b = '';

-- The batch argument is now a per-city cap, a safety bound and never a target.
alter table private.matching_runs drop constraint if exists matching_runs_requested_limit_check;
alter table private.matching_runs add constraint matching_runs_requested_limit_check
  check (requested_limit between 1 and 5000);

-- ---------------------------------------------------------------------------------------
-- Per-city run records: counts only, never a member's identity or words. Purged with the run.
-- ---------------------------------------------------------------------------------------

create table if not exists private.matching_run_cities (
  run_id uuid not null references private.matching_runs(id) on delete cascade,
  city_key text not null,
  eligible_members integer not null default 0 check (eligible_members >= 0),
  unmatched_no_peers integer not null default 0 check (unmatched_no_peers >= 0),
  unmatched_all_excluded integer not null default 0 check (unmatched_all_excluded >= 0),
  unmatched_no_meeting_overlap integer not null default 0 check (unmatched_no_meeting_overlap >= 0),
  unmatched_below_floor integer not null default 0 check (unmatched_below_floor >= 0),
  unmatched_partners_taken integer not null default 0 check (unmatched_partners_taken >= 0),
  pairs_above_floor integer not null default 0 check (pairs_above_floor >= 0),
  pairs_dropped_at_commit integer not null default 0 check (pairs_dropped_at_commit >= 0),
  introductions_created integer not null default 0 check (introductions_created >= 0),
  total_weight numeric not null default 0 check (total_weight >= 0),
  created_at timestamptz not null default now(),
  primary key (run_id, city_key)
);

revoke all on table private.matching_run_cities from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------
-- Pure helpers.
-- ---------------------------------------------------------------------------------------

create or replace function private.normalize_topic(p_value text)
returns text
language sql
immutable
set search_path = ''
as $$
  select nullif(btrim(regexp_replace(lower(coalesce(p_value, '')), '[^a-z0-9]+', ' ', 'g')), '');
$$;

create or replace function private.experience_band(p_value text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case btrim(regexp_replace(lower(coalesce(p_value, '')), '[–—‑-]', '-', 'g'))
    when '1-3 years' then 1
    when '4-6 years' then 2
    when '7-9 years' then 3
    when '10-15 years' then 4
    when '15+ years' then 5
    else null
  end;
$$;

create or replace function private.cadence_interval(p_frequency text)
returns interval
language sql
immutable
set search_path = ''
as $$
  select case p_frequency
    when 'weekly' then interval '7 days'
    when 'twice_monthly' then interval '14 days'
    when 'monthly' then interval '28 days'
    when 'exceptional_only' then interval '28 days'
    else null
  end;
$$;

-- Lower-cases the first character of a term unless it opens an acronym ("Platform strategy"
-- becomes "platform strategy"; "AI infrastructure" is unchanged).
create or replace function private.lower_first_word(p_value text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_value is null then null
    when length(p_value) >= 2 and substr(p_value, 2, 1) ~ '[a-z]' then lower(substr(p_value, 1, 1)) || substr(p_value, 2)
    else p_value
  end;
$$;

-- An introduction is a member's active one while it is unexpired and either mutual or offered
-- without a Pass from that member. A mutual introduction therefore stops blocking its members
-- at its expiry, with no change to its status or to the conversation.
create or replace function private.has_active_introduction(p_member uuid, p_now timestamptz)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.introductions i
    where p_member in (i.member_a, i.member_b)
      and i.expires_at > p_now
      and (
        i.status = 'mutual'
        or (i.status = 'offered' and not private.introduction_passed_by(i.id, p_member))
      )
  );
$$;

revoke all on function private.normalize_topic(text) from public, anon, authenticated, service_role;
revoke all on function private.experience_band(text) from public, anon, authenticated, service_role;
revoke all on function private.cadence_interval(text) from public, anon, authenticated, service_role;
revoke all on function private.lower_first_word(text) from public, anon, authenticated, service_role;
revoke all on function private.has_active_introduction(uuid, timestamptz) from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------------------
-- Eligible members with everything the pair rules need, precomputed once per member.
-- ---------------------------------------------------------------------------------------

create or replace function private.matching_eligible_members(p_now timestamptz, p_member uuid default null)
returns table (
  user_id uuid,
  city_key text,
  name text,
  company_domain text,
  industry text,
  growth_areas text[],
  contribution_areas text[],
  growth_lower text[],
  serves_same text[],
  serves_adjacent text[],
  contribution text,
  professional_ambition text,
  help_formats text[],
  areas text[],
  formats text[],
  windows text[],
  goals text[],
  cross_company boolean,
  cross_industry boolean,
  exceptional boolean,
  flexible boolean,
  band integer,
  topics_norm text[],
  wait_days numeric,
  wait_bonus numeric
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    p.id,
    p.city_key,
    p.name,
    p.company_domain,
    p.industry,
    p.growth_areas,
    p.contribution_areas,
    (select coalesce(array_agg(distinct lower(btrim(g.value))), '{}'::text[])
     from unnest(p.growth_areas) g(value) where btrim(g.value) <> ''),
    (select coalesce(array_agg(distinct sv.value), '{}'::text[])
     from (
       select lower(btrim(c.value)) as value from unnest(p.contribution_areas) c(value) where btrim(c.value) <> ''
       union
       select lower(a.growth_area)
       from private.growth_contribution_affinity a
       join unnest(p.contribution_areas) c(value) on lower(btrim(c.value)) = lower(a.contribution_area)
       where a.strength = 'same'
     ) sv),
    (select coalesce(array_agg(distinct lower(a.growth_area)), '{}'::text[])
     from private.growth_contribution_affinity a
     join unnest(p.contribution_areas) c(value) on lower(btrim(c.value)) = lower(a.contribution_area)
     where a.strength = 'adjacent'),
    p.contribution,
    p.professional_ambition,
    p.help_formats,
    m.areas,
    m.formats,
    m.windows,
    n.goals,
    n.cross_company,
    n.cross_industry,
    n.frequency = 'exceptional_only',
    'Flexible within the city' = any(m.areas),
    private.experience_band(p.years_experience),
    (select coalesce(array_agg(distinct x.topic order by x.topic), '{}'::text[])
     from unnest(p.topics) t(value), lateral (select private.normalize_topic(t.value) as topic) x
     where x.topic is not null),
    wait.wait_days,
    round(0.15 * least(28, wait.wait_days) / 28, 6)
  from public.profiles p
  join public.networking_preferences n on n.user_id = p.id
  join public.meeting_preferences m on m.user_id = p.id
  join private.memberships s on s.user_id = p.id
  left join lateral (
    select max(i.created_at) as last_created_at
    from public.introductions i
    where p.id in (i.member_a, i.member_b)
  ) li on true
  cross join lateral (
    select round(greatest(0, extract(epoch from (p_now - coalesce(li.last_created_at, s.trial_started_at))) / 86400.0), 6) as wait_days
  ) wait
  where (p_member is null or p.id = p_member)
    and p.is_active
    and p.onboarding_complete
    and p.city_key <> ''
    and private.has_membership_access(p.id, p_now)
    and n.frequency <> 'paused'
    and private.cadence_interval(n.frequency) is not null
    and not private.has_active_introduction(p.id, p_now)
    and (li.last_created_at is null or li.last_created_at <= p_now - private.cadence_interval(n.frequency));
$$;

revoke all on function private.matching_eligible_members(timestamptz, uuid) from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------------------
-- Candidate pairs: every unordered pair of eligible members in a city with the stage it
-- reached (0 excluded by a block, a repeat within 180 days, or a consent; 1 no meeting
-- overlap; 2 below the quality floor; 3 above it) and, for stage 3, the weight and the
-- explanation inputs. With p_member_a and p_member_b set, only that pair is evaluated, which
-- is how a chosen pair is re-validated at commit. This is the "candidates out" seam.
-- ---------------------------------------------------------------------------------------

create or replace function private.matching_candidate_pairs(
  p_city_key text,
  p_now timestamptz,
  p_member_a uuid default null,
  p_member_b uuid default null
)
returns table (
  member_a uuid,
  member_b uuid,
  stage smallint,
  weight numeric,
  same_to_a integer,
  adjacent_to_a integer,
  same_to_b integer,
  adjacent_to_b integer,
  goal_jaccard numeric,
  shared_topics integer,
  band_distance integer,
  crosses_company boolean,
  crosses_industry boolean,
  served_growth_a text,
  serving_contribution_b text,
  served_growth_b text,
  serving_contribution_a text,
  wait_a numeric,
  wait_b numeric
)
language sql
stable
security definer
set search_path = ''
as $$
  with members as (
    select e.*
    from private.matching_eligible_members(p_now, p_member_a) e
    where e.city_key = p_city_key
      and (p_member_a is null or e.user_id = p_member_a)
    union all
    select e.*
    from private.matching_eligible_members(p_now, p_member_b) e
    where p_member_b is not null
      and e.city_key = p_city_key
      and e.user_id = p_member_b
  ), blocked as (
    select least(bl.blocker_id, bl.blocked_id) as first_member, greatest(bl.blocker_id, bl.blocked_id) as second_member
    from public.blocks bl
  ), recent as (
    select i.member_a as first_member, i.member_b as second_member
    from public.introductions i
    where i.created_at > p_now - interval '180 days'
  ), pairs as (
    select
      a.user_id as member_a,
      b.user_id as member_b,
      (
        not exists (select 1 from blocked x where x.first_member = a.user_id and x.second_member = b.user_id)
        and not exists (select 1 from recent x where x.first_member = a.user_id and x.second_member = b.user_id)
        and (a.cross_company or a.company_domain = b.company_domain)
        and (b.cross_company or a.company_domain = b.company_domain)
        and (a.cross_industry or a.industry = b.industry)
        and (b.cross_industry or a.industry = b.industry)
      ) as allowed,
      (
        (a.flexible or b.flexible or a.areas && b.areas)
        and a.formats && b.formats
        and a.windows && b.windows
      ) as meets,
      (
        (a.growth_lower && (b.serves_same || b.serves_adjacent))
        and (b.growth_lower && (a.serves_same || a.serves_adjacent))
        and (
          not (a.exceptional or b.exceptional)
          or ((a.growth_lower && b.serves_same) and (b.growth_lower && a.serves_same) and a.goals && b.goals)
        )
      ) as above,
      a.growth_lower as growth_lower_a,
      b.growth_lower as growth_lower_b,
      a.serves_same as serves_same_a,
      a.serves_adjacent as serves_adjacent_a,
      b.serves_same as serves_same_b,
      b.serves_adjacent as serves_adjacent_b,
      a.growth_areas as growth_a,
      b.growth_areas as growth_b,
      a.contribution_areas as contribution_a,
      b.contribution_areas as contribution_b,
      a.goals as goals_a,
      b.goals as goals_b,
      a.topics_norm as topics_a,
      b.topics_norm as topics_b,
      a.band as band_a,
      b.band as band_b,
      a.company_domain <> b.company_domain as crosses_company,
      a.industry <> b.industry as crosses_industry,
      a.wait_days as wait_a,
      b.wait_days as wait_b,
      a.wait_bonus as bonus_a,
      b.wait_bonus as bonus_b
    from members a
    join members b on a.user_id < b.user_id
  ), staged as (
    select
      p.*,
      (case when not p.allowed then 0 when not p.meets then 1 when not p.above then 2 else 3 end)::smallint as stage,
      (p.allowed and p.meets and p.above) as scored
    from pairs p
  ), counted as (
    -- Counts come from the per-member arrays; the registry is consulted once per member, not per pair.
    select
      s.*,
      case when s.scored then
        (select count(*) from unnest(s.growth_lower_a) g(value) where g.value = any(s.serves_same_b))::integer end as same_to_a,
      case when s.scored then
        (select count(*) from unnest(s.growth_lower_a) g(value)
         where g.value = any(s.serves_adjacent_b) and not g.value = any(s.serves_same_b))::integer end as adjacent_to_a,
      case when s.scored then
        (select count(*) from unnest(s.growth_lower_b) g(value) where g.value = any(s.serves_same_a))::integer end as same_to_b,
      case when s.scored then
        (select count(*) from unnest(s.growth_lower_b) g(value)
         where g.value = any(s.serves_adjacent_a) and not g.value = any(s.serves_same_a))::integer end as adjacent_to_b,
      case when s.scored then
        (select count(*) from unnest(s.goals_a) g(value) where g.value = any(s.goals_b))::numeric
          / nullif((select count(distinct g.value) from unnest(s.goals_a || s.goals_b) g(value)), 0)
      end as goal_jaccard,
      case when s.scored then
        (select count(*) from unnest(s.topics_a) t(value) where t.value = any(s.topics_b))::integer end as shared_topics,
      case when s.band_a is null or s.band_b is null then null else abs(s.band_a - s.band_b) end as band_distance,
      -- The explained pair is only needed when one pair is evaluated, at commit.
      case when s.scored and p_member_a is not null and p_member_b is not null
        then (select r from private.growth_service(s.growth_a, s.contribution_b) r) end as to_a,
      case when s.scored and p_member_a is not null and p_member_b is not null
        then (select r from private.growth_service(s.growth_b, s.contribution_a) r) end as to_b
    from staged s
  ), fitted as (
    select
      c.*,
      case when c.stage = 3 then
        least(2.0, 1.0 * c.same_to_a + 0.6 * c.adjacent_to_a)
        + least(2.0, 1.0 * c.same_to_b + 0.6 * c.adjacent_to_b)
        + 0.5 * coalesce(c.goal_jaccard, 0)
        + 0.2 * least(3, coalesce(c.shared_topics, 0))
        + case c.band_distance when 0 then 0.4 when 1 then 0.4 when 2 then 0.2 else 0 end
        + case when c.crosses_company then 0.2 else 0 end
        + case when c.crosses_industry then 0.2 else 0 end
      end as fit
    from counted c
  )
  select
    f.member_a,
    f.member_b,
    f.stage,
    case when f.stage = 3 then round(f.fit + f.bonus_a + f.bonus_b, 6) end,
    f.same_to_a,
    f.adjacent_to_a,
    f.same_to_b,
    f.adjacent_to_b,
    round(f.goal_jaccard, 6),
    f.shared_topics,
    f.band_distance,
    f.crosses_company,
    f.crosses_industry,
    (f.to_a).served_growth_area,
    (f.to_a).serving_contribution_area,
    (f.to_b).served_growth_area,
    (f.to_b).serving_contribution_area,
    f.wait_a,
    f.wait_b
  from fitted f;
$$;

revoke all on function private.matching_candidate_pairs(text, timestamptz, uuid, uuid) from public, anon, authenticated, service_role;

create or replace function private.matching_pair_is_valid(p_a uuid, p_b uuid, p_now timestamptz)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from private.matching_candidate_pairs(
      (select p.city_key from public.profiles p where p.id = least(p_a, p_b)),
      p_now,
      least(p_a, p_b),
      greatest(p_a, p_b)
    ) c
    where c.stage = 3
  );
$$;

revoke all on function private.matching_pair_is_valid(uuid, uuid, timestamptz) from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------------------
-- Selection: greedy by weight over the pairs above the floor, each member at most once.
-- Materializes the city's stage-3 pairs in pg_temp.matching_batch_pairs for the run's
-- records. Deterministic: weight, then the longer wait, then member identifiers.
-- ---------------------------------------------------------------------------------------

create or replace function private.select_matching_pairs(p_city_key text, p_now timestamptz, p_limit integer)
returns table (member_a uuid, member_b uuid, weight numeric)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  pair record;
  chosen integer := 0;
  members_total integer := 0;
begin
  if p_limit is null or p_limit < 1 then raise exception 'Invalid selection limit'; end if;

  if to_regclass('pg_temp.matching_batch_pairs') is not null then drop table pg_temp.matching_batch_pairs; end if;
  create temp table matching_batch_pairs on commit drop as
    select c.member_a, c.member_b, c.weight, greatest(c.wait_a, c.wait_b) as longest_wait
    from private.matching_candidate_pairs(p_city_key, p_now) c
    where c.stage = 3;

  if to_regclass('pg_temp.matching_batch_taken') is not null then drop table pg_temp.matching_batch_taken; end if;
  create temp table matching_batch_taken (user_id uuid primary key) on commit drop;

  select count(distinct x.user_id) into members_total
  from (
    select bp.member_a as user_id from pg_temp.matching_batch_pairs bp
    union all
    select bp.member_b from pg_temp.matching_batch_pairs bp
  ) x;

  for pair in
    select bp.member_a, bp.member_b, bp.weight
    from pg_temp.matching_batch_pairs bp
    order by bp.weight desc, bp.longest_wait desc, bp.member_a, bp.member_b
  loop
    exit when chosen >= p_limit or chosen * 2 >= members_total;
    if exists (select 1 from pg_temp.matching_batch_taken t where t.user_id in (pair.member_a, pair.member_b)) then
      continue;
    end if;
    insert into pg_temp.matching_batch_taken (user_id) values (pair.member_a), (pair.member_b);
    chosen := chosen + 1;
    member_a := pair.member_a;
    member_b := pair.member_b;
    weight := pair.weight;
    return next;
  end loop;
end;
$$;

revoke all on function private.select_matching_pairs(text, timestamptz, integer) from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------------------
-- Explanations, assembled only from what the members chose and wrote (contracts/copy.md).
-- ---------------------------------------------------------------------------------------

create or replace function private.compose_introduction_copy(
  p_a uuid,
  p_b uuid,
  p_served_growth_a text,
  p_serving_contribution_b text,
  p_served_growth_b text,
  p_serving_contribution_a text
)
returns table (
  reason_for_a text,
  reason_for_b text,
  reciprocal_for_a text,
  reciprocal_for_b text,
  meeting_context text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  a record;
  b record;
  first_a text;
  first_b text;
  help_a text;
  help_b text;
  words_a text;
  words_b text;
  ambition_a text;
  ambition_b text;
  shared_format text;
  shared_area text;
begin
  select p.name, p.help_formats, p.contribution, p.professional_ambition, m.areas, m.formats
  into a
  from public.profiles p
  join public.meeting_preferences m on m.user_id = p.id
  where p.id = p_a;

  select p.name, p.help_formats, p.contribution, p.professional_ambition, m.areas, m.formats
  into b
  from public.profiles p
  join public.meeting_preferences m on m.user_id = p.id
  where p.id = p_b;

  first_a := coalesce(nullif(split_part(btrim(coalesce(a.name, '')), ' ', 1), ''), 'They');
  first_b := coalesce(nullif(split_part(btrim(coalesce(b.name, '')), ' ', 1), ''), 'They');
  help_a := private.lower_first_word(nullif(btrim(coalesce(a.help_formats[1], '')), ''));
  help_b := private.lower_first_word(nullif(btrim(coalesce(b.help_formats[1], '')), ''));
  words_a := nullif(btrim(coalesce(a.contribution, '')), '');
  words_b := nullif(btrim(coalesce(b.contribution, '')), '');
  ambition_a := nullif(btrim(coalesce(a.professional_ambition, '')), '');
  ambition_b := nullif(btrim(coalesce(b.professional_ambition, '')), '');

  reason_for_a :=
    'You want to grow in ' || private.lower_first_word(coalesce(p_served_growth_a, 'an area you chose'))
    || '. ' || first_b || ' offers ' || private.lower_first_word(coalesce(p_serving_contribution_b, 'relevant experience'))
    || coalesce(' and can ' || help_b, '') || '.'
    || coalesce(' In their words: “' || words_b || '”', '')
    || coalesce(' What ' || first_b || ' is working toward: “' || ambition_b || '”', '');

  reason_for_b :=
    'You want to grow in ' || private.lower_first_word(coalesce(p_served_growth_b, 'an area you chose'))
    || '. ' || first_a || ' offers ' || private.lower_first_word(coalesce(p_serving_contribution_a, 'relevant experience'))
    || coalesce(' and can ' || help_a, '') || '.'
    || coalesce(' In their words: “' || words_a || '”', '')
    || coalesce(' What ' || first_a || ' is working toward: “' || ambition_a || '”', '');

  reciprocal_for_a :=
    first_b || ' wants to grow in ' || private.lower_first_word(coalesce(p_served_growth_b, 'an area they chose'))
    || '. You offer ' || private.lower_first_word(coalesce(p_serving_contribution_a, 'relevant experience'))
    || coalesce(' and can ' || help_a, '') || '.'
    || coalesce(' In your words: “' || words_a || '”', '');

  reciprocal_for_b :=
    first_a || ' wants to grow in ' || private.lower_first_word(coalesce(p_served_growth_a, 'an area they chose'))
    || '. You offer ' || private.lower_first_word(coalesce(p_serving_contribution_b, 'relevant experience'))
    || coalesce(' and can ' || help_b, '') || '.'
    || coalesce(' In your words: “' || words_b || '”', '');

  select f.value into shared_format
  from unnest(coalesce(a.formats, '{}'::text[])) with ordinality f(value, position)
  where f.value = any(coalesce(b.formats, '{}'::text[]))
  order by f.position
  limit 1;

  select ar.value into shared_area
  from unnest(coalesce(a.areas, '{}'::text[])) with ordinality ar(value, position)
  where ar.value = any(coalesce(b.areas, '{}'::text[])) and ar.value <> 'Flexible within the city'
  order by ar.position
  limit 1;

  if shared_area is null then
    if not ('Flexible within the city' = any(coalesce(a.areas, '{}'::text[]))) then
      select ar.value into shared_area
      from unnest(coalesce(a.areas, '{}'::text[])) with ordinality ar(value, position)
      where ar.value <> 'Flexible within the city'
      order by ar.position limit 1;
    elsif not ('Flexible within the city' = any(coalesce(b.areas, '{}'::text[]))) then
      select ar.value into shared_area
      from unnest(coalesce(b.areas, '{}'::text[])) with ordinality ar(value, position)
      where ar.value <> 'Flexible within the city'
      order by ar.position limit 1;
    end if;
  end if;

  meeting_context :=
    'You are both in the same city and prefer ' || coalesce(private.lower_first_word(shared_format), 'a coffee')
    || case when shared_area is not null then ' around ' || shared_area else ' and are flexible about where in the city' end
    || '. Confirm a public place together after mutual interest.';

  return next;
end;
$$;

revoke all on function private.compose_introduction_copy(uuid, uuid, text, text, text, text) from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------------------
-- Commit: the "chosen pairs in" seam. Every pair is re-validated from the tables before an
-- introduction is created; the active-pair unique index is the last guard.
-- ---------------------------------------------------------------------------------------

create or replace function private.commit_matching_pairs(p_run_id uuid, p_city_key text, p_pairs jsonb, p_now timestamptz)
returns table (created integer, dropped integer, total_weight numeric)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  item jsonb;
  first_member uuid;
  second_member uuid;
  detail record;
  copy record;
  created_id uuid;
  n_created integer := 0;
  n_dropped integer := 0;
  sum_weight numeric := 0;
begin
  if p_pairs is not null and jsonb_typeof(p_pairs) = 'array' then
    for item in select value from jsonb_array_elements(p_pairs) loop
      begin
        first_member := least((item->>'a')::uuid, (item->>'b')::uuid);
        second_member := greatest((item->>'a')::uuid, (item->>'b')::uuid);
      exception when others then
        first_member := null;
        second_member := null;
      end;

      if first_member is null or second_member is null or first_member = second_member then
        n_dropped := n_dropped + 1;
        continue;
      end if;

      select c.stage, c.weight, c.served_growth_a, c.serving_contribution_b, c.served_growth_b, c.serving_contribution_a
      into detail
      from private.matching_candidate_pairs(p_city_key, p_now, first_member, second_member) c;

      if detail.stage is distinct from 3::smallint then
        n_dropped := n_dropped + 1;
        continue;
      end if;

      select * into copy
      from private.compose_introduction_copy(
        first_member, second_member,
        detail.served_growth_a, detail.serving_contribution_b, detail.served_growth_b, detail.serving_contribution_a
      );

      insert into public.introductions (
        member_a, member_b, reason_for_a, reason_for_b, reciprocal_for_a, reciprocal_for_b, meeting_context, matching_run_id
      ) values (
        first_member, second_member,
        copy.reason_for_a, copy.reason_for_b, copy.reciprocal_for_a, copy.reciprocal_for_b, copy.meeting_context, p_run_id
      ) returning id into created_id;

      insert into public.notification_events (user_id, kind, payload) values
        (first_member, 'introduction_ready', jsonb_build_object('introduction_id', created_id)),
        (second_member, 'introduction_ready', jsonb_build_object('introduction_id', created_id));

      n_created := n_created + 1;
      sum_weight := sum_weight + coalesce(detail.weight, 0);
    end loop;
  end if;

  created := n_created;
  dropped := n_dropped;
  total_weight := sum_weight;
  return next;
end;
$$;

revoke all on function private.commit_matching_pairs(uuid, text, jsonb, timestamptz) from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------------------
-- The batch. Records every run and never raises; a run that starts while another holds the
-- advisory lock is recorded as skipped.
-- ---------------------------------------------------------------------------------------

drop function if exists public.generate_next_introduction();
drop function if exists private.generate_one_introduction();

create or replace function private.execute_matching_batch(p_limit integer)
returns table (run_id uuid, status text, introductions_created integer)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  current_run uuid;
  total_created integer := 0;
  run_now timestamptz := now();
  city record;
  committed record;
  selected jsonb;
begin
  if p_limit is null or p_limit not between 1 and 5000 then raise exception 'Invalid batch size'; end if;

  if not pg_try_advisory_xact_lock(hashtextextended('network.to:matching', 0)) then
    insert into private.matching_runs (requested_limit, status, started_at, completed_at)
    values (p_limit, 'skipped', clock_timestamp(), clock_timestamp())
    returning id into current_run;
    run_id := current_run;
    status := 'skipped';
    introductions_created := 0;
    return next;
    return;
  end if;

  -- clock_timestamp() records when the run actually began, even inside a longer transaction.
  insert into private.matching_runs (requested_limit, started_at) values (p_limit, clock_timestamp()) returning id into current_run;

  begin
    update public.introductions i
    set status = 'expired'
    where i.status = 'offered' and i.expires_at <= run_now;

    for city in
      select e.city_key, count(*)::integer as eligible
      from private.matching_eligible_members(run_now) e
      group by e.city_key
      order by e.city_key
    loop
      if city.eligible < 2 then
        insert into private.matching_run_cities (run_id, city_key, eligible_members, unmatched_no_peers)
        values (current_run, city.city_key, city.eligible, city.eligible);
        continue;
      end if;

      -- Pass one: the furthest stage each member reached with anyone, for the run's records.
      if to_regclass('pg_temp.matching_batch_stages') is not null then drop table pg_temp.matching_batch_stages; end if;
      create temp table matching_batch_stages on commit drop as
        select v.member_id, max(c.stage) as max_stage
        from private.matching_candidate_pairs(city.city_key, run_now) c
        cross join lateral (values (c.member_a), (c.member_b)) v(member_id)
        group by v.member_id;

      -- Pass two: selection over the pairs above the floor, then re-validated creation.
      select coalesce(jsonb_agg(jsonb_build_object('a', s.member_a, 'b', s.member_b, 'weight', s.weight)), '[]'::jsonb)
      into selected
      from private.select_matching_pairs(city.city_key, run_now, p_limit) s;

      select * into committed
      from private.commit_matching_pairs(current_run, city.city_key, selected, run_now);

      insert into private.matching_run_cities (
        run_id, city_key, eligible_members, unmatched_no_peers, unmatched_all_excluded,
        unmatched_no_meeting_overlap, unmatched_below_floor, unmatched_partners_taken,
        pairs_above_floor, pairs_dropped_at_commit, introductions_created, total_weight
      )
      select
        current_run,
        city.city_key,
        city.eligible,
        0,
        (count(*) filter (where st.max_stage = 0))::integer,
        (count(*) filter (where st.max_stage = 1))::integer,
        (count(*) filter (where st.max_stage = 2))::integer,
        (count(*) filter (
          where st.max_stage = 3
            and not exists (
              select 1 from public.introductions i
              where i.matching_run_id = current_run and st.member_id in (i.member_a, i.member_b)
            )
        ))::integer,
        (select count(*) from pg_temp.matching_batch_pairs)::integer,
        committed.dropped,
        committed.created,
        coalesce(committed.total_weight, 0)
      from pg_temp.matching_batch_stages st;

      total_created := total_created + coalesce(committed.created, 0);
    end loop;

    update private.matching_runs r
    set status = 'completed', completed_at = clock_timestamp(), introductions_created = total_created
    where r.id = current_run;
  exception when others then
    update private.matching_runs r
    set status = 'failed', completed_at = clock_timestamp(), error_message = left(sqlerrm, 1000)
    where r.id = current_run;
    run_id := current_run;
    status := 'failed';
    introductions_created := 0;
    return next;
    return;
  end;

  run_id := current_run;
  status := 'completed';
  introductions_created := total_created;
  return next;
end;
$$;

revoke all on function private.execute_matching_batch(integer) from public, anon, authenticated, service_role;

create or replace function private.run_matching_batch(p_limit integer default 1000)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare result record;
begin
  select * into result from private.execute_matching_batch(p_limit);
  return coalesce(result.introductions_created, 0);
end;
$$;

revoke all on function private.run_matching_batch(integer) from public, anon, authenticated, service_role;

-- The operations path: the same batch on demand, for the service role only.
create or replace function public.run_matching_now()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare result record;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'Service role required'; end if;
  select * into result from private.execute_matching_batch(1000);
  return jsonb_build_object(
    'run_id', result.run_id,
    'status', result.status,
    'introductions_created', result.introductions_created
  );
end;
$$;

revoke execute on function public.run_matching_now() from public, anon, authenticated;
grant execute on function public.run_matching_now() to service_role;

-- ---------------------------------------------------------------------------------------
-- Read model: "Why they may want to meet you" now comes from the reader's own reciprocal
-- explanation instead of the other member's "Why you should meet".
-- ---------------------------------------------------------------------------------------

create or replace function public.get_current_introduction()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  result jsonb;
begin
  if caller is null then raise exception 'Authentication required'; end if;

  select jsonb_build_object(
    'id', i.id,
    'status', i.status,
    'created_at', i.created_at,
    'expires_at', i.expires_at,
    'reason_for_you', case when i.member_a = caller then i.reason_for_a else i.reason_for_b end,
    'reason_for_them', case when i.member_a = caller then i.reciprocal_for_a else i.reciprocal_for_b end,
    'meeting_context', i.meeting_context,
    'your_response', r.decision,
    'person', jsonb_build_object(
      'id', p.id,
      'name', p.name,
      'role', p.role,
      'company_name', p.company_name,
      'company_mark', private.company_mark_reference(p.company_domain),
      'city', p.city,
      'topics', p.topics,
      'bio', p.bio,
      'role_scope', p.role_scope,
      'current_focus', p.current_focus,
      'years_experience', p.years_experience,
      'growth_areas', p.growth_areas,
      'professional_ambition', p.professional_ambition,
      'growth_interest', p.growth_interest,
      'contribution_areas', p.contribution_areas,
      'help_formats', p.help_formats,
      'contribution', p.contribution,
      'contribution_boundaries', p.contribution_boundaries
    )
  ) into result
  from public.introductions i
  join public.profiles p on p.id = case when i.member_a = caller then i.member_b else i.member_a end
  left join public.introduction_responses r on r.introduction_id = i.id and r.user_id = caller
  where caller in (i.member_a, i.member_b)
    and i.status in ('offered', 'mutual')
    and i.expires_at > now()
    and not private.users_blocked(i.member_a, i.member_b)
    -- A member's own Pass hides the introduction from them and from nobody else.
    and not private.introduction_passed_by(i.id, caller)
  order by i.created_at desc
  limit 1;

  return result;
end;
$$;

revoke execute on function public.get_current_introduction() from public, anon;
grant execute on function public.get_current_introduction() to authenticated;

-- ---------------------------------------------------------------------------------------
-- Schedule: the daily batch replaces the hourly job.
-- ---------------------------------------------------------------------------------------

do $$
declare existing_job bigint;
begin
  for existing_job in
    select jobid from cron.job where jobname in ('network-to-hourly-matching', 'network-to-daily-matching')
  loop
    perform cron.unschedule(existing_job);
  end loop;
end;
$$;

select cron.schedule(
  'network-to-daily-matching',
  '7 13 * * *',
  'select private.run_matching_batch(1000)'
);
