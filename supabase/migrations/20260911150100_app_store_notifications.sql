-- App Store Server Notifications v2 keep membership accurate while the app is
-- closed: renewals, billing retry, grace periods, cancellations, and refunds.
-- The Edge Function verifies Apple's signature; the database makes each
-- notification idempotent and ignores notifications that arrive out of order.

create table private.app_store_notifications (
  notification_uuid text primary key
    check (char_length(notification_uuid) between 8 and 128),
  notification_type text not null check (char_length(notification_type) between 1 and 64),
  subtype text check (subtype is null or char_length(subtype) <= 64),
  environment text not null check (environment in ('sandbox', 'production')),
  original_transaction_id text
    check (original_transaction_id is null or char_length(original_transaction_id) <= 128),
  user_id uuid references public.profiles(id) on delete set null,
  signed_at timestamptz not null,
  outcome text not null default 'received'
    check (outcome in ('received', 'applied', 'ignored', 'unmatched', 'stale', 'failed')),
  detail text check (detail is null or char_length(detail) <= 1000),
  received_at timestamptz not null default now()
);

create index app_store_notifications_transaction_idx
  on private.app_store_notifications (original_transaction_id, signed_at desc);
revoke all on table private.app_store_notifications from public, anon, authenticated;

-- A verified App Store transaction is the only way this function creates a
-- membership row. Paying members never need the free month, and a refund or
-- expiry notification for a member without a row must not start one.
create or replace function public.record_app_store_entitlement(
  p_user_id uuid,
  p_product_id text,
  p_original_transaction_id text,
  p_latest_transaction_id text,
  p_status text,
  p_access_ends_at timestamptz,
  p_auto_renews boolean,
  p_environment text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_product_id <> 'com.mesbahtanvir.networkto.monthly' then
    raise exception 'Unsupported product';
  end if;
  if p_status not in ('active', 'grace_period', 'billing_retry', 'expired', 'revoked') then
    raise exception 'Invalid subscription status';
  end if;
  if p_environment not in ('sandbox', 'production') then
    raise exception 'Invalid App Store environment';
  end if;

  insert into private.memberships (
    user_id,
    trial_started_at,
    trial_ends_at,
    status,
    product_id,
    original_transaction_id,
    latest_transaction_id,
    access_ends_at,
    auto_renews,
    environment,
    last_verified_at,
    updated_at
  ) values (
    p_user_id,
    now() - interval '1 month',
    now(),
    p_status,
    p_product_id,
    p_original_transaction_id,
    p_latest_transaction_id,
    p_access_ends_at,
    p_auto_renews,
    p_environment,
    now(),
    now()
  )
  on conflict (user_id) do update set
    status = excluded.status,
    product_id = excluded.product_id,
    original_transaction_id = excluded.original_transaction_id,
    latest_transaction_id = excluded.latest_transaction_id,
    access_ends_at = excluded.access_ends_at,
    auto_renews = excluded.auto_renews,
    environment = excluded.environment,
    last_verified_at = excluded.last_verified_at,
    updated_at = now();
end;
$$;

-- p_status is null for informational notifications; they are recorded and
-- ignored. The member is resolved from the appAccountToken the app attached at
-- purchase, falling back to the original transaction already on file.
create or replace function public.record_app_store_notification(
  p_notification_uuid text,
  p_notification_type text,
  p_subtype text,
  p_environment text,
  p_signed_at timestamptz,
  p_original_transaction_id text,
  p_latest_transaction_id text,
  p_app_account_token uuid,
  p_product_id text,
  p_status text,
  p_access_ends_at timestamptz,
  p_auto_renews boolean
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  member_id uuid;
  result_outcome text;
  failure_detail text;
begin
  if p_environment not in ('sandbox', 'production') then
    raise exception 'Invalid App Store environment';
  end if;
  if p_signed_at is null then raise exception 'Signed date required'; end if;

  insert into private.app_store_notifications (
    notification_uuid, notification_type, subtype, environment, original_transaction_id, signed_at
  ) values (
    p_notification_uuid, p_notification_type, p_subtype, p_environment, p_original_transaction_id, p_signed_at
  )
  on conflict (notification_uuid) do nothing;
  if not found then return 'duplicate'; end if;

  if p_status is null or p_original_transaction_id is null then
    result_outcome := 'ignored';
  elsif p_product_id is distinct from 'com.mesbahtanvir.networkto.monthly' then
    result_outcome := 'ignored';
    failure_detail := 'Unsupported product';
  else
    select p.id into member_id
    from public.profiles p
    where p.id = p_app_account_token;

    if member_id is null then
      select m.user_id into member_id
      from private.memberships m
      where m.original_transaction_id = p_original_transaction_id;
    end if;

    if member_id is null then
      result_outcome := 'unmatched';
    elsif exists (
      select 1 from private.app_store_notifications n
      where n.original_transaction_id = p_original_transaction_id
        and n.outcome = 'applied'
        and n.signed_at > p_signed_at
    ) then
      result_outcome := 'stale';
    else
      begin
        perform public.record_app_store_entitlement(
          member_id,
          p_product_id,
          p_original_transaction_id,
          coalesce(p_latest_transaction_id, p_original_transaction_id),
          p_status,
          p_access_ends_at,
          coalesce(p_auto_renews, false),
          p_environment
        );
        result_outcome := 'applied';
      exception when others then
        result_outcome := 'failed';
        failure_detail := left(sqlerrm, 1000);
      end;
    end if;
  end if;

  update private.app_store_notifications
  set user_id = member_id,
      outcome = result_outcome,
      detail = failure_detail
  where notification_uuid = p_notification_uuid;

  return result_outcome;
end;
$$;

revoke execute on function public.record_app_store_notification(
  text, text, text, text, timestamptz, text, text, uuid, text, text, timestamptz, boolean
) from public, anon, authenticated;
grant execute on function public.record_app_store_notification(
  text, text, text, text, timestamptz, text, text, uuid, text, text, timestamptz, boolean
) to service_role;
