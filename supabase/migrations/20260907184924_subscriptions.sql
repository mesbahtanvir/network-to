-- One account-scoped free month, followed by an App Store subscription.
-- App Store entitlements are written only by trusted server-side verification.

create table private.memberships (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  trial_started_at timestamptz not null,
  trial_ends_at timestamptz not null,
  status text not null default 'trialing'
    check (status in ('trialing', 'active', 'grace_period', 'billing_retry', 'expired', 'revoked')),
  product_id text,
  original_transaction_id text unique,
  latest_transaction_id text,
  access_ends_at timestamptz,
  auto_renews boolean not null default false,
  environment text check (environment in ('sandbox', 'production')),
  last_verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (trial_ends_at > trial_started_at),
  check (product_id is null or product_id = 'com.mesbahtanvir.networkto.monthly')
);

alter table private.memberships enable row level security;
revoke all on private.memberships from public, anon, authenticated;

create or replace function private.start_membership_trial()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.onboarding_complete and not old.onboarding_complete then
    insert into private.memberships (user_id, trial_started_at, trial_ends_at)
    values (new.id, now(), now() + interval '1 month')
    on conflict (user_id) do nothing;
  end if;
  return new;
end;
$$;

create trigger profiles_start_membership_trial
after update of onboarding_complete on public.profiles
for each row execute function private.start_membership_trial();

-- Existing completed accounts receive a fresh month when subscriptions launch.
insert into private.memberships (user_id, trial_started_at, trial_ends_at)
select id, now(), now() + interval '1 month'
from public.profiles
where onboarding_complete
on conflict (user_id) do nothing;

create or replace function private.has_membership_access(
  p_user_id uuid,
  p_at timestamptz default now()
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select
      m.trial_ends_at > p_at
      or (
        m.status in ('active', 'grace_period')
        and m.access_ends_at is not null
        and m.access_ends_at > p_at
      )
    from private.memberships m
    where m.user_id = p_user_id
  ), false)
$$;

create or replace function public.get_membership_status()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  member_id uuid := auth.uid();
  membership private.memberships%rowtype;
  effective_state text;
begin
  if member_id is null then raise exception 'Authentication required'; end if;

  select * into membership
  from private.memberships
  where user_id = member_id;

  if membership.user_id is null then
    return jsonb_build_object('state', 'not_started');
  end if;

  effective_state := case
    when membership.status in ('active', 'grace_period')
      and membership.access_ends_at > now() then 'subscribed'
    when membership.trial_ends_at > now() then 'trial'
    else 'expired'
  end;

  return jsonb_build_object(
    'state', effective_state,
    'trial_started_at', membership.trial_started_at,
    'trial_ends_at', membership.trial_ends_at,
    'product_id', membership.product_id,
    'access_ends_at', membership.access_ends_at,
    'auto_renews', membership.auto_renews
  );
end;
$$;

create or replace function public.record_app_store_entitlement(
  p_user_id uuid,
  p_product_id text,
  p_original_transaction_id text,
  p_latest_transaction_id text,
  p_status text,
  p_access_ends_at timestamptz,
  p_auto_renews boolean,
  p_environment text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_product_id <> 'com.mesbahtanvir.networkto.monthly' then
    raise exception 'Unsupported product';
  end if;
  if p_status not in ('active', 'grace_period', 'billing_retry', 'expired', 'revoked') then
    raise exception 'Invalid subscription status';
  end if;
  if p_environment not in ('sandbox', 'production') then
    raise exception 'Invalid App Store environment';
  end if;

  insert into private.memberships (
    user_id,
    trial_started_at,
    trial_ends_at,
    status,
    product_id,
    original_transaction_id,
    latest_transaction_id,
    access_ends_at,
    auto_renews,
    environment,
    last_verified_at,
    updated_at
  ) values (
    p_user_id,
    now(),
    now() + interval '1 month',
    p_status,
    p_product_id,
    p_original_transaction_id,
    p_latest_transaction_id,
    p_access_ends_at,
    p_auto_renews,
    p_environment,
    now(),
    now()
  )
  on conflict (user_id) do update set
    status = excluded.status,
    product_id = excluded.product_id,
    original_transaction_id = excluded.original_transaction_id,
    latest_transaction_id = excluded.latest_transaction_id,
    access_ends_at = excluded.access_ends_at,
    auto_renews = excluded.auto_renews,
    environment = excluded.environment,
    last_verified_at = excluded.last_verified_at,
    updated_at = now();
end;
$$;

revoke all on function private.start_membership_trial() from public, anon, authenticated, service_role;
revoke all on function private.has_membership_access(uuid, timestamptz) from public, anon, authenticated, service_role;
revoke execute on function public.get_membership_status() from public, anon;
grant execute on function public.get_membership_status() to authenticated;
revoke execute on function public.record_app_store_entitlement(uuid, text, text, text, text, timestamptz, boolean, text)
  from public, anon, authenticated;
grant execute on function public.record_app_store_entitlement(uuid, text, text, text, text, timestamptz, boolean, text)
  to service_role;

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
    join private.memberships s1 on s1.user_id = p1.id
    join private.memberships s2 on s2.user_id = p2.id
    where p1.is_active and p2.is_active
      and p1.onboarding_complete and p2.onboarding_complete
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

revoke all on function private.generate_one_introduction() from public, anon, authenticated, service_role;

-- Authorization is enforced by EXECUTE privileges. Keeping the wrapper free of
-- request-JWT helpers also makes scheduled service-role execution deterministic.
create or replace function public.generate_next_introduction()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
begin
  return private.generate_one_introduction();
end;
$$;

revoke execute on function public.generate_next_introduction() from public, anon, authenticated;
grant execute on function public.generate_next_introduction() to service_role;
