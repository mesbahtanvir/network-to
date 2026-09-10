-- network.to initial Supabase schema
-- All exposed tables use RLS. Sensitive multi-row operations are transactional RPCs.

create extension if not exists pgcrypto with schema extensions;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table public.company_domains (
  domain text primary key check (domain = lower(domain)),
  company_name text not null,
  industry text not null,
  status text not null default 'approved' check (status in ('approved', 'review_pending', 'rejected')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  company_domain text not null references public.company_domains(domain),
  company_name text not null,
  industry text not null,
  name text not null default '',
  role text not null default '',
  city text not null default 'Toronto',
  topics text[] not null default '{}',
  bio text not null default '',
  role_scope text not null default '',
  current_focus text not null default '',
  years_experience text not null default '',
  growth_areas text[] not null default '{}',
  professional_ambition text not null default '',
  growth_interest text not null default '',
  contribution_areas text[] not null default '{}',
  help_formats text[] not null default '{}',
  contribution text not null default '',
  contribution_boundaries text not null default '',
  education text not null default '',
  onboarding_complete boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.professional_experiences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null,
  company text not null,
  period text not null,
  position integer not null default 0,
  created_at timestamptz not null default now()
);

create table public.networking_preferences (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  frequency text not null default 'weekly' check (frequency in ('weekly', 'twice_monthly', 'monthly', 'exceptional_only', 'paused')),
  goals text[] not null default array['Learn from peers', 'Broaden industry perspective'],
  relationship_mix text not null default 'Peers and adjacent leaders',
  cross_company boolean not null default true,
  cross_industry boolean not null default true,
  updated_at timestamptz not null default now()
);

create table public.meeting_preferences (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  areas text[] not null default array['Downtown Toronto', 'Financial District'],
  formats text[] not null default array['Coffee', 'Walk'],
  windows text[] not null default array['Lunch', 'After work'],
  updated_at timestamptz not null default now()
);

create table public.availabilities (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  area text not null,
  time_window text not null,
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  check (expires_at > created_at)
);

create table public.introductions (
  id uuid primary key default gen_random_uuid(),
  member_a uuid not null references public.profiles(id) on delete cascade,
  member_b uuid not null references public.profiles(id) on delete cascade,
  reason_for_a text not null,
  reason_for_b text not null,
  meeting_context text not null,
  status text not null default 'offered' check (status in ('offered', 'mutual', 'closed', 'expired')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '7 days'),
  updated_at timestamptz not null default now(),
  check (member_a <> member_b),
  check (member_a < member_b)
);

create unique index introductions_one_active_pair
  on public.introductions (member_a, member_b)
  where status in ('offered', 'mutual');
create index introductions_member_a_idx on public.introductions(member_a, created_at desc);
create index introductions_member_b_idx on public.introductions(member_b, created_at desc);

create table public.introduction_responses (
  introduction_id uuid not null references public.introductions(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  decision text not null check (decision in ('interested', 'pass')),
  private_feedback text,
  created_at timestamptz not null default now(),
  primary key (introduction_id, user_id)
);

create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  introduction_id uuid not null unique references public.introductions(id) on delete cascade,
  member_a uuid not null references public.profiles(id) on delete cascade,
  member_b uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'active' check (status in ('active', 'ended', 'blocked')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (member_a <> member_b)
);
create index conversations_member_a_idx on public.conversations(member_a, updated_at desc);
create index conversations_member_b_idx on public.conversations(member_b, updated_at desc);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index messages_conversation_idx on public.messages(conversation_id, created_at);

create table public.meetups (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  proposed_by uuid not null references public.profiles(id) on delete cascade,
  starts_at timestamptz,
  place_name text,
  area text,
  status text not null default 'proposed' check (status in ('proposed', 'confirmed', 'cancelled', 'feedback_due', 'completed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.meetup_feedback (
  meetup_id uuid not null references public.meetups(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  outcome text not null check (outcome in ('good', 'okay', 'not_for_me', 'did_not_meet')),
  stay_connected boolean not null default false,
  private_note text,
  created_at timestamptz not null default now(),
  primary key (meetup_id, user_id)
);

create table public.connections (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references public.profiles(id) on delete cascade,
  connected_user_id uuid not null references public.profiles(id) on delete cascade,
  introduction_id uuid references public.introductions(id) on delete set null,
  origin text not null,
  connected_at timestamptz not null default now(),
  check (owner_user_id <> connected_user_id),
  unique (owner_user_id, connected_user_id)
);

create table public.blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  subject_id uuid not null references public.profiles(id) on delete cascade,
  conversation_id uuid references public.conversations(id) on delete set null,
  category text not null check (category in ('harassment', 'spam', 'fraud', 'inappropriate', 'romantic', 'discrimination', 'threatening', 'other')),
  note text not null default '' check (char_length(note) <= 2000),
  status text not null default 'open' check (status in ('open', 'reviewing', 'resolved', 'dismissed')),
  created_at timestamptz not null default now(),
  check (reporter_id <> subject_id)
);

create table public.resume_documents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  storage_path text not null unique,
  status text not null default 'uploaded' check (status in ('uploaded', 'processing', 'ready', 'failed')),
  extracted_suggestions jsonb not null default '[]'::jsonb,
  error_message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  token text not null unique,
  environment text not null check (environment in ('sandbox', 'production')),
  updated_at timestamptz not null default now()
);

create table public.notification_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('introduction_ready', 'mutual_interest', 'new_message', 'meetup_reminder', 'feedback_due')),
  payload jsonb not null default '{}'::jsonb,
  deliver_after timestamptz not null default now(),
  delivered_at timestamptz,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index notification_events_user_idx on public.notification_events(user_id, created_at desc);
create index notification_events_delivery_idx
  on public.notification_events(deliver_after)
  where delivered_at is null;

create or replace function private.enqueue_message_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare recipient uuid;
begin
  select case when c.member_a = new.sender_id then c.member_b else c.member_a end
  into recipient
  from public.conversations c
  where c.id = new.conversation_id
    and new.sender_id in (c.member_a, c.member_b)
    and c.status = 'active';

  if recipient is not null then
    insert into public.notification_events (user_id, kind, payload)
    values (
      recipient,
      'new_message',
      jsonb_build_object('conversation_id', new.conversation_id, 'message_id', new.id)
    );
  end if;
  return new;
end;
$$;

create trigger messages_enqueue_notification
after insert on public.messages
for each row execute function private.enqueue_message_notification();

create or replace function private.enqueue_meetup_notifications()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.notification_events (user_id, kind, payload, deliver_after)
  select
    participant,
    'meetup_reminder',
    jsonb_build_object(
      'conversation_id', new.conversation_id,
      'meetup_id', new.id,
      'starts_at', new.starts_at,
      'place_name', new.place_name,
      'area', new.area
    ),
    greatest(now(), coalesce(new.starts_at, now()) - interval '1 hour')
  from public.conversations c,
    lateral unnest(array[c.member_a, c.member_b]) participant
  where c.id = new.conversation_id;
  return new;
end;
$$;

create trigger meetups_enqueue_notifications
after insert on public.meetups
for each row execute function private.enqueue_meetup_notifications();

create or replace function private.touch_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger company_domains_touch before update on public.company_domains
for each row execute function private.touch_updated_at();
create trigger profiles_touch before update on public.profiles
for each row execute function private.touch_updated_at();
create trigger networking_preferences_touch before update on public.networking_preferences
for each row execute function private.touch_updated_at();
create trigger meeting_preferences_touch before update on public.meeting_preferences
for each row execute function private.touch_updated_at();
create trigger introductions_touch before update on public.introductions
for each row execute function private.touch_updated_at();
create trigger conversations_touch before update on public.conversations
for each row execute function private.touch_updated_at();
create trigger meetups_touch before update on public.meetups
for each row execute function private.touch_updated_at();
create trigger resume_documents_touch before update on public.resume_documents
for each row execute function private.touch_updated_at();
create trigger device_tokens_touch before update on public.device_tokens
for each row execute function private.touch_updated_at();

create or replace function public.hook_restrict_signup_by_company_domain(event jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  requested_email text := lower(event->'user'->>'email');
  requested_domain text := split_part(requested_email, '@', 2);
  domain_status text;
begin
  select cd.status into domain_status
  from public.company_domains cd
  where cd.domain = requested_domain;

  if domain_status = 'approved' then
    return '{}'::jsonb;
  end if;

  return jsonb_build_object(
    'error', jsonb_build_object(
      'http_code', 403,
      'message', case
        when domain_status = 'review_pending' then 'This company domain is still under review.'
        else 'Use an approved company email to join network.to.'
      end
    )
  );
end;
$$;

grant execute on function public.hook_restrict_signup_by_company_domain(jsonb) to supabase_auth_admin;
revoke execute on function public.hook_restrict_signup_by_company_domain(jsonb) from public, anon, authenticated;

create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  requested_domain text := split_part(lower(new.email), '@', 2);
  approved_company public.company_domains%rowtype;
begin
  select * into approved_company
  from public.company_domains
  where domain = requested_domain and status = 'approved';

  if approved_company.domain is null then
    raise exception 'Approved company domain required';
  end if;

  insert into public.profiles (id, email, company_domain, company_name, industry, name)
  values (
    new.id,
    lower(new.email),
    approved_company.domain,
    approved_company.company_name,
    approved_company.industry,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1))
  );
  insert into public.networking_preferences (user_id) values (new.id);
  insert into public.meeting_preferences (user_id) values (new.id);
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function private.handle_new_user();

create or replace function public.validate_company_domain(requested_domain text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when cd.status = 'approved' then jsonb_build_object(
      'decision', 'eligible', 'domain', cd.domain, 'company_name', cd.company_name, 'industry', cd.industry
    )
    when cd.status = 'review_pending' then jsonb_build_object('decision', 'review_required', 'domain', lower(requested_domain))
    else jsonb_build_object('decision', 'ineligible', 'domain', lower(requested_domain))
  end
  from (select 1) seed
  left join public.company_domains cd on cd.domain = lower(trim(requested_domain));
$$;

revoke execute on function public.validate_company_domain(text) from public;
grant execute on function public.validate_company_domain(text) to anon, authenticated;

create or replace function private.is_introduction_participant(introduction uuid, member uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.introductions i
    where i.id = introduction and member in (i.member_a, i.member_b)
  );
$$;

create or replace function private.is_conversation_participant(conversation uuid, member uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.conversations c
    where c.id = conversation and member in (c.member_a, c.member_b)
  );
$$;

create or replace function private.users_blocked(left_user uuid, right_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.blocks b
    where (b.blocker_id = left_user and b.blocked_id = right_user)
       or (b.blocker_id = right_user and b.blocked_id = left_user)
  );
$$;

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
  order by i.created_at desc
  limit 1;

  return result;
end;
$$;

revoke execute on function public.get_current_introduction() from public, anon;
grant execute on function public.get_current_introduction() to authenticated;

create or replace function public.respond_to_introduction(p_introduction_id uuid, p_decision text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  intro public.introductions%rowtype;
  response_count integer;
  interested_count integer;
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

  if p_decision = 'pass' then
    update public.introductions set status = 'closed' where id = intro.id;
    return jsonb_build_object('state', 'not_mutual');
  end if;

  select count(*), count(*) filter (where decision = 'interested')
  into response_count, interested_count
  from public.introduction_responses where introduction_id = intro.id;

  if response_count = 2 and interested_count = 2 then
    update public.introductions set status = 'mutual' where id = intro.id;
    insert into public.conversations (introduction_id, member_a, member_b)
    values (intro.id, intro.member_a, intro.member_b)
    returning id into conversation_id;
    insert into public.notification_events (user_id, kind, payload)
    values
      (intro.member_a, 'mutual_interest', jsonb_build_object('introduction_id', intro.id, 'conversation_id', conversation_id)),
      (intro.member_b, 'mutual_interest', jsonb_build_object('introduction_id', intro.id, 'conversation_id', conversation_id));
    return jsonb_build_object('state', 'mutual', 'conversation_id', conversation_id);
  elsif response_count = 2 then
    update public.introductions set status = 'closed' where id = intro.id;
    return jsonb_build_object('state', 'not_mutual');
  end if;

  return jsonb_build_object('state', 'waiting');
end;
$$;

revoke execute on function public.respond_to_introduction(uuid, text) from public, anon;
grant execute on function public.respond_to_introduction(uuid, text) to authenticated;

create or replace function public.end_conversation(p_conversation_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not private.is_conversation_participant(p_conversation_id, auth.uid()) then
    raise exception 'Conversation not found';
  end if;
  update public.conversations set status = 'ended' where id = p_conversation_id and status = 'active';
end;
$$;

create or replace function public.block_member(p_member_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare caller uuid := auth.uid();
begin
  if caller is null or caller = p_member_id then raise exception 'Invalid block'; end if;
  if not exists (
    select 1 from public.introductions i where caller in (i.member_a, i.member_b) and p_member_id in (i.member_a, i.member_b)
  ) and not exists (
    select 1 from public.connections c where c.owner_user_id = caller and c.connected_user_id = p_member_id
  ) then raise exception 'Member not found'; end if;

  insert into public.blocks (blocker_id, blocked_id) values (caller, p_member_id) on conflict do nothing;
  update public.conversations set status = 'blocked'
  where caller in (member_a, member_b) and p_member_id in (member_a, member_b);
  delete from public.connections
  where (owner_user_id = caller and connected_user_id = p_member_id)
     or (owner_user_id = p_member_id and connected_user_id = caller);
end;
$$;

create or replace function public.submit_member_report(
  p_subject_id uuid,
  p_conversation_id uuid,
  p_category text,
  p_note text default ''
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare caller uuid := auth.uid(); report_id uuid;
begin
  if caller is null or caller = p_subject_id then raise exception 'Invalid report'; end if;
  if p_category not in ('harassment', 'spam', 'fraud', 'inappropriate', 'romantic', 'discrimination', 'threatening', 'other') then
    raise exception 'Invalid report category';
  end if;
  if p_conversation_id is not null and not private.is_conversation_participant(p_conversation_id, caller) then
    raise exception 'Conversation not found';
  end if;
  if not exists (
    select 1 from public.introductions i
    where caller in (i.member_a, i.member_b)
      and p_subject_id in (i.member_a, i.member_b)
  ) and not exists (
    select 1 from public.connections c
    where c.owner_user_id = caller and c.connected_user_id = p_subject_id
  ) then
    raise exception 'Member not found';
  end if;
  insert into public.reports (reporter_id, subject_id, conversation_id, category, note)
  values (caller, p_subject_id, p_conversation_id, p_category, left(coalesce(p_note, ''), 2000))
  returning id into report_id;
  return report_id;
end;
$$;

revoke execute on function public.end_conversation(uuid) from public, anon;
revoke execute on function public.block_member(uuid) from public, anon;
revoke execute on function public.submit_member_report(uuid, uuid, text, text) from public, anon;
grant execute on function public.end_conversation(uuid) to authenticated;
grant execute on function public.block_member(uuid) to authenticated;
grant execute on function public.submit_member_report(uuid, uuid, text, text) to authenticated;

create or replace function private.array_overlap_count(left_values text[], right_values text[])
returns integer
language sql
immutable
security invoker
set search_path = ''
as $$
  select count(*)::integer
  from unnest(coalesce(left_values, '{}')) value
  where value = any(coalesce(right_values, '{}'));
$$;

create or replace function public.generate_next_introduction()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare selected_pair record; created_id uuid;
begin
  if auth.role() <> 'service_role' then raise exception 'Service role required'; end if;

  select
    p1.id as member_a,
    p2.id as member_b,
    p1.name as name_a,
    p2.name as name_b,
    p1.current_focus as focus_a,
    p2.current_focus as focus_b,
    p1.professional_ambition as ambition_a,
    p2.professional_ambition as ambition_b,
    private.array_overlap_count(p1.contribution_areas, p2.growth_areas)
      + private.array_overlap_count(p2.contribution_areas, p1.growth_areas) as reciprocal_score
  into selected_pair
  from public.profiles p1
  join public.profiles p2 on p1.id < p2.id
  join public.networking_preferences n1 on n1.user_id = p1.id
  join public.networking_preferences n2 on n2.user_id = p2.id
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
  order by reciprocal_score desc, random()
  limit 1;

  if selected_pair.member_a is null or selected_pair.reciprocal_score < 1 then return null; end if;

  insert into public.introductions (member_a, member_b, reason_for_a, reason_for_b, meeting_context)
  values (
    selected_pair.member_a,
    selected_pair.member_b,
    selected_pair.name_b || ' is working toward ' || selected_pair.ambition_b || ' Their experience connects with your current focus: ' || selected_pair.focus_a,
    selected_pair.name_a || ' is working toward ' || selected_pair.ambition_a || ' Their experience connects with your current focus: ' || selected_pair.focus_b,
    'You share compatible meeting preferences. Confirm a public place together after mutual interest.'
  ) returning id into created_id;

  insert into public.notification_events (user_id, kind, payload)
  values
    (selected_pair.member_a, 'introduction_ready', jsonb_build_object('introduction_id', created_id)),
    (selected_pair.member_b, 'introduction_ready', jsonb_build_object('introduction_id', created_id));
  return created_id;
end;
$$;

revoke execute on function public.generate_next_introduction() from public, anon, authenticated;
grant execute on function public.generate_next_introduction() to service_role;

-- RLS and least-privilege Data API grants.
alter table public.company_domains enable row level security;
alter table public.profiles enable row level security;
alter table public.professional_experiences enable row level security;
alter table public.networking_preferences enable row level security;
alter table public.meeting_preferences enable row level security;
alter table public.availabilities enable row level security;
alter table public.introductions enable row level security;
alter table public.introduction_responses enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.meetups enable row level security;
alter table public.meetup_feedback enable row level security;
alter table public.connections enable row level security;
alter table public.blocks enable row level security;
alter table public.reports enable row level security;
alter table public.resume_documents enable row level security;
alter table public.device_tokens enable row level security;
alter table public.notification_events enable row level security;

revoke all on all tables in schema public from anon, authenticated;
grant select on public.profiles to authenticated;
grant update (
  name, role, city, topics, bio, role_scope, current_focus, years_experience,
  growth_areas, professional_ambition, growth_interest, contribution_areas,
  help_formats, contribution, contribution_boundaries, education, onboarding_complete
) on public.profiles to authenticated;
grant select, insert, update, delete on public.professional_experiences to authenticated;
grant select, insert, update on public.networking_preferences, public.meeting_preferences to authenticated;
grant select, insert, update, delete on public.availabilities to authenticated;
grant select on public.introductions, public.introduction_responses, public.conversations to authenticated;
grant select, insert on public.messages to authenticated;
grant select on public.meetups, public.meetup_feedback to authenticated;
grant select, delete on public.connections to authenticated;
grant select, delete on public.blocks to authenticated;
grant select on public.reports to authenticated;
grant select, insert, delete on public.resume_documents to authenticated;
grant select, insert, update, delete on public.device_tokens to authenticated;
grant select on public.notification_events to authenticated;
grant update (read_at) on public.notification_events to authenticated;
grant all on all tables in schema public to service_role;

create policy profiles_own_select on public.profiles for select to authenticated using ((select auth.uid()) = id);
create policy profiles_own_update on public.profiles for update to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

create policy experiences_own_all on public.professional_experiences for all to authenticated
using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy networking_preferences_own_all on public.networking_preferences for all to authenticated
using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy meeting_preferences_own_all on public.meeting_preferences for all to authenticated
using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy availabilities_own_all on public.availabilities for all to authenticated
using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

create policy introductions_participant_select on public.introductions for select to authenticated
using ((select auth.uid()) in (member_a, member_b));
create policy responses_own_select on public.introduction_responses for select to authenticated
using ((select auth.uid()) = user_id);
create policy conversations_participant_select on public.conversations for select to authenticated
using ((select auth.uid()) in (member_a, member_b));
create policy messages_participant_select on public.messages for select to authenticated
using (private.is_conversation_participant(conversation_id, (select auth.uid())));
create policy messages_participant_insert on public.messages for insert to authenticated
with check (
  sender_id = (select auth.uid())
  and private.is_conversation_participant(conversation_id, (select auth.uid()))
  and exists (select 1 from public.conversations c where c.id = conversation_id and c.status = 'active')
);
create policy meetups_participant_select on public.meetups for select to authenticated
using (private.is_conversation_participant(conversation_id, (select auth.uid())));
create policy meetup_feedback_own_select on public.meetup_feedback for select to authenticated
using ((select auth.uid()) = user_id);
create policy connections_own_select on public.connections for select to authenticated using ((select auth.uid()) = owner_user_id);
create policy connections_own_delete on public.connections for delete to authenticated using ((select auth.uid()) = owner_user_id);
create policy blocks_own_select on public.blocks for select to authenticated using ((select auth.uid()) = blocker_id);
create policy blocks_own_delete on public.blocks for delete to authenticated using ((select auth.uid()) = blocker_id);
create policy reports_own_select on public.reports for select to authenticated using ((select auth.uid()) = reporter_id);
create policy resumes_own_select on public.resume_documents for select to authenticated
using ((select auth.uid()) = user_id);
create policy resumes_own_insert on public.resume_documents for insert to authenticated
with check (
  (select auth.uid()) = user_id
  and status = 'uploaded'
  and extracted_suggestions = '[]'::jsonb
);
create policy resumes_own_delete on public.resume_documents for delete to authenticated
using ((select auth.uid()) = user_id);
create policy device_tokens_own_all on public.device_tokens for all to authenticated
using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy notifications_own_select on public.notification_events for select to authenticated using ((select auth.uid()) = user_id);
create policy notifications_own_update on public.notification_events for update to authenticated
using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

-- Private résumé bucket. The first path component must be the authenticated user ID.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('resumes', 'resumes', false, 10485760, array['application/pdf'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create policy resumes_storage_select on storage.objects for select to authenticated
using (bucket_id = 'resumes' and owner_id = (select auth.uid()::text));
create policy resumes_storage_insert on storage.objects for insert to authenticated
with check (
  bucket_id = 'resumes'
  and owner_id = (select auth.uid()::text)
  and (storage.foldername(name))[1] = (select auth.uid()::text)
);
create policy resumes_storage_update on storage.objects for update to authenticated
using (bucket_id = 'resumes' and owner_id = (select auth.uid()::text))
with check (bucket_id = 'resumes' and owner_id = (select auth.uid()::text));
create policy resumes_storage_delete on storage.objects for delete to authenticated
using (bucket_id = 'resumes' and owner_id = (select auth.uid()::text));

-- Realtime is limited to participant-protected tables. Clients still receive only rows allowed by RLS.
alter publication supabase_realtime add table public.conversations;
alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.meetups;
alter publication supabase_realtime add table public.notification_events;
