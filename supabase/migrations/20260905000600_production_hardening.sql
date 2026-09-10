-- Production hardening for the first closed launch.
-- Sensitive writes become idempotent RPCs, matching respects member cadence and
-- meeting overlap, and Supabase Cron owns matching and retention maintenance.

create extension if not exists pg_cron with schema pg_catalog;

alter table private.auth_handoffs
  add column failed_claims integer not null default 0 check (failed_claims between 0 and 10);

alter table public.notification_events
  add column attempt_count integer not null default 0 check (attempt_count >= 0),
  add column last_attempt_at timestamptz,
  add column last_error text check (last_error is null or char_length(last_error) <= 1000);

alter table public.device_tokens
  add column created_at timestamptz not null default now();

alter table public.device_tokens
  add constraint device_tokens_token_format
  check (token ~ '^[0-9a-f]{64,200}$') not valid;

alter table public.device_tokens validate constraint device_tokens_token_format;

create table private.matching_runs (
  id uuid primary key default gen_random_uuid(),
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  requested_limit integer not null check (requested_limit between 1 and 100),
  introductions_created integer not null default 0 check (introductions_created >= 0),
  status text not null default 'running' check (status in ('running', 'completed', 'failed', 'skipped')),
  error_message text check (error_message is null or char_length(error_message) <= 1000)
);

create index matching_runs_started_idx on private.matching_runs(started_at desc);
revoke all on table private.matching_runs from public, anon, authenticated;

create table private.edge_rate_limits (
  key_hash text not null check (key_hash ~ '^[0-9a-f]{64}$'),
  action text not null check (action in ('create', 'complete', 'claim')),
  window_start timestamptz not null,
  attempts integer not null default 1 check (attempts > 0),
  primary key (key_hash, action, window_start)
);

create index edge_rate_limits_window_idx on private.edge_rate_limits(window_start);
revoke all on table private.edge_rate_limits from public, anon, authenticated;

create or replace function public.consume_edge_rate_limit(
  p_key_hash text,
  p_action text,
  p_limit integer,
  p_window_seconds integer
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare bucket timestamptz; current_attempts integer;
begin
  if p_key_hash !~ '^[0-9a-f]{64}$'
     or p_action not in ('create', 'complete', 'claim')
     or p_limit not between 1 and 1000
     or p_window_seconds not between 60 and 86400 then
    raise exception 'Invalid rate limit request';
  end if;

  bucket := to_timestamp(
    floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds
  );
  delete from private.edge_rate_limits
    where window_start < now() - interval '2 days';

  insert into private.edge_rate_limits (key_hash, action, window_start, attempts)
  values (p_key_hash, p_action, bucket, 1)
  on conflict (key_hash, action, window_start) do update
    set attempts = private.edge_rate_limits.attempts + 1
  returning attempts into current_attempts;

  return current_attempts <= p_limit;
end;
$$;

revoke execute on function public.consume_edge_rate_limit(text, text, integer, integer)
  from public, anon, authenticated;
grant execute on function public.consume_edge_rate_limit(text, text, integer, integer)
  to service_role;

create or replace function private.clean_text_array(
  p_value jsonb,
  p_max_items integer,
  p_max_length integer
)
returns text[]
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare result text[];
begin
  if p_value is null or p_value = 'null'::jsonb then return '{}'::text[]; end if;
  if jsonb_typeof(p_value) <> 'array' or jsonb_array_length(p_value) > p_max_items then
    raise exception 'Invalid profile list';
  end if;

  select coalesce(array_agg(value order by ordinal), '{}'::text[])
  into result
  from (
    select left(trim(item), p_max_length) as value, min(position) as ordinal
    from jsonb_array_elements_text(p_value) with ordinality values_list(item, position)
    where trim(item) <> ''
    group by left(trim(item), p_max_length)
  ) cleaned;
  return result;
end;
$$;

create or replace function public.save_professional_profile(
  p_profile jsonb,
  p_experiences jsonb default '[]'::jsonb,
  p_onboarding_complete boolean default false
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  clean_name text;
  clean_role text;
  clean_city text;
  clean_role_scope text;
  clean_focus text;
  clean_ambition text;
  clean_growth text;
  experience jsonb;
  experience_position integer := 0;
begin
  if caller is null then raise exception 'Authentication required'; end if;
  if jsonb_typeof(p_profile) <> 'object' or pg_column_size(p_profile) > 65536 then
    raise exception 'Invalid profile';
  end if;
  if jsonb_typeof(coalesce(p_experiences, '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_experiences, '[]'::jsonb)) > 20 then
    raise exception 'Invalid professional history';
  end if;

  clean_name := left(trim(coalesce(p_profile->>'name', '')), 120);
  clean_role := left(trim(coalesce(p_profile->>'role', '')), 160);
  clean_city := left(trim(coalesce(p_profile->>'city', '')), 120);
  clean_role_scope := left(trim(coalesce(p_profile->>'role_scope', '')), 1200);
  clean_focus := left(trim(coalesce(p_profile->>'current_focus', '')), 1200);
  clean_ambition := left(trim(coalesce(p_profile->>'professional_ambition', '')), 1200);
  clean_growth := left(trim(coalesce(p_profile->>'growth_interest', '')), 1200);

  if p_onboarding_complete and (
    clean_name = '' or clean_role = '' or clean_city = '' or clean_role_scope = ''
    or clean_focus = '' or clean_ambition = '' or clean_growth = ''
    or cardinality(private.clean_text_array(p_profile->'growth_areas', 12, 120)) = 0
    or cardinality(private.clean_text_array(p_profile->'contribution_areas', 12, 120)) = 0
  ) then
    raise exception 'Complete the required professional context before continuing';
  end if;

  update public.profiles
  set name = clean_name,
      role = clean_role,
      city = clean_city,
      topics = private.clean_text_array(p_profile->'topics', 12, 120),
      bio = left(trim(coalesce(p_profile->>'bio', '')), 1200),
      role_scope = clean_role_scope,
      current_focus = clean_focus,
      years_experience = left(trim(coalesce(p_profile->>'years_experience', '')), 80),
      growth_areas = private.clean_text_array(p_profile->'growth_areas', 12, 120),
      professional_ambition = clean_ambition,
      growth_interest = clean_growth,
      contribution_areas = private.clean_text_array(p_profile->'contribution_areas', 12, 120),
      help_formats = private.clean_text_array(p_profile->'help_formats', 12, 120),
      contribution = left(trim(coalesce(p_profile->>'contribution', '')), 1200),
      contribution_boundaries = left(trim(coalesce(p_profile->>'contribution_boundaries', '')), 800),
      education = left(trim(coalesce(p_profile->>'education', '')), 500),
      onboarding_complete = p_onboarding_complete
  where id = caller;

  if not found then raise exception 'Profile not found'; end if;

  delete from public.professional_experiences where user_id = caller;
  for experience in select value from jsonb_array_elements(coalesce(p_experiences, '[]'::jsonb))
  loop
    if jsonb_typeof(experience) <> 'object'
       or trim(coalesce(experience->>'role', '')) = ''
       or trim(coalesce(experience->>'company', '')) = '' then
      raise exception 'Invalid professional history item';
    end if;
    insert into public.professional_experiences (id, user_id, role, company, period, position)
    values (
      case when coalesce(experience->>'id', '') ~* '^[0-9a-f-]{36}$'
        then (experience->>'id')::uuid else gen_random_uuid() end,
      caller,
      left(trim(experience->>'role'), 160),
      left(trim(experience->>'company'), 160),
      left(trim(coalesce(experience->>'period', '')), 120),
      experience_position
    );
    experience_position := experience_position + 1;
  end loop;
end;
$$;

revoke execute on function public.save_professional_profile(jsonb, jsonb, boolean) from public, anon;
grant execute on function public.save_professional_profile(jsonb, jsonb, boolean) to authenticated;

create or replace function public.send_message(
  p_message_id uuid,
  p_conversation_id uuid,
  p_body text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  clean_body text := trim(coalesce(p_body, ''));
  existing public.messages%rowtype;
begin
  if caller is null then raise exception 'Authentication required'; end if;
  if p_message_id is null or char_length(clean_body) not between 1 and 2000 then
    raise exception 'Message must contain between 1 and 2000 characters';
  end if;
  if not exists (
    select 1 from public.conversations c
    where c.id = p_conversation_id
      and caller in (c.member_a, c.member_b)
      and c.status = 'active'
      and not private.users_blocked(c.member_a, c.member_b)
  ) then
    raise exception 'Conversation not found';
  end if;

  select * into existing from public.messages where id = p_message_id;
  if existing.id is not null then
    if existing.conversation_id = p_conversation_id
       and existing.sender_id = caller
       and existing.body = clean_body then
      return existing.id;
    end if;
    raise exception 'Message identifier already used';
  end if;

  insert into public.messages (id, conversation_id, sender_id, body)
  values (p_message_id, p_conversation_id, caller, clean_body);
  return p_message_id;
end;
$$;

revoke insert on public.messages from authenticated;
revoke execute on function public.send_message(uuid, uuid, text) from public, anon;
grant execute on function public.send_message(uuid, uuid, text) to authenticated;

create or replace function public.get_safety_preferences()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'blocked_members',
    coalesce(jsonb_agg(p.name order by b.created_at desc) filter (where p.id is not null), '[]'::jsonb)
  )
  from public.blocks b
  join public.profiles p on p.id = b.blocked_id
  where b.blocker_id = auth.uid();
$$;

revoke execute on function public.get_safety_preferences() from public, anon;
grant execute on function public.get_safety_preferences() to authenticated;

create or replace function public.register_device_token(p_token text, p_environment text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare caller uuid := auth.uid(); normalized_token text := lower(trim(coalesce(p_token, '')));
begin
  if caller is null then raise exception 'Authentication required'; end if;
  if normalized_token !~ '^[0-9a-f]{64,200}$' then raise exception 'Invalid device token'; end if;
  if p_environment not in ('sandbox', 'production') then raise exception 'Invalid push environment'; end if;

  insert into public.device_tokens (user_id, token, environment)
  values (caller, normalized_token, p_environment)
  on conflict (token) do update
    set user_id = excluded.user_id,
        environment = excluded.environment,
        updated_at = now();
end;
$$;

create or replace function public.unregister_device_token(p_token text)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.device_tokens
  where user_id = auth.uid() and token = lower(trim(p_token));
$$;

revoke insert, update, delete on public.device_tokens from authenticated;
revoke execute on function public.register_device_token(text, text) from public, anon;
revoke execute on function public.unregister_device_token(text) from public, anon;
grant execute on function public.register_device_token(text, text) to authenticated;
grant execute on function public.unregister_device_token(text) to authenticated;

create or replace function public.claim_auth_handoff(p_id uuid, p_claim_secret_hash text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  handoff private.auth_handoffs%rowtype;
  claimed_code text;
begin
  select * into handoff from private.auth_handoffs where id = p_id for update;
  if handoff.id is null then return null; end if;
  if handoff.expires_at <= now() or handoff.failed_claims >= 10 then
    delete from private.auth_handoffs where id = p_id;
    return null;
  end if;
  if handoff.claim_secret_hash <> p_claim_secret_hash then
    update private.auth_handoffs set failed_claims = failed_claims + 1 where id = p_id;
    return null;
  end if;
  if handoff.auth_code is null then return null; end if;

  delete from private.auth_handoffs where id = p_id returning auth_code into claimed_code;
  return claimed_code;
end;
$$;

revoke execute on function public.claim_auth_handoff(uuid, text) from public, anon, authenticated;
grant execute on function public.claim_auth_handoff(uuid, text) to service_role;

create or replace function private.generate_one_introduction()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare selected_pair record; created_id uuid;
begin
  with candidates as (
    select
      p1.id as member_a,
      p2.id as member_b,
      p1.name as name_a,
      p2.name as name_b,
      p1.current_focus as focus_a,
      p2.current_focus as focus_b,
      p1.professional_ambition as ambition_a,
      p2.professional_ambition as ambition_b,
      p1.company_domain as company_a,
      p2.company_domain as company_b,
      p1.industry as industry_a,
      p2.industry as industry_b,
      n1.frequency as frequency_a,
      n2.frequency as frequency_b,
      private.array_overlap_count(p1.contribution_areas, p2.growth_areas)
        + private.array_overlap_count(p2.contribution_areas, p1.growth_areas) as reciprocal_score,
      private.array_overlap_count(p1.topics, p2.topics) as topic_score,
      private.array_overlap_count(n1.goals, n2.goals) as goal_score,
      private.array_overlap_count(m1.areas, m2.areas) as area_score,
      private.array_overlap_count(m1.formats, m2.formats) as format_score,
      private.array_overlap_count(m1.windows, m2.windows) as window_score,
      (select value from unnest(m1.areas) value where value = any(m2.areas) limit 1) as shared_area,
      (select value from unnest(m1.formats) value where value = any(m2.formats) limit 1) as shared_format,
      (select max(i.created_at) from public.introductions i where p1.id in (i.member_a, i.member_b)) as last_a,
      (select max(i.created_at) from public.introductions i where p2.id in (i.member_a, i.member_b)) as last_b
    from public.profiles p1
    join public.profiles p2 on p1.id < p2.id
    join public.networking_preferences n1 on n1.user_id = p1.id
    join public.networking_preferences n2 on n2.user_id = p2.id
    join public.meeting_preferences m1 on m1.user_id = p1.id
    join public.meeting_preferences m2 on m2.user_id = p2.id
    where p1.is_active and p2.is_active
      and p1.onboarding_complete and p2.onboarding_complete
      and n1.frequency <> 'paused' and n2.frequency <> 'paused'
      and (n1.cross_company or p1.company_domain = p2.company_domain)
      and (n2.cross_company or p1.company_domain = p2.company_domain)
      and (n1.cross_industry or p1.industry = p2.industry)
      and (n2.cross_industry or p1.industry = p2.industry)
      and not private.users_blocked(p1.id, p2.id)
      and not exists (
        select 1 from public.introductions i
        where p1.id in (i.member_a, i.member_b) and p2.id in (i.member_a, i.member_b)
          and i.created_at > now() - interval '180 days'
      )
      and not exists (
        select 1 from public.introductions active_i
        where active_i.status in ('offered', 'mutual')
          and (p1.id in (active_i.member_a, active_i.member_b) or p2.id in (active_i.member_a, active_i.member_b))
      )
      and not exists (
        select 1 from public.introductions recent_a
        where p1.id in (recent_a.member_a, recent_a.member_b)
          and recent_a.created_at > now() - case n1.frequency
            when 'weekly' then interval '7 days'
            when 'twice_monthly' then interval '14 days'
            when 'monthly' then interval '28 days'
            else interval '90 days' end
      )
      and not exists (
        select 1 from public.introductions recent_b
        where p2.id in (recent_b.member_a, recent_b.member_b)
          and recent_b.created_at > now() - case n2.frequency
            when 'weekly' then interval '7 days'
            when 'twice_monthly' then interval '14 days'
            when 'monthly' then interval '28 days'
            else interval '90 days' end
      )
  ), eligible as (
    select *,
      reciprocal_score * 5 + topic_score * 2 + goal_score
        + case when company_a <> company_b then 1 else 0 end
        + case when industry_a <> industry_b then 1 else 0 end as quality_score
    from candidates
    where reciprocal_score >= 1 and area_score >= 1 and format_score >= 1 and window_score >= 1
  )
  select * into selected_pair
  from eligible
  order by quality_score desc,
    greatest(coalesce(last_a, '-infinity'::timestamptz), coalesce(last_b, '-infinity'::timestamptz)) asc,
    random()
  limit 1;

  if selected_pair.member_a is null then return null; end if;

  insert into public.introductions (member_a, member_b, reason_for_a, reason_for_b, meeting_context)
  values (
    selected_pair.member_a,
    selected_pair.member_b,
    selected_pair.name_b || ' is working toward ' || selected_pair.ambition_b
      || '. Their experience connects with your current focus: ' || selected_pair.focus_a,
    selected_pair.name_a || ' is working toward ' || selected_pair.ambition_a
      || '. Their experience connects with your current focus: ' || selected_pair.focus_b,
    'You both prefer ' || selected_pair.shared_format || ' around ' || selected_pair.shared_area
      || '. Confirm a public place together after mutual interest.'
  ) returning id into created_id;

  insert into public.notification_events (user_id, kind, payload)
  values
    (selected_pair.member_a, 'introduction_ready', jsonb_build_object('introduction_id', created_id)),
    (selected_pair.member_b, 'introduction_ready', jsonb_build_object('introduction_id', created_id));
  return created_id;
end;
$$;

create or replace function public.generate_next_introduction()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.role() <> 'service_role' then raise exception 'Service role required'; end if;
  return private.generate_one_introduction();
end;
$$;

revoke execute on function public.generate_next_introduction() from public, anon, authenticated;
grant execute on function public.generate_next_introduction() to service_role;

create or replace function private.run_matching_batch(p_limit integer default 25)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  run_id uuid;
  created_count integer := 0;
  introduction_id uuid;
begin
  if p_limit not between 1 and 100 then raise exception 'Invalid batch size'; end if;
  if not pg_try_advisory_xact_lock(hashtextextended('network.to:matching', 0)) then
    insert into private.matching_runs (requested_limit, status, completed_at)
    values (p_limit, 'skipped', now());
    return 0;
  end if;

  insert into private.matching_runs (requested_limit) values (p_limit) returning id into run_id;
  begin
    update public.introductions
    set status = 'expired'
    where status = 'offered' and expires_at <= now();

    for batch_index in 1..p_limit loop
      introduction_id := private.generate_one_introduction();
      exit when introduction_id is null;
      created_count := created_count + 1;
    end loop;

    update private.matching_runs
    set status = 'completed', completed_at = now(), introductions_created = created_count
    where id = run_id;
  exception when others then
    update private.matching_runs
    set status = 'failed', completed_at = now(), error_message = left(sqlerrm, 1000)
    where id = run_id;
    return 0;
  end;
  return created_count;
end;
$$;

create or replace function private.run_retention_maintenance()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from private.auth_handoffs where expires_at <= now();
  delete from public.availabilities where expires_at <= now();
  update public.introductions set status = 'expired'
    where status = 'offered' and expires_at <= now();
  delete from public.notification_events
    where created_at < now() - interval '90 days'
      and (read_at is not null or delivered_at is not null);
  delete from private.matching_runs where started_at < now() - interval '180 days';
  delete from private.edge_rate_limits where window_start < now() - interval '2 days';
end;
$$;

revoke all on function private.generate_one_introduction() from public, anon, authenticated, service_role;
revoke all on function private.run_matching_batch(integer) from public, anon, authenticated, service_role;
revoke all on function private.run_retention_maintenance() from public, anon, authenticated, service_role;

do $$
declare existing_job bigint;
begin
  for existing_job in
    select jobid from cron.job where jobname in ('network-to-hourly-matching', 'network-to-daily-maintenance')
  loop
    perform cron.unschedule(existing_job);
  end loop;
end;
$$;

select cron.schedule(
  'network-to-hourly-matching',
  '7 * * * *',
  'select private.run_matching_batch(25)'
);

select cron.schedule(
  'network-to-daily-maintenance',
  '15 4 * * *',
  'select private.run_retention_maintenance()'
);
