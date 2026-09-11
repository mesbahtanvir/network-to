begin;
select plan(81);

-- Structure and least privilege -------------------------------------------------

select has_table('private', 'app_store_notifications', 'App Store Server Notifications are recorded outside the Data API');
select has_table('private', 'operational_incidents', 'edge function failures have a private incident log');
select has_table('private', 'operations_alerts', 'posted operations alerts are remembered so they are never repeated');
select has_function('public', 'claim_notification_deliveries', array['integer'], 'the delivery function can claim due notifications');
select has_function('public', 'complete_notification_delivery', array['uuid', 'boolean', 'text'], 'delivery outcomes are recorded through a validated transition');
select has_function('public', 'retire_device_token', array['text'], 'tokens rejected by APNs can be retired');
select has_function(
  'public', 'record_app_store_notification',
  array['text', 'text', 'text', 'text', 'timestamp with time zone', 'text', 'text', 'uuid', 'text', 'text', 'timestamp with time zone', 'boolean'],
  'verified App Store notifications update membership through one idempotent transition'
);
select has_function('public', 'record_operational_incident', array['text', 'text', 'text'], 'edge functions can report operational incidents');
select has_function('private', 'dispatch_notification_delivery', array[]::text[], 'notification delivery is dispatched from the database schedule');
select has_function('private', 'run_meetup_followups', array[]::text[], 'meetup feedback follow-ups run on a schedule');
select has_function('private', 'pending_operations_alerts', array[]::text[], 'operations alerts are computed from operational tables');
select has_function('private', 'run_operations_alerts', array[]::text[], 'operations alerts are posted on a schedule');

select ok(not has_function_privilege('authenticated', 'public.claim_notification_deliveries(integer)', 'EXECUTE'), 'members cannot claim notification deliveries');
select ok(has_function_privilege('service_role', 'public.claim_notification_deliveries(integer)', 'EXECUTE'), 'the trusted delivery function can claim notification deliveries');
select ok(not has_function_privilege('authenticated', 'public.complete_notification_delivery(uuid,boolean,text)', 'EXECUTE'), 'members cannot mark notifications delivered');
select ok(not has_function_privilege('authenticated', 'public.retire_device_token(text)', 'EXECUTE'), 'members cannot retire other devices through the delivery RPC');
select ok(
  not has_function_privilege('authenticated', 'public.record_app_store_notification(text,text,text,text,timestamp with time zone,text,text,uuid,text,text,timestamp with time zone,boolean)', 'EXECUTE'),
  'members cannot forge App Store notifications'
);
select ok(
  has_function_privilege('service_role', 'public.record_app_store_notification(text,text,text,text,timestamp with time zone,text,text,uuid,text,text,timestamp with time zone,boolean)', 'EXECUTE'),
  'only trusted verification can record App Store notifications'
);
select ok(not has_function_privilege('anon', 'public.record_operational_incident(text,text,text)', 'EXECUTE'), 'anonymous clients cannot create incidents');
select ok(has_function_privilege('service_role', 'public.record_operational_incident(text,text,text)', 'EXECUTE'), 'trusted functions can create incidents');
select ok(not has_table_privilege('authenticated', 'private.app_store_notifications', 'SELECT'), 'members cannot read App Store notification records');
select ok(not has_table_privilege('authenticated', 'private.operational_incidents', 'SELECT'), 'members cannot read operational incidents');

select is((select count(*) from cron.job where jobname = 'network-to-notification-delivery'), 1::bigint, 'notification delivery dispatch is scheduled exactly once');
select is((select count(*) from cron.job where jobname = 'network-to-hourly-meetup-followups'), 1::bigint, 'meetup follow-ups are scheduled exactly once');
select is((select count(*) from cron.job where jobname = 'network-to-operations-alerts'), 1::bigint, 'operations alerts are scheduled exactly once');
select ok(exists (select 1 from pg_extension where extname = 'pg_net'), 'pg_net is installed for scheduled HTTP dispatch');
select ok(exists (select 1 from pg_extension where extname = 'supabase_vault'), 'Vault is installed for scheduler secrets');

-- Fixtures --------------------------------------------------------------------------

insert into auth.users (id, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('c1000000-0000-0000-0000-000000000001', 'delivery-one@shopify.com', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('c2000000-0000-0000-0000-000000000002', 'delivery-two@google.com', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

update public.profiles set name = 'Priya Natarajan' where id = 'c2000000-0000-0000-0000-000000000002';
update public.profiles set name = 'Alex Morgan' where id = 'c1000000-0000-0000-0000-000000000001';

insert into public.introductions (id, member_a, member_b, reason_for_a, reason_for_b, meeting_context, status)
values (
  'c3000000-0000-0000-0000-000000000003',
  'c1000000-0000-0000-0000-000000000001',
  'c2000000-0000-0000-0000-000000000002',
  'Relevant experience', 'Relevant experience', 'Coffee downtown', 'mutual'
);

insert into public.conversations (id, introduction_id, member_a, member_b)
values (
  'c4000000-0000-0000-0000-000000000004',
  'c3000000-0000-0000-0000-000000000003',
  'c1000000-0000-0000-0000-000000000001',
  'c2000000-0000-0000-0000-000000000002'
);

insert into public.device_tokens (user_id, token, environment)
values ('c1000000-0000-0000-0000-000000000001', repeat('c', 64), 'production');

insert into public.notification_events (id, user_id, kind, payload, deliver_after)
values
  ('c5000000-0000-0000-0000-000000000005', 'c1000000-0000-0000-0000-000000000001', 'new_message',
    jsonb_build_object('conversation_id', 'c4000000-0000-0000-0000-000000000004'), now() - interval '1 minute'),
  ('c6000000-0000-0000-0000-000000000006', 'c2000000-0000-0000-0000-000000000002', 'introduction_ready',
    jsonb_build_object('introduction_id', 'c3000000-0000-0000-0000-000000000003'), now() - interval '1 minute'),
  ('c7000000-0000-0000-0000-000000000007', 'c1000000-0000-0000-0000-000000000001', 'meetup_reminder',
    jsonb_build_object('conversation_id', 'c4000000-0000-0000-0000-000000000004'), now() + interval '1 hour');

-- Delivery claims ---------------------------------------------------------------------

create temp table claimed as select public.claim_notification_deliveries(10) as batch;

select is((select jsonb_array_length(batch) from claimed), 1, 'only due events for members with a registered device are claimed');
select is((select batch->0->>'id' from claimed), 'c5000000-0000-0000-0000-000000000005', 'the due message notification is claimed first');
select is((select batch->0->>'counterpart_first_name' from claimed), 'Priya', 'the claim carries only the other member''s first name');
select is((select batch->0->'devices'->0->>'token' from claimed), repeat('c', 64), 'the claim lists the member''s registered devices');
select is((select batch->0->'devices'->0->>'environment' from claimed), 'production', 'each device carries its APNs environment');
select is((select attempt_count from public.notification_events where id = 'c5000000-0000-0000-0000-000000000005'), 1, 'a claim counts as a delivery attempt');
select is(jsonb_array_length(public.claim_notification_deliveries(10)), 0, 'a claimed event is not claimed again until its backoff passes');
select lives_ok($$select public.complete_notification_delivery('c5000000-0000-0000-0000-000000000005', true)$$, 'a successful delivery can be recorded');
select ok(
  (select delivered_at is not null and last_error is null from public.notification_events where id = 'c5000000-0000-0000-0000-000000000005'),
  'a delivered event is marked delivered without an error'
);
select lives_ok($$select public.complete_notification_delivery('c6000000-0000-0000-0000-000000000006', false, 'APNs is not configured')$$, 'a failed delivery can be recorded');
select is(
  (select last_error from public.notification_events where id = 'c6000000-0000-0000-0000-000000000006'),
  'APNs is not configured',
  'a failed delivery keeps the last error for operations review'
);
select lives_ok($$select public.retire_device_token(repeat('c', 64))$$, 'a token rejected by APNs can be retired');
select is((select count(*) from public.device_tokens where token = repeat('c', 64)), 0::bigint, 'a retired token is removed');

-- Scheduled dispatch --------------------------------------------------------------------

insert into public.device_tokens (user_id, token, environment)
values ('c1000000-0000-0000-0000-000000000001', repeat('d', 64), 'sandbox');
insert into public.notification_events (id, user_id, kind, payload)
values ('c8000000-0000-0000-0000-000000000008', 'c1000000-0000-0000-0000-000000000001', 'mutual_interest',
  jsonb_build_object('introduction_id', 'c3000000-0000-0000-0000-000000000003', 'conversation_id', 'c4000000-0000-0000-0000-000000000004'));

select is(private.dispatch_notification_delivery(), null::bigint, 'the dispatcher stays silent until Vault holds the project URL and job secret');
select vault.create_secret('https://example.supabase.co', 'project_url');
select vault.create_secret(repeat('e', 64), 'notification_job_secret');
select ok(private.dispatch_notification_delivery() is not null, 'the dispatcher queues a request to the delivery function once configured');
select public.complete_notification_delivery('c8000000-0000-0000-0000-000000000008', true);
select is(private.dispatch_notification_delivery(), null::bigint, 'the dispatcher does nothing when no delivery is due');

-- Meetup follow-ups ---------------------------------------------------------------------

insert into auth.users (id, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('c9000000-0000-0000-0000-000000000009', 'delivery-three@meta.com', now(), '{}'::jsonb, '{}'::jsonb, now(), now());
insert into public.introductions (id, member_a, member_b, reason_for_a, reason_for_b, meeting_context, status)
values ('ca000000-0000-0000-0000-00000000000a', 'c1000000-0000-0000-0000-000000000001', 'c9000000-0000-0000-0000-000000000009',
  'Relevant experience', 'Relevant experience', 'Coffee downtown', 'mutual');
insert into public.conversations (id, introduction_id, member_a, member_b, status)
values ('cb000000-0000-0000-0000-00000000000b', 'ca000000-0000-0000-0000-00000000000a',
  'c1000000-0000-0000-0000-000000000001', 'c9000000-0000-0000-0000-000000000009', 'ended');

insert into public.meetups (id, conversation_id, proposed_by, starts_at, place_name, area, status)
values
  ('cc000000-0000-0000-0000-00000000000c', 'c4000000-0000-0000-0000-000000000004', 'c1000000-0000-0000-0000-000000000001',
    now() - interval '5 hours', 'Quiet cafe', 'Downtown / city centre', 'proposed'),
  ('cd000000-0000-0000-0000-00000000000d', 'c4000000-0000-0000-0000-000000000004', 'c2000000-0000-0000-0000-000000000002',
    now() - interval '1 hour', 'Quiet cafe', 'Downtown / city centre', 'confirmed'),
  ('ce000000-0000-0000-0000-00000000000e', 'cb000000-0000-0000-0000-00000000000b', 'c1000000-0000-0000-0000-000000000001',
    now() - interval '5 hours', 'Quiet cafe', 'Downtown / city centre', 'proposed');

select is(private.run_meetup_followups(), 1, 'only meetups that started over three hours ago in active conversations become feedback due');
select is((select status from public.meetups where id = 'cc000000-0000-0000-0000-00000000000c'), 'feedback_due', 'a past meetup is marked feedback due');
select is((select status from public.meetups where id = 'cd000000-0000-0000-0000-00000000000d'), 'confirmed', 'a recent meetup keeps its planned status');
select is((select status from public.meetups where id = 'ce000000-0000-0000-0000-00000000000e'), 'proposed', 'meetups in ended conversations are not followed up');
select is(
  (select count(*) from public.notification_events where kind = 'feedback_due' and payload->>'meetup_id' = 'cc000000-0000-0000-0000-00000000000c'),
  2::bigint,
  'both participants are asked for private feedback'
);
select is(private.run_meetup_followups(), 0, 'follow-ups are never repeated for the same meetup');

-- App Store Server Notifications --------------------------------------------------------------

select is(
  public.record_app_store_notification('notif-0001', 'SUBSCRIBED', 'INITIAL_BUY', 'sandbox', now() - interval '2 hours',
    'orig-1000', 'tx-1001', 'c1000000-0000-0000-0000-000000000001', 'com.mesbahtanvir.networkto.monthly',
    'active', now() + interval '30 days', true),
  'applied',
  'a verified subscription notification is applied to the member named by its app account token'
);
select is((select status || ':' || original_transaction_id from private.memberships where user_id = 'c1000000-0000-0000-0000-000000000001'),
  'active:orig-1000', 'the membership records the App Store subscription');
select ok(private.has_membership_access('c1000000-0000-0000-0000-000000000001', now()), 'a server-side renewal grants matching access');
select ok((select trial_ends_at <= now() from private.memberships where user_id = 'c1000000-0000-0000-0000-000000000001'), 'a subscription recorded without an existing membership row never starts a free month');
select is(
  public.record_app_store_notification('notif-0001', 'SUBSCRIBED', 'INITIAL_BUY', 'sandbox', now() - interval '2 hours',
    'orig-1000', 'tx-1001', 'c1000000-0000-0000-0000-000000000001', 'com.mesbahtanvir.networkto.monthly',
    'active', now() + interval '30 days', true),
  'duplicate',
  'a redelivered notification is recognised and not applied twice'
);
select is(
  public.record_app_store_notification('notif-0002', 'EXPIRED', 'VOLUNTARY', 'sandbox', now() - interval '3 hours',
    'orig-1000', 'tx-0999', null, 'com.mesbahtanvir.networkto.monthly',
    'expired', now() - interval '3 hours', false),
  'stale',
  'an older notification arriving late never overrides newer state'
);
select is((select status from private.memberships where user_id = 'c1000000-0000-0000-0000-000000000001'), 'active', 'stale notifications leave membership untouched');
select is(
  public.record_app_store_notification('notif-0003', 'DID_FAIL_TO_RENEW', 'GRACE_PERIOD', 'sandbox', now() - interval '1 hour',
    'orig-1000', 'tx-1002', 'c1000000-0000-0000-0000-000000000001', 'com.mesbahtanvir.networkto.monthly',
    'grace_period', now() + interval '16 days', true),
  'applied',
  'a billing grace period is applied'
);
select ok(private.has_membership_access('c1000000-0000-0000-0000-000000000001', now()), 'a grace period keeps matching access');
select is(
  public.record_app_store_notification('notif-0004', 'REFUND', null, 'sandbox', now(),
    'orig-1000', 'tx-1002', 'c1000000-0000-0000-0000-000000000001', 'com.mesbahtanvir.networkto.monthly',
    'revoked', now(), false),
  'applied',
  'a refund is applied'
);
select ok(not private.has_membership_access('c1000000-0000-0000-0000-000000000001', now() + interval '1 second'), 'a refund removes matching access');
select is(
  public.record_app_store_notification('notif-0005', 'DID_RENEW', null, 'sandbox', now(),
    'orig-unknown', 'tx-2001', 'cf000000-0000-0000-0000-00000000000f', 'com.mesbahtanvir.networkto.monthly',
    'active', now() + interval '30 days', true),
  'unmatched',
  'a notification for an unknown member is recorded without changing anyone''s membership'
);
select is(
  public.record_app_store_notification('notif-0006', 'DID_RENEW', 'BILLING_RECOVERY', 'sandbox', now() + interval '1 second',
    'orig-1000', 'tx-1003', null, 'com.mesbahtanvir.networkto.monthly',
    'active', now() + interval '30 days', true),
  'applied',
  'a notification without an app account token is matched through the original transaction on file'
);
select is((select status || ':' || latest_transaction_id from private.memberships where user_id = 'c1000000-0000-0000-0000-000000000001'),
  'active:tx-1003', 'the renewal restores access and records the latest transaction');
select is(
  public.record_app_store_notification('notif-0007', 'SUBSCRIBED', 'INITIAL_BUY', 'sandbox', now(),
    'orig-3000', 'tx-3001', 'c1000000-0000-0000-0000-000000000001', 'com.example.other',
    'active', now() + interval '30 days', true),
  'ignored',
  'notifications for other products are ignored'
);
select is(
  public.record_app_store_notification('notif-0008', 'TEST', null, 'sandbox', now(), null, null, null, null, null, null, null),
  'ignored',
  'informational notifications are recorded and ignored'
);
select is((select count(*) from private.app_store_notifications), 8::bigint, 'every distinct notification is recorded once');
select throws_ok(
  $$select public.record_app_store_notification('notif-0009', 'TEST', null, 'xcode', now(), null, null, null, null, null, null, null)$$,
  'P0001',
  'Invalid App Store environment',
  'only sandbox and production notifications are accepted'
);

-- Operations alerts -----------------------------------------------------------------------

create temp table incident as
  select public.record_operational_incident('account_deletion_failed', 'Auth admin deletion returned HTTP 500', 'c1000000-0000-0000-0000-000000000001') as id;
select throws_ok(
  $$select public.record_operational_incident('something_else', 'detail')$$,
  'P0001',
  'Invalid incident kind',
  'incident kinds are constrained'
);
select ok(
  exists (select 1 from private.pending_operations_alerts() a where a.fingerprint = 'incident:' || (select id::text from incident)),
  'incidents reported by edge functions become pending alerts'
);

insert into private.matching_runs (requested_limit, status, completed_at, error_message)
values (25, 'failed', now(), 'division by zero');
select ok(
  exists (select 1 from private.pending_operations_alerts() a where a.fingerprint like 'matching_run_failed:%' and a.message like '%division by zero%'),
  'failed matching runs become pending alerts'
);

update public.notification_events
set attempt_count = 4, last_attempt_at = now(), last_error = 'InvalidProviderToken'
where id = 'c6000000-0000-0000-0000-000000000006';
select ok(
  exists (select 1 from private.pending_operations_alerts() a where a.fingerprint like 'notification_delivery_failures:%' and a.message like '%InvalidProviderToken%'),
  'repeated delivery failures become one pending alert per hour'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
create temp table report as
  select public.submit_member_report('c2000000-0000-0000-0000-000000000002', 'c4000000-0000-0000-0000-000000000004', 'spam', 'private note text') as id;
reset role;

select ok(
  exists (select 1 from private.pending_operations_alerts() a where a.fingerprint = 'member_report:' || (select id::text from report)),
  'new member reports become pending alerts'
);
select ok(
  not exists (select 1 from private.pending_operations_alerts() a where a.message like '%private note text%'),
  'alerts never include member-authored text'
);

select is(private.run_operations_alerts(), 0, 'alerts stay pending until a webhook URL is configured');
select ok((select count(*) from private.pending_operations_alerts()) >= 4, 'unposted alerts remain pending');
select vault.create_secret('https://hooks.example.test/ops', 'ops_alert_webhook_url');
select ok(private.run_operations_alerts() >= 4, 'configured alerts are posted in one batch');
select is((select count(*) from private.pending_operations_alerts()), 0::bigint, 'posted alerts are not pending anymore');
select is(private.run_operations_alerts(), 0, 'posted alerts are never repeated');
select ok(exists (select 1 from private.operations_alerts where request_id is not null), 'posted alerts remember the outbound request');

-- Retention ------------------------------------------------------------------------------------

insert into public.notification_events (id, user_id, kind, payload, created_at)
values ('d0000000-0000-0000-0000-000000000010', 'c2000000-0000-0000-0000-000000000002', 'introduction_ready',
  jsonb_build_object('introduction_id', 'c3000000-0000-0000-0000-000000000003'), now() - interval '100 days');
select lives_ok($$select private.run_retention_maintenance()$$, 'retention maintenance runs with the new tables');
select is((select count(*) from public.notification_events where id = 'd0000000-0000-0000-0000-000000000010'), 0::bigint,
  'undelivered notification events are removed after ninety days');

select * from finish();
rollback;
