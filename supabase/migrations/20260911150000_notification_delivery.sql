-- Remote notification delivery.
-- Postgres owns the delivery queue: it claims due notification events for
-- members with a registered device, records every attempt, and asks a trusted
-- Edge Function to perform the APNs transport. The APNs signing key never
-- reaches the database or the iOS app. The dispatcher reads the project URL and
-- job secret from Supabase Vault so no secret is committed to a migration.

create extension if not exists pg_net with schema extensions;
create extension if not exists supabase_vault;

create or replace function private.notification_counterpart_first_name(
  p_user_id uuid,
  p_payload jsonb
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare other_member uuid; full_name text;
begin
  if p_payload ? 'conversation_id' then
    select case when c.member_a = p_user_id then c.member_b else c.member_a end
    into other_member
    from public.conversations c
    where c.id = (p_payload->>'conversation_id')::uuid;
  elsif p_payload ? 'introduction_id' then
    select case when i.member_a = p_user_id then i.member_b else i.member_a end
    into other_member
    from public.introductions i
    where i.id = (p_payload->>'introduction_id')::uuid;
  end if;

  if other_member is null then return null; end if;
  select p.name into full_name from public.profiles p where p.id = other_member;
  return nullif(split_part(trim(coalesce(full_name, '')), ' ', 1), '');
exception when others then
  return null;
end;
$$;

-- Claims due events for members who have at least one registered device. Each
-- claim counts as an attempt so a crashed delivery run backs off instead of
-- retrying the same event every minute. Events without a device are left for
-- the in-app stream and retention.
create or replace function public.claim_notification_deliveries(p_limit integer default 50)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare result jsonb;
begin
  if p_limit not between 1 and 200 then raise exception 'Invalid batch size'; end if;

  with due as (
    select e.id
    from public.notification_events e
    where e.delivered_at is null
      and e.deliver_after <= now()
      and e.attempt_count < 8
      and (
        e.last_attempt_at is null
        or e.last_attempt_at < now() - (interval '1 minute' * power(2, e.attempt_count))
      )
      and exists (select 1 from public.device_tokens d where d.user_id = e.user_id)
    order by e.deliver_after, e.created_at
    limit p_limit
    for update of e skip locked
  ), claimed as (
    update public.notification_events e
    set attempt_count = e.attempt_count + 1,
        last_attempt_at = now()
    from due
    where e.id = due.id
    returning e.id, e.user_id, e.kind, e.payload, e.created_at, e.deliver_after
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', c.id,
    'user_id', c.user_id,
    'kind', c.kind,
    'payload', c.payload,
    'created_at', c.created_at,
    'counterpart_first_name', private.notification_counterpart_first_name(c.user_id, c.payload),
    'devices', (
      select coalesce(jsonb_agg(
        jsonb_build_object('token', d.token, 'environment', d.environment)
        order by d.updated_at desc
      ), '[]'::jsonb)
      from public.device_tokens d
      where d.user_id = c.user_id
    )
  ) order by c.deliver_after, c.created_at), '[]'::jsonb)
  into result
  from claimed c;

  return result;
end;
$$;

create or replace function public.complete_notification_delivery(
  p_event_id uuid,
  p_delivered boolean,
  p_error text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_delivered then
    update public.notification_events
    set delivered_at = coalesce(delivered_at, now()),
        last_error = null
    where id = p_event_id;
  else
    update public.notification_events
    set last_error = left(coalesce(nullif(trim(p_error), ''), 'Delivery failed'), 1000)
    where id = p_event_id and delivered_at is null;
  end if;
end;
$$;

-- APNs reports tokens that no longer belong to an installed app.
create or replace function public.retire_device_token(p_token text)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.device_tokens where token = lower(trim(coalesce(p_token, '')));
$$;

revoke execute on function public.claim_notification_deliveries(integer) from public, anon, authenticated;
revoke execute on function public.complete_notification_delivery(uuid, boolean, text) from public, anon, authenticated;
revoke execute on function public.retire_device_token(text) from public, anon, authenticated;
grant execute on function public.claim_notification_deliveries(integer) to service_role;
grant execute on function public.complete_notification_delivery(uuid, boolean, text) to service_role;
grant execute on function public.retire_device_token(text) to service_role;
revoke all on function private.notification_counterpart_first_name(uuid, jsonb)
  from public, anon, authenticated, service_role;

-- Runs every minute. It stays silent unless something is due and both Vault
-- secrets exist, so an unconfigured project never produces failed requests.
--   select vault.create_secret('https://<project-ref>.supabase.co', 'project_url');
--   select vault.create_secret('<random 256-bit secret>', 'notification_job_secret');
-- The same secret must be set as NOTIFICATION_JOB_SECRET on the Edge Function.
create or replace function private.dispatch_notification_delivery()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare project_url text; job_secret text; request_id bigint;
begin
  if not exists (
    select 1
    from public.notification_events e
    where e.delivered_at is null
      and e.deliver_after <= now()
      and e.attempt_count < 8
      and (
        e.last_attempt_at is null
        or e.last_attempt_at < now() - (interval '1 minute' * power(2, e.attempt_count))
      )
      and exists (select 1 from public.device_tokens d where d.user_id = e.user_id)
  ) then
    return null;
  end if;

  select s.decrypted_secret into project_url from vault.decrypted_secrets s where s.name = 'project_url';
  select s.decrypted_secret into job_secret from vault.decrypted_secrets s where s.name = 'notification_job_secret';
  if coalesce(project_url, '') = '' or coalesce(job_secret, '') = '' then
    return null;
  end if;

  select net.http_post(
    url := rtrim(project_url, '/') || '/functions/v1/deliver-notifications',
    body := jsonb_build_object('source', 'pg_cron', 'requested_at', now()),
    headers := jsonb_build_object('content-type', 'application/json', 'x-job-secret', job_secret),
    timeout_milliseconds := 15000
  ) into request_id;

  return request_id;
end;
$$;

revoke all on function private.dispatch_notification_delivery()
  from public, anon, authenticated, service_role;

do $$
declare existing_job bigint;
begin
  for existing_job in
    select jobid from cron.job where jobname = 'network-to-notification-delivery'
  loop
    perform cron.unschedule(existing_job);
  end loop;
end;
$$;

select cron.schedule(
  'network-to-notification-delivery',
  '* * * * *',
  'select private.dispatch_notification_delivery()'
);
