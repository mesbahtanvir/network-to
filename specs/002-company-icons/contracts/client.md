# Contract: iOS client

## Models (`NetworkTo/Models/Models.swift`)

```swift
struct CompanyMarkReference: Codable, Hashable, Sendable {
    let key: String      // company slug, never an email domain
    let version: Int
    let path: String     // "<key>/<version>.<png|jpg>"
}

extension ProfessionalProfile { var companyMark: CompanyMarkReference? }  // default nil

enum CompanyMonogram {
    /// FR-004: at most two uppercase characters from the first letter or digit of the first two
    /// words; words with no letter or digit and the joining words "and", "of", "the" are skipped
    /// unless they are the only word.
    static func characters(for companyName: String) -> String
}
```

Examples: "Thomson Reuters" → "TR", "Shopify" → "S", "1Password" → "1", "Procter & Gamble" → "PG",
"The Trade Desk" → "TD", "D-Wave Quantum" → "DQ", "Hims & Hers" → "HH", "The" → "T", "" → "".

## BackendService (`NetworkTo/Services/BackendService.swift`)

```swift
/// Bytes of a company mark served by the product backend, or nil when unavailable.
func loadCompanyMark(_ reference: CompanyMarkReference) async throws -> Data?
```

Default implementation returns `nil`. `SupabaseBackendService` performs
`GET <url>/storage/v1/object/public/company-marks/<path>` with `URLSession`, returns the body on
200 with an `image/*` content type, `nil` on 404, and throws on other failures. The reference
path is validated against `^[a-z0-9][a-z0-9-]{0,62}/[0-9]+\.(png|jpg)$` before a request is
built. `MockBackendService` returns a fixed 128×128 PNG for key `northstar-ai`, `nil` otherwise.

## AppStore (`NetworkTo/App/AppStore.swift`)

```swift
@Published private(set) var companyMarks: [CompanyMarkReference: Data]
func companyMarkData(for reference: CompanyMarkReference?) -> Data?
func ensureCompanyMark(_ reference: CompanyMarkReference?) async   // memory → disk → backend; one task per reference
func clearCompanyMarks()                                          // memory + disk; called from signOut() and after confirmed deletion
```

Failures are swallowed (a missing decoration is not an error the member can act on; FR-003);
nothing is written to `transientMessage`.

## Disk cache (`NetworkTo/Services/CompanyMarkDiskCache.swift`)

`struct CompanyMarkDiskCache: Sendable` with `read(_:) -> Data?`, `write(_:for:)`, `removeAll()`,
files at `Caches/CompanyMarks/<key>-<version>`. All file work runs off the main actor.

## Design system (`NetworkTo/DesignSystem/CompanyMark.swift`)

```swift
struct NTCompanyMark: View {
    let companyName: String
    let reference: CompanyMarkReference?   // nil → monogram
    let textStyle: Font.TextStyle          // .caption for verified lines, .subheadline for rows
}
/// Text fragment "Role at [mark] Company" that wraps as ordinary text.
struct NTRoleAndCompanyLine: View { let role: String; let companyName: String; let reference: CompanyMarkReference? }
```

- Tile side = line height of `textStyle` for the current content size category; corner radius
  = 25% of the side (continuous); inner padding = side / 8; backing `NTColor.companyMarkBacking`;
  monogram glyphs `NTColor.companyMarkGlyph`, semibold, sized to fit two characters.
- The tile is rasterised once per (reference or monogram, side, display scale) and cached; the
  image is placed inline with the text so wrapping is native. No animation on change.
- `.accessibilityHidden(true)` on the tile; host text keeps its label (`"<role> at <company>"`
  or the existing verified-company label).
- `NTVerifiedCompanyLine(company:reference:)` keeps `checkmark.seal.fill` first and places the
  tile immediately before the company name; the accessibility label is unchanged.
- `NTProfessionalIdentity` passes `profile.isWorkEmailVerified ? profile.companyMark : nil`.

## Placements (FR-001)

| Surface | File | Line style |
|---------|------|------------|
| Introduction identity, mutual-interest identity | `IntroductionFlowView.swift` via `NTProfessionalIdentity` | caption (verified company line) |
| Connection detail, own profile identity | `ConnectionsView.swift`, `ProfileView.swift` via `NTProfessionalIdentity` | caption |
| Conversation list row | `MessagesView.swift` `conversationCard` | subheadline (role-and-company line) |
| Conversation header (new identity line) | `MessagesView.swift` `ConversationView` principal toolbar item | headline name + caption role-and-company |
| Connection row | `ConnectionsView.swift` `connectionCard` | subheadline |

Not changed: onboarding identity/review steps, Edit profile Company field, the
"Work email verified" settings row and Work verification screen, Conversation details.

## New tokens (`NetworkTo/DesignSystem/DesignSystem.swift`)

`NTColor.companyMarkBacking` = `#F3EEE6` (both appearances), `NTColor.companyMarkGlyph` =
`#354C3D` (both appearances).
