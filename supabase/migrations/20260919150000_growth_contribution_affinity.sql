-- Batch matching (feature 005), part one of two: the product-owned affinity registry between
-- the growth areas a member can choose and the contribution areas that serve them.
--
-- Growth areas and contribution areas are two different fixed lists that share one term, so
-- the reciprocity check that gates every introduction almost never fired. From here on a
-- contribution area serves a growth area when the two terms are identical (always 'same',
-- whether or not a row exists) or when this registry lists the pair. The registry is product
-- data, changed only by a migration as a product decision, like the company registry. It is
-- read only by the private matching functions. No operator step; re-runnable.

create table if not exists private.growth_contribution_affinity (
  growth_area text not null check (growth_area = btrim(growth_area) and growth_area <> ''),
  contribution_area text not null check (contribution_area = btrim(contribution_area) and contribution_area <> ''),
  strength text not null check (strength in ('same', 'adjacent')),
  created_at timestamptz not null default now(),
  primary key (growth_area, contribution_area)
);

revoke all on table private.growth_contribution_affinity from public, anon, authenticated;

insert into private.growth_contribution_affinity (growth_area, contribution_area, strength) values
  ('Applied AI products', 'AI infrastructure', 'adjacent'),
  ('Applied AI products', 'Product strategy', 'adjacent'),
  ('Executive communication', 'Engineering leadership', 'adjacent'),
  ('Executive communication', 'Scaling teams', 'adjacent'),
  ('Executive communication', 'Fundraising', 'adjacent'),
  ('Executive communication', 'Go-to-market', 'adjacent'),
  ('Engineering leadership', 'Engineering leadership', 'same'),
  ('Engineering leadership', 'Scaling teams', 'adjacent'),
  ('Platform strategy', 'Distributed systems', 'adjacent'),
  ('Platform strategy', 'Developer tools', 'adjacent'),
  ('Platform strategy', 'Product strategy', 'adjacent'),
  ('Product thinking', 'Product strategy', 'adjacent'),
  ('Product thinking', 'Go-to-market', 'adjacent'),
  ('Product thinking', 'Developer tools', 'adjacent'),
  ('Founder perspective', 'Fundraising', 'adjacent'),
  ('Founder perspective', 'Go-to-market', 'adjacent'),
  ('Founder perspective', 'Scaling teams', 'adjacent'),
  ('Career transition', 'Engineering leadership', 'adjacent'),
  ('Career transition', 'Product strategy', 'adjacent'),
  ('Career transition', 'Scaling teams', 'adjacent'),
  ('Local tech ecosystem', 'Fundraising', 'adjacent'),
  ('Local tech ecosystem', 'Go-to-market', 'adjacent'),
  ('Local tech ecosystem', 'Scaling teams', 'adjacent')
on conflict (growth_area, contribution_area) do nothing;

-- How well one member's contribution areas serve another member's growth areas. Counts how
-- many growth areas are served by an identical term ('same') and how many only by a registry
-- pair ('adjacent'), and names the pair to explain: the first growth area (in the member's
-- own order) served by a 'same' term, else the first served by an 'adjacent' one, with the
-- first contribution area (in the other member's order) that serves it. Empty input returns
-- zeros and nulls; it never raises.
do $$ begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace where n.nspname = 'private' and t.typname = 'growth_service_result') then
    create type private.growth_service_result as (
      same_count integer,
      adjacent_count integer,
      served_growth_area text,
      serving_contribution_area text
    );
  end if;
end $$;


create or replace function private.growth_service(p_growth text[], p_contribution text[])
returns private.growth_service_result
language sql
stable
security definer
set search_path = ''
as $$
  with growth as (
    select btrim(g.value) as growth_area, g.ordinality as growth_position
    from unnest(coalesce(p_growth, '{}'::text[])) with ordinality as g(value, ordinality)
    where btrim(g.value) <> ''
  ), contribution as (
    select btrim(c.value) as contribution_area, c.ordinality as contribution_position
    from unnest(coalesce(p_contribution, '{}'::text[])) with ordinality as c(value, ordinality)
    where btrim(c.value) <> ''
  ), served as (
    select
      growth.growth_area,
      growth.growth_position,
      contribution.contribution_area,
      contribution.contribution_position,
      case
        when lower(growth.growth_area) = lower(contribution.contribution_area) then 'same'
        else (
          select a.strength
          from private.growth_contribution_affinity a
          where lower(a.growth_area) = lower(growth.growth_area)
            and lower(a.contribution_area) = lower(contribution.contribution_area)
        )
      end as strength
    from growth
    cross join contribution
  ), best as (
    select
      growth_area,
      growth_position,
      min(case when strength = 'same' then contribution_position end) as same_position,
      min(case when strength = 'adjacent' then contribution_position end) as adjacent_position
    from served
    where strength is not null
    group by growth_area, growth_position
  ), ranked as (
    select
      b.growth_area,
      b.growth_position,
      case when b.same_position is not null then 'same' else 'adjacent' end as strength,
      coalesce(b.same_position, b.adjacent_position) as contribution_position
    from best b
  )
  select row(
    coalesce((select count(*) from ranked r where r.strength = 'same'), 0)::integer,
    coalesce((select count(*) from ranked r where r.strength = 'adjacent'), 0)::integer,
    (select r.growth_area from ranked r order by (r.strength <> 'same'), r.growth_position limit 1),
    (select c.contribution_area
     from ranked r
     join contribution c on c.contribution_position = r.contribution_position
     order by (r.strength <> 'same'), r.growth_position
     limit 1)
  )::private.growth_service_result;
$$;

revoke all on function private.growth_service(text[], text[]) from public, anon, authenticated, service_role;
