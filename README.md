# network.to for iOS

A native SwiftUI app for helping ambitious professionals across North American cities move toward their goals through high-quality, cross-company and cross-industry relationships.

The product is intentionally centered on selective same-city introductions, reciprocal interest, and in-person 1:1 coffee chats. It has no feed, global directory, event discovery, cold messaging, swipe deck, or compatibility score.

## What is implemented

- Calm magic-link work-email verification with automatic work-laptop-to-iPhone handoff
- Résumé-first professional onboarding with real processing stages, item-by-item removal, and member-authored career direction
- Today, Connections, Messages, and Profile experiences
- Private Interested/Pass decisions and a mutual-interest conversation gate
- 1:1 meetup planning, private feedback, and opt-in connection creation
- Temporary coarse-grained availability
- Reporting, blocking, ending conversations, and account deletion
- Notification management through native iPhone Settings
- One account-scoped free month, followed by a native Apple monthly membership
- No gender collection, gender filters, or gender-based ranking
- A production-hardened Supabase backend for Auth, Postgres, RLS, hourly matching, meetup follow-ups, retention, Realtime tables, APNs delivery, App Store Server Notifications, operations alerting, and Edge Functions
- Transactional profile setup, retry-safe messaging, and a restart-safe cross-device magic-link flow
- On-device PDFKit/Vision résumé text extraction with contact-detail redaction and schema-constrained DeepSeek drafting of identity, role context, expertise, history, education, and demonstrated experience through a rate-limited Supabase Edge Function
- Deterministic mock data for previews and unit tests

The membership product identifier is `com.mesbahtanvir.networkto.monthly`. The local Xcode scheme uses `NetworkTo/Products.storekit` at $9.99/month for simulator testing; production always displays Apple’s localized App Store price.

## Run the UI with mock data

1. Open `NetworkTo.xcodeproj` in Xcode.
2. Select the `NetworkTo` scheme and an iPhone simulator running iOS 17 or later.
3. Open Product → Scheme → Edit Scheme → Run → Arguments and add `--mock-backend`.
4. Run the app.

Remove `--mock-backend` to use the hosted Supabase project embedded in the build settings. Feature-preview launch arguments always use deterministic mock data.

## Run with Supabase

The Xcode project resolves the official `supabase-swift` package and uses the hosted project by default. To point a Debug run at the local Supabase stack, start it and add these environment variables to the scheme’s Run action:

```text
SUPABASE_URL=http://127.0.0.1:55321
SUPABASE_PUBLISHABLE_KEY=<local publishable/anon key from supabase status>
```

See [docs/SUPABASE_BACKEND.md](docs/SUPABASE_BACKEND.md) for local setup, the deployed production architecture, security boundaries, and the external SMTP, résumé-extraction, and APNs launch dependencies.

Who the product is for and how the audience widens is defined in [docs/PRODUCT_DEFINITION.md](docs/PRODUCT_DEFINITION.md). The design philosophy is calm technology, defined in [docs/DESIGN_PHILOSOPHY.md](docs/DESIGN_PHILOSOPHY.md). Both are binding through [the constitution](.specify/memory/constitution.md), which every feature spec and plan under `specs/` is checked against.

Hosted Supabase migrations and Edge Functions are deployed only through the repository’s GitHub Actions workflow after validation, reaching a staging project first once one is configured. Local development commands must not mutate the production project.

## Verify

```sh
xcodebuild \
  -project NetworkTo.xcodeproj \
  -scheme NetworkTo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test
```

With Docker Desktop running, verify the database separately:

```sh
supabase start
supabase db reset
supabase test db
```

Type-check and unit-test the Edge Functions with Deno:

```sh
deno check supabase/functions/*/index.ts supabase/functions/_shared/*.ts
deno test supabase/functions
```
