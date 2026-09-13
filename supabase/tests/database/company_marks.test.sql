begin;
select plan(117);

-- Fixtures: two members (Shopify, Google), an offered introduction between them for the
-- introduction read model, and a separate mutual introduction with a conversation and a
-- connection for the other read models.
insert into auth.users (id, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('10000000-0000-0000-0000-0000000000a1', 'mark-one@shopify.com', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('20000000-0000-0000-0000-0000000000a2', 'mark-two@google.com', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('30000000-0000-0000-0000-0000000000a3', 'mark-three@google.com', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.introductions (id, member_a, member_b, reason_for_a, reason_for_b, meeting_context, status)
values ('40000000-0000-0000-0000-0000000000a4', '10000000-0000-0000-0000-0000000000a1', '20000000-0000-0000-0000-0000000000a2', 'r', 'r', 'Coffee', 'offered');

insert into public.introductions (id, member_a, member_b, reason_for_a, reason_for_b, meeting_context, status)
values ('40000000-0000-0000-0000-0000000000a5', '10000000-0000-0000-0000-0000000000a1', '30000000-0000-0000-0000-0000000000a3', 'r', 'r', 'Coffee', 'mutual');

insert into public.conversations (id, introduction_id, member_a, member_b)
values ('50000000-0000-0000-0000-0000000000a5', '40000000-0000-0000-0000-0000000000a5', '10000000-0000-0000-0000-0000000000a1', '30000000-0000-0000-0000-0000000000a3');

insert into public.connections (owner_user_id, connected_user_id, introduction_id, origin)
values ('10000000-0000-0000-0000-0000000000a1', '30000000-0000-0000-0000-0000000000a3', '40000000-0000-0000-0000-0000000000a5', 'Met for coffee');

-- Schema and access
select has_table('public', 'companies', 'the registry has one row per company');
select has_column('public', 'company_domains', 'company_key', 'every domain belongs to a company');
select has_table('private', 'company_mark_versions', 'mark versions are kept privately');
select has_table('private', 'company_mark_runs', 'operations runs are recorded privately');
select has_table('private', 'company_mark_run_items', 'per-company outcomes are recorded privately');
select isnt_empty($$select 1 from pg_class where oid = 'public.companies'::regclass and relrowsecurity$$, 'companies has RLS enabled');
select ok(not has_table_privilege('authenticated', 'public.companies', 'SELECT'), 'members cannot list the registry');
select ok(not has_table_privilege('anon', 'public.companies', 'SELECT'), 'anonymous clients cannot list the registry');
select ok(not has_table_privilege('authenticated', 'private.company_mark_versions', 'SELECT'), 'members cannot read mark versions');
select ok(not has_table_privilege('authenticated', 'private.company_mark_runs', 'SELECT'), 'members cannot read operations runs');
select is((select public from storage.buckets where id = 'company-marks'), true, 'the company-marks bucket serves objects publicly');
select is((select file_size_limit from storage.buckets where id = 'company-marks'), 1048576::bigint, 'marks are capped at 1 MiB');
select is((select allowed_mime_types from storage.buckets where id = 'company-marks'), array['image/png', 'image/jpeg'], 'marks are PNG or JPEG only');
select is(
  (select count(*) from pg_policies where schemaname = 'storage' and tablename = 'objects' and (coalesce(qual, '') like '%company-marks%' or coalesce(with_check, '') like '%company-marks%')),
  0::bigint,
  'no storage policy lets a client list or write company marks'
);

-- Registry
select cmp_ok((select count(*) from public.companies where status = 'approved'), '>=', 200::bigint, 'at least 200 approved companies');
select is(
  (select array_agg(key order by key) from public.companies where coverage_clause = 'launch' and key not in ('orbit-systems', 'northstar-ai', 'harbour-labs', 'new-venture-labs')),
  array['dropbox', 'figma', 'lyft', 'pinterest', 'snap', 'twilio'],
  'only the six carried-over launch companies use the closed launch clause'
);
select is(
  (select count(*) from public.company_domains d join public.companies c on c.key = d.company_key where d.status = 'approved' and c.status <> 'approved'),
  0::bigint,
  'every approved domain belongs to an approved company'
);
select is((select count(*) from public.company_domains where company_key is null), 0::bigint, 'no domain is without a company');
select is((public.validate_company_domain('servicenow.com')->>'decision'), 'eligible', 'a clause-a company domain is eligible');
select is((public.validate_company_domain('ca.ibm.com')->>'company_name'), 'IBM', 'a secondary domain resolves to its company name');
select is((public.validate_company_domain('databricks.com')->>'decision'), 'eligible', 'a clause-b company domain is eligible');
select is((public.validate_company_domain('tenstorrent.com')->>'decision'), 'eligible', 'a clause-c company domain is eligible');
select is((public.validate_company_domain('gmail.com')->>'decision'), 'ineligible', 'consumer domains stay ineligible');
select is(
  (public.hook_restrict_signup_by_company_domain('{"user":{"email":"someone@gmail.com"}}'::jsonb)->'error'->>'http_code'),
  '403',
  'the signup hook still refuses consumer domains'
);

insert into public.company_domains (domain, company_name, industry, status)
values ('example-tech.com', 'Example Tech', 'Software', 'approved');
select is((select company_key from public.company_domains where domain = 'example-tech.com'), 'example-tech', 'a domain inserted without a company gets one');
select is((select coverage_clause from public.companies where key = 'example-tech'), 'launch', 'a derived company is recorded under the closed launch clause');
update public.companies set name = 'Example Technologies' where key = 'example-tech';
select is((select company_name from public.company_domains where domain = 'example-tech.com'), 'Example Technologies', 'renaming a company renames its domains');

-- Function privileges
select has_function('public', 'get_own_company_mark', array[]::text[], 'members can read their own mark reference');
select ok(has_function_privilege('authenticated', 'public.get_own_company_mark()', 'EXECUTE'), 'authenticated members can call get_own_company_mark');
select ok(not has_function_privilege('anon', 'public.get_own_company_mark()', 'EXECUTE'), 'anonymous clients cannot call get_own_company_mark');

select ok(not has_function_privilege('anon', 'public.start_company_mark_run(jsonb,text)', 'EXECUTE'), 'anon cannot start a mark run');
select ok(not has_function_privilege('authenticated', 'public.start_company_mark_run(jsonb,text)', 'EXECUTE'), 'members cannot start a mark run');
select ok(has_function_privilege('service_role', 'public.start_company_mark_run(jsonb,text)', 'EXECUTE'), 'the operations function can start a mark run');
select ok(not has_function_privilege('anon', 'public.claim_company_mark_targets(uuid,integer)', 'EXECUTE'), 'anon cannot claim targets');
select ok(not has_function_privilege('authenticated', 'public.claim_company_mark_targets(uuid,integer)', 'EXECUTE'), 'members cannot claim targets');
select ok(has_function_privilege('service_role', 'public.claim_company_mark_targets(uuid,integer)', 'EXECUTE'), 'the operations function can claim targets');
select ok(not has_function_privilege('anon', 'public.record_company_mark_outcome(uuid,text,text,text,text,integer,integer,integer,text,text)', 'EXECUTE'), 'anon cannot record outcomes');
select ok(not has_function_privilege('authenticated', 'public.record_company_mark_outcome(uuid,text,text,text,text,integer,integer,integer,text,text)', 'EXECUTE'), 'members cannot record outcomes');
select ok(has_function_privilege('service_role', 'public.record_company_mark_outcome(uuid,text,text,text,text,integer,integer,integer,text,text)', 'EXECUTE'), 'the operations function can record outcomes');
select ok(not has_function_privilege('anon', 'public.finish_company_mark_run(uuid,text,jsonb,text)', 'EXECUTE'), 'anon cannot finish runs');
select ok(not has_function_privilege('authenticated', 'public.finish_company_mark_run(uuid,text,jsonb,text)', 'EXECUTE'), 'members cannot finish runs');
select ok(has_function_privilege('service_role', 'public.finish_company_mark_run(uuid,text,jsonb,text)', 'EXECUTE'), 'the operations function can finish runs');
select ok(not has_function_privilege('anon', 'public.set_company_mark_withheld(text,boolean)', 'EXECUTE'), 'anon cannot withhold marks');
select ok(not has_function_privilege('authenticated', 'public.set_company_mark_withheld(text,boolean)', 'EXECUTE'), 'members cannot withhold marks');
select ok(has_function_privilege('service_role', 'public.set_company_mark_withheld(text,boolean)', 'EXECUTE'), 'the product team can withhold marks');
select ok(not has_function_privilege('anon', 'public.request_company_mark_refresh(text)', 'EXECUTE'), 'anon cannot request refreshes');
select ok(not has_function_privilege('authenticated', 'public.request_company_mark_refresh(text)', 'EXECUTE'), 'members cannot request refreshes');
select ok(has_function_privilege('service_role', 'public.request_company_mark_refresh(text)', 'EXECUTE'), 'the product team can request refreshes');
select ok(not has_function_privilege('anon', 'public.get_company_mark_overview()', 'EXECUTE'), 'anon cannot read the mark overview');
select ok(not has_function_privilege('authenticated', 'public.get_company_mark_overview()', 'EXECUTE'), 'members cannot read the mark overview');
select ok(has_function_privilege('service_role', 'public.get_company_mark_overview()', 'EXECUTE'), 'the product team can read the mark overview');
select ok(not has_function_privilege('anon', 'public.list_company_mark_purges(integer)', 'EXECUTE'), 'anon cannot list purges');
select ok(not has_function_privilege('authenticated', 'public.list_company_mark_purges(integer)', 'EXECUTE'), 'members cannot list purges');
select ok(has_function_privilege('service_role', 'public.list_company_mark_purges(integer)', 'EXECUTE'), 'the operations function can list purges');
select ok(not has_function_privilege('anon', 'public.confirm_company_mark_purge(text,integer)', 'EXECUTE'), 'anon cannot confirm purges');
select ok(not has_function_privilege('authenticated', 'public.confirm_company_mark_purge(text,integer)', 'EXECUTE'), 'members cannot confirm purges');
select ok(has_function_privilege('service_role', 'public.confirm_company_mark_purge(text,integer)', 'EXECUTE'), 'the operations function can confirm purges');
select ok(not has_function_privilege('service_role', 'private.company_mark_reference(text)', 'EXECUTE'), 'the private reference helper is not callable by clients');
select ok(not has_function_privilege('service_role', 'private.dispatch_company_mark_purge()', 'EXECUTE'), 'the purge dispatcher is not callable by clients');

-- Read models before any mark exists
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-0000000000a1', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select ok((public.get_current_introduction()->'person') ? 'company_mark', 'the introduction person carries a company_mark field');
select ok((public.get_current_introduction()->'person'->>'company_mark') is null, 'the mark reference is null before a mark exists');
select ok((public.get_own_company_mark()->>'company_mark') is null, 'a member without a served mark gets a null reference');
select throws_ok($$select public.start_company_mark_run('{}'::jsonb, 'member')$$, '42501', null, 'members cannot start a run even by name');
reset role;

-- Operations run
create temp table t_run as select public.start_company_mark_run('{"action":"populate"}'::jsonb, '  pgtap  ') as result;
select is((select result->>'status' from t_run), 'running', 'a run starts when none is running');
select is((select requested_by from private.company_mark_runs where id = (select (result->>'run_id')::uuid from t_run)), 'pgtap', 'the requester is recorded');
select is((public.start_company_mark_run('{"action":"populate"}'::jsonb, 'again')->>'status'), 'skipped', 'a second start while a run is running is skipped');
select is((select count(*) from private.company_mark_runs where status = 'skipped'), 1::bigint, 'the skipped start is recorded');
select throws_ok($$select public.start_company_mark_run('{"action":"populate","companies":["Bad Key"]}'::jsonb, 'x')$$, 'Invalid company key', 'company keys are validated');

create temp table t_claim1 as select public.claim_company_mark_targets((select (result->>'run_id')::uuid from t_run), 2) as batch;
create temp table t_claim2 as select public.claim_company_mark_targets((select (result->>'run_id')::uuid from t_run), 2) as batch;
select is((select jsonb_array_length(batch) from t_claim1), 2, 'a claim returns the requested batch size');
select is(
  (select count(*) from jsonb_array_elements((select batch from t_claim1)) a join jsonb_array_elements((select batch from t_claim2)) b on a->>'key' = b->>'key'),
  0::bigint,
  'a fresh claim is not handed out again within fifteen minutes'
);
select ok((select batch->0 ? 'domains' from t_claim1), 'claimed targets carry their domains');

select throws_ok(
  $$select public.record_company_mark_outcome((select (result->>'run_id')::uuid from t_run), 'google', 'fetched', 'google/2.png', 'image/png', 2048, 512, 512, 'https://www.google.com/apple-touch-icon.png')$$,
  'Unexpected object path',
  'a fetched mark must use the next version path'
);
select throws_ok(
  $$select public.record_company_mark_outcome((select (result->>'run_id')::uuid from t_run), 'google', 'fetched', 'google/1.png', 'image/png', 2048, 64, 64, 'https://www.google.com/favicon.ico')$$,
  'Image too small',
  'a fetched mark must be at least 128 px'
);
select is(
  (public.record_company_mark_outcome((select (result->>'run_id')::uuid from t_run), 'google', 'fetched', 'google/1.png', 'image/png', 2048, 512, 512, 'https://www.google.com/apple-touch-icon.png')->>'mark_status'),
  'available',
  'a fetched mark becomes available'
);
select is((select mark_path from public.companies where key = 'google'), 'google/1.png', 'the served path is recorded');
select is((select state from private.company_mark_versions where company_key = 'google' and version = 1), 'served', 'version 1 is served');

-- Read models after a mark exists
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-0000000000a1', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is(
  (public.get_current_introduction()->'person'->'company_mark'),
  '{"key": "google", "version": 1, "path": "google/1.png"}'::jsonb,
  'the introduction read model carries the counterpart mark reference'
);
select is((public.get_active_conversation()->'person'->'company_mark'->>'key'), 'google', 'the conversation read model carries the counterpart mark reference');
select is((public.get_connections()->0->'person'->'company_mark'->>'version'), '1', 'the connections read model carries the mark reference');
select ok((public.get_current_introduction()->'person'->>'company_mark') !~ '@', 'the mark reference never carries an email domain');
select set_config('request.jwt.claim.sub', '20000000-0000-0000-0000-0000000000a2', true);
select is((public.get_own_company_mark()->'company_mark'->>'path'), 'google/1.png', 'a member sees their own company mark reference');
reset role;

-- Versions, refresh, withholding, retirement
select is(
  (public.record_company_mark_outcome((select (result->>'run_id')::uuid from t_run), 'google', 'fetched', 'google/2.png', 'image/png', 4096, 1024, 1024, 'https://www.google.com/icon-1024.png')->>'mark_version'),
  '2',
  'a second fetch stores a new version'
);
select is((select state from private.company_mark_versions where company_key = 'google' and version = 1), 'superseded', 'the previous version is superseded');
select ok((select retired_at is not null from private.company_mark_versions where company_key = 'google' and version = 1), 'a superseded version records when it retired');
select is(
  (public.record_company_mark_outcome((select (result->>'run_id')::uuid from t_run), 'google', 'no_icon_published', null, null, null, null, null, null, 'largest published icon is 64 px')->>'mark_status'),
  'available',
  'a failed refresh keeps the current mark serving'
);
select is((select mark_failure_reason from public.companies where key = 'google'), 'largest published icon is 64 px', 'the failure reason is recorded');
select is(
  (public.record_company_mark_outcome((select (result->>'run_id')::uuid from t_run), 'shopify', 'fetch_failed', null, null, null, null, null, null, 'unreachable')->>'mark_status'),
  'fetch_failed',
  'a failed first fetch is recorded on the company'
);
select is((public.set_company_mark_withheld('google', true)->>'mark_status'), 'withheld', 'the product team can withhold a mark');
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-0000000000a1', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select ok((public.get_current_introduction()->'person'->>'company_mark') is null, 'a withheld mark disappears from the read models');
reset role;
select is((public.set_company_mark_withheld('google', false)->>'mark_status'), 'available', 'lifting a withholding restores the current version');
select is((select mark_path from public.companies where key = 'google'), 'google/2.png', 'the restored path is the current version');
select is((public.request_company_mark_refresh('google')->>'mark_refresh_requested'), 'true', 'the product team can request a refresh');
select cmp_ok((select jsonb_array_length(public.get_company_mark_overview())), '>=', 200, 'the overview lists every company');
select ok((select bool_and(value ? 'mark_status') from jsonb_array_elements(public.get_company_mark_overview())), 'every overview row carries a mark status');

update public.companies set status = 'rejected' where key = 'google';
select is((select state from private.company_mark_versions where company_key = 'google' and version = 2), 'withdrawn', 'leaving the registry withdraws the served version');
select is((select mark_status from public.companies where key = 'google'), 'not_yet_fetched', 'a retired company no longer serves a mark');
set local role authenticated;
select set_config('request.jwt.claim.sub', '20000000-0000-0000-0000-0000000000a2', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select ok((public.get_own_company_mark()->>'company_mark') is null, 'members of a retired company see no mark reference');
select is((select company_name from public.profiles where id = '20000000-0000-0000-0000-0000000000a2'), 'Google', 'retiring a company keeps the member company name');
reset role;

-- Finishing, purging, and abandoned runs
select public.finish_company_mark_run((select (result->>'run_id')::uuid from t_run), 'completed', '{"purged": 0}'::jsonb, null);
select is((select status from private.company_mark_runs where id = (select (result->>'run_id')::uuid from t_run)), 'completed', 'a run can be completed');
select is((select summary->>'fetch_failed' from private.company_mark_runs where id = (select (result->>'run_id')::uuid from t_run)), '1', 'the summary counts recorded outcomes');
select is((select summary->>'no_icon_published' from private.company_mark_runs where id = (select (result->>'run_id')::uuid from t_run)), '1', 'the latest outcome per company is what counts');
select is(public.list_company_mark_purges(50), '[]'::jsonb, 'freshly retired versions are not purged yet');
update private.company_mark_versions set retired_at = now() - interval '31 days' where company_key = 'google' and version = 1;
select is((public.list_company_mark_purges(50)->0->>'path'), 'google/1.png', 'a version retired more than 30 days ago is due for purge');
select is(public.confirm_company_mark_purge('google', 1), true, 'a purged version row is removed');
select is((select count(*) from private.company_mark_versions where company_key = 'google' and version = 1), 0::bigint, 'the purged version is gone');

create temp table t_run2 as select public.start_company_mark_run('{"action":"refresh","companies":["apple"]}'::jsonb, 'pgtap') as result;
select is((select result->>'status' from t_run2), 'running', 'a new run starts after the previous one finished');
select is((select mark_refresh_requested from public.companies where key = 'apple'), true, 'a refresh run flags the named companies');
select is((select jsonb_array_length(public.claim_company_mark_targets((select (result->>'run_id')::uuid from t_run2), 25))), 1, 'a scoped run claims only its companies');
select is(
  (public.record_company_mark_outcome((select (result->>'run_id')::uuid from t_run2), 'apple', 'fetched', 'apple/1.jpg', 'image/jpeg', 9000, 180, 180, 'https://www.apple.com/apple-touch-icon.png')->>'mark_status'),
  'available',
  'a JPEG mark is accepted'
);
select is(public.confirm_company_mark_purge('apple', 1), false, 'a served version is never purged');
update private.company_mark_runs set started_at = now() - interval '31 minutes' where id = (select (result->>'run_id')::uuid from t_run2);
select is((public.start_company_mark_run('{"action":"populate"}'::jsonb, 'pgtap')->>'status'), 'running', 'an abandoned run no longer blocks a new one');
select is((select error_message from private.company_mark_runs where id = (select (result->>'run_id')::uuid from t_run2)), 'abandoned', 'the abandoned run is failed with a reason');

-- Retention
insert into private.company_mark_runs (started_at, finished_at, status) values (now() - interval '181 days', now() - interval '181 days', 'completed');
select is((select count(*) from private.company_mark_runs where started_at < now() - interval '180 days'), 1::bigint, 'an old run exists before maintenance');
select private.run_retention_maintenance();
select is((select count(*) from private.company_mark_runs where started_at < now() - interval '180 days'), 0::bigint, 'runs older than 180 days are purged by retention');
select cmp_ok((select count(*) from private.company_mark_runs), '>=', 3::bigint, 'recent runs survive retention');
select is(private.dispatch_company_mark_purge(), null, 'the purge dispatcher stays idle without Vault secrets');
select is((select count(*) from cron.job where jobname like 'network-to-%'), 5::bigint, 'no new scheduled job was added');

select * from finish();
rollback;
