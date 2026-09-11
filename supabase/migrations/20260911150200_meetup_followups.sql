-- A planned 1:1 becomes "feedback due" a few hours after it was scheduled to
-- start, so both members are asked for private feedback even if neither opens
-- the conversation first. Only active conversations are followed up.

create or replace function private.run_meetup_followups()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare followed_up integer := 0;
begin
  with due as (
    update public.meetups m
    set status = 'feedback_due'
    where m.status in ('proposed', 'confirmed')
      and m.starts_at is not null
      and m.starts_at <= now() - interval '3 hours'
      and exists (
        select 1 from public.conversations c
        where c.id = m.conversation_id and c.status = 'active'
      )
    returning m.id, m.conversation_id
  ), notified as (
    insert into public.notification_events (user_id, kind, payload)
    select
      participant,
      'feedback_due',
      jsonb_build_object('conversation_id', due.conversation_id, 'meetup_id', due.id)
    from due
    join public.conversations c on c.id = due.conversation_id
    cross join lateral unnest(array[c.member_a, c.member_b]) as participant
    where not exists (
      select 1 from public.meetup_feedback f
      where f.meetup_id = due.id and f.user_id = participant
    )
    and not exists (
      select 1 from public.notification_events n
      where n.user_id = participant
        and n.kind = 'feedback_due'
        and n.payload->>'meetup_id' = due.id::text
    )
    returning 1
  )
  select count(*) into followed_up from due;

  return followed_up;
end;
$$;

revoke all on function private.run_meetup_followups()
  from public, anon, authenticated, service_role;

do $$
declare existing_job bigint;
begin
  for existing_job in
    select jobid from cron.job where jobname = 'network-to-hourly-meetup-followups'
  loop
    perform cron.unschedule(existing_job);
  end loop;
end;
$$;

select cron.schedule(
  'network-to-hourly-meetup-followups',
  '37 * * * *',
  'select private.run_meetup_followups()'
);
