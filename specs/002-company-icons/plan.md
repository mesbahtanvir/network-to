# Implementation Plan: Verified Company Marks

**Branch**: `002-company-icons` | **Date**: 2026-09-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/002-company-icons/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Show a small company mark beside every verified company name (introduction, mutual-interest
state, conversation rows and header, connection rows and detail, own profile), falling back to
a company monogram drawn from the company name whenever no mark can be shown. The registry
becomes one row per company with one or more work-email domains and grows to about 240
approved companies. Marks are fetched once, server-side, from each company's own public
website by a job-secret-protected Edge Function (`company-marks`), stored versioned in a
public Storage bucket the phone reads from the project host only, and referenced from the
existing relationship-scoped read models. Operations records live in the `private` schema with
retention on the existing daily job; no new cron schedule is added.

## Technical Context

**Language/Version**: Swift 6 (SwiftUI, iOS 17+, strict concurrency complete); PL/pgSQL on
Postgres 17 (Supabase); TypeScript on Deno v2.5.2 (Edge Functions)

**Primary Dependencies**: `supabase-swift` (only iOS dependency); Supabase Storage, Vault,
`pg_net`, `pg_cron` (already enabled); Deno standard `fetch` and Web Crypto (no new npm imports)

**Storage**: Postgres tables `public.companies` (new), `public.company_domains` (reshaped),
`private.company_mark_versions`, `private.company_mark_runs`, `private.company_mark_run_items`
(new); Storage bucket `company-marks` (public, 1 MiB limit, PNG/JPEG only); on the phone a
Caches-directory file per mark version plus an in-memory dictionary in `AppStore`

**Testing**: pgTAP (`supabase test db`), Deno (`deno test supabase/functions`), XCTest on the
`NetworkToTests` target; local harness `scratchpad/harness/run_db_tests.sh` mirrors CI

**Target Platform**: iPhone, iOS 17.0+; Supabase hosted project (staging then production)

**Project Type**: Mobile app + Supabase backend (existing layout)

**Performance Goals**: a mark row renders its text immediately (never waits for an image); a
cached mark is drawn from disk or memory without network; the operations action processes a
batch of 10 companies per invocation and chains itself until the registry is covered, so the
whole registry completes well inside the 30-minute bound in SC-008

**Constraints**: phone talks only to the project host (FR-011); no list/browse of companies or
members (FR-012); no member-to-mark record server-side (FR-014); marks ≤ 1 MB and ≥ 128 px
shorter side (FR-025); fetch only from the company's own website or where it redirects
(FR-024); no animation on mark arrival (FR-005); no new secret or URL in a migration; no new
cron job

**Scale/Scope**: ~240 approved companies, ~300 domains; at most three marks on screen per
session for a typical member; 6 client surfaces changed, 2 migrations, 1 Edge Function,
3 test files

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Principles touched: I, II, IV, V, VI, VII, VIII and the "Company registry" constraint.

- **I (one introduction, never a feed)**: no new tab, list, browse, or search. `companies` has
  RLS with no client grants; the phone learns a company only through the existing
  relationship-scoped read models and its own profile. PASS.
- **II (reciprocal interest is the only gate)**: the mark reference travels inside
  `get_current_introduction`, `get_active_conversation`, `get_connections`, which already gate
  on participation; the same reference appears whatever either member answered; the private
  waiting state shows no counterpart identity. No one-sided decision is revealed. PASS.
- **III (in-person outcome)**: unchanged; the conversation header gains an identity line only.
  PASS.
- **IV (members own their data)**: the reference carries a company key, version, and path,
  never an email domain (FR-013); the bucket is public and unauthenticated so no request can
  be tied to a member; the backend keeps no member-to-mark table; verification wording is
  unchanged. PASS.
- **V (native, accessible, single store)**: new component `NTCompanyMark` uses `NTColor`,
  `NTSpacing`, and Dynamic Type; two new fixed tokens (`companyMarkBacking`,
  `companyMarkGlyph`) are added to `NTColor` and to `docs/UI_DESIGN_SPEC.md`; mark data is
  owned by `AppStore` and fetched through `BackendService` with a no-op default; marks are
  `accessibilityHidden` and add no spoken text; no motion. The state matrix below lists the
  new header line and the mark states. PASS.
- **VI (backend owns trust)**: every new table has RLS and revoke-then-grant; every RPC is
  `security definer`, empty `search_path`, explicit revoke/grant to the exact role; the Edge
  Function authenticates with a constant-time job-secret compare and mutates only through
  service-role RPCs; the run RPC takes an advisory lock and records `skipped`; retention rules
  are added to `run_retention_maintenance()` with pgTAP proofs; the job secret lives in Vault
  (`company_marks_job_secret`) and as the function secret `COMPANY_MARKS_JOB_SECRET`; no secret
  or URL in a migration. PASS.
- **VII (deterministic tests, CI-only deploys)**: pgTAP, Deno, and XCTest additions are named
  below; deploy stays in `.github/workflows/supabase.yml` (the new function joins the
  self-authenticating deploy step). PASS.
- **VIII (calm technology)**: see the Calm Technology check at the end of this plan. PASS.
- **Company registry constraint**: expansion is a migration reviewed in the PR; marks are served
  by the product backend; the client falls back to a monogram and fetches nothing from a third
  party. PASS.
- **Product and Platform Constraints updates required (constitution amendment, MINOR)**: the
  self-authenticating function list gains `company-marks`; the Vault secret list gains
  `company_marks_job_secret`; the retention list gains "company mark runs 180 days, unserved
  mark files 30 days". These are recorded in the same PR as an amendment to v1.2.0 together
  with the wording reconciliation already owed from v1.1.0.

Gate details required by the plan gate:

| Item | RLS / grants | Privilege assertions | Secret | Idempotency | Retention |
|------|--------------|----------------------|--------|-------------|-----------|
| `public.companies` | RLS on; revoke all from anon/authenticated; no client policy | anon/authenticated cannot select; service_role can (bypass) | none | upsert by key | permanent registry |
| `public.company_domains.company_key` | unchanged table grants (already no client grants) | existing | none | backfill idempotent | permanent |
| `private.company_mark_versions` | private schema, revoke all | anon/authenticated/service_role have no table privilege | none | (company_key, version) pk | file deleted ≤ 30 days after retirement; row deleted when purge confirmed |
| `private.company_mark_runs`, `_run_items` | private schema, revoke all | as above | none | one `running` run at a time | 180 days |
| `get_own_company_mark()` | execute: authenticated only | asserted | none | read | n/a |
| `start_company_mark_run`, `claim_company_mark_targets`, `record_company_mark_outcome`, `finish_company_mark_run`, `set_company_mark_withheld`, `request_company_mark_refresh`, `get_company_mark_overview`, `list_company_mark_purges`, `confirm_company_mark_purge` | execute: service_role only | asserted for anon, authenticated, service_role | none | keyed by run id / company key / version | n/a |
| Storage bucket `company-marks` | public bucket; no `storage.objects` policy for client roles (no listing) | bucket row asserted public with limits | none | versioned paths | files purged by function |
| Edge Function `company-marks` | self-authenticating (`x-job-secret`) | Deno tests for pure logic | `COMPANY_MARKS_JOB_SECRET` (function secret) = Vault `company_marks_job_secret` | run id carried across chained invocations | n/a |
| Retention hook `private.dispatch_company_mark_purge()` | private, revoke all | asserted | reads Vault `project_url`, `company_marks_job_secret` | silent when nothing due or unconfigured | invoked by existing daily job |

No push payload changes (no notification is added). No new scheduled job.

## Project Structure

### Documentation (this feature)

```text
specs/002-company-icons/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   ├── database.md      # RPC and read-model contracts
│   ├── company-marks-function.md
│   └── client.md        # iOS component and store contracts
├── checklists/requirements.md
└── tasks.md             # Phase 2 output (/speckit-tasks)
```

### Source Code (repository root)

```text
supabase/
├── migrations/
│   ├── 20260912100000_company_registry.sql     # companies table, domain reshape, expansion
│   └── 20260912100100_company_marks.sql        # bucket, versions, runs, RPCs, read models, retention
├── functions/
│   ├── company-marks/index.ts                  # transport glue (auth, actions, chaining)
│   └── _shared/
│       ├── company_marks.ts                    # pure logic: link/manifest/ICO parsing, image sniffing, selection, URL safety
│       └── company_marks_test.ts
├── tests/database/company_marks.test.sql
├── seed.sql                                    # development companies + domains
├── config.toml                                 # [functions.company-marks] verify_jwt = false
└── functions/.env.example                      # COMPANY_MARKS_JOB_SECRET

NetworkTo/
├── Models/Models.swift                         # CompanyMarkReference, ProfessionalProfile.companyMark, CompanyMonogram
├── Services/
│   ├── BackendService.swift                    # loadCompanyMark(_:) with no-op default
│   ├── SupabaseBackendService.swift            # decode company_mark; public object GET
│   ├── MockBackendService.swift                # deterministic sample mark bytes
│   └── CompanyMarkDiskCache.swift              # Caches-directory store (new)
├── App/AppStore.swift                          # companyMarkData, ensureCompanyMark, clearCompanyMarks
├── DesignSystem/
│   ├── DesignSystem.swift                      # NTColor.companyMarkBacking / companyMarkGlyph
│   ├── Components.swift                        # NTVerifiedCompanyLine gains the mark
│   └── CompanyMark.swift                       # NTCompanyMark, NTRoleAndCompanyLine, tile renderer (new)
└── Features/
    ├── Messages/MessagesView.swift             # row line, conversation header identity line
    ├── Connections/ConnectionsView.swift       # row line
    └── (Introduction, Profile unchanged: they use NTProfessionalIdentity)

NetworkToTests/CompanyMarkTests.swift           # monogram rule, cache, sign-out clearing (new)
NetworkTo.xcodeproj/project.pbxproj             # register the three new files

docs/SUPABASE_BACKEND.md, README.md, docs/UI_DESIGN_SPEC.md, docs/COMPONENT_STATE_SHEET.md,
docs/ACCESSIBILITY_REVIEW.md, .specify/memory/constitution.md (v1.2.0), .github/workflows/supabase.yml
```

**Structure Decision**: the existing mobile + Supabase layout is kept. Backend work is two
migrations plus one Edge Function whose pure logic lives in `_shared` with a sibling test. The
iOS work adds one DesignSystem file, one Services file, one test file, and edits to the store,
models, and the two list surfaces.

## State matrix and offline states (new or changed surfaces)

- **`NTCompanyMark`** (every placement): `mark` (image available on this phone) and
  `monogram` (no reference, withheld, not approved, not yet downloaded, offline, or failed).
  There is no loading, error, or retry state of its own. The switch from monogram to mark
  happens on the next redraw with no animation.
- **Conversation header identity line** (new): `resting` (name, role and verified company with
  mark or monogram); `ended` and `blocked` follow the existing conversation states unchanged;
  offline shows the same line from the last snapshot.
- **Own profile identity row**: `verified` shows the mark; `reverification required`,
  `pending review`, `company changed` show the monogram with today's wording (FR-028).
- Host surfaces keep their existing matrices (`docs/COMPONENT_STATE_SHEET.md` §4, §8, §9).

## Tests to add

- **pgTAP** `supabase/tests/database/company_marks.test.sql`: tables and RLS; privilege
  assertions for every new RPC (anon, authenticated, service_role); bucket row public with
  limits; registry size ≥ 200 approved with a clause each and no post-launch company recorded
  `launch`; every approved domain maps to an approved company; `validate_company_domain` for
  new domains and a consumer domain; read models emit `company_mark` null before a fetch,
  a reference after `record_company_mark_outcome('fetched')`, null when withheld and when the
  company is not approved; run start / skip / stale semantics; version supersession; retention
  of runs (180 days) and purge listing (30 days); still exactly five `network-to-` cron jobs.
- **Deno** `supabase/functions/_shared/company_marks_test.ts`: icon link extraction with
  sizes, manifest icon extraction, ICO directory parsing with an embedded PNG, PNG and JPEG
  dimension sniffing, APNG rejection, candidate selection (largest square within limits,
  too small → no icon published), URL safety (scheme, IP literal, localhost), outcome mapping.
- **XCTest** `NetworkToTests/CompanyMarkTests.swift`: monogram rule examples from FR-004;
  `ensureCompanyMark` stores data from the mock and is idempotent; `signOut()` clears memory
  and disk; a profile without a reference yields no data.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Retention of stored files goes through the Edge Function (called by the existing daily SQL job via `pg_net`) instead of pure SQL | Deleting `storage.objects` rows directly leaves the S3 file behind, so the 30-day file rule (FR-027) would be false | A new cron job for the function would add a schedule to the constitution's constraints; pure SQL cannot delete the file |
| The operations action chains itself in batches of 10 | One invocation cannot fetch ~240 websites inside an Edge Function wall-clock budget, and SC-008 asks for one action | Asking the operator to invoke the function ten times is not "one action"; a queue table plus schedule would add a cron job |

## Calm Technology check

- Reduce or add attention? Adds one small still element beside a name and removes the need to
  read the company name to recognise it. No text, control, step, or state is added.
- Inform or alarm? Informs; a missing mark is a quiet monogram, never an error.
- Live in the periphery? Yes: caption-line height, decorative to assistive technology, no
  badge or count.
- Help two people meet or keep them in the app? Quicker recognition at the decision moment and
  while arranging coffee; no notification, no new reason to open the app.
- Fail quietly? Offline, failed, withheld, or absent marks all show the monogram; server
  failures are recorded per company and affect nobody.
- Simpler way? Fetch once on the backend, cache on the phone, fall back to a monogram is the
  least technology that keeps the phone off third-party services.
- Would a thoughtful professional find it normal? Yes: a company mark beside a verified
  affiliation with the same "Work email verified" wording.
