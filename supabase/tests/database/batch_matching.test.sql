begin;
select plan(114);

-- Fixture helpers. Members are created through auth.users so the signup trigger builds their
-- profile and default preferences; completing onboarding starts their free month.
insert into public.company_domains (domain, company_name, industry, status)
values
  ('north.test', 'North Labs', 'Software', 'approved'),
  ('south.test', 'South Works', 'Software', 'approved'),
  ('east.test', 'East Systems', 'Finance technology', 'approved'),
  ('west.test', 'West Studio', 'Design', 'approved'),
  ('solo.test', 'Solo Shop', 'Hardware', 'approved')
on conflict (domain) do update set status = excluded.status;

create function pg_temp.add_member(
  p_id uuid,
  p_email text,
  p_name text,
  p_city text,
  p_growth text[],
  p_contribution text[],
  p_help text[] default array['Compare approaches'],
  p_words text default 'What I can share from experience.',
  p_ambition text default 'What I am working toward.',
  p_years text default '7–9 years',
  p_topics text[] default '{}'::text[]
) returns void
language plpgsql
as $$
begin
  insert into auth.users (id, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values (p_id, p_email, now(), '{}'::jsonb, jsonb_build_object('name', p_name), now(), now());
  update public.profiles
  set name = p_name,
      role = 'Builder',
      city = p_city,
      growth_areas = p_growth,
      contribution_areas = p_contribution,
      help_formats = p_help,
      contribution = p_words,
      professional_ambition = p_ambition,
      years_experience = p_years,
      topics = p_topics,
      onboarding_complete = true
  where id = p_id;
end;
$$;

create function pg_temp.pairs_created(p_run uuid) returns text
language sql
as $$
  select coalesce(string_agg(left(i.member_a::text, 8) || '-' || left(i.member_b::text, 8), ',' order by i.member_a, i.member_b), '')
  from public.introductions i
  where i.matching_run_id = p_run;
$$;

-- Between scenarios every member so far is paused and every open introduction expired, so the
-- next scenario's batch sees only its own members. (Savepoints would also roll back pgTAP's
-- own bookkeeping.)
create function pg_temp.retire_all() returns void
language plpgsql
as $$
begin
  update public.networking_preferences set frequency = 'paused';
  update public.introductions set expires_at = now() - interval '1 second' where expires_at > now();
end;
$$;

-- Registry, helpers, schedule, privileges ----------------------------------------------------

select has_table('private', 'growth_contribution_affinity', 'the affinity registry exists');
select ok(not has_table_privilege('authenticated', 'private.growth_contribution_affinity', 'SELECT'), 'members cannot read the registry');
select ok(not has_table_privilege('anon', 'private.growth_contribution_affinity', 'SELECT'), 'anonymous clients cannot read the registry');
select is(
  (select count(distinct lower(a.growth_area)) from private.growth_contribution_affinity a
   where lower(a.growth_area) in ('applied ai products', 'executive communication', 'engineering leadership', 'platform strategy',
                                  'product thinking', 'founder perspective', 'career transition', 'local tech ecosystem')),
  8::bigint,
  'the registry serves every growth area a member can choose'
);
select is((private.growth_service(array['Platform strategy', 'Applied AI products'], array['Product strategy', 'AI infrastructure'])).same_count, 0, 'adjacent service counts no same terms');
select is((private.growth_service(array['Platform strategy', 'Applied AI products'], array['Product strategy', 'AI infrastructure'])).adjacent_count, 2, 'adjacent service counts both served growth areas');
select is((private.growth_service(array['Platform strategy', 'Applied AI products'], array['Product strategy', 'AI infrastructure'])).served_growth_area, 'Platform strategy', 'the explained growth area is the first served in the member''s own order');
select is((private.growth_service(array['Platform strategy', 'Applied AI products'], array['Product strategy', 'AI infrastructure'])).serving_contribution_area, 'Product strategy', 'the explained contribution area is the first that serves it');
select is((private.growth_service(array['Applied AI products', 'Engineering leadership'], array['AI infrastructure', 'engineering leadership'])).same_count, 1, 'an identical term serves as same whatever its case');
select is((private.growth_service(array['Applied AI products', 'Engineering leadership'], array['AI infrastructure', 'engineering leadership'])).served_growth_area, 'Engineering leadership', 'a same term is explained before an adjacent one');
select is((private.growth_service('{}'::text[], '{}'::text[])).same_count, 0, 'empty input serves nothing');
select ok((private.growth_service(null, array['Product strategy'])).served_growth_area is null, 'null input explains nothing');
select is(private.experience_band('10–15 years'), 4, 'experience bands read the en dash');
select is(private.experience_band('1-3 years'), 1, 'experience bands read a hyphen');
select ok(private.experience_band('') is null, 'an unknown experience band is null');
select is(private.normalize_topic('  ML-Infrastructure! '), 'ml infrastructure', 'topics normalize case, spacing, and punctuation');
select is(private.cadence_interval('exceptional_only'), interval '28 days', 'exceptional only spaces introductions by 28 days');
select ok(private.cadence_interval('paused') is null, 'a paused member has no cadence');
select is(private.lower_first_word('Platform strategy'), 'platform strategy', 'area names lower-case their first letter in copy');
select is(private.lower_first_word('AI infrastructure'), 'AI infrastructure', 'an acronym keeps its case in copy');
select has_table('private', 'matching_run_cities', 'per-city run records exist');
select ok(not has_table_privilege('authenticated', 'private.matching_run_cities', 'SELECT'), 'members cannot read run records');
select ok(not has_table_privilege('anon', 'private.matching_run_cities', 'SELECT'), 'anonymous clients cannot read run records');
select ok(
  not exists (
    select 1 from information_schema.columns c
    where c.table_schema = 'private' and c.table_name = 'matching_run_cities'
      and c.column_name not in ('run_id', 'city_key', 'created_at')
      and c.data_type not in ('integer', 'numeric')
  ),
  'run records hold counts only'
);
select has_column('public', 'introductions', 'reciprocal_for_a', 'member A has a reciprocal explanation');
select has_column('public', 'introductions', 'reciprocal_for_b', 'member B has a reciprocal explanation');
select has_column('public', 'introductions', 'matching_run_id', 'an introduction remembers the run that created it');
select ok(not has_function_privilege('authenticated', 'private.matching_candidate_pairs(text,timestamp with time zone,uuid,uuid)', 'EXECUTE'), 'members cannot compute candidate pairs');
select ok(not has_function_privilege('authenticated', 'private.select_matching_pairs(text,timestamp with time zone,integer)', 'EXECUTE'), 'members cannot run selection');
select ok(not has_function_privilege('authenticated', 'private.commit_matching_pairs(uuid,text,jsonb,timestamp with time zone)', 'EXECUTE'), 'members cannot commit pairs');
select ok(not has_function_privilege('authenticated', 'private.execute_matching_batch(integer)', 'EXECUTE'), 'members cannot run the batch');
select ok(not has_function_privilege('service_role', 'private.execute_matching_batch(integer)', 'EXECUTE'), 'the service role reaches the batch only through run_matching_now');
select ok(not has_function_privilege('authenticated', 'private.growth_service(text[],text[])', 'EXECUTE'), 'members cannot call growth_service');
select ok(not has_function_privilege('authenticated', 'private.has_active_introduction(uuid,timestamp with time zone)', 'EXECUTE'), 'members cannot call the active-introduction helper');
select is((select count(*) from cron.job where jobname = 'network-to-daily-matching'), 1::bigint, 'the daily batch is scheduled exactly once');
select is((select count(*) from cron.job where jobname = 'network-to-hourly-matching'), 0::bigint, 'the hourly job is gone');
select is((select count(*) from cron.job where jobname like 'network-to-%'), 5::bigint, 'the number of scheduled jobs is unchanged');
select is(
  (select command from cron.job where jobname = 'network-to-daily-matching'),
  'select private.run_matching_batch(1000)',
  'the daily batch runs with a per-city cap of 1000'
);
select is((select schedule from cron.job where jobname = 'network-to-daily-matching'), '7 13 * * *', 'the daily batch runs at 13:07 UTC');

-- Story 1: only worthwhile introductions, explained in the members' own words -------------------

select pg_temp.add_member('a1000000-0000-0000-0000-000000000001', 'alex@north.test', 'Alex Morgan', 'Toronto, ON',
  array['Platform strategy', 'Applied AI products'], array['Engineering leadership', 'Scaling teams'],
  array['Compare approaches'], 'Experience scaling distributed platforms and engineering organizations.',
  'Build an engineering organization that turns AI capabilities into dependable products.', '10–15 years', array['Distributed systems']);
select pg_temp.add_member('b1000000-0000-0000-0000-000000000002', 'maya@south.test', 'Maya Patel', '  toronto,   ON ',
  array['Executive communication'], array['Product strategy', 'Developer tools'],
  array['Review a challenge'], 'Lessons from building product teams and developer platforms.',
  'Help build a durable product company.', '7–9 years', array['distributed-systems']);
-- Sam offers AI infrastructure, which serves nobody here, and wants Career transition, which
-- only Alex could serve; Alex is taken by the stronger pair, so Sam waits.
select pg_temp.add_member('c1000000-0000-0000-0000-000000000003', 'sam@east.test', 'Sam Lee', 'Toronto, ON',
  array['Career transition'], array['AI infrastructure'], array['Share lessons learned'], '', '');
-- One direction only: Priya can help Omar (AI infrastructure serves Applied AI products) but
-- nothing Omar offers (Distributed systems serves Platform strategy) serves Priya.
select pg_temp.add_member('d1000000-0000-0000-0000-000000000004', 'priya@west.test', 'Priya Nair', 'Vancouver, BC',
  array['Career transition'], array['AI infrastructure']);
select pg_temp.add_member('e1000000-0000-0000-0000-000000000005', 'omar@north.test', 'Omar Haddad', 'Vancouver, BC',
  array['Applied AI products'], array['Distributed systems']);

select is(
  (select c.stage from private.matching_candidate_pairs('toronto, on', now(), 'a1000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000002') c),
  3::smallint,
  'two members who serve each other clear the floor'
);
select is(
  (select c.stage from private.matching_candidate_pairs('vancouver, bc', now(), 'd1000000-0000-0000-0000-000000000004', 'e1000000-0000-0000-0000-000000000005') c),
  2::smallint,
  'help in one direction only stays below the floor'
);
select is(private.run_matching_batch(1000), 1, 'the batch creates one introduction across both cities');
select is(
  (select count(*) from public.introductions i
   where i.member_a = 'a1000000-0000-0000-0000-000000000001' and i.member_b = 'b1000000-0000-0000-0000-000000000002'),
  1::bigint,
  'the serving pair is introduced despite different city formatting'
);
select is(
  (select count(*) from public.introductions i where 'd1000000-0000-0000-0000-000000000004' in (i.member_a, i.member_b)),
  0::bigint,
  'a one-direction pair is never introduced'
);
select is(
  (select count(*) from public.notification_events e where e.kind = 'introduction_ready'
     and e.user_id in ('a1000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000002')),
  2::bigint,
  'each member of the pair receives one introduction-ready event'
);
select is(
  (select i.reason_for_a from public.introductions i where i.member_a = 'a1000000-0000-0000-0000-000000000001'),
  'You want to grow in platform strategy. Maya offers product strategy and can review a challenge. In their words: “Lessons from building product teams and developer platforms.” What Maya is working toward: “Help build a durable product company.”',
  'why Alex should meet names the served growth area, the serving contribution area, and Maya''s own words'
);
select is(
  (select i.reciprocal_for_a from public.introductions i where i.member_a = 'a1000000-0000-0000-0000-000000000001'),
  'Maya wants to grow in executive communication. You offer engineering leadership and can compare approaches. In your words: “Experience scaling distributed platforms and engineering organizations.”',
  'why Maya may want to meet Alex is written to Alex'
);
select is(
  (select i.reason_for_b from public.introductions i where i.member_a = 'a1000000-0000-0000-0000-000000000001'),
  'You want to grow in executive communication. Alex offers engineering leadership and can compare approaches. In their words: “Experience scaling distributed platforms and engineering organizations.” What Alex is working toward: “Build an engineering organization that turns AI capabilities into dependable products.”',
  'why Maya should meet names Alex''s serving area and words'
);
select is(
  (select i.reciprocal_for_b from public.introductions i where i.member_a = 'a1000000-0000-0000-0000-000000000001'),
  'Alex wants to grow in platform strategy. You offer product strategy and can review a challenge. In your words: “Lessons from building product teams and developer platforms.”',
  'why Alex may want to meet Maya is written to Maya'
);
select is(
  (select i.meeting_context from public.introductions i where i.member_a = 'a1000000-0000-0000-0000-000000000001'),
  'You are both in the same city and prefer coffee around Downtown / city centre. Confirm a public place together after mutual interest.',
  'the meeting context names a shared format and area'
);
select ok(
  not exists (
    select 1 from public.introductions i
    where i.reason_for_a || i.reason_for_b || i.reciprocal_for_a || i.reciprocal_for_b || i.meeting_context ~ '!'
       or i.reason_for_a || i.reason_for_b || i.reciprocal_for_a || i.reciprocal_for_b || i.meeting_context ~* '\m(match|matched|compatibility|score|swipe|deck|streak|AI-powered)\M'
  ),
  'explanations carry no exclamation point and no forbidden word'
);
select is(
  (select c.eligible_members || ':' || c.unmatched_partners_taken || ':' || c.pairs_above_floor || ':' || c.introductions_created
   from private.matching_run_cities c join private.matching_runs r on r.id = c.run_id
   where c.city_key = 'toronto, on' order by r.started_at desc limit 1),
  '3:1:2:1',
  'the Toronto record counts three eligible, one member whose partner was taken, two pairs above the floor, one introduction'
);
select is(
  (select c.eligible_members || ':' || c.unmatched_below_floor || ':' || c.pairs_above_floor || ':' || c.introductions_created
   from private.matching_run_cities c join private.matching_runs r on r.id = c.run_id
   where c.city_key = 'vancouver, bc' order by r.started_at desc limit 1),
  '2:2:0:0',
  'the Vancouver record counts two members below the floor and nothing created'
);

-- Empty free text omits its sentence; the reader is still addressed correctly.
select pg_temp.add_member('f1000000-0000-0000-0000-000000000006', 'quiet@solo.test', 'Quiet Person', 'Toronto, ON',
  array['Career transition'], array['Engineering leadership'], '{}'::text[], '', '');
-- Sam (Career transition, offers AI infrastructure) and Quiet serve each other? Quiet offers
-- Engineering leadership, which serves Career transition; Sam offers AI infrastructure, which
-- serves nothing Quiet wants, so they stay below the floor. Give Quiet a growth area Sam serves.
update public.profiles set growth_areas = array['Applied AI products'] where id = 'f1000000-0000-0000-0000-000000000006';
select is(private.run_matching_batch(1000), 1, 'a second batch introduces the remaining serving pair');
select is(
  (select i.reason_for_a from public.introductions i
   where i.member_a = 'c1000000-0000-0000-0000-000000000003' and i.member_b = 'f1000000-0000-0000-0000-000000000006'),
  'You want to grow in career transition. Quiet offers engineering leadership.',
  'empty words and ambition drop their sentences'
);
select is(
  (select i.reciprocal_for_a from public.introductions i
   where i.member_a = 'c1000000-0000-0000-0000-000000000003' and i.member_b = 'f1000000-0000-0000-0000-000000000006'),
  'Quiet wants to grow in applied AI products. You offer AI infrastructure and can share lessons learned.',
  'an acronym keeps its case and the help format is lower-cased'
);

-- The read model serves each member their own two explanations.
set local role authenticated;
select set_config('request.jwt.claim.sub', 'a1000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is(
  public.get_current_introduction()->>'reason_for_you',
  (select i.reason_for_a from public.introductions i where i.member_a = 'a1000000-0000-0000-0000-000000000001'),
  'member A reads why they should meet from their own explanation'
);
select is(
  public.get_current_introduction()->>'reason_for_them',
  (select i.reciprocal_for_a from public.introductions i where i.member_a = 'a1000000-0000-0000-0000-000000000001'),
  'member A reads why the other may want to meet them from their own reciprocal explanation'
);
select set_config('request.jwt.claim.sub', 'b1000000-0000-0000-0000-000000000002', true);
select is(
  public.get_current_introduction()->>'reason_for_you',
  (select i.reason_for_b from public.introductions i where i.member_a = 'a1000000-0000-0000-0000-000000000001'),
  'member B reads why they should meet from their own explanation'
);
select is(
  public.get_current_introduction()->>'reason_for_them',
  (select i.reciprocal_for_b from public.introductions i where i.member_a = 'a1000000-0000-0000-0000-000000000001'),
  'member B reads their own reciprocal explanation'
);
reset role;
select pg_temp.retire_all();

-- Meeting overlap and the flexible wildcard.
select pg_temp.add_member('a2000000-0000-0000-0000-000000000001', 'lunch@north.test', 'Lunch Only', 'Toronto, ON',
  array['Engineering leadership'], array['Engineering leadership']);
select pg_temp.add_member('b2000000-0000-0000-0000-000000000002', 'evening@south.test', 'Evening Only', 'Toronto, ON',
  array['Engineering leadership'], array['Engineering leadership']);
update public.meeting_preferences set windows = array['Lunch'] where user_id = 'a2000000-0000-0000-0000-000000000001';
update public.meeting_preferences set windows = array['After work'] where user_id = 'b2000000-0000-0000-0000-000000000002';
select is(private.run_matching_batch(1000), 0, 'no shared window means no introduction');
select is(
  (select c.unmatched_no_meeting_overlap from private.matching_run_cities c join private.matching_runs r on r.id = c.run_id
   where c.city_key = 'toronto, on' order by r.started_at desc limit 1),
  2,
  'both members are recorded as lacking meeting overlap'
);
update public.meeting_preferences set windows = array['Lunch', 'After work'], areas = array['Flexible within the city']
where user_id = 'a2000000-0000-0000-0000-000000000001';
update public.meeting_preferences set windows = array['Lunch', 'After work'], areas = array['West side']
where user_id = 'b2000000-0000-0000-0000-000000000002';
select is(private.run_matching_batch(1000), 1, 'flexible within the city overlaps any area');
select is(
  (select i.meeting_context from public.introductions i where i.member_a = 'a2000000-0000-0000-0000-000000000001'),
  'You are both in the same city and prefer coffee around West side. Confirm a public place together after mutual interest.',
  'the meeting context names the other member''s area when one member is flexible'
);
select pg_temp.retire_all();

-- Exceptional introductions only: a stronger floor and 28-day spacing.
select pg_temp.add_member('a3000000-0000-0000-0000-000000000001', 'rare@north.test', 'Rare Member', 'Toronto, ON',
  array['Platform strategy'], array['Scaling teams']);
update public.networking_preferences set frequency = 'exceptional_only' where user_id = 'a3000000-0000-0000-0000-000000000001';
select pg_temp.add_member('b3000000-0000-0000-0000-000000000002', 'adjacent@south.test', 'Adjacent Fit', 'Toronto, ON',
  array['Engineering leadership'], array['Developer tools']);
select is(private.run_matching_batch(1000), 0, 'an adjacent-only pair is not enough for an exceptional-only member');
select pg_temp.add_member('c3000000-0000-0000-0000-000000000003', 'same@east.test', 'Same Fit', 'Toronto, ON',
  array['Scaling teams'], array['Platform strategy']);
select is(private.run_matching_batch(1000), 1, 'a same-term pair in both directions with a shared goal clears the exceptional floor');
select is(
  (select count(*) from public.introductions i
   where i.member_a = 'a3000000-0000-0000-0000-000000000001' and i.member_b = 'c3000000-0000-0000-0000-000000000003'),
  1::bigint,
  'the exceptional-only member is introduced to the same-term pair'
);
update public.introductions set created_at = now() - interval '20 days', expires_at = now() - interval '13 days', status = 'expired'
where member_a = 'a3000000-0000-0000-0000-000000000001';
select is(
  (select count(*) from private.matching_eligible_members(now()) e where e.user_id = 'a3000000-0000-0000-0000-000000000001'),
  0::bigint,
  'an exceptional-only member waits 28 days between introductions'
);
update public.introductions set created_at = now() - interval '29 days' where member_a = 'a3000000-0000-0000-0000-000000000001';
select is(
  (select count(*) from private.matching_eligible_members(now()) e where e.user_id = 'a3000000-0000-0000-0000-000000000001'),
  1::bigint,
  'after 28 days the exceptional-only member is eligible again'
);
select pg_temp.retire_all();

-- Story 2: one introduction at a time, then the next ---------------------------------------------

select pg_temp.add_member('a4000000-0000-0000-0000-000000000001', 'one@north.test', 'Member One', 'Toronto, ON',
  array['Engineering leadership'], array['Engineering leadership']);
select pg_temp.add_member('b4000000-0000-0000-0000-000000000002', 'two@south.test', 'Member Two', 'Toronto, ON',
  array['Engineering leadership'], array['Engineering leadership']);
select pg_temp.add_member('c4000000-0000-0000-0000-000000000003', 'three@east.test', 'Member Three', 'Toronto, ON',
  array['Engineering leadership'], array['Engineering leadership']);
insert into public.introductions (id, member_a, member_b, reason_for_a, reason_for_b, reciprocal_for_a, reciprocal_for_b, meeting_context, status, created_at, expires_at)
values ('e4000000-0000-0000-0000-000000000004', 'a4000000-0000-0000-0000-000000000001', 'b4000000-0000-0000-0000-000000000002',
  'r', 'r', 'r', 'r', 'm', 'mutual', now() - interval '3 days', now() + interval '4 days');
insert into public.conversations (id, introduction_id, member_a, member_b)
values ('f4000000-0000-0000-0000-000000000005', 'e4000000-0000-0000-0000-000000000004', 'a4000000-0000-0000-0000-000000000001', 'b4000000-0000-0000-0000-000000000002');
select is(private.run_matching_batch(1000), 0, 'a mutual introduction younger than seven days blocks both members');
update public.introductions set created_at = now() - interval '8 days', expires_at = now() - interval '1 day'
where id = 'e4000000-0000-0000-0000-000000000004';
select is(private.run_matching_batch(1000), 1, 'after its expiry a mutual introduction no longer blocks its members');
select is((select i.status from public.introductions i where i.id = 'e4000000-0000-0000-0000-000000000004'), 'mutual', 'the mutual introduction keeps its status');
select is((select c.status from public.conversations c where c.id = 'f4000000-0000-0000-0000-000000000005'), 'active', 'the conversation is untouched');
select is(
  (select count(*) from public.notification_events e where e.kind <> 'introduction_ready'),
  0::bigint,
  'nothing is sent about the expiry'
);
select pg_temp.retire_all();

-- A passed-on introduction frees the passer at their cadence and keeps blocking the waiting member.
select pg_temp.add_member('a5000000-0000-0000-0000-000000000001', 'passer@north.test', 'Passer', 'Toronto, ON',
  array['Engineering leadership'], array['Engineering leadership']);
select pg_temp.add_member('b5000000-0000-0000-0000-000000000002', 'waiter@south.test', 'Waiter', 'Toronto, ON',
  array['Engineering leadership'], array['Engineering leadership']);
select pg_temp.add_member('c5000000-0000-0000-0000-000000000003', 'third@east.test', 'Third', 'Toronto, ON',
  array['Engineering leadership'], array['Engineering leadership']);
insert into public.introductions (id, member_a, member_b, reason_for_a, reason_for_b, meeting_context, status, created_at, expires_at)
values ('e5000000-0000-0000-0000-000000000004', 'a5000000-0000-0000-0000-000000000001', 'b5000000-0000-0000-0000-000000000002',
  'r', 'r', 'm', 'offered', now() - interval '2 days', now() + interval '5 days');
insert into public.introduction_responses (introduction_id, user_id, decision)
values ('e5000000-0000-0000-0000-000000000004', 'a5000000-0000-0000-0000-000000000001', 'pass');
select is(private.run_matching_batch(1000), 0, 'a member who passed two days ago still waits for their weekly cadence');
update public.introductions set created_at = now() - interval '8 days', expires_at = now() + interval '1 day'
where id = 'e5000000-0000-0000-0000-000000000004';
select is(private.run_matching_batch(1000), 1, 'once the cadence has passed the member who passed is introduced again');
select is(
  (select count(*) from public.introductions i
   where i.member_a = 'a5000000-0000-0000-0000-000000000001' and i.member_b = 'c5000000-0000-0000-0000-000000000003'),
  1::bigint,
  'the passer is introduced to the third member'
);
select is(
  (select count(*) from public.introductions i where 'b5000000-0000-0000-0000-000000000002' in (i.member_a, i.member_b)),
  1::bigint,
  'the waiting member keeps exactly one active introduction'
);
select pg_temp.retire_all();

-- The 180-day rule, blocks, cadence windows, pause, and membership.
select pg_temp.add_member('a6000000-0000-0000-0000-000000000001', 'again@north.test', 'Again', 'Toronto, ON',
  array['Engineering leadership'], array['Engineering leadership']);
select pg_temp.add_member('b6000000-0000-0000-0000-000000000002', 'repeat@south.test', 'Repeat', 'Toronto, ON',
  array['Engineering leadership'], array['Engineering leadership']);
insert into public.introductions (member_a, member_b, reason_for_a, reason_for_b, meeting_context, status, created_at, expires_at)
values ('a6000000-0000-0000-0000-000000000001', 'b6000000-0000-0000-0000-000000000002', 'r', 'r', 'm', 'expired', now() - interval '100 days', now() - interval '93 days');
select is(private.run_matching_batch(1000), 0, 'a pair introduced 100 days ago is not introduced again');
update public.introductions set created_at = now() - interval '181 days', expires_at = now() - interval '174 days'
where member_a = 'a6000000-0000-0000-0000-000000000001';
insert into public.blocks (blocker_id, blocked_id) values ('a6000000-0000-0000-0000-000000000001', 'b6000000-0000-0000-0000-000000000002');
select is(private.run_matching_batch(1000), 0, 'a blocked pair is never introduced');
select is(
  (select c.unmatched_all_excluded from private.matching_run_cities c join private.matching_runs r on r.id = c.run_id
   where c.city_key = 'toronto, on' order by r.started_at desc limit 1),
  2,
  'both members are recorded as having every candidate excluded'
);
delete from public.blocks where blocker_id = 'a6000000-0000-0000-0000-000000000001';
select is(private.run_matching_batch(1000), 1, 'after 180 days and without a block the pair may be introduced again');
select pg_temp.retire_all();

select pg_temp.add_member('a7000000-0000-0000-0000-000000000001', 'weekly@north.test', 'Weekly', 'Toronto, ON', array['Engineering leadership'], array['Engineering leadership']);
select pg_temp.add_member('b7000000-0000-0000-0000-000000000002', 'twice@south.test', 'Twice', 'Toronto, ON', array['Engineering leadership'], array['Engineering leadership']);
select pg_temp.add_member('c7000000-0000-0000-0000-000000000003', 'monthly@east.test', 'Monthly', 'Toronto, ON', array['Engineering leadership'], array['Engineering leadership']);
select pg_temp.add_member('d7000000-0000-0000-0000-000000000004', 'paused@west.test', 'Paused', 'Toronto, ON', array['Engineering leadership'], array['Engineering leadership']);
select pg_temp.add_member('e7000000-0000-0000-0000-000000000005', 'lapsed@solo.test', 'Lapsed', 'Toronto, ON', array['Engineering leadership'], array['Engineering leadership']);
update public.networking_preferences set frequency = 'twice_monthly' where user_id = 'b7000000-0000-0000-0000-000000000002';
update public.networking_preferences set frequency = 'monthly' where user_id = 'c7000000-0000-0000-0000-000000000003';
update public.networking_preferences set frequency = 'paused' where user_id = 'd7000000-0000-0000-0000-000000000004';
update private.memberships set trial_started_at = now() - interval '2 months', trial_ends_at = now() - interval '1 month', status = 'expired'
where user_id = 'e7000000-0000-0000-0000-000000000005';
-- Each of the first three had an introduction with an outsider ten days ago.
select pg_temp.add_member('f7000000-0000-0000-0000-000000000006', 'outsider@solo.test', 'Outsider', 'Ottawa, ON', array['Engineering leadership'], array['Engineering leadership']);
insert into public.introductions (member_a, member_b, reason_for_a, reason_for_b, meeting_context, status, created_at, expires_at) values
  ('a7000000-0000-0000-0000-000000000001', 'f7000000-0000-0000-0000-000000000006', 'r', 'r', 'm', 'expired', now() - interval '10 days', now() - interval '3 days'),
  ('b7000000-0000-0000-0000-000000000002', 'f7000000-0000-0000-0000-000000000006', 'r', 'r', 'm', 'expired', now() - interval '10 days', now() - interval '3 days'),
  ('c7000000-0000-0000-0000-000000000003', 'f7000000-0000-0000-0000-000000000006', 'r', 'r', 'm', 'expired', now() - interval '10 days', now() - interval '3 days');
select is(
  (select string_agg(left(e.user_id::text, 8), ',' order by e.user_id) from private.matching_eligible_members(now()) e),
  'a7000000,f7000000',
  'ten days on, only the weekly member and the outsider are eligible; twice-monthly, monthly, paused, and lapsed members are not'
);
update public.introductions set created_at = now() - interval '15 days' where member_a = 'b7000000-0000-0000-0000-000000000002';
update public.introductions set created_at = now() - interval '29 days' where member_a = 'c7000000-0000-0000-0000-000000000003';
select is(
  (select string_agg(left(e.user_id::text, 8), ',' order by e.user_id) from private.matching_eligible_members(now()) e),
  'a7000000,b7000000,c7000000,f7000000',
  'after 14 and 28 days the twice-monthly and monthly members are eligible'
);
select is(
  (select round(e.wait_days) from private.matching_eligible_members(now()) e where e.user_id = 'c7000000-0000-0000-0000-000000000003'),
  29::numeric,
  'waiting time is measured from the most recent introduction'
);
select is(
  (select e.wait_bonus from private.matching_eligible_members(now()) e where e.user_id = 'c7000000-0000-0000-0000-000000000003'),
  0.150000,
  'the waiting bonus is capped at 28 days'
);
select pg_temp.retire_all();

-- Commit re-validates every pair.
select pg_temp.add_member('a8000000-0000-0000-0000-000000000001', 'guard-one@north.test', 'Guard One', 'Toronto, ON', array['Engineering leadership'], array['Engineering leadership']);
select pg_temp.add_member('b8000000-0000-0000-0000-000000000002', 'guard-two@south.test', 'Guard Two', 'Toronto, ON', array['Engineering leadership'], array['Engineering leadership']);
select pg_temp.add_member('c8000000-0000-0000-0000-000000000003', 'guard-three@east.test', 'Guard Three', 'Toronto, ON', array['Applied AI products'], array['AI infrastructure']);
insert into private.matching_runs (id, requested_limit) values ('e8000000-0000-0000-0000-000000000009', 1000);
insert into public.blocks (blocker_id, blocked_id) values ('b8000000-0000-0000-0000-000000000002', 'a8000000-0000-0000-0000-000000000001');
select is(
  (select c.created || ':' || c.dropped from private.commit_matching_pairs('e8000000-0000-0000-0000-000000000009', 'toronto, on',
    '[{"a":"a8000000-0000-0000-0000-000000000001","b":"b8000000-0000-0000-0000-000000000002","weight":2.0},
      {"a":"a8000000-0000-0000-0000-000000000001","b":"c8000000-0000-0000-0000-000000000003","weight":2.0},
      {"a":"not a uuid","b":"c8000000-0000-0000-0000-000000000003"}]'::jsonb, now()) c),
  '0:3',
  'a blocked pair, a pair below the floor, and a malformed pair are all dropped at commit'
);
delete from public.blocks where blocker_id = 'b8000000-0000-0000-0000-000000000002';
select is(
  (select c.created || ':' || c.dropped from private.commit_matching_pairs('e8000000-0000-0000-0000-000000000009', 'toronto, on',
    '[{"b":"a8000000-0000-0000-0000-000000000001","a":"b8000000-0000-0000-0000-000000000002","weight":2.0}]'::jsonb, now()) c),
  '1:0',
  'a valid pair is created whatever the order of its members'
);
select is(
  (select c.created || ':' || c.dropped from private.commit_matching_pairs('e8000000-0000-0000-0000-000000000009', 'toronto, on',
    '[{"a":"a8000000-0000-0000-0000-000000000001","b":"b8000000-0000-0000-0000-000000000002","weight":2.0}]'::jsonb, now()) c),
  '0:1',
  'a pair whose members now hold an introduction is dropped'
);
select ok(private.matching_pair_is_valid('a8000000-0000-0000-0000-000000000001', 'c8000000-0000-0000-0000-000000000003', now()) is false, 'validity re-evaluates the floor');
select pg_temp.retire_all();

-- Story 3: a daily batch that treats the city fairly ------------------------------------------------

select pg_temp.add_member('a9000000-0000-0000-0000-000000000001', 'centre@north.test', 'Centre', 'Toronto, ON', array['Platform strategy'], array['Scaling teams']);
select pg_temp.add_member('b9000000-0000-0000-0000-000000000002', 'patient@south.test', 'Patient', 'Toronto, ON', array['Engineering leadership'], array['Developer tools']);
select pg_temp.add_member('c9000000-0000-0000-0000-000000000003', 'recent@south.test', 'Recent', 'Toronto, ON', array['Engineering leadership'], array['Developer tools']);
update private.memberships set trial_started_at = now() - interval '30 days' where user_id = 'b9000000-0000-0000-0000-000000000002';
update private.memberships set trial_started_at = now() - interval '1 day' where user_id = 'c9000000-0000-0000-0000-000000000003';
select is(
  (select c.weight from private.matching_candidate_pairs('toronto, on', now(), 'a9000000-0000-0000-0000-000000000001', 'b9000000-0000-0000-0000-000000000002') c)
    - (select c.weight from private.matching_candidate_pairs('toronto, on', now(), 'a9000000-0000-0000-0000-000000000001', 'c9000000-0000-0000-0000-000000000003') c),
  0.150000 - round(0.15 * least(28, 1) / 28, 6),
  'equal fit differs only by the bounded waiting bonus'
);
select is(private.run_matching_batch(1000), 1, 'a member with two possible partners receives exactly one introduction');
select is(
  (select count(*) from public.introductions i
   where i.member_a = 'a9000000-0000-0000-0000-000000000001' and i.member_b = 'b9000000-0000-0000-0000-000000000002'),
  1::bigint,
  'with equal fit the longer-waiting member is introduced'
);
select pg_temp.retire_all();

select pg_temp.add_member('a9100000-0000-0000-0000-000000000001', 'centre-strong@north.test', 'Centre', 'Toronto, ON', array['Platform strategy'], array['Scaling teams']);
select pg_temp.add_member('b9100000-0000-0000-0000-000000000002', 'patient-strong@south.test', 'Patient', 'Toronto, ON', array['Engineering leadership'], array['Developer tools']);
select pg_temp.add_member('c9100000-0000-0000-0000-000000000003', 'stronger@south.test', 'Stronger', 'Toronto, ON', array['Engineering leadership'], array['Platform strategy']);
update private.memberships set trial_started_at = now() - interval '60 days' where user_id = 'b9100000-0000-0000-0000-000000000002';
select is(private.run_matching_batch(1000), 1, 'one introduction is created');
select is(
  (select count(*) from public.introductions i
   where i.member_a = 'a9100000-0000-0000-0000-000000000001' and i.member_b = 'c9100000-0000-0000-0000-000000000003'),
  1::bigint,
  'a same-term fit beats a longer wait'
);
select pg_temp.retire_all();

select pg_temp.add_member('a9200000-0000-0000-0000-000000000001', 'waiting@north.test', 'Waiting Long', 'Toronto, ON', array['Applied AI products'], array['Distributed systems']);
select pg_temp.add_member('b9200000-0000-0000-0000-000000000002', 'partial@south.test', 'Partial', 'Toronto, ON', array['Career transition'], array['AI infrastructure']);
update private.memberships set trial_started_at = now() - interval '90 days' where user_id = 'a9200000-0000-0000-0000-000000000001';
select is(private.run_matching_batch(1000), 0, 'waiting never admits a pair below the floor');
select pg_temp.retire_all();

select pg_temp.add_member('a9300000-0000-0000-0000-000000000001', 'alone@north.test', 'Alone', 'Halifax, NS', array['Engineering leadership'], array['Engineering leadership']);
select pg_temp.add_member('b9300000-0000-0000-0000-000000000002', 'far@south.test', 'Far Away', 'Austin, TX', array['Engineering leadership'], array['Engineering leadership']);
select is(private.run_matching_batch(1000), 0, 'members in different cities are never paired');
select is(
  (select string_agg(c.city_key || '=' || c.unmatched_no_peers, ',' order by c.city_key)
   from private.matching_run_cities c join private.matching_runs r on r.id = c.run_id
   where r.started_at = (select max(started_at) from private.matching_runs)),
  'austin, tx=1,halifax, ns=1',
  'a city with one eligible member records that member as having no peers'
);
select is(
  (select r.status || ':' || r.introductions_created from private.matching_runs r order by r.started_at desc limit 1),
  'completed:0',
  'a batch that creates nothing is still a completed run'
);
select ok(
  not exists (select 1 from private.pending_operations_alerts() a where a.fingerprint like 'matching_stalled:%'),
  'a recorded run keeps the stalled alert quiet'
);
select pg_temp.retire_all();

select pg_temp.add_member('a9400000-0000-0000-0000-000000000001', 'd1@north.test', 'D One', 'Toronto, ON', array['Engineering leadership'], array['Engineering leadership']);
select pg_temp.add_member('b9400000-0000-0000-0000-000000000002', 'd2@south.test', 'D Two', 'Toronto, ON', array['Engineering leadership'], array['Scaling teams']);
select pg_temp.add_member('c9400000-0000-0000-0000-000000000003', 'd3@east.test', 'D Three', 'Toronto, ON', array['Executive communication'], array['Engineering leadership']);
select pg_temp.add_member('d9400000-0000-0000-0000-000000000004', 'd4@west.test', 'D Four', 'Toronto, ON', array['Engineering leadership'], array['Fundraising']);
select pg_temp.add_member('e9400000-0000-0000-0000-000000000005', 'd5@solo.test', 'D Five', 'Toronto, ON', array['Career transition'], array['Scaling teams']);
select is(
  (select string_agg(left(s.member_a::text, 8) || '-' || left(s.member_b::text, 8) || '@' || s.weight, ',' order by s.member_a, s.member_b)
   from private.select_matching_pairs('toronto, on', now(), 1000) s),
  (select string_agg(left(s.member_a::text, 8) || '-' || left(s.member_b::text, 8) || '@' || s.weight, ',' order by s.member_a, s.member_b)
   from private.select_matching_pairs('toronto, on', now(), 1000) s),
  'selection over identical data is identical'
);
select is(
  (select count(*) from private.select_matching_pairs('toronto, on', now(), 1) s),
  1::bigint,
  'the per-city cap bounds the selection'
);
select is(
  (select count(distinct m) from (
     select s.member_a as m from private.select_matching_pairs('toronto, on', now(), 1000) s
     union all select s.member_b from private.select_matching_pairs('toronto, on', now(), 1000) s) x),
  (select 2 * count(*) from private.select_matching_pairs('toronto, on', now(), 1000) s),
  'no member appears in two selected pairs'
);
select pg_temp.retire_all();

-- The operations path runs the same batch for the service role only.
select pg_temp.add_member('a9500000-0000-0000-0000-000000000001', 'm1@north.test', 'Manual One', 'Toronto, ON', array['Engineering leadership'], array['Engineering leadership']);
select pg_temp.add_member('b9500000-0000-0000-0000-000000000002', 'm2@south.test', 'Manual Two', 'Toronto, ON', array['Engineering leadership'], array['Engineering leadership']);
set local role authenticated;
select set_config('request.jwt.claim.sub', 'a9500000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok($$select public.run_matching_now()$$, '42501', null, 'a member cannot run matching on demand');
reset role;
set local role service_role;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.role', 'service_role', true);
select is(public.run_matching_now()->>'status', 'completed', 'the service role runs the batch on demand');
select is((public.run_matching_now()->>'introductions_created')::integer, 0, 'a second run on demand creates nothing more');
reset role;
select is((select count(*) from public.introductions i where i.matching_run_id is not null and i.member_a = 'a9500000-0000-0000-0000-000000000001'), 1::bigint, 'the on-demand run created the introduction and recorded its run');
select pg_temp.retire_all();

-- Story 4: operations can see why --------------------------------------------------------------------

select pg_temp.add_member('a9600000-0000-0000-0000-000000000001', 'o1@north.test', 'Paired One', 'Toronto, ON', array['Engineering leadership'], array['Engineering leadership']);
select pg_temp.add_member('b9600000-0000-0000-0000-000000000002', 'o2@south.test', 'Paired Two', 'Toronto, ON', array['Engineering leadership'], array['Engineering leadership']);
select pg_temp.add_member('c9600000-0000-0000-0000-000000000003', 'o3@solo.test', 'Own Company Only', 'Toronto, ON', array['Engineering leadership'], array['Engineering leadership']);
update public.networking_preferences set cross_company = false where user_id = 'c9600000-0000-0000-0000-000000000003';
select pg_temp.add_member('d9600000-0000-0000-0000-000000000004', 'o4@east.test', 'Afternoons Only', 'Toronto, ON', array['Engineering leadership'], array['Engineering leadership']);
update public.meeting_preferences set windows = array['Afternoon'] where user_id = 'd9600000-0000-0000-0000-000000000004';
select pg_temp.add_member('e9600000-0000-0000-0000-000000000005', 'o5@west.test', 'One Direction', 'Toronto, ON', array['Applied AI products'], array['AI infrastructure']);
select pg_temp.add_member('f9600000-0000-0000-0000-000000000006', 'o6@east.test', 'Partner Taken', 'Toronto, ON', array['Engineering leadership'], array['Scaling teams']);
select is(private.run_matching_batch(1000), 1, 'the operations fixture creates one introduction');
select is(
  (select c.eligible_members || ':' || c.unmatched_no_peers || ':' || c.unmatched_all_excluded || ':' || c.unmatched_no_meeting_overlap || ':'
     || c.unmatched_below_floor || ':' || c.unmatched_partners_taken || ':' || c.pairs_above_floor || ':' || c.pairs_dropped_at_commit || ':'
     || c.introductions_created
   from private.matching_run_cities c join private.matching_runs r on r.id = c.run_id
   where c.city_key = 'toronto, on' order by r.started_at desc limit 1),
  '6:0:1:1:1:1:3:0:1',
  'the run record counts every unmatched reason'
);
select ok(
  (select c.total_weight from private.matching_run_cities c join private.matching_runs r on r.id = c.run_id
   where c.city_key = 'toronto, on' order by r.started_at desc limit 1) > 0,
  'the run record keeps the total weight of created pairs'
);
-- Retention: an old run takes its city records with it.
insert into private.matching_runs (id, started_at, completed_at, requested_limit, status)
values ('e9600000-0000-0000-0000-000000000099', now() - interval '200 days', now() - interval '200 days', 1000, 'completed');
insert into private.matching_run_cities (run_id, city_key, eligible_members) values ('e9600000-0000-0000-0000-000000000099', 'toronto, on', 2);
select lives_ok($$select private.run_retention_maintenance()$$, 'retention maintenance runs with the run city records');
select is((select count(*) from private.matching_runs r where r.id = 'e9600000-0000-0000-0000-000000000099'), 0::bigint, 'runs older than 180 days are removed');
select is((select count(*) from private.matching_run_cities c where c.run_id = 'e9600000-0000-0000-0000-000000000099'), 0::bigint, 'their city records are removed with them');
select ok(
  exists (select 1 from private.matching_run_cities c join private.matching_runs r on r.id = c.run_id where r.started_at > now() - interval '1 day'),
  'recent city records are kept'
);
select pg_temp.retire_all();

select * from finish();
rollback;
