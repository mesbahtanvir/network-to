-- Keep introductions local as network.to expands across North American cities.
-- The display value remains member-authored while a normalized generated value
-- gives matching a stable, non-editable comparison key.

alter table public.profiles alter column city set default '';

alter table public.profiles
  add column city_key text generated always as (
    lower(regexp_replace(trim(city), '\s+', ' ', 'g'))
  ) stored;

create index profiles_active_city_key_idx
  on public.profiles (city_key, id)
  where is_active and onboarding_complete;

-- Replace Toronto neighborhood labels with portable within-city regions.
alter table public.meeting_preferences
  alter column areas set default array['Downtown / city centre', 'Flexible within the city']::text[];

update public.meeting_preferences preferences
set areas = coalesce((
  select array_agg(distinct case area
    when 'Downtown Toronto' then 'Downtown / city centre'
    when 'Financial District' then 'Downtown / city centre'
    when 'King West' then 'Downtown / city centre'
    else area
  end)
  from unnest(preferences.areas) as area
), array['Flexible within the city']::text[])
where preferences.areas && array['Downtown Toronto', 'Financial District', 'King West']::text[];

update public.availabilities
set area = case area
  when 'Downtown Toronto' then 'Downtown / city centre'
  when 'Financial District' then 'Downtown / city centre'
  when 'King West' then 'Downtown / city centre'
  else area
end
where area in ('Downtown Toronto', 'Financial District', 'King West');

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
