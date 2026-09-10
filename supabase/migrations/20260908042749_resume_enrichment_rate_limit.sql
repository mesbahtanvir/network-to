-- AI résumé processing is an authenticated, cost-bearing operation. Extend the
-- existing durable limiter so one account cannot trigger unbounded extraction.

alter table private.edge_rate_limits
  drop constraint edge_rate_limits_action_check;

alter table private.edge_rate_limits
  add constraint edge_rate_limits_action_check
  check (action in ('create', 'complete', 'claim', 'resume'));

create or replace function public.consume_edge_rate_limit(
  p_key_hash text,
  p_action text,
  p_limit integer,
  p_window_seconds integer
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare bucket timestamptz; current_attempts integer;
begin
  if p_key_hash !~ '^[0-9a-f]{64}$'
     or p_action not in ('create', 'complete', 'claim', 'resume')
     or p_limit not between 1 and 1000
     or p_window_seconds not between 60 and 86400 then
    raise exception 'Invalid rate limit request';
  end if;

  bucket := to_timestamp(
    floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds
  );
  delete from private.edge_rate_limits
    where window_start < now() - interval '2 days';

  insert into private.edge_rate_limits (key_hash, action, window_start, attempts)
  values (p_key_hash, p_action, bucket, 1)
  on conflict (key_hash, action, window_start) do update
    set attempts = private.edge_rate_limits.attempts + 1
  returning attempts into current_attempts;

  return current_attempts <= p_limit;
end;
$$;
