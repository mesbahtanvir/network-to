-- A Pass is private. Until now a Pass closed the introduction at once, so the other member's
-- introduction disappeared at their next refresh (or their Interested response failed with
-- "Introduction is no longer open"), which announced the Pass by timing. From here on a Pass
-- records the member's response and changes nothing the other member can read: the
-- introduction stays open for them, with its original expiry, until it expires, becomes
-- mutual, or is blocked. It closes at once only when both members have passed. A member's
-- own Pass hides the introduction from them and frees them for matching at their cadence.
--
-- No schema change, no new secret, no operator step. Four functions are (re)defined.

create or replace function private.introduction_passed_by(p_introduction_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.introduction_responses r
    where r.introduction_id = p_introduction_id
      and r.user_id = p_user_id
      and r.decision = 'pass'
  );
$$;

revoke all on function private.introduction_passed_by(uuid, uuid)
  from public, anon, authenticated, service_role;

create or replace function public.respond_to_introduction(p_introduction_id uuid, p_decision text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  intro public.introductions%rowtype;
  other_decision text;
  conversation_id uuid;
begin
  if caller is null then raise exception 'Authentication required'; end if;
  if p_decision not in ('interested', 'pass') then raise exception 'Invalid response'; end if;

  select * into intro from public.introductions
  where id = p_introduction_id for update;

  if intro.id is null or caller not in (intro.member_a, intro.member_b) then
    raise exception 'Introduction not found';
  end if;
  if intro.status <> 'offered' or intro.expires_at <= now() then
    raise exception 'Introduction is no longer open';
  end if;
  if private.users_blocked(intro.member_a, intro.member_b) then
    raise exception 'Introduction is unavailable';
  end if;

  insert into public.introduction_responses (introduction_id, user_id, decision)
  values (intro.id, caller, p_decision)
  on conflict (introduction_id, user_id) do nothing;

  if not found then raise exception 'Response already recorded'; end if;

  select r.decision into other_decision
  from public.introduction_responses r
  where r.introduction_id = intro.id and r.user_id <> caller;

  if p_decision = 'pass' then
    -- The introduction stays open for the other member so nothing they can read changes.
    -- It closes only once nobody is waiting on it.
    if other_decision = 'pass' then
      update public.introductions set status = 'closed' where id = intro.id;
    end if;
    return jsonb_build_object('state', 'not_mutual');
  end if;

  if other_decision = 'interested' then
    update public.introductions set status = 'mutual' where id = intro.id;
    insert into public.conversations (introduction_id, member_a, member_b)
    values (intro.id, intro.member_a, intro.member_b)
    returning id into conversation_id;
    insert into public.notification_events (user_id, kind, payload)
    values
      (intro.member_a, 'mutual_interest', jsonb_build_object('introduction_id', intro.id, 'conversation_id', conversation_id)),
      (intro.member_b, 'mutual_interest', jsonb_build_object('introduction_id', intro.id, 'conversation_id', conversation_id));
    return jsonb_build_object('state', 'mutual', 'conversation_id', conversation_id);
  end if;

  -- The other member has not answered, or has passed: both look the same to the caller, and
  -- the introduction ends for the caller only at its expiry.
  return jsonb_build_object('state', 'waiting');
end;
$$;

revoke execute on function public.respond_to_introduction(uuid, text) from public, anon;
grant execute on function public.respond_to_introduction(uuid, text) to authenticated;

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
    'reason_for_them', case when i.member_a = caller then i.reason_for_b else i.reason_for_a end,
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
    join public.profiles p2 on p1.id < p2.id and p1.city_key = p2.city_key
    join public.networking_preferences n1 on n1.user_id = p1.id
    join public.networking_preferences n2 on n2.user_id = p2.id
    join public.meeting_preferences m1 on m1.user_id = p1.id
    join public.meeting_preferences m2 on m2.user_id = p2.id
    join private.memberships s1 on s1.user_id = p1.id
    join private.memberships s2 on s2.user_id = p2.id
    where p1.is_active and p2.is_active
      and p1.onboarding_complete and p2.onboarding_complete
      and p1.city_key <> ''
      and (
        s1.trial_ends_at > now()
        or (s1.status in ('active', 'grace_period') and s1.access_ends_at > now())
      )
      and (
        s2.trial_ends_at > now()
        or (s2.status in ('active', 'grace_period') and s2.access_ends_at > now())
      )
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
      -- An open introduction is a member's active one only while they have not passed on it:
      -- the member who passed is free again at their cadence, the waiting member is not.
      and not exists (
        select 1 from public.introductions active_i
        where active_i.status in ('offered', 'mutual')
          and (
            (p1.id in (active_i.member_a, active_i.member_b)
              and not private.introduction_passed_by(active_i.id, p1.id))
            or (p2.id in (active_i.member_a, active_i.member_b)
              and not private.introduction_passed_by(active_i.id, p2.id))
          )
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
    'You are both in the same city and prefer ' || selected_pair.shared_format || ' around '
      || selected_pair.shared_area || '. Confirm a public place together after mutual interest.'
  ) returning id into created_id;

  insert into public.notification_events (user_id, kind, payload)
  values
    (selected_pair.member_a, 'introduction_ready', jsonb_build_object('introduction_id', created_id)),
    (selected_pair.member_b, 'introduction_ready', jsonb_build_object('introduction_id', created_id));
  return created_id;
end;
$$;

revoke all on function private.generate_one_introduction() from public, anon, authenticated, service_role;
