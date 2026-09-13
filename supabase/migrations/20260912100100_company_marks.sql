-- Company marks (feature 002).
-- Each approved company may carry one served mark: its own publicly published icon, fetched
-- once server-side by the company-marks Edge Function, stored versioned in the public
-- company-marks bucket, and referenced from the relationship-scoped read models. Operations
-- records live in the private schema. Retention reuses the daily maintenance job; the file
-- purge is delegated to the Edge Function because deleting storage.objects rows in SQL would
-- leave the stored file behind.
-- Operator step (once per project): create the Vault secret company_marks_job_secret and set
-- the same value as the COMPANY_MARKS_JOB_SECRET function secret. Until then the purge stays idle.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('company-marks', 'company-marks', true, 1048576, array['image/png', 'image/jpeg'])
on conflict (id) do update set
  public = true,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create table if not exists private.company_mark_versions (
  company_key text not null references public.companies(key) on delete cascade,
  version integer not null check (version >= 1),
  path text not null check (path ~ '^[a-z0-9][a-z0-9-]{0,62}/[0-9]+\.(png|jpg)$'),
  content_type text not null check (content_type in ('image/png', 'image/jpeg')),
  byte_size integer not null check (byte_size between 1 and 1048576),
  width integer not null check (width >= 128),
  height integer not null check (height >= 128),
  source_url text check (source_url is null or char_length(source_url) <= 500),
  fetched_at timestamptz not null default now(),
  state text not null default 'served' check (state in ('served', 'superseded', 'withheld', 'withdrawn')),
  retired_at timestamptz,
  primary key (company_key, version)
);

create index if not exists company_mark_versions_retired_idx
  on private.company_mark_versions(retired_at) where state <> 'served';
revoke all on table private.company_mark_versions from public, anon, authenticated;

create table if not exists private.company_mark_runs (
  id uuid primary key default gen_random_uuid(),
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  requested_by text not null default 'unspecified' check (char_length(requested_by) between 1 and 120),
  scope jsonb not null default '{}'::jsonb,
  status text not null default 'running' check (status in ('running', 'completed', 'failed', 'skipped')),
  invocations integer not null default 0 check (invocations >= 0),
  summary jsonb,
  error_message text check (error_message is null or char_length(error_message) <= 1000)
);

create unique index if not exists company_mark_runs_single_running_idx
  on private.company_mark_runs((status)) where status = 'running';
create index if not exists company_mark_runs_started_idx on private.company_mark_runs(started_at desc);
revoke all on table private.company_mark_runs from public, anon, authenticated;

create table if not exists private.company_mark_run_items (
  run_id uuid not null references private.company_mark_runs(id) on delete cascade,
  company_key text not null references public.companies(key) on delete cascade,
  outcome text not null check (outcome in ('fetched', 'no_icon_published', 'fetch_failed', 'skipped_existing')),
  detail text check (detail is null or char_length(detail) <= 300),
  recorded_at timestamptz not null default now(),
  primary key (run_id, company_key)
);

revoke all on table private.company_mark_run_items from public, anon, authenticated;

-- A company that leaves the approved registry stops serving its mark at once; the file is
-- purged on the retention schedule.
create or replace function private.withdraw_company_mark_on_retirement()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status <> 'approved' and old.status = 'approved' then
    update private.company_mark_versions
      set state = 'withdrawn', retired_at = now()
      where company_key = new.key and state = 'served';
    new.mark_status := 'not_yet_fetched';
    new.mark_path := null;
    new.mark_content_type := null;
    new.mark_refresh_requested := false;
  end if;
  return new;
end;
$$;

revoke all on function private.withdraw_company_mark_on_retirement() from public, anon, authenticated, service_role;

drop trigger if exists companies_withdraw_mark on public.companies;
create trigger companies_withdraw_mark before update of status on public.companies
for each row execute function private.withdraw_company_mark_on_retirement();

-- The mark reference is keyed by company, never by an email domain, and exists only while
-- the company is approved and its mark is available.
create or replace function private.company_mark_reference(p_domain text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when c.mark_status = 'available' and c.mark_path is not null
    then jsonb_build_object('key', c.key, 'version', c.mark_version, 'path', c.mark_path)
  end
  from public.company_domains d
  join public.companies c on c.key = d.company_key
  where d.domain = p_domain
    and c.status = 'approved';
$$;

revoke all on function private.company_mark_reference(text) from public, anon, authenticated, service_role;

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
    'company_mark', private.company_mark_reference(profile.company_domain),
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
  order by i.created_at desc
  limit 1;

  return result;
end;
$$;

revoke execute on function public.get_current_introduction() from public, anon;
grant execute on function public.get_current_introduction() to authenticated;

create or replace function public.get_own_company_mark()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare caller uuid := auth.uid(); reference jsonb;
begin
  if caller is null then raise exception 'Authentication required'; end if;
  select private.company_mark_reference(p.company_domain) into reference
  from public.profiles p
  where p.id = caller;
  return jsonb_build_object('company_mark', reference);
end;
$$;

revoke execute on function public.get_own_company_mark() from public, anon;
grant execute on function public.get_own_company_mark() to authenticated;

-- Operations: run bookkeeping. One run at a time; a second start records skipped.
create or replace function public.start_company_mark_run(p_scope jsonb, p_requested_by text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  running_run private.company_mark_runs%rowtype;
  run_id uuid;
  requester text;
  scope jsonb := coalesce(p_scope, '{}'::jsonb);
  action text := coalesce(p_scope->>'action', 'populate');
  keys text[];
begin
  perform pg_advisory_xact_lock(hashtext('company_mark_runs'));

  requester := coalesce(nullif(left(trim(coalesce(p_requested_by, '')), 120), ''), 'unspecified');
  if action not in ('populate', 'refresh') then raise exception 'Invalid action'; end if;
  if scope ? 'companies' then
    if jsonb_typeof(scope->'companies') <> 'array' or jsonb_array_length(scope->'companies') > 300 then
      raise exception 'Invalid company list';
    end if;
    select array_agg(value) into keys from jsonb_array_elements_text(scope->'companies') as items(value);
    if exists (select 1 from unnest(keys) k where k !~ '^[a-z0-9][a-z0-9-]{0,62}$') then
      raise exception 'Invalid company key';
    end if;
  end if;

  update private.company_mark_runs
    set status = 'failed', finished_at = now(), error_message = 'abandoned'
    where status = 'running' and started_at < now() - interval '30 minutes';

  select * into running_run from private.company_mark_runs where status = 'running' limit 1;
  if found then
    insert into private.company_mark_runs (requested_by, scope, status, finished_at, summary)
    values (
      requester,
      jsonb_build_object('action', action),
      'skipped',
      now(),
      jsonb_build_object('reason', 'run_in_progress', 'running_run_id', running_run.id)
    )
    returning id into run_id;
    return jsonb_build_object('status', 'skipped', 'reason', 'run_in_progress', 'run_id', run_id);
  end if;

  if action = 'refresh' then
    update public.companies
      set mark_refresh_requested = true
      where status = 'approved' and (keys is null or key = any(keys));
  end if;

  insert into private.company_mark_runs (requested_by, scope)
  values (
    requester,
    jsonb_build_object('action', action)
      || case when keys is null then '{}'::jsonb else jsonb_build_object('companies', to_jsonb(keys)) end
  )
  returning id into run_id;

  return jsonb_build_object('status', 'running', 'run_id', run_id);
end;
$$;

create or replace function public.claim_company_mark_targets(p_run_id uuid, p_limit integer default 25)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare run private.company_mark_runs%rowtype; keys text[]; result jsonb;
begin
  if p_limit not between 1 and 50 then raise exception 'Invalid batch size'; end if;
  select * into run from private.company_mark_runs where id = p_run_id for update;
  if not found or run.status <> 'running' then raise exception 'Run is not running'; end if;
  if run.scope ? 'companies' then
    select array_agg(value) into keys from jsonb_array_elements_text(run.scope->'companies') as items(value);
  end if;

  update private.company_mark_runs set invocations = invocations + 1 where id = p_run_id;

  with picked as (
    select c.key
    from public.companies c
    where c.status = 'approved'
      and (c.mark_status in ('not_yet_fetched', 'fetch_failed') or c.mark_refresh_requested)
      and (c.mark_claimed_at is null or c.mark_claimed_at < now() - interval '15 minutes')
      and (keys is null or c.key = any(keys))
      and not exists (
        select 1 from private.company_mark_run_items i
        where i.run_id = p_run_id and i.company_key = c.key
      )
    order by c.mark_refresh_requested desc, c.key
    limit p_limit
    for update skip locked
  ), claimed as (
    update public.companies c
      set mark_claimed_at = now()
      from picked
      where c.key = picked.key
      returning c.key, c.name, c.website_url, c.mark_version, c.mark_refresh_requested
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'key', cl.key,
    'name', cl.name,
    'website_url', cl.website_url,
    'mark_version', cl.mark_version,
    'refresh', cl.mark_refresh_requested,
    'domains', (
      select coalesce(jsonb_agg(d.domain order by d.domain), '[]'::jsonb)
      from public.company_domains d where d.company_key = cl.key
    )
  ) order by cl.key), '[]'::jsonb)
  into result
  from claimed cl;

  return result;
end;
$$;

create or replace function public.record_company_mark_outcome(
  p_run_id uuid,
  p_company_key text,
  p_outcome text,
  p_path text default null,
  p_content_type text default null,
  p_byte_size integer default null,
  p_width integer default null,
  p_height integer default null,
  p_source_url text default null,
  p_failure_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  company public.companies%rowtype;
  run_status text;
  next_version integer;
  extension text;
  expected_path text;
  reason text := left(coalesce(p_failure_reason, p_outcome), 300);
begin
  select status into run_status from private.company_mark_runs where id = p_run_id;
  if run_status is null or run_status <> 'running' then raise exception 'Run is not running'; end if;
  if p_outcome not in ('fetched', 'no_icon_published', 'fetch_failed', 'skipped_existing') then
    raise exception 'Invalid outcome';
  end if;

  select * into company from public.companies where key = p_company_key for update;
  if not found then raise exception 'Unknown company'; end if;

  if p_outcome = 'fetched' then
    if p_content_type not in ('image/png', 'image/jpeg') then raise exception 'Unsupported content type'; end if;
    if coalesce(p_byte_size, 0) not between 1 and 1048576 then raise exception 'Invalid byte size'; end if;
    if coalesce(p_width, 0) < 128 or coalesce(p_height, 0) < 128 then raise exception 'Image too small'; end if;
    next_version := company.mark_version + 1;
    extension := case when p_content_type = 'image/png' then 'png' else 'jpg' end;
    expected_path := p_company_key || '/' || next_version || '.' || extension;
    if p_path is distinct from expected_path then raise exception 'Unexpected object path'; end if;

    update private.company_mark_versions
      set state = 'superseded', retired_at = now()
      where company_key = p_company_key and state = 'served';
    insert into private.company_mark_versions (company_key, version, path, content_type, byte_size, width, height, source_url)
    values (p_company_key, next_version, p_path, p_content_type, p_byte_size, p_width, p_height, left(p_source_url, 500));
    update public.companies
      set mark_status = 'available',
          mark_version = next_version,
          mark_path = p_path,
          mark_content_type = p_content_type,
          mark_fetched_at = now(),
          mark_source_url = left(p_source_url, 500),
          mark_failure_reason = null,
          mark_refresh_requested = false,
          mark_claimed_at = null
      where key = p_company_key;
  elsif p_outcome in ('no_icon_published', 'fetch_failed') then
    if company.mark_status in ('available', 'withheld') then
      -- A failed refresh keeps the current version in place.
      update public.companies
        set mark_failure_reason = reason, mark_refresh_requested = false, mark_claimed_at = null
        where key = p_company_key;
    else
      update public.companies
        set mark_status = p_outcome, mark_failure_reason = reason, mark_refresh_requested = false, mark_claimed_at = null
        where key = p_company_key;
    end if;
  else
    update public.companies
      set mark_refresh_requested = false, mark_claimed_at = null
      where key = p_company_key;
  end if;

  insert into private.company_mark_run_items (run_id, company_key, outcome, detail)
  values (p_run_id, p_company_key, p_outcome, case when p_outcome = 'fetched' then null else reason end)
  on conflict (run_id, company_key) do update
    set outcome = excluded.outcome, detail = excluded.detail, recorded_at = now();

  select * into company from public.companies where key = p_company_key;
  return jsonb_build_object('key', company.key, 'mark_status', company.mark_status, 'mark_version', company.mark_version);
end;
$$;

create or replace function public.finish_company_mark_run(
  p_run_id uuid,
  p_status text,
  p_summary jsonb default null,
  p_error text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare counts jsonb;
begin
  if p_status not in ('completed', 'failed') then raise exception 'Invalid run status'; end if;
  select jsonb_build_object(
    'fetched', count(*) filter (where i.outcome = 'fetched'),
    'no_icon_published', count(*) filter (where i.outcome = 'no_icon_published'),
    'fetch_failed', count(*) filter (where i.outcome = 'fetch_failed'),
    'skipped_existing', count(*) filter (where i.outcome = 'skipped_existing')
  ) into counts
  from private.company_mark_run_items i
  where i.run_id = p_run_id;

  update private.company_mark_runs
    set status = p_status,
        finished_at = now(),
        summary = coalesce(p_summary, '{}'::jsonb) || counts,
        error_message = left(p_error, 1000)
    where id = p_run_id and status = 'running';
end;
$$;

create or replace function private.company_mark_fields(p_company_key text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'key', c.key,
    'name', c.name,
    'status', c.status,
    'coverage_clause', c.coverage_clause,
    'mark_status', c.mark_status,
    'mark_version', c.mark_version,
    'mark_path', c.mark_path,
    'mark_fetched_at', c.mark_fetched_at,
    'mark_source_url', c.mark_source_url,
    'mark_failure_reason', c.mark_failure_reason,
    'mark_refresh_requested', c.mark_refresh_requested
  )
  from public.companies c
  where c.key = p_company_key;
$$;

revoke all on function private.company_mark_fields(text) from public, anon, authenticated, service_role;

create or replace function public.set_company_mark_withheld(p_company_key text, p_withheld boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare company public.companies%rowtype; restored private.company_mark_versions%rowtype;
begin
  select * into company from public.companies where key = p_company_key for update;
  if not found then raise exception 'Unknown company'; end if;

  if p_withheld then
    update private.company_mark_versions
      set state = 'withheld', retired_at = now()
      where company_key = p_company_key and state = 'served';
    update public.companies
      set mark_status = 'withheld', mark_path = null, mark_content_type = null, mark_refresh_requested = false
      where key = p_company_key;
  else
    select * into restored from private.company_mark_versions
      where company_key = p_company_key and version = company.mark_version and state = 'withheld';
    if found then
      update private.company_mark_versions
        set state = 'served', retired_at = null
        where company_key = p_company_key and version = restored.version;
      update public.companies
        set mark_status = 'available', mark_path = restored.path, mark_content_type = restored.content_type
        where key = p_company_key;
    elsif company.mark_status = 'withheld' then
      update public.companies set mark_status = 'not_yet_fetched' where key = p_company_key;
    end if;
  end if;

  return private.company_mark_fields(p_company_key);
end;
$$;

create or replace function public.request_company_mark_refresh(p_company_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.companies set mark_refresh_requested = true where key = p_company_key;
  if not found then raise exception 'Unknown company'; end if;
  return private.company_mark_fields(p_company_key);
end;
$$;

create or replace function public.get_company_mark_overview()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(private.company_mark_fields(c.key) order by c.key), '[]'::jsonb)
  from public.companies c;
$$;

create or replace function public.list_company_mark_purges(p_limit integer default 50)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('key', due.company_key, 'version', due.version, 'path', due.path) order by due.retired_at), '[]'::jsonb)
  from (
    select v.company_key, v.version, v.path, v.retired_at
    from private.company_mark_versions v
    where v.state <> 'served'
      and v.retired_at is not null
      and v.retired_at < now() - interval '30 days'
    order by v.retired_at
    limit greatest(1, least(coalesce(p_limit, 50), 200))
  ) due;
$$;

create or replace function public.confirm_company_mark_purge(p_company_key text, p_version integer)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare removed integer;
begin
  delete from private.company_mark_versions
    where company_key = p_company_key and version = p_version and state <> 'served';
  get diagnostics removed = row_count;
  return removed > 0;
end;
$$;

revoke all on function public.start_company_mark_run(jsonb, text) from public, anon, authenticated;
revoke all on function public.claim_company_mark_targets(uuid, integer) from public, anon, authenticated;
revoke all on function public.record_company_mark_outcome(uuid, text, text, text, text, integer, integer, integer, text, text) from public, anon, authenticated;
revoke all on function public.finish_company_mark_run(uuid, text, jsonb, text) from public, anon, authenticated;
revoke all on function public.set_company_mark_withheld(text, boolean) from public, anon, authenticated;
revoke all on function public.request_company_mark_refresh(text) from public, anon, authenticated;
revoke all on function public.get_company_mark_overview() from public, anon, authenticated;
revoke all on function public.list_company_mark_purges(integer) from public, anon, authenticated;
revoke all on function public.confirm_company_mark_purge(text, integer) from public, anon, authenticated;
grant execute on function public.start_company_mark_run(jsonb, text) to service_role;
grant execute on function public.claim_company_mark_targets(uuid, integer) to service_role;
grant execute on function public.record_company_mark_outcome(uuid, text, text, text, text, integer, integer, integer, text, text) to service_role;
grant execute on function public.finish_company_mark_run(uuid, text, jsonb, text) to service_role;
grant execute on function public.set_company_mark_withheld(text, boolean) to service_role;
grant execute on function public.request_company_mark_refresh(text) to service_role;
grant execute on function public.get_company_mark_overview() to service_role;
grant execute on function public.list_company_mark_purges(integer) to service_role;
grant execute on function public.confirm_company_mark_purge(text, integer) to service_role;

-- Retention: run records after 180 days in SQL; retired files through the function, which is
-- the only component that can delete the stored object. Silent when nothing is due or the
-- Vault secrets do not exist yet.
create or replace function private.dispatch_company_mark_purge()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare project_url text; job_secret text; request_id bigint;
begin
  if not exists (
    select 1 from private.company_mark_versions v
    where v.state <> 'served' and v.retired_at is not null and v.retired_at < now() - interval '30 days'
  ) then
    return null;
  end if;

  select s.decrypted_secret into project_url from vault.decrypted_secrets s where s.name = 'project_url';
  select s.decrypted_secret into job_secret from vault.decrypted_secrets s where s.name = 'company_marks_job_secret';
  if coalesce(project_url, '') = '' or coalesce(job_secret, '') = '' then
    return null;
  end if;

  select net.http_post(
    url := rtrim(project_url, '/') || '/functions/v1/company-marks',
    body := jsonb_build_object('action', 'purge', 'source', 'pg_cron', 'requested_at', now()),
    headers := jsonb_build_object('content-type', 'application/json', 'x-job-secret', job_secret),
    timeout_milliseconds := 15000
  ) into request_id;

  return request_id;
end;
$$;

revoke all on function private.dispatch_company_mark_purge() from public, anon, authenticated, service_role;

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
  delete from private.company_mark_runs where started_at < now() - interval '180 days';
  begin
    perform private.dispatch_company_mark_purge();
  exception when others then
    null;
  end;
end;
$$;

revoke all on function private.run_retention_maintenance()
  from public, anon, authenticated, service_role;
