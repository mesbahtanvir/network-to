import XCTest
@testable import NetworkTo

@MainActor
final class CompanyMarkTests: XCTestCase {
    private func makeStore(cacheDirectory: URL? = nil) -> AppStore {
        let defaults = UserDefaults(suiteName: "CompanyMarkTests.\(UUID().uuidString)")!
        let directory = cacheDirectory ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        return AppStore(
            defaults: defaults,
            hasAuthenticated: true,
            hasCompletedOnboarding: true,
            seedMockData: false,
            backend: MockBackendService(latency: .zero),
            markCache: CompanyMarkDiskCache(directory: directory)
        )
    }

    func testMonogramFollowsTheCompanyNameRule() {
        XCTAssertEqual(CompanyMonogram.characters(for: "Thomson Reuters"), "TR")
        XCTAssertEqual(CompanyMonogram.characters(for: "Shopify"), "S")
        XCTAssertEqual(CompanyMonogram.characters(for: "1Password"), "1")
        XCTAssertEqual(CompanyMonogram.characters(for: "Procter & Gamble"), "PG")
        XCTAssertEqual(CompanyMonogram.characters(for: "The Trade Desk"), "TD")
        XCTAssertEqual(CompanyMonogram.characters(for: "D-Wave Quantum"), "DQ")
        XCTAssertEqual(CompanyMonogram.characters(for: "Hims & Hers"), "HH")
        XCTAssertEqual(CompanyMonogram.characters(for: "The"), "T")
        XCTAssertEqual(CompanyMonogram.characters(for: "  "), "")
    }

    func testEnsureCompanyMarkStoresTheServedBytesOnce() async {
        let store = makeStore()
        let reference = CompanyMarkReference(key: "northstar-ai", version: 1, path: "northstar-ai/1.png")

        XCTAssertNil(store.companyMarkData(for: reference))
        await store.ensureCompanyMark(reference)
        await store.ensureCompanyMark(reference)

        XCTAssertEqual(store.companyMarkData(for: reference), MockData.sampleMarkPNG)
        XCTAssertEqual(store.companyMarks.count, 1)
    }

    func testCompaniesWithoutAServedMarkStayOnTheMonogram() async {
        let store = makeStore()
        let reference = CompanyMarkReference(key: "orbit-systems", version: 1, path: "orbit-systems/1.png")

        await store.ensureCompanyMark(reference)
        await store.ensureCompanyMark(nil)

        XCTAssertNil(store.companyMarkData(for: reference))
        XCTAssertNil(store.companyMarkData(for: nil))
        XCTAssertTrue(store.companyMarks.isEmpty)
    }

    func testSignOutClearsCachedMarks() async {
        let store = makeStore()
        let reference = CompanyMarkReference(key: "northstar-ai", version: 1, path: "northstar-ai/1.png")
        await store.ensureCompanyMark(reference)
        XCTAssertNotNil(store.companyMarkData(for: reference))

        store.signOut()

        XCTAssertTrue(store.companyMarks.isEmpty)
        XCTAssertNil(store.companyMarkData(for: reference))
    }

    func testDiskCacheRoundTripsAndClears() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cache = CompanyMarkDiskCache(directory: directory)
        let reference = CompanyMarkReference(key: "shopify", version: 2, path: "shopify/2.png")
        let payload = Data([0x89, 0x50, 0x4E, 0x47])

        await cache.write(payload, for: reference)
        let stored = await cache.read(reference)
        XCTAssertEqual(stored, payload)

        await cache.removeAll()
        let cleared = await cache.read(reference)
        XCTAssertNil(cleared)
    }

    func testUnverifiedAffiliationShowsNoMark() {
        var profile = ProfessionalProfile.sarah
        XCTAssertNotNil(profile.displayedCompanyMark)

        profile.isWorkEmailVerified = false

        XCTAssertNil(profile.displayedCompanyMark)
    }

    func testReferencesCarryNoEmailDomain() {
        let reference = ProfessionalProfile.sarah.companyMark
        XCTAssertEqual(reference?.key, "northstar-ai")
        XCTAssertFalse(reference?.path.contains("@") ?? true)
    }
}
