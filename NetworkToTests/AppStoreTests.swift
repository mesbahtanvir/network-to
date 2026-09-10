import XCTest
@testable import NetworkTo

@MainActor
final class AppStoreTests: XCTestCase {
    private func makeStore() -> AppStore {
        let defaults = UserDefaults(suiteName: "AppStoreTests.\(UUID().uuidString)")!
        return AppStore(
            defaults: defaults,
            hasAuthenticated: true,
            hasCompletedOnboarding: true,
            seedMockData: false,
            backend: MockBackendService(latency: .zero)
        )
    }

    func testInterestRemainsPrivateUntilMutual() {
        let store = makeStore()

        store.respondInterested()

        XCTAssertEqual(store.phase, .waiting)
        XCTAssertFalse(store.canMessage)
        XCTAssertNil(store.conversation)
    }

    func testMutualInterestOpensConversation() {
        let store = makeStore()

        store.respondInterested()
        store.confirmMutualInterest()

        XCTAssertEqual(store.phase, .mutual)
        XCTAssertTrue(store.canMessage)
        XCTAssertEqual(store.conversation?.person, .sarah)
    }

    func testPassingNeverCreatesConversation() {
        let store = makeStore()

        store.passIntroduction()
        store.confirmMutualInterest()

        XCTAssertEqual(store.phase, .passed)
        XCTAssertFalse(store.canMessage)
        XCTAssertNil(store.conversation)
    }

    func testConnectionRequiresMeetingAndOptIn() {
        let store = makeStore()
        store.respondInterested()
        store.confirmMutualInterest()
        store.requestFeedback()

        store.recordFeedback(.good, stayConnected: true)

        XCTAssertEqual(store.phase, .connected)
        XCTAssertEqual(store.connections.count, 1)
    }

    func testDidNotMeetNeverCreatesConnection() {
        let store = makeStore()
        store.respondInterested()
        store.confirmMutualInterest()
        store.requestFeedback()

        store.recordFeedback(.didNotMeet, stayConnected: true)

        XCTAssertTrue(store.connections.isEmpty)
        XCTAssertEqual(store.phase, .searching)
    }

    func testExpiredAvailabilityIsNotActive() {
        let store = makeStore()
        store.availability = TodayAvailability(
            area: .downtown,
            window: .lunch,
            expiresAt: Date().addingTimeInterval(-1)
        )

        XCTAssertNil(store.activeAvailability)
    }

    func testFreeTrialAllowsNewIntroductions() {
        let store = makeStore()

        XCTAssertEqual(store.membership.state, .trial)
        XCTAssertTrue(store.canReceiveNewIntroductions)
    }

    func testExpiredTrialPausesOnlyNewIntroductions() {
        let defaults = UserDefaults(suiteName: "AppStoreTests.\(UUID().uuidString)")!
        let store = AppStore(
            defaults: defaults,
            hasAuthenticated: true,
            hasCompletedOnboarding: true,
            seedMockData: true,
            membership: .expired,
            backend: MockBackendService(latency: .zero)
        )

        XCTAssertFalse(store.canReceiveNewIntroductions)
        XCTAssertFalse(store.connections.isEmpty)
    }

    func testProfessionalContextCanBeAuthoredWithoutChangingVerification() {
        let store = makeStore()

        store.updateMemberContext(
            name: "Alex Morgan",
            role: "VP Engineering",
            city: "Toronto, ON",
            roleScope: "Leads platform and product engineering across three teams.",
            currentFocus: "Introducing applied AI capabilities into a mature platform.",
            yearsExperience: "15+ years",
            growthAreas: ["Applied AI products", "Executive communication"],
            professionalAmbition: "Build a product-minded engineering organization that makes responsible AI useful at scale.",
            growthInterest: "Compare how peers are setting an AI strategy without derailing delivery.",
            contributionAreas: ["Engineering leadership", "Scaling teams"],
            helpFormats: ["Compare approaches"],
            contribution: "Lessons from scaling engineering ownership across a growing organization.",
            contributionBoundaries: "Not offering recruiting referrals."
        )

        XCTAssertEqual(store.member.role, "VP Engineering")
        XCTAssertEqual(store.member.professionalAmbition, "Build a product-minded engineering organization that makes responsible AI useful at scale.")
        XCTAssertEqual(store.member.growthAreas.count, 2)
        XCTAssertEqual(store.member.contributionAreas.count, 2)
        XCTAssertTrue(store.member.isWorkEmailVerified)
    }

    func testSignUpContinuesIntoProfessionalContextSetup() {
        let store = makeStore()

        store.completeAuthentication(.signUp)

        XCTAssertTrue(store.hasAuthenticated)
        XCTAssertFalse(store.hasCompletedOnboarding)
    }

    func testSignInRestoresExistingAccount() {
        let store = makeStore()
        store.signOut()

        store.completeAuthentication(.signIn)

        XCTAssertTrue(store.hasAuthenticated)
        XCTAssertTrue(store.hasCompletedOnboarding)
    }

    func testMockBackendRecognizesKnownCompany() async throws {
        let defaults = UserDefaults(suiteName: "AppStoreTests.\(UUID().uuidString)")!
        let store = AppStore(
            defaults: defaults,
            hasAuthenticated: false,
            hasCompletedOnboarding: false,
            seedMockData: false,
            backend: MockBackendService(latency: .zero)
        )

        let decision = try await store.validateCompany(for: "alex@shopify.com")

        XCTAssertEqual(decision, .eligible(company: "Shopify", domain: "shopify.com"))
    }

    func testMockBackendSupportsCompanyReviewState() async throws {
        let defaults = UserDefaults(suiteName: "AppStoreTests.\(UUID().uuidString)")!
        let store = AppStore(
            defaults: defaults,
            hasAuthenticated: false,
            hasCompletedOnboarding: false,
            seedMockData: false,
            backend: MockBackendService(latency: .zero)
        )

        let decision = try await store.validateCompany(for: "alex@newventurelabs.ca")

        XCTAssertEqual(decision, .reviewRequired(domain: "newventurelabs.ca"))
    }

    func testNetworkingPreferencesCanBeUpdated() {
        let store = makeStore()
        let preferences = NetworkingPreferences(
            frequency: .monthly,
            goals: ["Explore entrepreneurship"],
            relationshipMix: "Mostly peers",
            crossCompany: true,
            crossIndustry: true
        )

        store.saveNetworkingPreferences(preferences)

        XCTAssertEqual(store.networkingPreferences, preferences)
    }

    func testResumeBuildsReviewableStructuredDraft() async {
        let store = makeStore()

        await store.processResume(fileURL: URL(fileURLWithPath: "/tmp/profile.pdf"))

        guard case .ready(let draft) = store.member.resumeStatus else {
            return XCTFail("Expected a structured résumé draft")
        }
        XCTAssertEqual(draft.role, "Engineering Director")
        XCTAssertEqual(draft.professionalHistory.count, 2)
        XCTAssertTrue(draft.topics.contains("Distributed systems"))
    }

    func testApplyingResumeDraftDoesNotInventCareerGoals() {
        let store = makeStore()
        let originalAmbition = store.member.professionalAmbition
        let draft = ProfileImportSuggestions(
            name: "Alex Morgan",
            role: "VP Engineering",
            city: "New York, NY",
            roleScope: "Leads platform and product engineering across a multi-team organization.",
            yearsExperience: "15+ years",
            topics: ["Platform strategy", "Engineering leadership"],
            professionalHistory: [
                ProfessionalExperience(id: UUID(), role: "VP Engineering", company: "Example", period: "2023–Present")
            ]
        )

        store.applyResumeSuggestions(draft)

        XCTAssertEqual(store.member.role, "VP Engineering")
        XCTAssertEqual(store.member.city, "New York, NY")
        XCTAssertEqual(store.member.professionalAmbition, originalAmbition)
        XCTAssertEqual(store.member.resumeStatus, .applied)
    }

    func testBlockingRemovesAnExistingConnection() {
        let defaults = UserDefaults(suiteName: "AppStoreTests.\(UUID().uuidString)")!
        let store = AppStore(
            defaults: defaults,
            hasAuthenticated: true,
            hasCompletedOnboarding: true,
            backend: MockBackendService(latency: .zero)
        )

        store.block(.maya)

        XCTAssertTrue(store.connections.isEmpty)
        XCTAssertEqual(store.safetyPreferences.blockedMembers, ["Maya Patel"])
    }

    func testNonMutualOutcomePreservesPrivacyAndReturnsToSearch() {
        let store = makeStore()
        store.respondInterested()

        store.resolveWithoutMutualInterest()
        XCTAssertEqual(store.phase, .notMutual)
        XCTAssertNil(store.conversation)

        store.lookAgain()
        XCTAssertEqual(store.phase, .searching)
    }
}
