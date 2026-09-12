# Research: Verified Company Marks

All unknowns from the Technical Context are resolved below. Each entry records the decision,
the rationale, and the alternatives considered.

## 1. Where marks are stored and how the phone reads them

- **Decision**: a public Supabase Storage bucket `company-marks` (1 MiB limit, `image/png`
  and `image/jpeg` only) with versioned object paths `<company-key>/<version>.<png|jpg>`. The
  phone issues a plain unauthenticated `GET` to
  `<project-url>/storage/v1/object/public/company-marks/<path>` and keeps the bytes in the
  Caches directory. No `storage.objects` policy is granted to `anon` or `authenticated`.
- **Rationale**: the phone already talks to the project host, so FR-011 holds. An
  unauthenticated read cannot be tied to a member (FR-014) and needs no signed URL that would
  expire and defeat caching. Without a `select` policy the Storage list endpoint returns
  nothing, so the registry is not exposed as a list (FR-012). Versioned paths make a refreshed
  mark new content (FR-015) without cache invalidation.
- **Alternatives considered**: a private bucket read with the member's JWT (a `select` policy
  also enables listing, which FR-012 forbids, and ties requests to members); signed URLs from
  an RPC (per-request authorisation was rejected in the spec as gold-plating, and expiry
  breaks the offline copy); bytes in Postgres served by RPC (DB bloat, PostgREST egress, and
  an authenticated per-view request).

## 2. Registry shape

- **Decision**: new `public.companies` keyed by a short slug (`key text primary key`, regex
  `^[a-z0-9][a-z0-9-]{0,62}$`) holding name, industry, website, coverage clause, status, and
  the current mark fields. `public.company_domains` gains `company_key` (not null after
  backfill). Sign-up still reads `company_domains.status`; marks read `companies.status`.
- **Rationale**: the spec's "Registry shape" assumption asks for one company with many domains;
  a stable slug reads well in migrations, tests, and storage paths and is not an email domain
  (FR-013). Keeping eligibility on the domain row keeps FR-019 unchanged (a subsidiary domain
  can be pending while the company is approved).
- **Alternatives considered**: UUID keys (unreadable in migrations, no natural `on conflict`
  target); deriving the company from `company_name` at read time (renames would split marks).

## 3. Coverage list

- **Decision**: 249 approved companies: the 40 launch companies (clauses a, b, c, or `launch`
  for Twilio, Figma, Dropbox, Lyft, Pinterest, and Snap, which meet none of the three clauses today) plus
  209 additions (the reviewed candidate list plus well-known index constituents, large private companies, and Toronto engineering employers it missed), each recorded with clause a, b, or c.
  Two companies share domains: Block (`block.xyz`, `squareup.com`) and Microsoft subsidiaries
  keep their own entries (GitHub, LinkedIn) as today. Added companies without a clear clause
  are listed under "Pending product-owner confirmation" in `data-model.md` and are not
  inserted.
- **Rationale**: SC-003 requires each company recorded with the clause that admitted it, so
  well-known companies that are public but outside the three indexes (Roku, Spotify, Unity,
  Klaviyo), small private labs (Linear, Substack, Runway), or Canadian companies whose
  Toronto engineering headcount could not be confirmed (FreshBooks, Flipp, KOHO) are left for
  the product owner to add by migration rather than recorded under a clause they do not meet.
- **Alternatives considered**: admitting every candidate (fails SC-003's auditability);
  index-only (about 120 companies, below the 200 target).

## 4. Fetching a company's published icon (FR-022, FR-024, FR-025)

- **Decision**: the `company-marks` function fetches `https://<website>/` (following redirects,
  which is "wherever the site directs it"), parses `<link rel="icon" | "apple-touch-icon" |
  "apple-touch-icon-precomposed" | "mask-icon">` and `<link rel="manifest">` (then the
  manifest's `icons`), and adds the conventional fallbacks `/apple-touch-icon.png`,
  `/apple-touch-icon-precomposed.png`, `/favicon.ico`. Each candidate is downloaded with a
  10-second timeout and a 1 MiB body cap, sniffed by magic bytes (PNG, JPEG, ICO), and its
  pixel size read from the header (PNG IHDR, JPEG SOF, ICO directory; PNG entries inside ICO
  are extracted, BMP entries ignored). APNG (an `acTL` chunk) is rejected as animation; SVG,
  WebP, GIF, and anything else are rejected as the wrong kind of file. The largest square
  candidate with shorter side ≥ 128 px and size ≤ 1 MiB wins (square first, then shorter side,
  then smaller bytes); a company whose best candidate is smaller than 128 px is recorded
  `no_icon_published`. Unreachable sites, oversized bodies, and wrong kinds are `fetch_failed`
  with the reason.
- **Rationale**: this uses only what the company itself publishes for browsers and phone home
  screens, needs no npm dependency, and is deterministic enough to unit-test in `_shared`.
- **Alternatives considered**: icon aggregation services (forbidden by FR-024); rendering SVG
  server-side (needs a rasteriser, not available in the Edge runtime); accepting WebP (native
  on iOS 14+, but header sniffing for animated WebP adds complexity for little gain).

## 5. URL safety for server-side fetches

- **Decision**: only `http`/`https`; refuse hosts that are IP literals or `localhost`; at most
  8 candidates per company; 10-second per-request timeout; `fetch` default redirect following
  (max 20 by the runtime) with the same host checks applied to the final URL.
- **Rationale**: registry websites are operator data, but a compromised or redirecting site
  should not be able to point the function at internal addresses.
- **Alternatives considered**: `redirect: "manual"` with a hand-rolled loop (more code, same
  effect); an allowlist per company (operator burden).

## 6. One action, bounded runtime (SC-008, FR-023)

- **Decision**: `start_company_mark_run` serialises with `pg_advisory_xact_lock`, marks a run
  older than 30 minutes as `failed` (abandoned), records `skipped` when another run is
  running, and otherwise inserts a `running` run. The function answers 202 at once and works
  in the background (`EdgeRuntime.waitUntil`), processing up to 10 companies per invocation
  (`claim_company_mark_targets` stamps `claimed_at` so a crashed batch is not re-claimed for
  15 minutes), then re-invokes itself with the run id and an invocation counter (max 60) until
  a batch comes back short, then `finish_company_mark_run`, which derives the summary from the
  recorded items.
- **Rationale**: keeps every invocation inside the Edge Function wall-clock budget while the
  operator runs a single command; the database remains the source of truth for progress.
- **Alternatives considered**: a queue table drained by a cron job (adds a schedule);
  processing everything in one invocation (times out on ~240 websites).

## 7. Deleting retired files without a new schedule (FR-027)

- **Decision**: `private.dispatch_company_mark_purge()` is called from the existing daily
  `run_retention_maintenance()`; when a retired version is older than 30 days and Vault holds
  `project_url` and `company_marks_job_secret`, it posts `{"action":"purge"}` to the function
  through `pg_net`. The function deletes the objects through the Storage API and confirms each
  with `confirm_company_mark_purge`, which deletes the version row. Run records older than
  180 days are deleted directly in SQL. Every populate or refresh run also purges due files.
- **Rationale**: deleting `storage.objects` rows in SQL orphans the S3 object; the Storage API
  is the only clean delete. Reusing the daily job means no new cron schedule and no new
  constitution schedule line.
- **Alternatives considered**: a new `network-to-company-marks` cron job (MINOR amendment for a
  schedule); deleting rows directly (violates the file rule).

## 8. Secret placement

- **Decision**: a new independently generated secret stored twice: Vault
  `company_marks_job_secret` (read by the purge dispatcher) and function secret
  `COMPANY_MARKS_JOB_SECRET` (compared in constant time by the function). Operators call the
  function with the same header (`x-job-secret`).
- **Rationale**: the constitution requires every secret to be generated independently and
  scheduled jobs to read from Vault; reusing `notification_job_secret` would couple two
  functions to one credential.
- **Alternatives considered**: a member JWT (operators are not members); reusing the
  notification secret (rejected above).

## 9. Client rendering of the mark inline with text

- **Decision**: `NTCompanyMark` renders a square tile whose side equals the line height of the
  accompanying text style (`UIFont.preferredFont(forTextStyle:compatibleWith:)` for the
  current content size category), with the fixed light backing, one-eighth inner padding, and
  either the fitted mark image or the monogram characters. The tile is rasterised once per
  (reference, monogram, size, scale) into a `UIImage` through `UIGraphicsImageRenderer` and
  placed inline with `Text(Image(uiImage:))` plus a baseline offset of the font descender, so
  "Role at [mark] Company" wraps as ordinary text and the mark stays on the company name's
  line (FR-001, FR-007). The verified company line keeps its seal icon and places the tile
  immediately before the company name inside the label text.
- **Rationale**: only an inline text attachment wraps correctly at accessibility sizes and at
  320 pt; an `HStack` splits the sentence into columns. Rasterising once keeps redraws cheap
  and gives identical geometry on every surface (FR-006).
- **Alternatives considered**: `HStack` layouts (poor wrapping); SF Symbol-style template
  images (would recolour the mark, forbidden by FR-006); a separate row for the mark
  (contradicts "immediately before the company name").

## 10. Fixed backing colours

- **Decision**: two new `NTColor` tokens with the same value in both appearances:
  `companyMarkBacking` `#F3EEE6` and `companyMarkGlyph` `#354C3D`. Contrast: glyph on backing
  8.07:1 (≥ 4.5:1 in both appearances and with Increased Contrast); backing on the dark surface
  `#20211D` 14.02:1 (≥ 3:1). Both are added to `docs/UI_DESIGN_SPEC.md` colour tokens and
  `docs/COMPONENT_STATE_SHEET.md` §2.1.
- **Rationale**: the clarified spec fixes a light neutral backing in both appearances; existing
  tokens are all dynamic, and the dark-mode `accentStrong` would fail contrast on a light tile.
- **Alternatives considered**: reusing `surfaceSecondary` (dark in dark appearance, contradicts
  the clarification); drawing no backing (legibility depends on each company's artwork).

## 11. Phone cache and clearing

- **Decision**: `CompanyMarkDiskCache` writes each mark to
  `Caches/CompanyMarks/<key>-<version>` and `AppStore` keeps `[CompanyMarkReference: Data]`
  in memory; `ensureCompanyMark` checks memory, then disk, then the backend, with one in-flight
  task per reference. `signOut()` and the confirmed account-deletion path clear both.
- **Rationale**: FR-016 and Story 1 scenario 11; the Caches directory is the platform's place
  for re-fetchable data and is excluded from backups.
- **Alternatives considered**: `URLCache` only (cannot be cleared selectively at sign-out
  without also dropping Supabase responses; no offline guarantee); Core Data (overkill).

## 12. Mock and previews

- **Decision**: `MockBackendService.loadCompanyMark` returns a fixed 128×128 PNG (embedded
  base64, solid colour) for the company key `northstar-ai` and `nil` for every other key, so
  previews show one mark and one monogram deterministically. Mock fixtures gain
  `companyMark` references for Sarah (Northstar AI) and for the current member (Orbit
  Systems, no served mark).
- **Rationale**: Principle VII requires deterministic fixtures with fixed identifiers.
- **Alternatives considered**: bundling image assets (asset catalog churn); random data
  (forbidden).
