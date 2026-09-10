-- Relationship-scoped read models keep private profile rows out of direct client access.

create or replace function private.public_profile(profile public.profiles)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'id', profile.id,
    'name', profile.name,
    'role', profile.role,
    'company_name', profile.company_name,
    'city', profile.city,
    'topics', profile.topics,
    'bio', profile.bio,
    'role_scope', profile.role_scope,
    'current_focus', profile.current_focus,
    'years_experience', profile.years_experience,
    'growth_areas', profile.growth_areas,
    'professional_ambition', profile.professional_ambition,
    'growth_interest', profile.growth_interest,
    'contribution_areas', profile.contribution_areas,
    'help_formats', profile.help_formats,
    'contribution', profile.contribution,
    'contribution_boundaries', profile.contribution_boundaries,
    'education', profile.education
  );
$$;

create or replace function public.get_connections()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', c.id,
      'connected_at', c.connected_at,
      'origin', c.origin,
      'person', private.public_profile(p),
      'meeting_history', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', m.id,
          'date', m.starts_at,
          'summary', concat_ws(' · ', m.place_name, m.area)
        ) order by m.starts_at desc)
        from public.conversations conversation
        join public.meetups m on m.conversation_id = conversation.id and m.status = 'completed'
        where conversation.introduction_id = c.introduction_id
      ), '[]'::jsonb)
    ) order by c.connected_at desc
  ), '[]'::jsonb)
  from public.connections c
  join public.profiles p on p.id = c.connected_user_id
  where c.owner_user_id = auth.uid()
    and not private.users_blocked(c.owner_user_id, c.connected_user_id);
$$;

create or replace function public.get_active_conversation()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare caller uuid := auth.uid(); result jsonb;
begin
  if caller is null then raise exception 'Authentication required'; end if;

  select jsonb_build_object(
    'id', c.id,
    'status', c.status,
    'introduction_reason', case when i.member_a = caller then i.reason_for_a else i.reason_for_b end,
    'person', private.public_profile(p),
    'messages', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id,
        'sender_id', m.sender_id,
        'body', m.body,
        'created_at', m.created_at
      ) order by m.created_at)
      from public.messages m where m.conversation_id = c.id
    ), '[]'::jsonb),
    'meetup', (
      select jsonb_build_object(
        'id', m.id,
        'starts_at', m.starts_at,
        'place_name', m.place_name,
        'area', m.area,
        'status', m.status
      ) from public.meetups m
      where m.conversation_id = c.id
      order by m.created_at desc limit 1
    )
  ) into result
  from public.conversations c
  join public.introductions i on i.id = c.introduction_id
  join public.profiles p on p.id = case when c.member_a = caller then c.member_b else c.member_a end
  where caller in (c.member_a, c.member_b)
    and c.status = 'active'
    and not private.users_blocked(c.member_a, c.member_b)
  order by c.updated_at desc
  limit 1;

  return result;
end;
$$;

create or replace function public.create_meetup(
  p_conversation_id uuid,
  p_starts_at timestamptz,
  p_place_name text,
  p_area text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare caller uuid := auth.uid(); meetup_id uuid;
begin
  if caller is null or not private.is_conversation_participant(p_conversation_id, caller) then
    raise exception 'Conversation not found';
  end if;
  if not exists (select 1 from public.conversations c where c.id = p_conversation_id and c.status = 'active') then
    raise exception 'Conversation is not active';
  end if;
  insert into public.meetups (conversation_id, proposed_by, starts_at, place_name, area)
  values (p_conversation_id, caller, p_starts_at, nullif(trim(p_place_name), ''), nullif(trim(p_area), ''))
  returning id into meetup_id;
  return meetup_id;
end;
$$;

create or replace function public.submit_meetup_feedback(
  p_meetup_id uuid,
  p_outcome text,
  p_stay_connected boolean,
  p_private_note text default ''
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare caller uuid := auth.uid(); other_member uuid; intro_id uuid;
begin
  if p_outcome not in ('good', 'okay', 'not_for_me', 'did_not_meet') then raise exception 'Invalid outcome'; end if;
  select
    case when c.member_a = caller then c.member_b else c.member_a end,
    c.introduction_id
  into other_member, intro_id
  from public.meetups m
  join public.conversations c on c.id = m.conversation_id
  where m.id = p_meetup_id and caller in (c.member_a, c.member_b);
  if other_member is null then raise exception 'Meetup not found'; end if;

  insert into public.meetup_feedback (meetup_id, user_id, outcome, stay_connected, private_note)
  values (p_meetup_id, caller, p_outcome, p_stay_connected, left(coalesce(p_private_note, ''), 2000))
  on conflict (meetup_id, user_id) do nothing;

  if not found then raise exception 'Feedback already submitted'; end if;

  update public.meetups
  set status = case
    when (select count(*) from public.meetup_feedback f where f.meetup_id = p_meetup_id) = 2 then 'completed'
    else 'feedback_due'
  end
  where id = p_meetup_id;

  if p_outcome <> 'did_not_meet' and p_stay_connected then
    insert into public.connections (owner_user_id, connected_user_id, introduction_id, origin)
    values (caller, other_member, intro_id, 'Connected after a mutual introduction and 1:1 meeting.')
    on conflict (owner_user_id, connected_user_id) do nothing;
  end if;
end;
$$;

revoke execute on function public.get_connections() from public, anon;
revoke execute on function public.get_active_conversation() from public, anon;
revoke execute on function public.create_meetup(uuid, timestamptz, text, text) from public, anon;
revoke execute on function public.submit_meetup_feedback(uuid, text, boolean, text) from public, anon;
grant execute on function public.get_connections() to authenticated;
grant execute on function public.get_active_conversation() to authenticated;
grant execute on function public.create_meetup(uuid, timestamptz, text, text) to authenticated;
grant execute on function public.submit_meetup_feedback(uuid, text, boolean, text) to authenticated;
