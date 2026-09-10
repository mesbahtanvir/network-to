begin;
select plan(26);

insert into auth.users (id, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('10000000-0000-0000-0000-000000000001', 'member-one@shopify.com', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('20000000-0000-0000-0000-000000000002', 'member-two@google.com', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('30000000-0000-0000-0000-000000000003', 'member-three@meta.com', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

update public.profiles set name = 'Member Two' where id = '20000000-0000-0000-0000-000000000002';

insert into public.introductions (
  id, member_a, member_b, reason_for_a, reason_for_b, meeting_context, status
) values (
  '40000000-0000-0000-0000-000000000004',
  '10000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000002',
  'Relevant experience', 'Relevant experience', 'Coffee in Toronto', 'mutual'
);

insert into public.conversations (id, introduction_id, member_a, member_b)
values (
  '50000000-0000-0000-0000-000000000005',
  '40000000-0000-0000-0000-000000000004',
  '10000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000002'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select lives_ok(
  $profile$
    select public.save_professional_profile(
      '{
        "name":"Member One",
        "role":"Engineering Director",
        "city":"  Toronto,   ON  ",
        "topics":["Platform strategy","Distributed systems"],
        "bio":"Builds reliable platforms.",
        "role_scope":"Leads a platform organization.",
        "current_focus":"Scaling ownership without losing reliability.",
        "years_experience":"10–15 years",
        "growth_areas":["Engineering leadership"],
        "professional_ambition":"Lead an organization-wide technical strategy.",
        "growth_interest":"Learn how peers scale platform organizations.",
        "contribution_areas":["Distributed systems"],
        "help_formats":["Compare approaches"],
        "contribution":"Share lessons from production platform work.",
        "contribution_boundaries":"No confidential architecture.",
        "education":""
      }'::jsonb,
      '[{
        "id":"60000000-0000-0000-0000-000000000006",
        "role":"Engineering Director",
        "company":"Shopify",
        "period":"2022–present"
      }]'::jsonb,
      true
    )
  $profile$,
  'a member can atomically save complete professional context'
);

select is(
  (select name || ':' || onboarding_complete::text from public.profiles
   where id = '10000000-0000-0000-0000-000000000001'),
  'Member One:true',
  'profile fields and onboarding state are saved'
);

select is(
  (select city_key from public.profiles
   where id = '10000000-0000-0000-0000-000000000001'),
  'toronto, on',
  'city matching normalizes case and repeated whitespace without changing the display field'
);

select is(
  (select count(*) from public.professional_experiences
   where user_id = '10000000-0000-0000-0000-000000000001'),
  1::bigint,
  'professional history is persisted with the profile transaction'
);

reset role;
select is(
  (select count(*) from private.memberships where user_id = '10000000-0000-0000-0000-000000000001'),
  1::bigint,
  'completing onboarding starts exactly one account trial'
);
select is(
  (select public.get_membership_status()->>'state'
   from (select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true)) claims),
  'trial',
  'the member read model reports the free trial'
);
select ok(
  (select trial_ends_at - trial_started_at between interval '27 days' and interval '32 days'
   from private.memberships where user_id = '10000000-0000-0000-0000-000000000001'),
  'the account trial lasts one calendar month'
);
select ok(
  private.has_membership_access('10000000-0000-0000-0000-000000000001', now()),
  'the trial grants matching access'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select is(
  (select count(*) from public.profiles),
  1::bigint,
  'profile RLS exposes only the caller profile'
);

select is(
  public.send_message(
    '70000000-0000-0000-0000-000000000007',
    '50000000-0000-0000-0000-000000000005',
    'Coffee next Thursday?'
  ),
  '70000000-0000-0000-0000-000000000007'::uuid,
  'a participant can send a message through the hardened RPC'
);

select is(
  public.send_message(
    '70000000-0000-0000-0000-000000000007',
    '50000000-0000-0000-0000-000000000005',
    'Coffee next Thursday?'
  ),
  '70000000-0000-0000-0000-000000000007'::uuid,
  'retrying the same client message identifier is idempotent'
);

reset role;
select is(
  (select count(*) from public.messages where id = '70000000-0000-0000-0000-000000000007'),
  1::bigint,
  'an idempotent retry does not duplicate the message'
);
select is(
  (select count(*) from public.notification_events
   where user_id = '20000000-0000-0000-0000-000000000002' and kind = 'new_message'),
  1::bigint,
  'an idempotent retry enqueues only one recipient notification'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000003', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok(
  $$select public.send_message(
    '80000000-0000-0000-0000-000000000008',
    '50000000-0000-0000-0000-000000000005',
    'I should not be here'
  )$$,
  'P0001',
  'Conversation not found',
  'a non-participant cannot send into a conversation'
);

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
select lives_ok(
  $$select public.block_member('20000000-0000-0000-0000-000000000002')$$,
  'a related member can be blocked'
);
select is(
  public.get_safety_preferences()->'blocked_members',
  '["Member Two"]'::jsonb,
  'blocked-member names can be restored without exposing profiles globally'
);

select lives_ok(
  $$select public.register_device_token(repeat('a', 64), 'sandbox')$$,
  'an authenticated member can register a normalized APNs token'
);
select is(
  (select count(*) from public.device_tokens where token = repeat('a', 64)),
  1::bigint,
  'the token owner can read the registered device token'
);

select set_config('request.jwt.claim.sub', '20000000-0000-0000-0000-000000000002', true);
select is(
  (select count(*) from public.device_tokens where token = repeat('a', 64)),
  0::bigint,
  'another member cannot read a device token'
);

reset role;
update private.memberships
set trial_started_at = now() - interval '2 months',
    trial_ends_at = now() - interval '1 month',
    status = 'expired'
where user_id = '10000000-0000-0000-0000-000000000001';
select ok(
  not private.has_membership_access('10000000-0000-0000-0000-000000000001', now()),
  'an expired trial no longer grants new matching access'
);
select lives_ok(
  $$select public.record_app_store_entitlement(
    '10000000-0000-0000-0000-000000000001',
    'com.mesbahtanvir.networkto.monthly',
    '100000000001',
    '100000000002',
    'active',
    now() + interval '1 month',
    true,
    'sandbox'
  )$$,
  'trusted App Store verification can restore access'
);
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is(
  public.get_membership_status()->>'state',
  'subscribed',
  'verified App Store access is visible through the scoped read model'
);

reset role;
insert into auth.users (id, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('90000000-0000-0000-0000-000000000009', 'local-one@shopify.com', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('a0000000-0000-0000-0000-00000000000a', 'local-two@google.com', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('b0000000-0000-0000-0000-00000000000b', 'other-city@meta.com', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

update public.profiles
set name = case id
      when '90000000-0000-0000-0000-000000000009' then 'Local One'
      when 'a0000000-0000-0000-0000-00000000000a' then 'Local Two'
      else 'Other City'
    end,
    role = 'Engineering Leader',
    city = case id
      when '90000000-0000-0000-0000-000000000009' then 'Toronto, ON'
      when 'a0000000-0000-0000-0000-00000000000a' then '  TORONTO,   ON '
      else 'Austin, TX'
    end,
    current_focus = 'Building durable technology organizations.',
    professional_ambition = 'Create products and teams with lasting impact.',
    growth_areas = array['Platform strategy'],
    contribution_areas = array['Platform strategy'],
    onboarding_complete = true
where id in (
  '90000000-0000-0000-0000-000000000009',
  'a0000000-0000-0000-0000-00000000000a',
  'b0000000-0000-0000-0000-00000000000b'
);

select lives_ok(
  $$select private.generate_one_introduction()$$,
  'matching can introduce compatible members in the same normalized city'
);
select is(
  (select count(*) from public.introductions
   where member_a = '90000000-0000-0000-0000-000000000009'
     and member_b = 'a0000000-0000-0000-0000-00000000000a'),
  1::bigint,
  'members using equivalent city formatting can match'
);
select is(
  (select count(*) from public.introductions
   where 'b0000000-0000-0000-0000-00000000000b' in (member_a, member_b)),
  0::bigint,
  'matching never pairs members from different cities'
);

select lives_ok(
  $$select public.consume_edge_rate_limit(repeat('b', 64), 'resume', 3, 86400)$$,
  'trusted résumé processing can consume its dedicated daily quota'
);

select * from finish();
rollback;
