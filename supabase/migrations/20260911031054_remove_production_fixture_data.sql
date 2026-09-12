-- Remove only identities that can be proven to originate from repository
-- fixtures. Do not classify incomplete onboarding or inactivity as garbage:
-- those can represent real members returning later.

create temporary table production_fixture_users (
  id uuid primary key
) on commit drop;

insert into production_fixture_users (id)
select id
from auth.users
where lower(split_part(coalesce(email, ''), '@', 2)) in (
  'orbitsystems.com',
  'northstar.ai',
  'harbourlabs.com',
  'newventurelabs.ca'
)
or id in (
  '10000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000002',
  '30000000-0000-0000-0000-000000000003',
  '90000000-0000-0000-0000-000000000009',
  'a0000000-0000-0000-0000-00000000000a',
  'b0000000-0000-0000-0000-00000000000b',
  'd4ba70e6-867b-4a84-a9f9-b598e4a15550',
  'b697877e-57a3-4a9f-8d01-85770f426128',
  '17c6ef44-57f3-4a0c-9daf-138d304b5ae1'
);

do $$
declare
  fixture_count integer;
  deleted_count integer;
begin
  select count(*) into fixture_count from production_fixture_users;

  if exists (
    select 1
    from storage.objects object
    join production_fixture_users fixture on object.owner_id = fixture.id::text
  ) then
    raise exception 'Fixture cleanup stopped: remove owned Storage objects through the Storage API first';
  end if;

  delete from auth.users member
  using production_fixture_users fixture
  where member.id = fixture.id;
  get diagnostics deleted_count = row_count;

  if deleted_count <> fixture_count then
    raise exception 'Fixture cleanup deleted % of % expected Auth users', deleted_count, fixture_count;
  end if;

  raise notice 'Fixture cleanup removed % Auth users', deleted_count;
end;
$$;

delete from public.company_domains domain
where domain.domain in (
  'orbitsystems.com',
  'northstar.ai',
  'harbourlabs.com',
  'newventurelabs.ca'
)
and not exists (
  select 1 from public.profiles profile where profile.company_domain = domain.domain
);

-- Apply the already-reviewed retention policy immediately instead of waiting
-- for the next scheduled maintenance window.
select private.run_retention_maintenance();
