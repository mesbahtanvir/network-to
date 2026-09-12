begin;
select plan(34);

-- Three Toronto members who can be introduced to one another: the auth trigger creates their
-- profiles and default preferences, completing onboarding starts their free month.
insert into auth.users (id, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('10000000-0000-0000-0000-000000000001', 'privacy-one@shopify.com', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('20000000-0000-0000-0000-000000000002', 'privacy-two@google.com', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('30000000-0000-0000-0000-000000000003', 'privacy-three@meta.com', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

update public.profiles
set name = case id
      when '10000000-0000-0000-0000-000000000001' then 'Member One'
      when '20000000-0000-0000-0000-000000000002' then 'Member Two'
      else 'Member Three'
    end,
    role = 'Engineering Leader',
    city = 'Toronto, ON',
    current_focus = 'Building durable technology organizations.',
    professional_ambition = 'Create products and teams with lasting impact.',
    growth_areas = array['Platform strategy'],
    contribution_areas = array['Platform strategy'],
    onboarding_complete = true
where id in (
  '10000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000002',
  '30000000-0000-0000-0000-000000000003'
);

-- An introduction between One and Two, created eight days ago and open for one more day, so
-- One's weekly cadence has passed while the introduction itself is still open.
insert into public.introductions (
  id, member_a, member_b, reason_for_a, reason_for_b, meeting_context, status, created_at, expires_at
) values (
  '40000000-0000-0000-0000-000000000004',
  '10000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000002',
  'Relevant experience', 'Relevant experience', 'Coffee in Toronto', 'offered',
  now() - interval '8 days', now() + interval '1 day'
);

select has_function('private', 'introduction_passed_by', array['uuid', 'uuid'], 'a private helper reports whether a member passed on an introduction');
select ok(not has_function_privilege('authenticated', 'private.introduction_passed_by(uuid,uuid)', 'EXECUTE'), 'members cannot call the pass helper directly');
select ok(not has_function_privilege('anon', 'private.introduction_passed_by(uuid,uuid)', 'EXECUTE'), 'anonymous callers cannot call the pass helper');
select ok(not has_function_privilege('service_role', 'private.introduction_passed_by(uuid,uuid)', 'EXECUTE'), 'the service role does not need the pass helper');

-- Member One passes.
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select is(
  public.respond_to_introduction('40000000-0000-0000-0000-000000000004', 'pass')->>'state',
  'not_mutual',
  'the member who passes learns only the outcome of their own decision'
);
select ok(public.get_current_introduction() is null, 'a member who passed no longer sees the introduction');

reset role;
select is((select status from public.introductions where id = '40000000-0000-0000-0000-000000000004'), 'offered', 'a Pass leaves the introduction open');
select is(
  (select expires_at from public.introductions where id = '40000000-0000-0000-0000-000000000004'),
  now() + interval '1 day',
  'a Pass leaves the expiry untouched'
);

-- Member Two reads and answers the same introduction after the Pass.
set local role authenticated;
select set_config('request.jwt.claim.sub', '20000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select is(public.get_current_introduction()->>'id', '40000000-0000-0000-0000-000000000004', 'the other member still sees the introduction after a Pass');
select is(public.get_current_introduction()->>'status', 'offered', 'the other member sees it as open');
select ok(public.get_current_introduction()->>'your_response' is null, 'the other member has not answered yet');
select is((public.get_current_introduction()->>'expires_at')::timestamptz, now() + interval '1 day', 'the other member sees the original expiry');
select is(
  public.respond_to_introduction('40000000-0000-0000-0000-000000000004', 'interested')->>'state',
  'waiting',
  'Interested after a Pass is indistinguishable from waiting'
);
select is(public.get_current_introduction()->>'your_response', 'interested', 'the waiting member keeps the introduction with their own response');
select is(public.get_current_introduction()->>'status', 'offered', 'the waiting member still sees it as open');
select throws_ok(
  $$select public.respond_to_introduction('40000000-0000-0000-0000-000000000004', 'interested')$$,
  'Response already recorded',
  'a response is recorded once'
);

reset role;
select is((select status from public.introductions where id = '40000000-0000-0000-0000-000000000004'), 'offered', 'an Interested response after a Pass leaves the introduction open until expiry');
select is((select count(*) from public.notification_events where kind = 'mutual_interest'), 0::bigint, 'no mutual-interest notification is created');
select is((select count(*) from public.conversations), 0::bigint, 'no conversation is created');

-- Matching: the member who passed is free again; the waiting member is not.
select lives_ok($$select private.generate_one_introduction()$$, 'matching runs with an open, passed-on introduction present');
select is(
  (select count(*) from public.introductions
   where member_a = '10000000-0000-0000-0000-000000000001' and member_b = '30000000-0000-0000-0000-000000000003'),
  1::bigint,
  'the member who passed can be introduced to someone else at their cadence'
);
select is(
  (select count(*) from public.introductions where '20000000-0000-0000-0000-000000000002' in (member_a, member_b)),
  1::bigint,
  'the waiting member keeps exactly one active introduction'
);

-- Both members passing closes the introduction at once.
set local role authenticated;
select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000003', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is(
  public.respond_to_introduction(
    (select id from public.introductions where member_a = '10000000-0000-0000-0000-000000000001' and member_b = '30000000-0000-0000-0000-000000000003'),
    'pass'
  )->>'state',
  'not_mutual',
  'the first Pass on the new introduction is recorded'
);
reset role;
select is(
  (select status from public.introductions where member_a = '10000000-0000-0000-0000-000000000001' and member_b = '30000000-0000-0000-0000-000000000003'),
  'offered',
  'one Pass keeps the introduction open for the other member'
);
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is(
  public.respond_to_introduction(
    (select id from public.introductions where member_a = '10000000-0000-0000-0000-000000000001' and member_b = '30000000-0000-0000-0000-000000000003'),
    'pass'
  )->>'state',
  'not_mutual',
  'the second Pass is recorded'
);
reset role;
select is(
  (select status from public.introductions where member_a = '10000000-0000-0000-0000-000000000001' and member_b = '30000000-0000-0000-0000-000000000003'),
  'closed',
  'both members passing closes the introduction'
);

-- Expiry ends the waiting member's introduction exactly as it would have without the Pass.
update public.introductions set expires_at = now() - interval '1 second' where id = '40000000-0000-0000-0000-000000000004';
select private.run_retention_maintenance();
select is((select status from public.introductions where id = '40000000-0000-0000-0000-000000000004'), 'expired', 'the introduction expires on schedule');

set local role authenticated;
select set_config('request.jwt.claim.sub', '20000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select ok(public.get_current_introduction() is null, 'the waiting member sees the introduction end only at its expiry');
select throws_ok(
  $$select public.respond_to_introduction('40000000-0000-0000-0000-000000000004', 'pass')$$,
  'Introduction is no longer open',
  'an expired introduction accepts no response'
);

-- Mutual interest is unchanged.
reset role;
insert into public.introductions (
  id, member_a, member_b, reason_for_a, reason_for_b, meeting_context, status
) values (
  '50000000-0000-0000-0000-000000000005',
  '20000000-0000-0000-0000-000000000002',
  '30000000-0000-0000-0000-000000000003',
  'Relevant experience', 'Relevant experience', 'Coffee in Toronto', 'offered'
);
set local role authenticated;
select set_config('request.jwt.claim.sub', '20000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is(public.respond_to_introduction('50000000-0000-0000-0000-000000000005', 'interested')->>'state', 'waiting', 'the first Interested waits');
select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000003', true);
select is(public.respond_to_introduction('50000000-0000-0000-0000-000000000005', 'interested')->>'state', 'mutual', 'the second Interested is mutual');
reset role;
select is((select status from public.introductions where id = '50000000-0000-0000-0000-000000000005'), 'mutual', 'mutual interest still marks the introduction mutual');
select is((select count(*) from public.conversations where introduction_id = '50000000-0000-0000-0000-000000000005'), 1::bigint, 'mutual interest still opens one conversation');
select is((select count(*) from public.notification_events where kind = 'mutual_interest'), 2::bigint, 'mutual interest still notifies both members');

select * from finish();
rollback;
