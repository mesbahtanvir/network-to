# Contract: database functions and read models

All functions are `security definer`, `set search_path = ''`, fully qualified, with
`revoke execute ... from public, anon, authenticated` followed by an explicit grant. Errors raise
with a short message and never distinguish "absent" from "not permitted".

## Member-facing (grant execute to `authenticated`)

### `public.get_own_company_mark() returns jsonb`

Returns an envelope holding the caller's mark reference or `null`. Raises `Authentication
required` when `auth.uid()` is null.

```json
{ "company_mark": { "key": "shopify", "version": 2, "path": "shopify/2.png" } }
```

### Read models that gain `company_mark`

- `private.public_profile(profile)` → `"company_mark": <reference|null>` beside `company_name`;
  used by `get_connections()` and `get_active_conversation()`.
- `public.get_current_introduction()` → `person.company_mark`.

The reference is produced by `private.company_mark_reference(p_domain text)`:
`null` unless `company_domains.company_key → companies.status = 'approved'` and
`companies.mark_status = 'available'` and `mark_path is not null`.

## Operations (grant execute to `service_role` only)

### `public.start_company_mark_run(p_scope jsonb, p_requested_by text) returns jsonb`

- Takes `pg_advisory_xact_lock(hashtext('company_mark_runs'))`.
- A `running` run started more than 30 minutes ago is set to `failed` with
  `error_message = 'abandoned'`.
- If a `running` run remains: inserts a `skipped` run and returns
  `{ "status": "skipped", "reason": "run_in_progress", "run_id": <skipped run id> }`.
- Otherwise inserts a `running` run and returns `{ "status": "running", "run_id": ... }`.
- `p_scope` shape: `{ "action": "populate" | "refresh", "companies": ["shopify", ...] }`
  (`companies` optional; at most 300 keys, each matching the key regex). For `refresh`, sets
  `mark_refresh_requested = true` on the named companies (or all approved companies when
  omitted).
- `p_requested_by` is trimmed to 120 characters; null becomes `'unspecified'`.

### `public.claim_company_mark_targets(p_run_id uuid, p_limit integer default 25) returns jsonb`

Returns up to `p_limit` (1…50) companies to process for this run, stamping `mark_claimed_at`.
Eligible: `status = 'approved'` and (`mark_status in ('not_yet_fetched','fetch_failed')` or
`mark_refresh_requested`) and (`mark_claimed_at is null or mark_claimed_at < now() - 15 minutes`)
and no item recorded for this run yet; restricted to the run's `companies` list when present.
Each element: `{ "key", "name", "website_url", "domains": [..], "mark_version", "refresh": bool }`.
Also increments `company_mark_runs.invocations`. Raises when the run is not `running`.

### `public.record_company_mark_outcome(p_run_id uuid, p_company_key text, p_outcome text, p_path text, p_content_type text, p_byte_size integer, p_width integer, p_height integer, p_source_url text, p_failure_reason text) returns jsonb`

- `p_outcome in ('fetched','no_icon_published','fetch_failed','skipped_existing')`.
- `fetched`: validates `p_path = p_company_key || '/' || (mark_version + 1) || '.' || ext`,
  byte size 1…1,048,576, width and height ≥ 128, content type png/jpeg; marks the current
  `served` version `superseded` (`retired_at = now()`), inserts the new `served` version, sets
  `mark_status = 'available'`, `mark_version + 1`, `mark_path`, `mark_content_type`,
  `mark_fetched_at = now()`, `mark_source_url`, clears `mark_failure_reason`,
  `mark_refresh_requested`, `mark_claimed_at`.
- `no_icon_published` / `fetch_failed`: records the reason; when the company has no served
  version sets `mark_status` accordingly; when it has one (a failed refresh) keeps
  `available` and stores the reason; clears `mark_refresh_requested` and `mark_claimed_at`.
- `skipped_existing`: clears `mark_claimed_at` only.
- Always upserts the run item (`run_id`, `company_key`, `outcome`, `detail`).
- Returns `{ "key", "mark_status", "mark_version" }`.

### `public.finish_company_mark_run(p_run_id uuid, p_status text, p_summary jsonb, p_error text) returns void`

`p_status in ('completed','failed')`; sets `finished_at = now()` and `error_message` (≤ 1000),
and stores as `summary` the per-outcome counts derived from the run's items merged with
`p_summary` (the function passes `purged` and `invocations`). Idempotent for a run already
finished.

### `public.set_company_mark_withheld(p_company_key text, p_withheld boolean) returns jsonb`

`true`: served version → `withheld` with `retired_at = now()`, `mark_status = 'withheld'`,
`mark_path = null`. `false`: if a `withheld` version exists for the current `mark_version`,
restore it to `served` and `available`; otherwise `not_yet_fetched`. Returns the company's mark
fields.

### `public.request_company_mark_refresh(p_company_key text) returns jsonb`

Sets `mark_refresh_requested = true`; returns the company's mark fields.

### `public.get_company_mark_overview() returns jsonb`

Array of every company: `key`, `name`, `status`, `coverage_clause`, `mark_status`,
`mark_version`, `mark_fetched_at`, `mark_failure_reason`, `mark_refresh_requested` (FR-026).
Contains no member data.

### `public.list_company_mark_purges(p_limit integer default 50) returns jsonb`

Versions with `state <> 'served'` and `retired_at < now() - interval '30 days'`, plus every
non-served version of a company whose `status <> 'approved'` older than 30 days:
`[{ "key", "version", "path" }]`.

### `public.confirm_company_mark_purge(p_company_key text, p_version integer) returns boolean`

Deletes the version row after the function has removed the object. Returns whether a row was
deleted. Refuses (returns false) when the version is still `served`.

## Private helpers (revoked from every client role)

- `private.company_mark_reference(p_domain text) returns jsonb` (stable).
- `private.sync_company_domain_names()` trigger: keeps `company_domains.company_name` and
  `industry` equal to the parent company on insert/update of either table.
- `private.dispatch_company_mark_purge() returns bigint`: when `list_company_mark_purges(1)`
  is non-empty and Vault holds `project_url` and `company_marks_job_secret`, posts
  `{"action":"purge","source":"pg_cron"}` with header `x-job-secret` to
  `<project_url>/functions/v1/company-marks` via `net.http_post`; otherwise returns null.
  Called at the end of `private.run_retention_maintenance()`, which also deletes
  `company_mark_runs` older than 180 days.

## pgTAP assertions (summary)

- Tables exist with RLS (`companies`) or in `private`; anon/authenticated have no privilege on
  `companies`, `company_mark_versions`, `company_mark_runs`, `company_mark_run_items`.
- Execute privileges: `get_own_company_mark` authenticated yes, anon no; every operations
  function anon no, authenticated no, service_role yes.
- Bucket `company-marks` exists, is public, 1 MiB, png/jpeg only.
- Registry: ≥ 200 approved companies; every approved company has a clause in (a, b, c, launch);
  exactly the six named carry-overs use `launch`; every approved domain maps to an approved
  company; `validate_company_domain('servicenow.com')` eligible, `('gmail.com')` ineligible.
- Read models: `company_mark` null before a fetch; reference after `fetched`; null after
  `set_company_mark_withheld(key, true)`; null when the company is `rejected`; version bumps
  and the previous version is `superseded` after a second fetch.
- Runs: second `start` while running returns `skipped`; abandoned run is failed; `claim`
  excludes recently claimed rows; `record_company_mark_outcome` rejects an out-of-order path.
- Retention: a run older than 180 days disappears after `run_retention_maintenance()`; a
  version retired 31 days ago is listed by `list_company_mark_purges`; one retired today is not;
  `confirm_company_mark_purge` refuses a served version.
- Exactly five `network-to-` cron jobs remain.
