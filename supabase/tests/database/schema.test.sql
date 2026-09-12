begin;
select plan(64);

insert into public.company_domains (domain, company_name, industry, status)
values ('shopify.com', 'Shopify', 'Commerce technology', 'approved')
on conflict (domain) do update set status = excluded.status;

select has_table('public', 'profiles', 'profiles table exists');
select has_table('public', 'introductions', 'introductions table exists');
select has_table('public', 'introduction_responses', 'private response table exists');
select has_table('public', 'messages', 'messages table exists');
select has_table('public', 'reports', 'reports table exists');
select has_table('public', 'blocks', 'blocks table exists');
select has_table('public', 'resume_documents', 'private resume records table exists');
select has_table('private', 'auth_handoffs', 'cross-device auth handoffs are stored outside the Data API');
select has_table('private', 'matching_runs', 'matching executions have a private operational audit trail');
select has_table('private', 'edge_rate_limits', 'public pre-session endpoints have durable abuse controls');
select has_table('private', 'memberships', 'membership billing state stays outside the Data API');
select has_column('public', 'profiles', 'professional_ambition', 'professional direction is first-class profile data');
select has_column('public', 'profiles', 'city_key', 'profiles include a normalized city matching key');
select isnt_empty(
  $$select 1 from pg_indexes where schemaname = 'public' and indexname = 'profiles_active_city_key_idx'$$,
  'active local matching has a partial city index'
);
select has_column('public', 'notification_events', 'deliver_after', 'notification delivery can be scheduled');
select has_column('public', 'notification_events', 'attempt_count', 'notification delivery attempts can be monitored');
select has_function('private', 'enqueue_message_notification', array[]::text[], 'messages enqueue durable notifications');
select has_function('private', 'enqueue_meetup_notifications', array[]::text[], 'meetups enqueue scheduled reminders');
select has_function('public', 'create_auth_handoff', array['uuid', 'text'], 'trusted backend can create a PKCE handoff');
select has_function('public', 'complete_auth_handoff', array['uuid', 'text'], 'verified laptop callback can complete a PKCE handoff');
select has_function('public', 'claim_auth_handoff', array['uuid', 'text'], 'originating phone can claim a PKCE handoff');
select has_function('public', 'save_professional_profile', array['jsonb', 'jsonb', 'boolean'], 'profile and experience writes are transactional');
select has_function('public', 'send_message', array['uuid', 'uuid', 'text'], 'messages use an idempotent server-side transition');
select has_function('public', 'get_safety_preferences', array[]::text[], 'blocked-member state has a scoped read model');
select has_function('public', 'register_device_token', array['text', 'text'], 'APNs device registration has a validated server transition');
select has_function('private', 'run_matching_batch', array['integer'], 'matching can run in bounded scheduled batches');
select has_function('public', 'consume_edge_rate_limit', array['text', 'text', 'integer', 'integer'], 'edge functions share an atomic rate limiter');
select isnt_empty(
  $$select 1 from pg_constraint
    where conrelid = 'private.edge_rate_limits'::regclass
      and conname = 'edge_rate_limits_action_check'
      and pg_get_constraintdef(oid) like '%resume%'$$,
  'AI résumé processing is covered by the durable edge rate limiter'
);
select has_function('public', 'get_membership_status', array[]::text[], 'members have a scoped membership read model');
select has_function('private', 'has_membership_access', array['uuid', 'timestamp with time zone'], 'matching uses centralized membership access checks');
select isnt_empty(
  $$select 1 from pg_class where oid = 'public.profiles'::regclass and relrowsecurity$$,
  'profiles has RLS enabled'
);
select isnt_empty(
  $$select 1 from pg_class where oid = 'public.introduction_responses'::regclass and relrowsecurity$$,
  'introduction responses have RLS enabled'
);
select isnt_empty(
  $$select 1 from pg_class where oid = 'public.messages'::regclass and relrowsecurity$$,
  'messages have RLS enabled'
);
select isnt_empty(
  $$select 1 from pg_class where oid = 'public.reports'::regclass and relrowsecurity$$,
  'reports have RLS enabled'
);
select ok(
  not has_column_privilege('authenticated', 'public.profiles', 'company_name', 'UPDATE'),
  'members cannot overwrite their trusted company'
);
select ok(
  has_column_privilege('authenticated', 'public.profiles', 'professional_ambition', 'UPDATE'),
  'members can update their professional direction'
);
select ok(
  not has_function_privilege('anon', 'public.get_current_introduction()', 'EXECUTE'),
  'anonymous clients cannot read an introduction'
);
select ok(
  has_function_privilege('authenticated', 'public.get_current_introduction()', 'EXECUTE'),
  'authenticated members can call their scoped introduction read model'
);
select ok(
  not has_function_privilege('authenticated', 'public.generate_next_introduction()', 'EXECUTE'),
  'clients cannot invoke matching directly'
);
select ok(
  has_function_privilege('service_role', 'public.generate_next_introduction()', 'EXECUTE'),
  'only the trusted matching job can invoke matching'
);
select ok(
  has_function_privilege('authenticated', 'public.register_device_token(text,text)', 'EXECUTE'),
  'authenticated members can invoke the validated device registration RPC'
);
select ok(
  not has_table_privilege('authenticated', 'public.messages', 'INSERT'),
  'clients cannot bypass the idempotent message RPC with a direct insert'
);
select ok(
  not has_table_privilege('authenticated', 'public.device_tokens', 'INSERT'),
  'clients cannot bypass validated device registration with a direct insert'
);
select ok(
  not has_table_privilege('authenticated', 'private.memberships', 'SELECT'),
  'members cannot read private billing records directly'
);
select ok(
  has_function_privilege('authenticated', 'public.get_membership_status()', 'EXECUTE'),
  'members can read only their effective membership status'
);
select ok(
  not has_function_privilege('anon', 'public.get_membership_status()', 'EXECUTE'),
  'anonymous clients cannot read membership state'
);
select ok(
  not has_function_privilege('authenticated', 'public.record_app_store_entitlement(uuid,text,text,text,text,timestamp with time zone,boolean,text)', 'EXECUTE'),
  'clients cannot grant themselves App Store access'
);
select ok(
  has_function_privilege('service_role', 'public.record_app_store_entitlement(uuid,text,text,text,text,timestamp with time zone,boolean,text)', 'EXECUTE'),
  'only trusted verification can record App Store access'
);
select is(
  (select count(*) from cron.job where jobname = 'network-to-hourly-matching'),
  1::bigint,
  'hourly matching is scheduled exactly once'
);
select is(
  (select count(*) from cron.job where jobname = 'network-to-daily-maintenance'),
  1::bigint,
  'daily retention maintenance is scheduled exactly once'
);
select ok(
  not has_table_privilege('anon', 'private.auth_handoffs', 'SELECT'),
  'anonymous clients cannot read handoff authorization codes'
);
select ok(
  not has_function_privilege('anon', 'public.create_auth_handoff(uuid,text)', 'EXECUTE'),
  'anonymous clients cannot create handoff rows through the database API'
);
select ok(
  not has_function_privilege('authenticated', 'public.claim_auth_handoff(uuid,text)', 'EXECUTE'),
  'member sessions cannot bypass the handoff edge function'
);
select ok(
  has_function_privilege('service_role', 'public.claim_auth_handoff(uuid,text)', 'EXECUTE'),
  'the trusted handoff service can atomically claim an authorization code'
);
select ok(
  not has_function_privilege('anon', 'public.consume_edge_rate_limit(text,text,integer,integer)', 'EXECUTE'),
  'anonymous clients cannot consume or reset trusted edge quotas directly'
);
select is(
  (select public from storage.buckets where id = 'resumes'),
  false,
  'resume storage is private'
);
select is(
  (public.validate_company_domain('shopify.com')->>'decision')::text,
  'eligible',
  'approved company domain is eligible'
);
select is(
  (public.validate_company_domain('gmail.com')->>'decision')::text,
  'ineligible',
  'consumer domain is not eligible'
);
select is(
  (public.validate_company_domain('apple.com')->>'decision')::text,
  'eligible',
  'well-known big-tech domains are eligible at launch'
);
select is(
  (public.validate_company_domain('openai.com')->>'decision')::text,
  'eligible',
  'established adjacent AI-company domains are eligible at launch'
);
select is((select count(*) from public.company_domains where domain = 'orbitsystems.com'), 0::bigint, 'Orbit Systems fixture is absent');
select is((select count(*) from public.company_domains where domain = 'northstar.ai'), 0::bigint, 'Northstar AI fixture is absent');
select is((select count(*) from public.company_domains where domain = 'harbourlabs.com'), 0::bigint, 'Harbour Labs fixture is absent');
select is((select count(*) from public.company_domains where domain = 'newventurelabs.ca'), 0::bigint, 'New Venture Labs fixture is absent');

select * from finish();
rollback;
