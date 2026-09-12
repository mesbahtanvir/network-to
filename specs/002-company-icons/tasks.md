# Tasks: Verified Company Marks

**Input**: Design documents from `/specs/002-company-icons/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Requested by the constitution (Principle VII) and the plan: pgTAP, Deno, and XCTest
tasks are included and land in the same change as the behaviour they protect.

**Organization**: Tasks are grouped by user story. Stories 1 and 3 share the client
component and the read models built in the foundational phase; Story 2 is the registry; Story 4
is the operations action.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4)
- Include exact file paths in descriptions

## Path Conventions

Mobile + backend: `NetworkTo/` (SwiftUI app), `NetworkToTests/`, `supabase/migrations/`,
`supabase/functions/`, `supabase/tests/database/`, `docs/`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: registry reshape, configuration entries, and the curated list every story depends on

- [X] T001 Create `supabase/migrations/20260912100000_company_registry.sql` opening comment (intent, operator step: none) and the `public.companies` table per data-model.md (columns, checks, RLS enabled, `revoke all ... from public, anon, authenticated`, `updated_at` trigger)
- [X] T002 In `supabase/migrations/20260912100000_company_registry.sql` add `company_domains.company_key` (FK), the `private.sync_company_domain_names()` trigger on both tables, the launch-company inserts (40 companies with their clauses), the explicit domain → key backfill, a generic backfill for any remaining domain (slug from `company_name`, clause `launch`), then `alter table ... alter column company_key set not null`
- [X] T003 [P] Add `[functions.company-marks]` with `verify_jwt = false` to `supabase/config.toml` and `COMPANY_MARKS_JOB_SECRET` (with the Vault note) to `supabase/functions/.env.example`
- [X] T004 [P] Update `supabase/seed.sql` to insert the three development companies (`orbit-systems`, `northstar-ai`, `harbour-labs`, clause `launch`, status approved) and `new-venture-labs` (review_pending) before their domains, with `company_key` on every domain row
- [X] T005 [P] Add `company-marks` to both "Deploy self-authenticating functions" steps in `.github/workflows/supabase.yml`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: mark storage, read models, and the client primitives that every story renders through

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T006 Create `supabase/migrations/20260912100100_company_marks.sql`: bucket `company-marks` (public, 1048576, png/jpeg), `private.company_mark_versions`, `private.company_mark_runs` (partial unique index on `status = 'running'`), `private.company_mark_run_items`, all revoked from client roles, per data-model.md
- [X] T007 In `supabase/migrations/20260912100100_company_marks.sql` add `private.company_mark_reference(text)`, redefine `private.public_profile(profile)` to add `company_mark`, redefine `public.get_current_introduction()` to add `person.company_mark`, and add `public.get_own_company_mark()` (grant authenticated; revoke anon) per contracts/database.md
- [X] T008 [P] Add `CompanyMarkReference`, `ProfessionalProfile.companyMark` (appended, default nil), and `CompanyMonogram.characters(for:)` to `NetworkTo/Models/Models.swift` per contracts/client.md
- [X] T009 [P] Add `loadCompanyMark(_:)` with a `nil` default to `NetworkTo/Services/BackendService.swift`
- [X] T010 [P] Create `NetworkTo/Services/CompanyMarkDiskCache.swift` (`read`, `write`, `removeAll` under `Caches/CompanyMarks`, off-main file work)
- [X] T011 [P] Add `NTColor.companyMarkBacking` (`0xF3EEE6`) and `NTColor.companyMarkGlyph` (`0x354C3D`) with identical light/dark values to `NetworkTo/DesignSystem/DesignSystem.swift`
- [X] T012 Add `companyMarks`, `companyMarkData(for:)`, `ensureCompanyMark(_:)` (memory → disk → backend, one in-flight task per reference, failures swallowed), and `clearCompanyMarks()` to `NetworkTo/App/AppStore.swift`; call `clearCompanyMarks()` from `signOut()` and from `deleteMockAccount()` after the backend confirms (depends on T008–T010)
- [X] T013 Decode `company_mark` in `ProfileRow` and pass it to `ProfessionalProfile` in `NetworkTo/Services/SupabaseBackendService.swift`; implement `loadCompanyMark` as a validated public-object `GET` on the project host (depends on T008, T009)
- [X] T014 [P] Implement `loadCompanyMark` in `NetworkTo/Services/MockBackendService.swift` returning `MockData.sampleMarkPNG` (embedded base64, 128×128) for key `northstar-ai` and `nil` otherwise; add `companyMark` references to `MockData` fixtures (`.sarah` → `northstar-ai/1.png`, `.currentMember` → nil, `.maya` → `harbour-labs` with no served mark → nil)
- [X] T015 Create `NetworkTo/DesignSystem/CompanyMark.swift` with `NTCompanyMark`, `NTRoleAndCompanyLine`, and the rasterised tile cache per contracts/client.md and research.md §9 (depends on T008, T011, T012)
- [X] T016 Register `CompanyMark.swift`, `CompanyMarkDiskCache.swift`, and `NetworkToTests/CompanyMarkTests.swift` in `NetworkTo.xcodeproj/project.pbxproj` (PBXBuildFile, PBXFileReference, group children, Sources phases)

**Checkpoint**: read models emit `company_mark`; the client can fetch, cache, and draw a mark or monogram

---

## Phase 3: User Story 1 - Recognise the company on the introduction screen and in conversations (Priority: P1) 🎯 MVP

**Goal**: mark or company monogram beside the verified company on the introduction and mutual-interest identity rows, in conversation rows, and in a new conversation header identity line

**Independent Test**: with marks placed for two test companies by hand (`record_company_mark_outcome`) and one company without, open the introduction, the conversation list, and a conversation online, offline, and with VoiceOver; observe network traffic goes only to the project host

### Tests for User Story 1

- [X] T017 [P] [US1] Create `NetworkToTests/CompanyMarkTests.swift` with the FR-004 monogram examples (`TR`, `S`, `1`, `PG`, `TD`, `DQ`, `HH`, `T`, empty), `ensureCompanyMark` storing mock bytes once, a nil reference yielding no data, and `signOut()` clearing memory and disk
- [X] T018 [P] [US1] Create `supabase/tests/database/company_marks.test.sql` with a correct `plan(N)`: read models (`get_current_introduction`, `get_active_conversation`, `get_connections`, `get_own_company_mark`) emit `company_mark` null before a fetch and a reference after `record_company_mark_outcome('fetched')`; privilege assertions for `get_own_company_mark`

### Implementation for User Story 1

- [X] T019 [US1] Update `NTVerifiedCompanyLine` in `NetworkTo/DesignSystem/Components.swift` to take `reference:` and place the tile immediately before the company name after the seal, keeping the accessibility label; pass `profile.isWorkEmailVerified ? profile.companyMark : nil` from `NTProfessionalIdentity`
- [X] T020 [US1] Replace the role-and-company `Text` in `conversationCard` in `NetworkTo/Features/Messages/MessagesView.swift` with `NTRoleAndCompanyLine`
- [X] T021 [US1] Add the conversation header identity line (name, role and verified company with the tile) as a `ToolbarItem(placement: .principal)` in `ConversationView` in `NetworkTo/Features/Messages/MessagesView.swift`, combined for accessibility, keeping `navigationTitle` and the safety menu unchanged
- [X] T022 [US1] Trigger `ensureCompanyMark` for the introduction person, the conversation person, each connection, and the member on refresh in `NetworkTo/App/AppStore.swift` (`refreshFromBackend`) and from `NTCompanyMark` via `.task(id:)` so a monogram is replaced in place when the copy arrives

**Checkpoint**: introduction, mutual-interest, conversation rows and header show marks or monograms with no blank space

---

## Phase 4: User Story 2 - Members from well-known technology companies can join and see their mark (Priority: P2)

**Goal**: expand the registry to ≥ 200 approved companies with a coverage clause each and unchanged eligibility rules

**Independent Test**: `validate_company_domain` answers eligible for a sample of new domains under each clause and ineligible for a consumer domain; a member from a new company completes sign-up and sees the monogram on their profile

### Tests for User Story 2

- [X] T023 [P] [US2] Extend `supabase/tests/database/company_marks.test.sql`: ≥ 200 approved companies; every company has a clause in (a, b, c, launch); exactly the six named carry-overs use `launch`; every approved domain maps to an approved company; `validate_company_domain('servicenow.com')` eligible, `('gmail.com')` ineligible; `companies` has RLS and no privilege for anon/authenticated; `hook_restrict_signup_by_company_domain` still refuses `gmail.com`

### Implementation for User Story 2

- [X] T024 [US2] Generate the 209 added companies and their domains (from data-model.md's table, sorted by key) as `insert ... on conflict (key) do update` and `insert ... on conflict (domain) do update` statements in `supabase/migrations/20260912100000_company_registry.sql`
- [X] T025 [P] [US2] Extend the `knownCompanies` map in `NetworkTo/Services/MockBackendService.swift` with a representative sample of the new domains (one per clause) so the mock sign-up flow recognises them

**Checkpoint**: registry expanded; sign-up eligibility unchanged for consumer addresses

---

## Phase 5: User Story 3 - Recognise companies in Connections and on the member's own profile (Priority: P3)

**Goal**: marks or monograms in connection rows, connection detail, and the own-profile identity row; the settings row keeps its seal

**Independent Test**: Connections list with companies with and without marks, connection detail, own profile in verified and reverification-required states

### Tests for User Story 3

- [X] T026 [P] [US3] Extend `supabase/tests/database/company_marks.test.sql`: `get_connections()` person carries `company_mark`; `get_own_company_mark()` returns null after `set_company_mark_withheld(key, true)` and after the company is set `rejected`

### Implementation for User Story 3

- [X] T027 [US3] Replace the role-and-company `Text` in `connectionCard` in `NetworkTo/Features/Connections/ConnectionsView.swift` with `NTRoleAndCompanyLine` (connection detail and own profile already render through `NTProfessionalIdentity`)
- [X] T028 [US3] Confirm `ProfileView.swift` settings row keeps `checkmark.seal.fill` only and that the identity row shows the monogram when `isWorkEmailVerified` is false; add an XCTest in `NetworkToTests/CompanyMarkTests.swift` that a profile with `isWorkEmailVerified == false` yields a nil effective reference

**Checkpoint**: all six surfaces show marks or monograms consistently

---

## Phase 6: User Story 4 - The product team populates and refreshes marks without an app release (Priority: P4)

**Goal**: one operations action fetches, stores, versions, withholds, refreshes, and purges marks, recording an outcome per company, safe to re-run, skipping when a run is in progress

**Independent Test**: approve a company with no mark, run `populate`, see `available` with version 1 and the mark on a phone after refresh; run again and see nothing fetched; start two runs and see `skipped`; withhold and see the monogram

### Tests for User Story 4

- [X] T029 [P] [US4] Create `supabase/functions/_shared/company_marks_test.ts` covering `candidateIconURLs` (link tags with sizes, manifest icons, fallbacks, dedupe, cap of 8), `isSafeIconURL`, `inspectImage` (PNG, APNG rejected, JPEG SOF, ICO with embedded PNG, BMP entries ignored, unsupported), `chooseMark` (square preference, size ordering, too small → `no_icon_published`, all failed → `fetch_failed` with dominant reason), and `objectPath(key, version, kind)`
- [X] T030 [P] [US4] Extend `supabase/tests/database/company_marks.test.sql`: privilege assertions for every operations RPC (anon no, authenticated no, service_role yes); `start_company_mark_run` twice → second `skipped`; abandoned run failed; `claim_company_mark_targets` skips a fresh claim and returns a stale one; `record_company_mark_outcome` rejects a wrong path and a 64 px image; second `fetched` supersedes version 1; `set_company_mark_withheld` toggles; `request_company_mark_refresh` flags; `list_company_mark_purges` lists a version retired 31 days ago and not one retired today; `confirm_company_mark_purge` refuses a served version; `run_retention_maintenance()` deletes a 181-day-old run; bucket row public with limits; still five `network-to-` cron jobs

### Implementation for User Story 4

- [X] T031 [US4] In `supabase/migrations/20260912100100_company_marks.sql` add `start_company_mark_run`, `claim_company_mark_targets`, `record_company_mark_outcome`, `finish_company_mark_run`, `set_company_mark_withheld`, `request_company_mark_refresh`, `get_company_mark_overview`, `list_company_mark_purges`, `confirm_company_mark_purge` per contracts/database.md with revoke-then-grant to `service_role`
- [X] T032 [US4] In `supabase/migrations/20260912100100_company_marks.sql` add `private.dispatch_company_mark_purge()` (Vault `project_url` + `company_marks_job_secret`, silent when unconfigured) and redefine `private.run_retention_maintenance()` to delete runs older than 180 days and call the dispatcher; revoke both from every client role
- [X] T033 [P] [US4] Create `supabase/functions/_shared/company_marks.ts` with the pure logic named in contracts/company-marks-function.md (`candidateIconURLs`, `isSafeIconURL`, `inspectImage`, `chooseMark`, `objectPath`, `parseManifestIcons`, outcome types)
- [X] T034 [US4] Create `supabase/functions/company-marks/index.ts`: job-secret auth, actions `populate`/`refresh`/`purge`/`status`, batch of 25 with self-chaining continuation (max 40 invocations), Storage upload and delete through the REST API with the service role, run bookkeeping through the RPCs, snake_case logs (depends on T031, T033)

**Checkpoint**: the product team can populate, refresh, withhold, and inspect marks without an app release

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: documentation, constitution reconciliation, and validation

- [X] T035 [P] Update `docs/SUPABASE_BACKEND.md`: data model bullets (companies, marks, runs), the `company-marks` function, the Vault secret `company_marks_job_secret`, retention rules, operator commands, and the "already implemented" list
- [X] T036 [P] Update `README.md` ("What is implemented") and `docs/UI_DESIGN_SPEC.md` (two fixed colour tokens, company mark component, verified company line anatomy), `docs/COMPONENT_STATE_SHEET.md` (§2.1 tokens, `NTCompanyMark` states, `NTConversationIdentityHeader` now shipped, `NTVerifiedCompanyLine` anatomy), and `docs/ACCESSIBILITY_REVIEW.md` (decorative marks, contrast figures)
- [X] T037 Amend `.specify/memory/constitution.md` to v1.2.0: add `company-marks` to the self-authenticating function list, `company_marks_job_secret` to the Vault list, the two retention rules, and apply the v1.1.0 wording reconciliation (see PR description); bump version and Last Amended
- [X] T038 Run `scratchpad/harness/run_db_tests.sh`, `deno check`, and `deno test supabase/functions`; fix until green; record results in the PR description (Xcode test pass to be recorded by the reviewer per Principle VII)
- [X] T039 Run the quickstart.md checks that do not need a hosted project and update the PR title and body

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies
- **Foundational (Phase 2)**: depends on T001–T002 (registry shape) for T006–T007; client tasks depend only on each other as noted
- **User Stories (Phase 3+)**: all depend on Phase 2
  - US1 and US3 are client placements over the same primitives; US2 is data only; US4 is backend only
- **Polish (Phase 7)**: after the stories

### User Story Dependencies

- **US1 (P1)**: after Phase 2; no dependency on other stories (marks can be recorded by hand)
- **US2 (P2)**: after Phase 1 (registry table); independent of US1
- **US3 (P3)**: after Phase 2; shares `NTRoleAndCompanyLine` with US1 but is testable alone
- **US4 (P4)**: after Phase 2 (tables); independent of the client stories

### Parallel Opportunities

- T003, T004, T005 with T001–T002
- T008–T011, T014 together; T012–T013, T015 after them
- T017, T018 together; T029, T030, T033 together
- T035, T036 together

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1 and Phase 2
2. Phase 3 (US1) with marks recorded by hand through `record_company_mark_outcome`
3. Validate with the quickstart §1 and §3 checks

### Incremental Delivery

1. US2 registry expansion (data only) → sign-up coverage
2. US3 remaining placements
3. US4 operations action → marks populate without an app release
4. Polish: docs, constitution v1.2.0, validation

## Notes

- Every new SQL object carries revoke-then-grant and pgTAP privilege assertions
- No new cron job; retention reuses `network-to-daily-maintenance`
- No secret or project URL in a migration; the job secret lives in Vault and as a function secret
- iOS files must be registered in `project.pbxproj`; an Xcode test pass is recorded by the reviewer
