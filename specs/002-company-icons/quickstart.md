# Quickstart: validating Verified Company Marks

Prerequisites: Supabase CLI 2.117.0, Deno v2.5.2, Xcode 26 with the NetworkTo scheme. The
paths below are relative to the repository root.

## 1. Database

```bash
supabase db reset                      # applies both new migrations and the seed
supabase test db supabase/tests/database --local
```

Expected: every file passes; `company_marks.test.sql` reports its plan count with zero
`not ok` lines. Spot checks in `psql`:

```sql
select count(*) from public.companies where status = 'approved';        -- >= 200
select coverage_clause, count(*) from public.companies group by 1;       -- a, b, c, launch(6)
select public.validate_company_domain('servicenow.com')->>'decision';    -- eligible
select public.validate_company_domain('gmail.com')->>'decision';         -- ineligible
select jobname from cron.job where jobname like 'network-to-%';          -- five rows, unchanged
```

## 2. Edge Function

```bash
deno check supabase/functions/*/index.ts supabase/functions/_shared/*.ts
deno test supabase/functions
```

Locally, with `COMPANY_MARKS_JOB_SECRET` set in `supabase/functions/.env`:

```bash
supabase functions serve company-marks --no-verify-jwt --env-file supabase/functions/.env
curl -sS -X POST http://127.0.0.1:55321/functions/v1/company-marks \
  -H "x-job-secret: $COMPANY_MARKS_JOB_SECRET" -H "content-type: application/json" \
  -d '{"action":"populate","companies":["shopify","cohere"],"requested_by":"local"}'
curl -sS -X POST http://127.0.0.1:55321/functions/v1/company-marks \
  -H "x-job-secret: $COMPANY_MARKS_JOB_SECRET" -H "content-type: application/json" \
  -d '{"action":"status"}' | jq '.companies[] | select(.key=="shopify")'
```

Expected: the first call returns `status: running` or `completed`; the status call shows
`mark_status: available` with `mark_version: 1` for a company that publishes a ≥ 128 px icon,
or `no_icon_published` / `fetch_failed` with a reason otherwise. Re-running `populate` fetches
nothing and records `skipped_existing` or no items. Starting a second run while one is running
returns `status: skipped`.

Operator actions from the SQL editor (service role or `postgres`):

```sql
select public.set_company_mark_withheld('shopify', true);   -- members see the monogram
select public.request_company_mark_refresh('shopify');      -- next populate fetches a new version
select public.get_company_mark_overview();                  -- FR-026
```

## 3. iOS

1. Run the `NetworkTo` scheme tests (`Cmd-U`). `CompanyMarkTests` covers the monogram rule,
   caching through the mock backend, and clearing at sign-out.
2. Launch with the mock backend (`--messages-populated-preview`, `--connections-populated-preview`,
   `--profile-preview`): Sarah (Northstar AI) shows a mark; Orbit Systems and Harbour Labs show
   monograms `OS` and `HL`. Toggle dark appearance and the largest accessibility text size and
   confirm the tile stays the height of its line, nothing clips at 320 pt (iPhone SE), and
   VoiceOver reads each identity row exactly as before.
3. Against a Supabase project after `populate` ran: open the introduction, Messages, a
   conversation, Connections, and Profile; observe with Charles or the Network Link Conditioner
   that every image request goes to the project host, that a mark shows after being seen once
   while offline, and that signing out and back in shows monograms until marks are fetched
   again.

## 4. Hosted configuration (once per project)

```sql
select vault.create_secret('<random 256-bit secret>', 'company_marks_job_secret');
```

Set the same value as the `COMPANY_MARKS_JOB_SECRET` function secret in the Dashboard. The
deploy workflow deploys `company-marks` with `--no-verify-jwt`. Until the Vault secret exists,
the daily retention job simply skips the file purge.
