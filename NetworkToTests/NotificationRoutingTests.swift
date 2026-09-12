import XCTest
@testable import NetworkTo

final class NotificationRoutingTests: XCTestCase {
    // MARK: Device token

    func testDeviceTokenFormatsAsLowercaseZeroPaddedHex() {
        let bytes = Data([UInt8](repeating: 0x0A, count: 31) + [0xDE])

        let registration = DeviceRegistration(deviceToken: bytes, environment: .sandbox)

        XCTAssertEqual(registration?.token, String(repeating: "0a", count: 31) + "de")
        XCTAssertEqual(registration?.environment, .sandbox)
    }

    func testDeviceTokenRejectsLengthsTheBackendRefuses() {
        XCTAssertNil(DeviceRegistration(deviceToken: Data(), environment: .sandbox))
        XCTAssertNil(DeviceRegistration(deviceToken: Data(repeating: 0xAB, count: 31), environment: .sandbox))
        XCTAssertNil(DeviceRegistration(deviceToken: Data(repeating: 0xAB, count: 101), environment: .production))
        XCTAssertNotNil(DeviceRegistration(deviceToken: Data(repeating: 0xAB, count: 32), environment: .production))
        XCTAssertNotNil(DeviceRegistration(deviceToken: Data(repeating: 0xAB, count: 100), environment: .production))
    }

    func testDeviceTokenStringMustBeLowercaseHex() {
        XCTAssertNotNil(DeviceRegistration(token: String(repeating: "f", count: 64), environment: .sandbox))
        XCTAssertNil(DeviceRegistration(token: String(repeating: "F", count: 64), environment: .sandbox))
        XCTAssertNil(DeviceRegistration(token: String(repeating: "g", count: 64), environment: .sandbox))
        XCTAssertNil(DeviceRegistration(token: String(repeating: "a", count: 63), environment: .sandbox))
    }

    // MARK: Environment

    private func profile(apsEnvironment: String?) -> Data {
        var plist = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        plist += "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">"
        plist += "<plist version=\"1.0\"><dict><key>Name</key><string>network.to Development</string>"
        plist += "<key>Entitlements</key><dict>"
        if let apsEnvironment {
            plist += "<key>aps-environment</key><string>\(apsEnvironment)</string>"
        }
        plist += "<key>application-identifier</key><string>6Z4KNLU26A.com.mesbahtanvir.networkto</string>"
        plist += "</dict></dict></plist>"
        // The real file is a CMS envelope: arbitrary bytes surround the plist.
        return Data([0x30, 0x82, 0x1A, 0x00, 0x06, 0x09]) + Data(plist.utf8) + Data([0x00, 0xFF, 0x31, 0x82])
    }

    func testEnvironmentParsesTheEntitlement() {
        XCTAssertEqual(PushEnvironment.parse(provisioningProfile: profile(apsEnvironment: "development")), .sandbox)
        XCTAssertEqual(PushEnvironment.parse(provisioningProfile: profile(apsEnvironment: "production")), .production)
    }

    func testEnvironmentIsNilWithoutTheEntitlementOrWithGarbage() {
        XCTAssertNil(PushEnvironment.parse(provisioningProfile: profile(apsEnvironment: nil)))
        XCTAssertNil(PushEnvironment.parse(provisioningProfile: profile(apsEnvironment: "staging")))
        XCTAssertNil(PushEnvironment.parse(provisioningProfile: Data([0x00, 0x01, 0x02])))
    }

    func testEnvironmentResolution() {
        XCTAssertNil(PushEnvironment.resolve(isSimulator: true, provisioningProfile: profile(apsEnvironment: "development")))
        XCTAssertEqual(PushEnvironment.resolve(isSimulator: false, provisioningProfile: nil), .production)
        XCTAssertEqual(PushEnvironment.resolve(isSimulator: false, provisioningProfile: profile(apsEnvironment: "development")), .sandbox)
        XCTAssertEqual(PushEnvironment.resolve(isSimulator: false, provisioningProfile: profile(apsEnvironment: "production")), .production)
        XCTAssertEqual(PushEnvironment.sandbox.rawValue, "sandbox")
        XCTAssertEqual(PushEnvironment.production.rawValue, "production")
    }

    // MARK: Routes

    private func payload(
        kind: String?,
        introductionID: String? = nil,
        conversationID: String? = nil,
        meetupID: String? = nil
    ) -> [AnyHashable: Any] {
        var userInfo: [AnyHashable: Any] = [
            "aps": [
                "alert": ["title": "New message", "body": "Sarah sent you a message."],
                "sound": "default",
                "thread-id": conversationID ?? "conversations",
                "interruption-level": "active",
            ],
        ]
        if let kind { userInfo["kind"] = kind }
        if let introductionID { userInfo["introduction_id"] = introductionID }
        if let conversationID { userInfo["conversation_id"] = conversationID }
        if let meetupID { userInfo["meetup_id"] = meetupID }
        return userInfo
    }

    func testIntroductionReadyRoutesToTheIntroduction() {
        let id = UUID()

        let route = NotificationRoute(userInfo: payload(kind: "introduction_ready", introductionID: id.uuidString.lowercased()))

        XCTAssertEqual(route, .introduction(id))
    }

    func testConversationKindsRouteToTheConversation() {
        let id = UUID()

        XCTAssertEqual(
            NotificationRoute(userInfo: payload(kind: "new_message", conversationID: id.uuidString)),
            .conversation(id, kind: .newMessage)
        )
        XCTAssertEqual(
            NotificationRoute(userInfo: payload(kind: "meetup_reminder", conversationID: id.uuidString, meetupID: UUID().uuidString)),
            .conversation(id, kind: .meetupReminder)
        )
        XCTAssertEqual(
            NotificationRoute(userInfo: payload(kind: "feedback_due", conversationID: id.uuidString, meetupID: UUID().uuidString)),
            .conversation(id, kind: .feedbackDue)
        )
    }

    func testMutualInterestWithoutAConversationIDStillRoutesToMessages() {
        let route = NotificationRoute(userInfo: payload(kind: "mutual_interest", introductionID: UUID().uuidString))

        XCTAssertEqual(route, .conversation(nil, kind: .mutualInterest))
    }

    func testUnknownOrMissingKindIsIgnored() {
        XCTAssertNil(NotificationRoute(userInfo: payload(kind: "streak_reminder")))
        XCTAssertNil(NotificationRoute(userInfo: payload(kind: nil, conversationID: UUID().uuidString)))
        XCTAssertNil(NotificationRoute(userInfo: [:]))
    }

    func testMalformedIdentifierStillSelectsTheTab() {
        XCTAssertEqual(
            NotificationRoute(userInfo: payload(kind: "new_message", conversationID: "not-a-uuid")),
            .conversation(nil, kind: .newMessage)
        )
        XCTAssertEqual(NotificationRoute(userInfo: payload(kind: "introduction_ready")), .introduction(nil))
    }

    // MARK: Delivered-notification matching

    func testItemMatchesItsIdentifierCaseInsensitively() {
        let id = UUID()

        XCTAssertTrue(NotificationItem.conversation(id).matches(userInfo: payload(kind: "new_message", conversationID: id.uuidString.lowercased())))
        XCTAssertTrue(NotificationItem.introduction(id).matches(userInfo: payload(kind: "introduction_ready", introductionID: id.uuidString)))
        XCTAssertFalse(NotificationItem.conversation(id).matches(userInfo: payload(kind: "new_message", conversationID: UUID().uuidString)))
        XCTAssertFalse(NotificationItem.conversation(id).matches(userInfo: payload(kind: "introduction_ready", introductionID: id.uuidString)))
        XCTAssertFalse(NotificationItem.introduction(id).matches(userInfo: [:]))
    }

    // MARK: Invitation policy

    private func offers(
        authorization: NotificationAuthorizationStatus = .notDetermined,
        hasAuthenticated: Bool = true,
        hasCompletedOnboarding: Bool = true,
        canReceiveIntroductions: Bool = true,
        phase: IntroductionPhase = .searching,
        hasDeclined: Bool = false
    ) -> Bool {
        NotificationInvitePolicy.shouldOffer(
            authorization: authorization,
            hasAuthenticated: hasAuthenticated,
            hasCompletedOnboarding: hasCompletedOnboarding,
            canReceiveIntroductions: canReceiveIntroductions,
            phase: phase,
            hasDeclined: hasDeclined
        )
    }

    func testInvitationAppearsOnlyWhileSearchingOrWaiting() {
        XCTAssertTrue(offers(phase: .searching))
        XCTAssertTrue(offers(phase: .waiting))
        for phase in [IntroductionPhase.ready, .mutual, .conversation, .feedback, .connected, .passed, .notMutual] {
            XCTAssertFalse(offers(phase: phase), "\(phase) must not show the invitation")
        }
    }

    func testInvitationNeedsANeverAskedPhoneAndAnOnboardedMember() {
        XCTAssertFalse(offers(authorization: .unknown))
        XCTAssertFalse(offers(authorization: .denied))
        XCTAssertFalse(offers(authorization: .authorized))
        XCTAssertFalse(offers(hasAuthenticated: false))
        XCTAssertFalse(offers(hasCompletedOnboarding: false))
        XCTAssertFalse(offers(canReceiveIntroductions: false))
        XCTAssertFalse(offers(hasDeclined: true))
    }
}
