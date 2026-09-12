import XCTest
@testable import NetworkTo

/// Token registration, its removal, tap routing, and arrival behaviour on the store.
@MainActor
final class NotificationRegistrationTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "NotificationRegistrationTests.\(UUID().uuidString)")!
    }

    /// A store on the live-flagged mock: session restore, registration, and routing run the
    /// live paths while every backend call is recorded.
    private func makeLiveStore(
        backend: MockBackendService,
        defaults: UserDefaults? = nil,
        hasAuthenticated: Bool = true,
        hasCompletedOnboarding: Bool = true,
        client: MockNotificationCenterClient = MockNotificationCenterClient(status: .authorized)
    ) -> AppStore {
        AppStore(
            defaults: defaults ?? makeDefaults(),
            startPhase: .searching,
            hasAuthenticated: hasAuthenticated,
            hasCompletedOnboarding: hasCompletedOnboarding,
            seedMockData: false,
            backend: backend,
            notificationCenter: client
        )
    }

    private func makeMockStore(
        client: MockNotificationCenterClient = MockNotificationCenterClient(),
        hasAuthenticated: Bool = true,
        hasCompletedOnboarding: Bool = true
    ) -> AppStore {
        AppStore(
            defaults: makeDefaults(),
            hasAuthenticated: hasAuthenticated,
            hasCompletedOnboarding: hasCompletedOnboarding,
            seedMockData: false,
            backend: MockBackendService(latency: .zero),
            notificationCenter: client
        )
    }

    /// A signed-in member with an open mutual-interest conversation on the mock backend.
    private func makeConversationStore() -> AppStore {
        let store = makeMockStore()
        store.respondInterested()
        store.confirmMutualInterest()
        return store
    }

    // MARK: Registration

    func testTokenIsRegisteredWithTheExpectedHexAndEnvironment() async {
        let backend = MockBackendService(latency: .zero, isLive: true)
        let store = makeLiveStore(backend: backend)
        let registration = DeviceRegistration(deviceToken: Data(repeating: 0xAB, count: 32), environment: .sandbox)!

        await store.receiveDeviceRegistration(registration)

        let registered = await backend.registeredDevices
        XCTAssertEqual(registered, [registration])
        XCTAssertEqual(registered.first?.token, String(repeating: "ab", count: 32))
        XCTAssertEqual(registered.first?.environment, .sandbox)
        XCTAssertNil(store.pendingDeviceRegistration)
        XCTAssertEqual(store.registeredDeviceRegistration, registration)
    }

    func testTokenIsBufferedUntilTheSessionIsRestored() async {
        let backend = MockBackendService(latency: .zero, isLive: true, hasSession: true)
        let store = makeLiveStore(backend: backend, hasAuthenticated: false, hasCompletedOnboarding: false)
        let registration = DeviceRegistration.fixture()

        await store.receiveDeviceRegistration(registration)
        var registered = await backend.registeredDevices
        XCTAssertTrue(registered.isEmpty)
        XCTAssertEqual(store.pendingDeviceRegistration, registration)

        await store.restoreBackendSession()

        registered = await backend.registeredDevices
        XCTAssertEqual(registered, [registration])
        XCTAssertNil(store.pendingDeviceRegistration)
        XCTAssertEqual(store.registeredDeviceRegistration, registration)
    }

    func testRepeatedTokenRegistersAgainSoTheLastConfirmedTimeMoves() async {
        let backend = MockBackendService(latency: .zero, isLive: true)
        let store = makeLiveStore(backend: backend)
        let registration = DeviceRegistration.fixture()

        await store.receiveDeviceRegistration(registration)
        await store.receiveDeviceRegistration(registration)

        let events = await backend.events
        XCTAssertEqual(events, ["register:\(registration.token)", "register:\(registration.token)"])
        let unregistered = await backend.unregisteredDeviceTokens
        XCTAssertTrue(unregistered.isEmpty)
    }

    func testChangedTokenRegistersTheNewOneAndRemovesTheOld() async {
        let backend = MockBackendService(latency: .zero, isLive: true)
        let store = makeLiveStore(backend: backend)
        let first = DeviceRegistration.fixture("a")
        let second = DeviceRegistration.fixture("b")

        await store.receiveDeviceRegistration(first)
        await store.receiveDeviceRegistration(second)

        let events = await backend.events
        XCTAssertEqual(events, ["register:\(first.token)", "register:\(second.token)", "unregister:\(first.token)"])
        XCTAssertEqual(store.registeredDeviceRegistration, second)
    }

    func testFailedRegistrationStaysPendingAndSilent() async {
        let backend = MockBackendService(latency: .zero, isLive: true)
        let store = makeLiveStore(backend: backend)
        let failing = DeviceRegistration(token: "dead" + String(repeating: "0", count: 60), environment: .sandbox)!

        await store.receiveDeviceRegistration(failing)

        let registered = await backend.registeredDevices
        XCTAssertTrue(registered.isEmpty)
        XCTAssertEqual(store.pendingDeviceRegistration, failing)
        XCTAssertNil(store.registeredDeviceRegistration)
        XCTAssertNil(store.transientMessage)
    }

    func testRegistrationIsRememberedAcrossLaunches() async {
        let defaults = makeDefaults()
        let store = makeLiveStore(backend: MockBackendService(latency: .zero, isLive: true), defaults: defaults)
        let registration = DeviceRegistration.fixture(environment: .production)

        await store.receiveDeviceRegistration(registration)

        let relaunched = makeLiveStore(backend: MockBackendService(latency: .zero, isLive: true), defaults: defaults)
        XCTAssertEqual(relaunched.registeredDeviceRegistration, registration)
    }

    func testNothingIsRegisteredBeforeOnboardingOrInDemonstrationMode() async {
        let backend = MockBackendService(latency: .zero, isLive: true)
        let notOnboarded = makeLiveStore(backend: backend, hasCompletedOnboarding: false)
        await notOnboarded.receiveDeviceRegistration(.fixture())
        let registered = await backend.registeredDevices
        XCTAssertTrue(registered.isEmpty)
        XCTAssertNotNil(notOnboarded.pendingDeviceRegistration)

        let demo = MockBackendService(latency: .zero)
        let demoStore = AppStore(
            defaults: makeDefaults(),
            hasAuthenticated: true,
            hasCompletedOnboarding: true,
            seedMockData: false,
            backend: demo,
            notificationCenter: MockNotificationCenterClient(status: .authorized)
        )
        await demoStore.receiveDeviceRegistration(.fixture())
        let demoRegistered = await demo.registeredDevices
        XCTAssertTrue(demoRegistered.isEmpty)
    }

    // MARK: Sign-out and deletion

    func testSignOutRemovesTheTokenBeforeEndingTheSessionAndForgetsIt() async {
        let defaults = makeDefaults()
        let backend = MockBackendService(latency: .zero, isLive: true)
        let store = makeLiveStore(backend: backend, defaults: defaults)
        let registration = DeviceRegistration.fixture()
        await store.receiveDeviceRegistration(registration)

        store.signOut()
        await store.signOutTask?.value

        let events = await backend.events
        XCTAssertEqual(events, ["register:\(registration.token)", "unregister:\(registration.token)", "signOut"])
        XCTAssertNil(store.registeredDeviceRegistration)
        XCTAssertNil(store.pendingDeviceRegistration)
        XCTAssertFalse(store.hasAuthenticated)
        let relaunched = makeLiveStore(backend: MockBackendService(latency: .zero, isLive: true), defaults: defaults)
        XCTAssertNil(relaunched.registeredDeviceRegistration)
    }

    func testSignOutWithoutARegistrationOnlyEndsTheSession() async {
        let backend = MockBackendService(latency: .zero)
        let store = AppStore(
            defaults: makeDefaults(),
            hasAuthenticated: true,
            hasCompletedOnboarding: true,
            seedMockData: false,
            backend: backend,
            notificationCenter: MockNotificationCenterClient()
        )

        store.signOut()
        await store.signOutTask?.value

        let events = await backend.events
        XCTAssertEqual(events, ["signOut"])
    }

    func testDeletionForgetsTheRegistrationAfterTheBackendConfirms() async {
        let defaults = makeDefaults()
        let backend = MockBackendService(latency: .zero, isLive: true)
        let store = makeLiveStore(backend: backend, defaults: defaults)
        await store.receiveDeviceRegistration(.fixture())
        store.declineNotificationInvite()

        store.deleteAccount()

        let deleted = await eventually { !store.hasAuthenticated }
        XCTAssertTrue(deleted)
        XCTAssertNil(store.registeredDeviceRegistration)
        XCTAssertFalse(store.hasDeclinedNotificationInvite)
        let relaunched = makeLiveStore(backend: MockBackendService(latency: .zero, isLive: true), defaults: defaults)
        XCTAssertNil(relaunched.registeredDeviceRegistration)
        XCTAssertFalse(relaunched.hasDeclinedNotificationInvite)
    }

    // MARK: Routing

    func testNewMessageTapOpensTheConversationWithoutMarkingItRead() {
        let store = makeConversationStore()
        let id = store.conversation!.id

        store.handleNotificationRoute(.conversation(id, kind: .newMessage))

        XCTAssertEqual(store.selectedTab, .messages)
        XCTAssertEqual(store.messagesPath, [.conversation(id)])
        XCTAssertEqual(store.conversation?.isUnread, true)
        XCTAssertNil(store.pendingNotificationRoute)

        store.openConversation()

        XCTAssertEqual(store.conversation?.isUnread, false)
    }

    func testMismatchedConversationLandsOnMessagesWithoutPushing() {
        let store = makeConversationStore()

        store.handleNotificationRoute(.conversation(UUID(), kind: .meetupReminder))

        XCTAssertEqual(store.selectedTab, .messages)
        XCTAssertTrue(store.messagesPath.isEmpty)
    }

    func testMutualInterestWithoutAnIdentifierOpensTheOnlyConversation() {
        let store = makeConversationStore()

        store.handleNotificationRoute(.conversation(nil, kind: .mutualInterest))

        XCTAssertEqual(store.selectedTab, .messages)
        XCTAssertEqual(store.messagesPath, [.conversation(store.conversation!.id)])
    }

    func testConversationTapWithoutAConversationLandsOnMessages() {
        let store = makeMockStore()

        store.handleNotificationRoute(.conversation(UUID(), kind: .newMessage))

        XCTAssertEqual(store.selectedTab, .messages)
        XCTAssertTrue(store.messagesPath.isEmpty)
    }

    func testIntroductionTapSelectsToday() {
        let store = makeMockStore()
        store.selectedTab = .profile

        store.handleNotificationRoute(.introduction(store.introduction.id))

        XCTAssertEqual(store.selectedTab, .today)
        XCTAssertNil(store.pendingNotificationRoute)
    }

    func testRouteIsDiscardedWhileSignedOutOrBeforeOnboarding() {
        let signedOut = makeMockStore(hasAuthenticated: false)
        signedOut.handleNotificationRoute(.conversation(nil, kind: .newMessage))
        XCTAssertEqual(signedOut.selectedTab, .today)
        XCTAssertNil(signedOut.pendingNotificationRoute)

        signedOut.completeAuthentication(.signIn)
        XCTAssertEqual(signedOut.selectedTab, .today)

        let onboarding = makeMockStore(hasCompletedOnboarding: false)
        onboarding.handleNotificationRoute(.conversation(nil, kind: .newMessage))
        XCTAssertEqual(onboarding.selectedTab, .today)
        XCTAssertNil(onboarding.pendingNotificationRoute)
    }

    func testColdLaunchTapWaitsForTheSessionRestore() async {
        let backend = MockBackendService(latency: .zero, isLive: true, hasSession: true)
        let store = makeLiveStore(backend: backend, hasAuthenticated: false, hasCompletedOnboarding: false)
        store.selectedTab = .profile

        store.handleNotificationRoute(.introduction(nil))
        XCTAssertEqual(store.pendingNotificationRoute, .introduction(nil))
        XCTAssertEqual(store.selectedTab, .profile)

        await store.restoreBackendSession()

        XCTAssertTrue(store.hasAuthenticated)
        XCTAssertNil(store.pendingNotificationRoute)
        XCTAssertEqual(store.selectedTab, .today)
    }

    func testColdLaunchTapIsDiscardedWhenTheSessionCannotBeRestored() async {
        let backend = MockBackendService(latency: .zero, isLive: true, hasSession: false)
        let store = makeLiveStore(backend: backend, hasAuthenticated: false, hasCompletedOnboarding: false)

        store.handleNotificationRoute(.conversation(nil, kind: .newMessage))
        await store.restoreBackendSession()

        XCTAssertFalse(store.hasAuthenticated)
        XCTAssertNil(store.pendingNotificationRoute)
        XCTAssertEqual(store.selectedTab, .today)
    }

    func testSignOutClearsThePathAndAnyPendingRoute() {
        let store = makeConversationStore()
        store.handleNotificationRoute(.conversation(store.conversation!.id, kind: .newMessage))
        XCTAssertFalse(store.messagesPath.isEmpty)

        store.signOut()

        XCTAssertTrue(store.messagesPath.isEmpty)
        XCTAssertNil(store.pendingNotificationRoute)
        XCTAssertEqual(store.selectedTab, .today)
    }

    // MARK: Arrival while the app is open

    func testViewingTheDestinationSuppressesTheBanner() {
        let store = makeConversationStore()
        let id = store.conversation!.id
        store.handleNotificationRoute(.conversation(id, kind: .newMessage))

        XCTAssertTrue(store.isViewingDestination(of: .conversation(id, kind: .newMessage)))
        XCTAssertTrue(store.isViewingDestination(of: .conversation(id, kind: .feedbackDue)))
        XCTAssertFalse(store.shouldPresentArrivingNotification(.conversation(id, kind: .meetupReminder)))
        XCTAssertFalse(store.isViewingDestination(of: .conversation(UUID(), kind: .newMessage)))
        XCTAssertFalse(store.isViewingDestination(of: .conversation(nil, kind: .mutualInterest)))
        XCTAssertFalse(store.isViewingDestination(of: .introduction(nil)))

        store.selectedTab = .today

        XCTAssertFalse(store.isViewingDestination(of: .conversation(id, kind: .newMessage)))
        XCTAssertTrue(store.shouldPresentArrivingNotification(.conversation(id, kind: .newMessage)))
        XCTAssertTrue(store.isViewingDestination(of: .introduction(nil)))
        XCTAssertFalse(store.shouldPresentArrivingNotification(.introduction(UUID())))
    }

    func testMutualInterestArrivingOnTodayStillShowsTheBanner() {
        let store = makeMockStore()
        store.selectedTab = .today

        XCTAssertTrue(store.shouldPresentArrivingNotification(.conversation(nil, kind: .mutualInterest)))
        XCTAssertTrue(store.shouldPresentArrivingNotification(nil))
    }

    func testViewedItemsLeaveThePhonesList() async {
        let client = MockNotificationCenterClient()
        let store = makeMockStore(client: client)
        let item = NotificationItem.conversation(UUID())

        store.didViewNotificationItem(item)

        let removed = await eventually { client.removedItems == [item] }
        XCTAssertTrue(removed)
    }
}
