create or replace function public.unblock_member_by_name(p_member_name text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  delete from public.blocks b
  using public.profiles p
  where b.blocker_id = auth.uid()
    and b.blocked_id = p.id
    and p.name = p_member_name;
end;
$$;

create or replace function public.submit_latest_meetup_feedback(
  p_conversation_id uuid,
  p_outcome text,
  p_stay_connected boolean,
  p_private_note text default ''
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare latest_meetup uuid;
begin
  if auth.uid() is null or not private.is_conversation_participant(p_conversation_id, auth.uid()) then
    raise exception 'Conversation not found';
  end if;
  select m.id into latest_meetup
  from public.meetups m
  where m.conversation_id = p_conversation_id
  order by m.created_at desc
  limit 1;
  if latest_meetup is null then raise exception 'Meetup not found'; end if;
  perform public.submit_meetup_feedback(latest_meetup, p_outcome, p_stay_connected, p_private_note);
end;
$$;

revoke execute on function public.unblock_member_by_name(text) from public, anon;
revoke execute on function public.submit_latest_meetup_feedback(uuid, text, boolean, text) from public, anon;
grant execute on function public.unblock_member_by_name(text) to authenticated;
grant execute on function public.submit_latest_meetup_feedback(uuid, text, boolean, text) to authenticated;
