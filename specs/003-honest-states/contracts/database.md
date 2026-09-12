# Database Contracts: Honest States

Migration `supabase/migrations/20260912130000_private_pass.sql`. No schema change; four
functions.

## `private.introduction_passed_by(p_introduction_id uuid, p_user_id uuid) returns boolean`

- `language sql stable security definer set search_path = ''`.
- True when `public.introduction_responses` holds a `pass` by that member for that
  introduction.
- `revoke all ... from public, anon, authenticated, service_role`.

## `public.respond_to_introduction(p_introduction_id uuid, p_decision text) returns jsonb`

Unchanged checks: authentication, valid decision, membership of the pair, `status = 'offered'`
and not expired, no block, one response per member ("Response already recorded").

New outcomes, given the other member's recorded decision:

| Caller's decision | Other member | Effect on `status` | Returns |
|-------------------|--------------|--------------------|---------|
| `pass` | none or `interested` | unchanged (`offered`) | `{"state":"not_mutual"}` |
| `pass` | `pass` | `closed` | `{"state":"not_mutual"}` |
| `interested` | none | unchanged | `{"state":"waiting"}` |
| `interested` | `pass` | unchanged | `{"state":"waiting"}` |
| `interested` | `interested` | `mutual`; conversation created; two `mutual_interest` events | `{"state":"mutual","conversation_id":…}` |

Grants unchanged: execute revoked from `public`, `anon`; granted to `authenticated`.

## `public.get_current_introduction() returns jsonb`

Same body as before with one more predicate: `and not private.introduction_passed_by(i.id, caller)`.
A member who passed reads `null`; the other member reads the introduction with its original
`status` and `expires_at` and their own `your_response`.

## `private.generate_one_introduction() returns uuid`

Same body as before with the active-introduction predicate changed to:

```sql
and not exists (
  select 1 from public.introductions active_i
  where active_i.status in ('offered', 'mutual')
    and (
      (p1.id in (active_i.member_a, active_i.member_b)
        and not private.introduction_passed_by(active_i.id, p1.id))
      or (p2.id in (active_i.member_a, active_i.member_b)
        and not private.introduction_passed_by(active_i.id, p2.id))
    )
)
```

Everything else (city, membership access, cadence, blocks, 180-day pair rule, scoring,
`introduction_ready` events) is unchanged.

## Expiry (unchanged)

`private.run_matching_batch` and `private.run_retention_maintenance` keep setting
`status = 'expired'` where `status = 'offered' and expires_at <= now()`. This is the only
way a waiting member's introduction ends without mutual interest or a block.

## pgTAP: `supabase/tests/database/introduction_privacy.test.sql`

Fixture: three Toronto members through `auth.users` (the existing matching fixture shape),
an `offered` introduction between the first two created eight days ago and expiring in one
day. Assertions cover the table above, the read model for both members, matching eligibility
(the passer pairs with the third member; the waiting member does not), both-pass closing,
expiry through retention, the stale response error, the mutual path, and privileges on the
helper.
