# Quickstart: Batch Matching

## Backend, as CI runs it

```sh
supabase db reset && supabase test db      # with Docker Desktop and the Supabase CLI
deno check supabase/functions/*/index.ts supabase/functions/_shared/*.ts
```

The Supabase workflow's validate job runs the same on the pull request; every pgTAP file must
pass with its declared `plan(N)`. `batch_matching.test.sql` covers this feature; the adjusted
files prove nothing else regressed.

## Backend, without Docker

A throwaway Postgres 16 cluster with pgTAP (`postgresql-16-pgtap`, `pg_prove`) and stub packages
for `pg_cron`, `pg_net`, and `supabase_vault` (fake extension control files whose scripts create
`cron.job`, `cron.schedule`, `cron.unschedule`, `net.http_post`, `vault.secrets`,
`vault.decrypted_secrets`, `vault.create_secret`), plus `auth.users`, `auth.uid()`,
`auth.role()`, `storage.buckets`, `storage.objects`, `storage.foldername`, the roles `anon`,
`authenticated`, `service_role`, `supabase_auth_admin`, an `extensions` schema, and the
`supabase_realtime` publication. Each migration is applied with `psql -1` (one transaction, as
the CLI does), then `seed.sql`, then `pg_prove --ext .sql supabase/tests/database/`. This is what
validated feature 005 in the authoring environment; the workflow's validate job remains the
proof of record for the pull request.

## Scenario checks (SQL, local or staging)

1. **A worthwhile pair.** Two Toronto members whose contribution areas serve each other's
   growth areas and whose meeting preferences overlap. `select private.run_matching_batch(1000);`
   creates one introduction; `select reason_for_a, reciprocal_for_a from public.introductions`
   shows the served growth area, the serving contribution area, and the quoted words.
2. **One direction only.** Change one member's contribution areas so nothing serves the other:
   the next run creates nothing and `private.matching_run_cities` shows
   `unmatched_below_floor = 2`.
3. **Mutual bound.** Set an introduction to `mutual` with `expires_at` in the future: neither
   member is introduced; move `expires_at` to the past: both are eligible at the next run.
4. **Fairness.** Three members where one can be introduced to either of the other two with
   equal fit; the member with the older `trial_started_at` is chosen; make the other a `same`
   match and it wins instead.
5. **Exceptional only.** Set `frequency = 'exceptional_only'` for one member: an adjacent-only
   pair creates nothing; a `same` pair in both directions with a shared goal creates one,
   and not again within 28 days.
6. **Determinism.** Run the batch twice on the same fixture from a savepoint: the same pairs.
7. **Operations.** `select * from private.matching_run_cities order by created_at desc;`
   shows the counts; `select public.run_matching_now();` as the service role runs the batch on
   demand and returns the run id.

## Staging (two accounts)

1. Complete onboarding on two phones in the same city with serving growth and contribution
   areas. After the next 13:07 UTC run (or `run_matching_now` from the SQL editor as the
   service role), both phones receive "introduction ready" and Today shows the introduction
   with the new explanations.
2. Choose Interested on both: mutual interest, conversation, and the context strip read as
   before.
3. After the introduction's expiry, both members receive a new introduction at the next run
   when a partner exists; the conversation is unchanged.
