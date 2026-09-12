# Contract: `company-marks` Edge Function

Self-authenticating operations function deployed with `--no-verify-jwt`. Runs entirely on the
backend; sends no member data anywhere; fetches icons only from each company's own website or
wherever that website redirects (FR-024).

## Authentication

- Header `x-job-secret` compared in constant time (`secretsMatch`) with the function secret
  `COMPANY_MARKS_JOB_SECRET`. Missing or wrong secret → `401 {"error":"Unauthorized"}`.
- Method other than `POST` → `405 {"error":"Method not allowed"}`.

## Request

```json
{
  "action": "populate" | "refresh" | "purge" | "status",
  "companies": ["shopify", "cohere"],
  "requested_by": "ops@example.com",
  "run_id": "uuid",
  "invocation": 3
}
```

- `companies` (optional, ≤ 300 keys) restricts `populate`/`refresh`.
- `run_id` and `invocation` are set only by the function itself when it chains a continuation.
- `source` is accepted (the purge dispatcher sends `"pg_cron"`) and ignored otherwise.

## Responses (JSON envelopes)

- `populate` / `refresh`: `202 { "status": "running", "run_id", "invocation" }` as soon as the
  run is registered; the batch itself runs after the response (`EdgeRuntime.waitUntil`) so an
  operator command returns at once. `200 { "status": "skipped", "reason": "run_in_progress",
  "run_id" }` when another run is running. Progress and the final summary are read from the
  run row (`status`, `finished_at`, `summary` with `fetched`, `no_icon_published`,
  `fetch_failed`, `skipped_existing`, `purged`, `invocations`) or from the `status` action.
- `purge`: `200 { "purged": n, "failed": m }`.
- `status`: `200 { "companies": [ ...overview rows... ] }` (from `get_company_mark_overview`).
- Configuration or database failure: `500 { "error": "..." }` after `finish_company_mark_run(...,
  'failed', ..., error)` when a run was open. The function never throws to the caller.

## Processing one company (pure logic in `_shared/company_marks.ts`)

1. `candidateIconURLs(html, baseURL, manifestJSON?)`: collect `<link>` icons with `rel` in
   `icon`, `shortcut icon`, `apple-touch-icon`, `apple-touch-icon-precomposed`, `mask-icon`
   (with their `sizes`), the manifest's `icons[]`, and the fallbacks
   `/apple-touch-icon.png`, `/apple-touch-icon-precomposed.png`, `/favicon.ico`; resolve
   relative URLs; drop duplicates and unsafe URLs (`isSafeIconURL`); cap at 8.
2. `isSafeIconURL(url)`: `http`/`https` only; host is not an IP literal, `localhost`, or empty.
3. Download each candidate with a 10 s timeout and a 1,048,576-byte cap (`fetch_failed:
   too_large` beyond it).
4. `inspectImage(bytes)`: returns `{ kind: "png" | "jpeg" | "ico" | "unsupported", width,
   height, animated }` from headers (PNG IHDR and `acTL`; JPEG SOF0/1/2 markers; ICO directory,
   extracting the largest PNG-encoded entry as a new PNG candidate; BMP entries ignored).
5. `chooseMark(candidates)`: keep kind png/jpeg, not animated, `min(width,height) >= 128`,
   bytes ≤ 1 MiB; order by square first (|w−h| ≤ 10% of max side), then shorter side desc, then
   bytes asc. If no candidate decoded at all and no download succeeded → `fetch_failed` with the
   dominant reason (`unreachable`, `too_large`, `wrong_kind`); if candidates decoded but all are
   below 128 px → `no_icon_published`.
6. Upload to `company-marks/<key>/<version+1>.<png|jpg>` (`x-upsert: true`, correct
   `content-type`) through the Storage REST API with the service role; then
   `record_company_mark_outcome(..., 'fetched', ...)`. An upload failure records
   `fetch_failed: upload_failed`.

## Chaining

After each batch of 10 the function posts to its own URL (`SUPABASE_URL` +
`/functions/v1/company-marks`) with `run_id`, `invocation + 1`, the running `purged` count, and
the same `x-job-secret`; the continuation responds immediately and works in the background,
so each isolate lives only for its own batch. Chaining stops when a batch comes back short or
`invocation >= 60`, and the run is then finished. Each company has a 30-second budget, each
request an 8-second timeout, and at most 6 icon downloads. The first invocation of every
populate/refresh run performs a purge pass first.

## Logging

snake_case event names with identifiers only: `company_mark_run_started`,
`company_mark_fetched`, `company_mark_no_icon`, `company_mark_fetch_failed`,
`company_mark_run_completed`, `company_mark_purge_failed`. Never logs member data (there is
none in this function) or secrets.

## Environment

`COMPANY_MARKS_JOB_SECRET` (function secret; equals Vault `company_marks_job_secret`),
`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` (provided by the platform).
