import XCTest
@testable import NetworkTo

/// Permission, the invitation card, and "Not now" memory, driven through the mock notification
/// centre so no test ever presents the phone's dialog.
@MainActor
final class NotificationStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "NotificationStoreTests.\(UUID().uuidString)")!
    }

    private func makeStore(
        client: MockNotificationCenterClient,
        defaults: UserDefaults? = nil,
        phase: IntroductionPhase = .searching,
        hasAuthenticated: Bool = true,
        hasCompletedOnboarding: Bool = true,
        membership: MembershipStatus = .trial(),
        backend: MockBackendService = MockBackendService(latency: .zero)
    ) -> AppStore {
        AppStore(
            defaults: defaults ?? makeDefaults(),
            startPhase: phase,
            hasAuthenticated: hasAuthenticated,
            hasCompletedOnboarding: hasCompletedOnboarding,
            seedMockData: false,
            membership: membership,
            backend: backend,
            notificationCenter: client
        )
    }

    // MARK: Invitation

    func testInviteWaitsUntilTheStatusIsRead() async {
        let client = MockNotificationCenterClient(status: .notDetermined)
        let store = makeStore(client: client)

        XCTAssertEqual(store.notificationAuthorization, .unknown)
        XCTAssertFalse(store.shouldOfferNotificationInvite)

        await store.refreshNotificationAuthorization()

        XCTAssertEqual(store.notificationAuthorization, .notDetermined)
        XCTAssertTrue(store.shouldOfferNotificationInvite)
    }

    func testInviteAppearsOnlyWhileSearchingOrWaiting() async {
        let expectations: [(IntroductionPhase, Bool)] = [
            (.searching, true), (.waiting, true), (.ready, false), (.mutual, false), (.conversation, false), (.passed, false),
        ]
        for (phase, expected) in expectations {
            let store = makeStore(client: MockNotificationCenterClient(), phase: phase)
            await store.refreshNotificationAuthorization()
            XCTAssertEqual(store.shouldOfferNotificationInvite, expected, "\(phase)")
        }
    }

    func testInviteIsHiddenWhenThePhoneAlreadyDecided() async {
        for status in [NotificationAuthorizationStatus.authorized, .denied] {
            let store = makeStore(client: MockNotificationCenterClient(status: status))
            await store.refreshNotificationAuthorization()
            XCTAssertFalse(store.shouldOfferNotificationInvite, "\(status)")
        }
    }

    func testInviteNeedsAccessToIntroductions() async {
        let store = makeStore(client: MockNotificationCenterClient(), membership: .expired)

        await store.refreshNotificationAuthorization()

        XCTAssertFalse(store.shouldOfferNotificationInvite)
    }

    func testInviteNeedsASignedInOnboardedMember() async {
        let signedOut = makeStore(client: MockNotificationCenterClient(), hasAuthenticated: false)
        await signedOut.refreshNotificationAuthorization()
        XCTAssertFalse(signedOut.shouldOfferNotificationInvite)

        let onboarding = makeStore(client: MockNotificationCenterClient(), hasCompletedOnboarding: false)
        await onboarding.refreshNotificationAuthorization()
        XCTAssertFalse(onboarding.shouldOfferNotificationInvite)
    }

    // MARK: Permission

    func testTurnOnPromptsOnceAndNeverAgain() async {
        let client = MockNotificationCenterClient()
        let store = makeStore(client: client)
        await store.refreshNotificationAuthorization()

        await store.requestNotificationAuthorization()
        await store.requestNotificationAuthorization()

        XCTAssertEqual(client.requestCount, 1)
        XCTAssertEqual(store.notificationAuthorization, .authorized)
        XCTAssertFalse(store.shouldOfferNotificationInvite)
        XCTAssertFalse(store.hasDeclinedNotificationInvite)
        XCTAssertNil(store.transientMessage)
    }

    func testDecliningInTheDialogIsFinalAndSilent() async {
        let client = MockNotificationCenterClient()
        client.grantsOnRequest = false
        let store = makeStore(client: client)
        await store.refreshNotificationAuthorization()

        await store.requestNotificationAuthorization()
        await store.requestNotificationAuthorization()

        XCTAssertEqual(client.requestCount, 1)
        XCTAssertEqual(store.notificationAuthorization, .denied)
        XCTAssertFalse(store.shouldOfferNotificationInvite)
        XCTAssertEqual(client.registerCalls, 0)
        XCTAssertNil(store.transientMessage)
    }

    func testADeniedPhoneIsNeverPrompted() async {
        let client = MockNotificationCenterClient(status: .denied)
        let store = makeStore(client: client)
        await store.refreshNotificationAuthorization()

        await store.requestNotificationAuthorization()

        XCTAssertEqual(client.requestCount, 0)
        XCTAssertEqual(store.notificationAuthorization, .denied)
    }

    func testInviteDisappearsWhenTheStatusChangesElsewhere() async {
        let client = MockNotificationCenterClient()
        let store = makeStore(client: client)
        await store.refreshNotificationAuthorization()
        XCTAssertTrue(store.shouldOfferNotificationInvite)

        client.status = .authorized
        await store.refreshNotificationAuthorization()

        XCTAssertFalse(store.shouldOfferNotificationInvite)
        XCTAssertFalse(store.hasDeclinedNotificationInvite)
    }

    // MARK: "Not now"

    func testNotNowIsRememberedForTheMemberOnThisPhoneAcrossSignOut() async {
        let defaults = makeDefaults()
        let store = makeStore(client: MockNotificationCenterClient(), defaults: defaults)
        await store.refreshNotificationAuthorization()
        XCTAssertTrue(store.shouldOfferNotificationInvite)

        store.declineNotificationInvite()

        XCTAssertFalse(store.shouldOfferNotificationInvite)
        XCTAssertTrue(store.hasDeclinedNotificationInvite)

        store.signOut()
        await store.signOutTask?.value
        XCTAssertTrue(store.hasDeclinedNotificationInvite)

        let again = makeStore(client: MockNotificationCenterClient(), defaults: defaults)
        await again.refreshNotificationAuthorization()
        XCTAssertTrue(again.hasDeclinedNotificationInvite)
        XCTAssertFalse(again.shouldOfferNotificationInvite)
    }

    func testDeletionClearsNotNowOnlyAfterTheBackendConfirms() async {
        let defaults = makeDefaults()
        let store = makeStore(client: MockNotificationCenterClient(), defaults: defaults)
        store.declineNotificationInvite()

        store.deleteAccount()

        XCTAssertFalse(store.hasDeclinedNotificationInvite)
        let again = makeStore(client: MockNotificationCenterClient(), defaults: defaults)
        XCTAssertFalse(again.hasDeclinedNotificationInvite)
    }

    // MARK: Asking iOS for a token

    func testDemonstrationModeNeverRegistersWithThePhone() async {
        let client = MockNotificationCenterClient(status: .authorized)
        let store = makeStore(client: client)

        await store.registerForRemoteNotificationsIfAllowed()
        await store.requestNotificationAuthorization()

        XCTAssertEqual(store.notificationAuthorization, .authorized)
        XCTAssertEqual(client.registerCalls, 0)
    }

    func testRegistrationIsRequestedOnlyWhenAllowedAndReady() async {
        let client = MockNotificationCenterClient(status: .authorized)

        let ready = makeStore(client: client, backend: MockBackendService(latency: .zero, isLive: true))
        await ready.registerForRemoteNotificationsIfAllowed()
        XCTAssertEqual(client.registerCalls, 1)

        let notOnboarded = makeStore(client: client, hasCompletedOnboarding: false, backend: MockBackendService(latency: .zero, isLive: true))
        await notOnboarded.registerForRemoteNotificationsIfAllowed()
        XCTAssertEqual(client.registerCalls, 1)

        let signedOut = makeStore(client: client, hasAuthenticated: false, backend: MockBackendService(latency: .zero, isLive: true))
        await signedOut.registerForRemoteNotificationsIfAllowed()
        XCTAssertEqual(client.registerCalls, 1)

        let deniedClient = MockNotificationCenterClient(status: .denied)
        let denied = makeStore(client: deniedClient, backend: MockBackendService(latency: .zero, isLive: true))
        await denied.registerForRemoteNotificationsIfAllowed()
        XCTAssertEqual(deniedClient.registerCalls, 0)
    }

    func testTurnOnRegistersWhenReady() async {
        let client = MockNotificationCenterClient()
        let store = makeStore(client: client, backend: MockBackendService(latency: .zero, isLive: true))
        await store.refreshNotificationAuthorization()

        await store.requestNotificationAuthorization()

        XCTAssertEqual(client.requestCount, 1)
        XCTAssertEqual(client.registerCalls, 1)
    }
}
