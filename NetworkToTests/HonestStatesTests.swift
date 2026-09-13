import XCTest
@testable import NetworkTo

/// Notices mean what they show, every save says what happened, and the phone never learns
/// why an introduction ended: the ended state appears once, at the expiry, whatever ended it.
@MainActor
final class HonestStatesTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "HonestStatesTests.\(UUID().uuidString)")!
    }

    /// The demonstration store: Maya is an existing Connection and Sarah is today's introduction.
    private func makeStore(
        backend: MockBackendService = MockBackendService(latency: .zero),
        defaults: UserDefaults? = nil
    ) -> AppStore {
        AppStore(
            defaults: defaults ?? makeDefaults(),
            hasAuthenticated: true,
            hasCompletedOnboarding: true,
            backend: backend,
            notificationCenter: MockNotificationCenterClient(status: .denied)
        )
    }

    /// A store on the live-flagged mock: every refresh derives the phase from the snapshot the
    /// backend serves, exactly as the product backend drives it.
    private func makeLiveStore(backend: MockBackendService, defaults: UserDefaults? = nil) -> AppStore {
        AppStore(
            defaults: defaults ?? makeDefaults(),
            startPhase: .searching,
            hasAuthenticated: true,
            hasCompletedOnboarding: true,
            seedMockData: false,
            backend: backend,
            notificationCenter: MockNotificationCenterClient(status: .denied)
        )
    }

    /// Waits for a condition and fails at the call site if it never holds.
    private func waitUntil(
        _ condition: () async -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let satisfied = await eventually(condition)
        XCTAssertTrue(satisfied, "the condition never held", file: file, line: line)
    }

    /// A store in a conversation with Sarah, with the interested response already recorded.
    private func makeStoreInConversation(backend: MockBackendService) async -> AppStore {
        let store = makeStore(backend: backend)
        store.respondInterested()
        store.confirmMutualInterest()
        await waitUntil { await backend.events.contains("respondToIntroduction") }
        return store
    }

    // MARK: - Notices

    func testSuccessAndInformationNoticesLeaveOnTheirOwn() {
        let store = makeStore()

        store.presentSuccess("Introduction preferences saved")
        XCTAssertEqual(store.notice?.kind, .success)
        XCTAssertEqual(store.notice?.persists, false)
        XCTAssertEqual(store.notice?.canRetry, false)

        store.presentInformation("Couldn’t refresh right now.")
        XCTAssertEqual(store.notice?.kind, .information)
        XCTAssertEqual(store.notice?.text, "Couldn’t refresh right now.")
        XCTAssertEqual(store.notice?.persists, false)
    }

    func testErrorNoticesPersistAndOfferRetryOnlyWhenTheActionCanRepeat() {
        let store = makeStore()

        store.presentError("Introduction is no longer open")
        XCTAssertEqual(store.notice?.kind, .error)
        XCTAssertEqual(store.notice?.persists, true)
        XCTAssertEqual(store.notice?.canRetry, false)

        store.presentError("Availability wasn’t saved.") {}
        XCTAssertEqual(store.notice?.canRetry, true)
    }

    func testANewerNoticeReplacesTheOlderAndDropsItsRetry() {
        let store = makeStore()
        let retries = Counter()
        store.presentError("Availability wasn’t saved.") { retries.increment() }
        let older = store.notice

        store.presentSuccess("Report submitted privately")
        XCTAssertNotEqual(store.notice, older)
        store.dismissNotice(id: older!.id)
        XCTAssertEqual(store.notice?.text, "Report submitted privately")

        store.retryFailedAction()
        XCTAssertEqual(retries.value, 0)
        XCTAssertNil(store.notice)
    }

    func testRetryRunsThePendingActionOnceAndClearsTheNotice() {
        let store = makeStore()
        let retries = Counter()
        store.presentError("Meeting preferences weren’t saved.") { retries.increment() }

        store.retryFailedAction()
        store.retryFailedAction()

        XCTAssertEqual(retries.value, 1)
        XCTAssertNil(store.notice)
    }

    func testDismissingByIdentifierIgnoresAReplacedNotice() {
        let store = makeStore()
        store.presentInformation("Membership is needed for new introductions.")
        let first = store.notice!
        store.presentSuccess("Safety settings saved")

        store.dismissNotice(id: first.id)
        XCTAssertEqual(store.notice?.text, "Safety settings saved")

        store.dismissNotice(id: store.notice!.id)
        XCTAssertNil(store.notice)
    }

    func testSignOutClearsTheNoticeAndThePendingRetry() {
        let store = makeStore()
        let retries = Counter()
        store.presentError("Connection wasn’t removed.") { retries.increment() }

        store.signOut()
        store.retryFailedAction()

        XCTAssertNil(store.notice)
        XCTAssertEqual(retries.value, 0)
    }

    func testARefreshThatFailsIsInformationNotAnError() async {
        let backend = MockBackendService(latency: .zero, isLive: true, hasSession: true)
        let store = makeLiveStore(backend: backend)
        await backend.setRefreshFails(true)

        await store.refreshFromBackend()

        XCTAssertEqual(store.notice?.kind, .information)
        XCTAssertEqual(store.notice?.text, "Couldn’t refresh right now.")
        XCTAssertEqual(store.notice?.persists, false)

        store.dismissNotice()
        await store.refreshFromBackend(silently: true)
        XCTAssertNil(store.notice)
    }

    // MARK: - Ended introduction

    func testTheEndedStateShowsOnceWhenAWaitedIntroductionIsGone() async {
        let backend = MockBackendService(latency: .zero, isLive: true, hasSession: true)
        let store = makeLiveStore(backend: backend)
        await store.refreshFromBackend()
        XCTAssertEqual(store.phase, .ready)

        store.respondInterested()
        await waitUntil { store.waitedIntroductionID == MockData.introduction.id }
        XCTAssertEqual(store.phase, .waiting)

        await backend.setSnapshot(MockData.snapshot(introduction: nil))
        await store.refreshFromBackend()
        XCTAssertEqual(store.phase, .notMutual)

        await store.refreshFromBackend()
        XCTAssertEqual(store.phase, .notMutual, "the ended state stays until Continue")

        store.lookAgain()
        XCTAssertEqual(store.phase, .searching)
        XCTAssertNil(store.waitedIntroductionID)

        await store.refreshFromBackend()
        XCTAssertEqual(store.phase, .searching, "Continue shows the ended state exactly once")
    }

    func testARefreshWhileWaitingRemembersTheIntroduction() async {
        let backend = MockBackendService(latency: .zero, isLive: true, hasSession: true)
        await backend.setSnapshot(MockData.snapshot(waiting: true))
        let store = makeLiveStore(backend: backend)

        await store.refreshFromBackend()

        XCTAssertEqual(store.phase, .waiting)
        XCTAssertEqual(store.waitedIntroductionID, MockData.introduction.id)
    }

    func testANewIntroductionSkipsTheEndedState() async {
        let backend = MockBackendService(latency: .zero, isLive: true, hasSession: true)
        await backend.setSnapshot(MockData.snapshot(waiting: true))
        let store = makeLiveStore(backend: backend)
        await store.refreshFromBackend()
        XCTAssertEqual(store.phase, .waiting)

        let next = MockData.introductionVariant(id: UUID())
        await backend.setSnapshot(MockData.snapshot(introduction: next))
        await store.refreshFromBackend()

        XCTAssertEqual(store.phase, .ready)
        XCTAssertEqual(store.introduction.id, next.id)
        XCTAssertNil(store.waitedIntroductionID)
    }

    func testMutualInterestClearsTheMemory() async {
        let backend = MockBackendService(latency: .zero, isLive: true, hasSession: true)
        await backend.setSnapshot(MockData.snapshot(waiting: true))
        let store = makeLiveStore(backend: backend)
        await store.refreshFromBackend()

        let conversation = Conversation(
            id: UUID(), person: .sarah, introductionReason: "Shared platform interests",
            messages: [], isUnread: true, meetupStatus: .coordinating
        )
        await backend.setSnapshot(MockData.snapshot(introduction: nil, conversation: conversation))
        await store.refreshFromBackend()

        XCTAssertEqual(store.phase, .conversation)
        XCTAssertNil(store.waitedIntroductionID)
    }

    func testTheEndedStateIsRememberedAcrossLaunches() async {
        let defaults = makeDefaults()
        let first = MockBackendService(latency: .zero, isLive: true, hasSession: true)
        await first.setSnapshot(MockData.snapshot(waiting: true))
        let earlier = makeLiveStore(backend: first, defaults: defaults)
        await earlier.refreshFromBackend()
        XCTAssertEqual(earlier.phase, .waiting)

        let relaunched = MockBackendService(latency: .zero, isLive: true, hasSession: true, introductionAvailable: false)
        let store = makeLiveStore(backend: relaunched, defaults: defaults)
        await store.refreshFromBackend()

        XCTAssertEqual(store.phase, .notMutual)
    }

    func testDeletingTheAccountForgetsTheWaitedIntroduction() async {
        let defaults = makeDefaults()
        let backend = MockBackendService(latency: .zero, isLive: true, hasSession: true)
        await backend.setSnapshot(MockData.snapshot(waiting: true))
        let store = makeLiveStore(backend: backend, defaults: defaults)
        await store.refreshFromBackend()
        let key = AppStore.waitedIntroductionKey(for: ProfessionalProfile.currentMember.id)
        XCTAssertNotNil(defaults.string(forKey: key))

        store.deleteAccount()

        await waitUntil { store.waitedIntroductionID == nil }
        XCTAssertNil(defaults.string(forKey: key))
    }

    // MARK: - Saves

    func testAvailabilityIsRestoredWhenTheSaveFailsAndKeptWhenRetrySucceeds() async {
        let backend = MockBackendService(latency: .zero)
        let store = makeStore(backend: backend)
        await backend.setSavesFail(true)

        store.setAvailability(area: .downtown, window: .lunch)
        XCTAssertEqual(store.availability?.area, .downtown)

        await waitUntil { store.notice?.kind == .error }
        XCTAssertNil(store.availability)
        XCTAssertEqual(store.notice?.text, "Availability wasn’t saved.")
        XCTAssertEqual(store.notice?.canRetry, true)

        await backend.setSavesFail(false)
        store.retryFailedAction()
        XCTAssertEqual(store.availability?.area, .downtown)
        XCTAssertEqual(store.availability?.window, .lunch)
        await waitUntil { await backend.events.contains("saveAvailability") }
        XCTAssertNil(store.notice, "the availability banner is the confirmation")
    }

    func testClearingAvailabilityIsRestoredWhenTheSaveFails() async {
        let backend = MockBackendService(latency: .zero)
        let store = makeStore(backend: backend)
        store.setAvailability(area: .westSide, window: .afterWork)
        await waitUntil { await backend.events.contains("saveAvailability") }
        await backend.setSavesFail(true)

        store.clearAvailability()
        XCTAssertNil(store.availability)

        await waitUntil { store.notice?.kind == .error }
        XCTAssertEqual(store.availability?.area, .westSide)
        XCTAssertEqual(store.notice?.text, "Availability wasn’t saved.")
    }

    func testIntroductionPreferencesRollBackAndSucceedOnRetry() async {
        let backend = MockBackendService(latency: .zero)
        let store = makeStore(backend: backend)
        let original = store.networkingPreferences
        var changed = original
        changed.frequency = .monthly
        await backend.setSavesFail(true)

        store.saveNetworkingPreferences(changed)
        XCTAssertEqual(store.networkingPreferences, changed)

        await waitUntil { store.notice?.kind == .error }
        XCTAssertEqual(store.networkingPreferences, original)
        XCTAssertEqual(store.notice?.text, "Introduction preferences weren’t saved.")

        await backend.setSavesFail(false)
        store.retryFailedAction()
        XCTAssertEqual(store.networkingPreferences, changed)
        await waitUntil { store.notice?.kind == .success }
        XCTAssertEqual(store.notice?.text, "Introduction preferences saved")
    }

    func testMeetingPreferencesRollBackAndSucceedOnRetry() async {
        let backend = MockBackendService(latency: .zero)
        let store = makeStore(backend: backend)
        let original = store.meetingPreferences
        var changed = original
        changed.windows = [.afternoon]
        await backend.setSavesFail(true)

        store.saveMeetingPreferences(changed)

        await waitUntil { store.notice?.kind == .error }
        XCTAssertEqual(store.meetingPreferences, original)
        XCTAssertEqual(store.notice?.text, "Meeting preferences weren’t saved.")

        await backend.setSavesFail(false)
        store.retryFailedAction()
        XCTAssertEqual(store.meetingPreferences, changed)
        await waitUntil { store.notice?.text == "Meeting preferences saved" }
        XCTAssertEqual(store.notice?.kind, .success)
    }

    func testUnblockRollsBackAndSucceedsOnRetry() async {
        let backend = MockBackendService(latency: .zero)
        let store = makeStore(backend: backend)
        store.saveSafetyPreferences(SafetyPreferences(blockedMembers: ["Maya Patel"]))
        await backend.setSavesFail(true)

        store.unblock("Maya Patel")
        XCTAssertTrue(store.safetyPreferences.blockedMembers.isEmpty)

        await waitUntil { store.notice?.kind == .error }
        XCTAssertEqual(store.safetyPreferences.blockedMembers, ["Maya Patel"])
        XCTAssertEqual(store.notice?.text, "Maya Patel wasn’t unblocked.")

        await backend.setSavesFail(false)
        store.retryFailedAction()
        XCTAssertTrue(store.safetyPreferences.blockedMembers.isEmpty)
        await waitUntil { store.notice?.text == "Maya Patel was unblocked" }
        XCTAssertEqual(store.notice?.kind, .success)
    }

    func testBlockRestoresTheConnectionAndTheConversationWhenTheSaveFails() async {
        let backend = MockBackendService(latency: .zero)
        let store = await makeStoreInConversation(backend: backend)
        XCTAssertEqual(store.connections.map(\.person), [.maya])
        await backend.setSavesFail(true)

        store.block(.maya)
        XCTAssertTrue(store.connections.isEmpty)
        XCTAssertEqual(store.safetyPreferences.blockedMembers, ["Maya Patel"])

        await waitUntil { store.notice?.kind == .error }
        XCTAssertEqual(store.connections.map(\.person), [.maya])
        XCTAssertTrue(store.safetyPreferences.blockedMembers.isEmpty)
        XCTAssertEqual(store.notice?.text, "Maya Patel wasn’t blocked.")

        store.dismissNotice()
        store.blockCurrentPerson()
        XCTAssertEqual(store.conversation?.isBlocked, true)
        XCTAssertEqual(store.phase, .searching)

        await waitUntil { store.notice?.kind == .error }
        XCTAssertEqual(store.conversation?.isBlocked, false)
        XCTAssertEqual(store.conversation?.isEnded, false)
        XCTAssertEqual(store.phase, .mutual)
        XCTAssertEqual(store.notice?.text, "Sarah Chen wasn’t blocked.")

        await backend.setSavesFail(false)
        store.retryFailedAction()
        await waitUntil { store.notice?.text == "Sarah Chen was blocked" }
        XCTAssertEqual(store.conversation?.isBlocked, true)
        XCTAssertEqual(store.safetyPreferences.blockedMembers, ["Sarah Chen"])
        XCTAssertEqual(store.phase, .searching)
    }

    func testRemovingAConnectionRollsBackAndSucceedsOnRetry() async {
        let backend = MockBackendService(latency: .zero)
        let store = makeStore(backend: backend)
        let connection = store.connections[0]
        await backend.setSavesFail(true)

        store.removeConnection(connection.id)
        XCTAssertTrue(store.connections.isEmpty)

        await waitUntil { store.notice?.kind == .error }
        XCTAssertEqual(store.connections, [connection])
        XCTAssertEqual(store.notice?.text, "Connection wasn’t removed.")

        await backend.setSavesFail(false)
        store.retryFailedAction()
        XCTAssertTrue(store.connections.isEmpty)
        await waitUntil { store.notice?.text == "Connection removed" }
    }

    func testEndingTheConversationRollsBackAndSucceedsOnRetry() async {
        let backend = MockBackendService(latency: .zero)
        let store = await makeStoreInConversation(backend: backend)
        await backend.setSavesFail(true)

        store.endCurrentConversation()
        XCTAssertEqual(store.conversation?.isEnded, true)
        XCTAssertEqual(store.phase, .searching)

        await waitUntil { store.notice?.kind == .error }
        XCTAssertEqual(store.conversation?.isEnded, false)
        XCTAssertEqual(store.phase, .mutual)
        XCTAssertEqual(store.notice?.text, "Conversation wasn’t ended.")

        await backend.setSavesFail(false)
        store.retryFailedAction()
        XCTAssertEqual(store.conversation?.isEnded, true)
        await waitUntil { store.notice?.text == "Conversation ended" }
        XCTAssertEqual(store.phase, .searching)
    }

    func testACoffeePlanAppearsOnlyOnceItIsSaved() async {
        let backend = MockBackendService(latency: .zero)
        let store = await makeStoreInConversation(backend: backend)
        await backend.setSavesFail(true)

        store.planMeetup(detail: "Thursday at 4:30 PM · Union Station")
        XCTAssertEqual(store.conversation?.meetupStatus, .coordinating)

        await waitUntil { store.notice?.kind == .error }
        XCTAssertEqual(store.conversation?.meetupStatus, .coordinating)
        XCTAssertEqual(store.notice?.text, "Coffee plan wasn’t sent.")
        XCTAssertEqual(store.notice?.canRetry, true)

        await backend.setSavesFail(false)
        store.retryFailedAction()
        await waitUntil { store.conversation?.meetupStatus == .planned("Thursday at 4:30 PM · Union Station") }
        XCTAssertNil(store.notice, "the plan on screen is the confirmation")
    }

    func testFeedbackChangesNothingUntilTheBackendHoldsIt() async {
        let backend = MockBackendService(latency: .zero)
        let store = await makeStoreInConversation(backend: backend)
        store.requestFeedback()
        await backend.setSavesFail(true)

        let submitted = await store.recordFeedback(.good, stayConnected: true)

        XCTAssertFalse(submitted)
        XCTAssertEqual(store.phase, .feedback)
        XCTAssertEqual(store.conversation?.meetupStatus, .feedbackDue)
        XCTAssertEqual(store.connections.count, 1)
        XCTAssertEqual(store.selectedTab, .today)
        XCTAssertNil(store.notice, "the sheet reports the failure inline")

        await backend.setSavesFail(false)
        let retried = await store.recordFeedback(.good, stayConnected: true)

        XCTAssertTrue(retried)
        XCTAssertEqual(store.phase, .connected)
        XCTAssertEqual(store.conversation?.meetupStatus, .completed)
        XCTAssertEqual(store.connections.count, 2)
        XCTAssertEqual(store.selectedTab, .connections)
    }

    func testASuccessNoticeWaitsForTheBackend() async {
        let backend = MockBackendService(latency: .milliseconds(150))
        let store = makeStore(backend: backend)
        var changed = store.networkingPreferences
        changed.crossCompany = false

        store.saveNetworkingPreferences(changed)

        XCTAssertNil(store.notice)
        await waitUntil { store.notice?.kind == .success }
        XCTAssertEqual(store.notice?.text, "Introduction preferences saved")
    }

    func testProfileEditsStayOnScreenWhenTheSaveFails() async {
        let backend = MockBackendService(latency: .zero)
        let store = makeStore(backend: backend)
        await backend.setSavesFail(true)

        store.updateMemberContext(
            name: "Alex Morgan",
            role: "VP Engineering",
            city: "Toronto, ON",
            roleScope: "Leads platform and product engineering across three teams.",
            currentFocus: "Introducing applied AI capabilities into a mature platform.",
            yearsExperience: "15+ years",
            growthAreas: ["Applied AI products"],
            professionalAmbition: "Build a product-minded engineering organization.",
            growthInterest: "Compare how peers set an AI strategy.",
            contributionAreas: ["Engineering leadership"],
            helpFormats: ["Compare approaches"],
            contribution: "Lessons from scaling engineering ownership.",
            contributionBoundaries: "Not offering recruiting referrals."
        )

        await waitUntil { store.notice?.kind == .error }
        XCTAssertEqual(store.member.role, "VP Engineering")
        XCTAssertEqual(store.notice?.text, "Profile changes weren’t saved.")
        XCTAssertEqual(store.notice?.canRetry, true)

        await backend.setSavesFail(false)
        store.retryFailedAction()
        await waitUntil { await backend.events.contains("saveProfile") }
        XCTAssertEqual(store.member.role, "VP Engineering")
        XCTAssertNil(store.notice)
    }

    func testAFailedIntroductionResponseReturnsTheButtonsWithTheBackendMessage() async {
        let backend = MockBackendService(latency: .zero)
        let store = makeStore(backend: backend)
        await backend.setSavesFail(true)

        store.respondInterested()
        XCTAssertEqual(store.phase, .waiting)

        await waitUntil { store.phase == .ready }
        XCTAssertEqual(store.notice?.kind, .error)
        XCTAssertEqual(store.notice?.text, MockServiceError.requestFailed.localizedDescription)
        XCTAssertEqual(store.notice?.canRetry, false)
        XCTAssertNil(store.waitedIntroductionID)
    }
}

/// A retry target tests can count; a class so the store's retry closure can update it.
@MainActor
private final class Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}
