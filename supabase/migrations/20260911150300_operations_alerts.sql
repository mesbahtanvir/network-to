-- Operations alerting without a second backend: the database notices failed
-- matching runs, stalled schedules, repeated notification delivery failures,
-- App Store notifications that could not be applied, new member reports, and
-- incidents reported by Edge Functions, then posts each once to a webhook whose
-- URL lives in Supabase Vault:
--   select vault.create_secret('https://hooks.example.com/...', 'ops_alert_webhook_url');
-- The body is {"text": "..."} so Slack-style incoming webhooks work directly.

create table private.operational_incidents (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in (
    'account_deletion_failed',
    'notification_delivery_failed',
    'app_store_notification_failed',
    'edge_function_error'
  )),
  detail text not null check (char_length(detail) between 1 and 2000),
  reference text check (reference is null or char_length(reference) <= 200),
  created_at timestamptz not null default now()
);

create index operational_incidents_created_idx
  on private.operational_incidents (created_at desc);
revoke all on table private.operational_incidents from public, anon, authenticated;

create table private.operations_alerts (
  fingerprint text primary key check (char_length(fingerprint) <= 200),
  message text not null,
  request_id bigint,
  sent_at timestamptz not null default now()
);

create index operations_alerts_sent_idx on private.operations_alerts (sent_at);
revoke all on table private.operations_alerts from public, anon, authenticated;

-- Edge Functions report failures that would otherwise only exist in logs.
-- Details must stay technical: no email addresses or member-authored text.
create or replace function public.record_operational_incident(
  p_kind text,
  p_detail text,
  p_reference text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare incident_id uuid;
begin
  if p_kind not in (
    'account_deletion_failed',
    'notification_delivery_failed',
    'app_store_notification_failed',
    'edge_function_error'
  ) then
    raise exception 'Invalid incident kind';
  end if;

  insert into private.operational_incidents (kind, detail, reference)
  values (
    p_kind,
    left(coalesce(nullif(trim(p_detail), ''), 'No detail provided'), 2000),
    left(nullif(trim(coalesce(p_reference, '')), ''), 200)
  )
  returning id into incident_id;
  return incident_id;
end;
$$;

revoke execute on function public.record_operational_incident(text, text, text) from public, anon, authenticated;
grant execute on function public.record_operational_incident(text, text, text) to service_role;

create or replace function private.pending_operations_alerts()
returns table (fingerprint text, message text)
language sql
stable
security definer
set search_path = ''
as $$
  with candidates as (
    select
      'matching_run_failed:' || r.id::text as fingerprint,
      'Matching run failed at ' || to_char(r.started_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI')
        || ' UTC: ' || coalesce(r.error_message, 'no error recorded') as message
    from private.matching_runs r
    where r.status = 'failed' and r.started_at > now() - interval '7 days'

    union all

    select
      'matching_stalled:' || to_char(now() at time zone 'UTC', 'YYYY-MM-DD'),
      'No scheduled matching run has been recorded in the last 25 hours.'
    where exists (select 1 from public.profiles p where p.onboarding_complete and p.is_active)
      and not exists (
        select 1 from private.matching_runs r where r.started_at > now() - interval '25 hours'
      )

    union all

    select
      'notification_delivery_failures:' || to_char(now() at time zone 'UTC', 'YYYY-MM-DD HH24'),
      count(*)::text || ' notification(s) have failed delivery at least 3 times in the last 24 hours. Latest error: '
        || coalesce((
          select latest.last_error from public.notification_events latest
          where latest.delivered_at is null and latest.attempt_count >= 3 and latest.last_error is not null
          order by latest.last_attempt_at desc nulls last
          limit 1
        ), 'none recorded')
    from public.notification_events e
    where e.delivered_at is null and e.attempt_count >= 3 and e.created_at > now() - interval '24 hours'
    having count(*) > 0

    union all

    select
      'app_store_notification_failed:' || n.notification_uuid,
      'App Store Server Notification ' || n.notification_type || ' could not be applied: '
        || coalesce(n.detail, 'no detail recorded')
    from private.app_store_notifications n
    where n.outcome = 'failed' and n.received_at > now() - interval '7 days'

    union all

    select
      'member_report:' || rp.id::text,
      'A member report (' || rp.category || ') was submitted at '
        || to_char(rp.created_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI') || ' UTC and is awaiting review.'
    from public.reports rp
    where rp.created_at > now() - interval '7 days'

    union all

    select
      'incident:' || i.id::text,
      'Operational incident (' || i.kind || ') at '
        || to_char(i.created_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI') || ' UTC: ' || i.detail
    from private.operational_incidents i
    where i.created_at > now() - interval '7 days'
  )
  select c.fingerprint, c.message
  from candidates c
  where not exists (select 1 from private.operations_alerts a where a.fingerprint = c.fingerprint)
  order by c.fingerprint
  limit 20;
$$;

create or replace function private.run_operations_alerts()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  webhook_url text;
  pending record;
  fingerprints text[] := '{}';
  messages text[] := '{}';
  request_id bigint;
begin
  for pending in select * from private.pending_operations_alerts() loop
    fingerprints := fingerprints || pending.fingerprint;
    messages := messages || pending.message;
  end loop;
  if cardinality(messages) = 0 then return 0; end if;

  select s.decrypted_secret into webhook_url
  from vault.decrypted_secrets s
  where s.name = 'ops_alert_webhook_url';
  if coalesce(webhook_url, '') = '' then return 0; end if;

  select net.http_post(
    url := webhook_url,
    body := jsonb_build_object(
      'text',
      'network.to operations (' || cardinality(messages)::text || ')' || E'\n• '
        || array_to_string(messages, E'\n• ')
    ),
    headers := jsonb_build_object('content-type', 'application/json'),
    timeout_milliseconds := 10000
  ) into request_id;

  insert into private.operations_alerts (fingerprint, message, request_id)
  select item.fingerprint, item.message, request_id
  from unnest(fingerprints, messages) as item(fingerprint, message);

  return cardinality(messages);
end;
$$;

revoke all on function private.pending_operations_alerts()
  from public, anon, authenticated, service_role;
revoke all on function private.run_operations_alerts()
  from public, anon, authenticated, service_role;

-- Retention now also covers undelivered notification events (previously kept
-- forever when no device was registered) and the new operational tables.
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
  delete from public.notification_events where created_at < now() - interval '90 days';
  delete from private.matching_runs where started_at < now() - interval '180 days';
  delete from private.edge_rate_limits where window_start < now() - interval '2 days';
  delete from private.app_store_notifications where received_at < now() - interval '400 days';
  delete from private.operations_alerts where sent_at < now() - interval '30 days';
  delete from private.operational_incidents where created_at < now() - interval '180 days';
end;
$$;

revoke all on function private.run_retention_maintenance()
  from public, anon, authenticated, service_role;

do $$
declare existing_job bigint;
begin
  for existing_job in
    select jobid from cron.job where jobname = 'network-to-operations-alerts'
  loop
    perform cron.unschedule(existing_job);
  end loop;
end;
$$;

select cron.schedule(
  'network-to-operations-alerts',
  '*/15 * * * *',
  'select private.run_operations_alerts()'
);
