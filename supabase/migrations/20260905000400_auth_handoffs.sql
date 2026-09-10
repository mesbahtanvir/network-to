-- Short-lived PKCE handoffs let a work-laptop magic link complete sign-in on
-- the personal iPhone that initiated it. The stored authorization code is
-- single-use and cannot create a session without the verifier held by the app.
create table private.auth_handoffs (
  id uuid primary key,
  claim_secret_hash text not null check (claim_secret_hash ~ '^[0-9a-f]{64}$'),
  auth_code text check (auth_code is null or char_length(auth_code) between 16 and 2048),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '10 minutes'),
  completed_at timestamptz,
  constraint auth_handoffs_short_lived check (expires_at <= created_at + interval '15 minutes')
);

revoke all on table private.auth_handoffs from public, anon, authenticated;
grant all on table private.auth_handoffs to service_role;

create or replace function public.create_auth_handoff(
  p_id uuid,
  p_claim_secret_hash text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_claim_secret_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid claim secret hash';
  end if;

  delete from private.auth_handoffs where expires_at <= now();
  insert into private.auth_handoffs (id, claim_secret_hash)
  values (p_id, p_claim_secret_hash);
end;
$$;

create or replace function public.complete_auth_handoff(
  p_id uuid,
  p_auth_code text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  changed_rows integer;
begin
  if char_length(p_auth_code) not between 16 and 2048 then
    return false;
  end if;

  update private.auth_handoffs
  set auth_code = p_auth_code,
      completed_at = now()
  where id = p_id
    and auth_code is null
    and expires_at > now();
  get diagnostics changed_rows = row_count;
  return changed_rows = 1;
end;
$$;

create or replace function public.claim_auth_handoff(
  p_id uuid,
  p_claim_secret_hash text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  claimed_code text;
begin
  delete from private.auth_handoffs
  where id = p_id
    and claim_secret_hash = p_claim_secret_hash
    and auth_code is not null
    and expires_at > now()
  returning auth_code into claimed_code;

  return claimed_code;
end;
$$;

revoke execute on function public.create_auth_handoff(uuid, text) from public, anon, authenticated;
revoke execute on function public.complete_auth_handoff(uuid, text) from public, anon, authenticated;
revoke execute on function public.claim_auth_handoff(uuid, text) from public, anon, authenticated;
grant execute on function public.create_auth_handoff(uuid, text) to service_role;
grant execute on function public.complete_auth_handoff(uuid, text) to service_role;
grant execute on function public.claim_auth_handoff(uuid, text) to service_role;

