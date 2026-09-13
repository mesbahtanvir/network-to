import Foundation

/// The phone's own record for this app of whether it may show notifications. `unknown` means
/// the status has not been read yet; it never triggers the invitation.
enum NotificationAuthorizationStatus: Equatable, Sendable {
    case unknown
    case notDetermined
    case denied
    case authorized

    /// The phone presents its dialog only while it has never been asked.
    var canPrompt: Bool { self == .notDetermined }

    /// Alerts may be shown, so the phone's token is worth registering.
    var allowsDelivery: Bool { self == .authorized }
}

/// Which APNs host the backend must use for a token. The raw value is exactly what
/// `register_device_token(p_environment)` accepts.
enum PushEnvironment: String, Sendable {
    case sandbox
    case production

    /// Reads `aps-environment` out of an embedded provisioning profile. The file is a CMS
    /// envelope whose payload is an uncompressed XML plist, so the plist is sliced between
    /// `<?xml` and `</plist>` and decoded on its own.
    static func parse(provisioningProfile data: Data) -> PushEnvironment? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
        else { return nil }
        let plist = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let object = try? PropertyListSerialization.propertyList(from: plist, options: [], format: nil),
              let root = object as? [String: Any],
              let entitlements = root["Entitlements"] as? [String: Any],
              let value = entitlements["aps-environment"] as? String
        else { return nil }
        switch value {
        case "development": return .sandbox
        case "production": return .production
        default: return nil
        }
    }

    /// A simulator process holds no routable token; an install without an embedded profile is
    /// an App Store install; anything else follows the profile's entitlement.
    static func resolve(isSimulator: Bool, provisioningProfile: Data?) -> PushEnvironment? {
        if isSimulator { return nil }
        guard let provisioningProfile else { return .production }
        return parse(provisioningProfile: provisioningProfile)
    }

    static func current(bundle: Bundle = .main) -> PushEnvironment? {
        #if targetEnvironment(simulator)
        let isSimulator = true
        #else
        let isSimulator = false
        #endif
        let profile = bundle.url(forResource: "embedded", withExtension: "mobileprovision")
            .flatMap { try? Data(contentsOf: $0) }
        return resolve(isSimulator: isSimulator, provisioningProfile: profile)
    }
}

/// One phone's delivery address for this app together with the channel it uses.
struct DeviceRegistration: Equatable, Sendable {
    /// Lowercase hex. `register_device_token` accepts `^[0-9a-f]{64,200}$`
    /// (see `supabase/migrations/20260905000600_production_hardening.sql`).
    let token: String
    let environment: PushEnvironment

    init?(token: String, environment: PushEnvironment) {
        guard Self.isValidToken(token) else { return nil }
        self.token = token
        self.environment = environment
    }

    init?(deviceToken: Data, environment: PushEnvironment) {
        self.init(token: deviceToken.map { String(format: "%02x", $0) }.joined(), environment: environment)
    }

    static func isValidToken(_ token: String) -> Bool {
        (64...200).contains(token.utf8.count) && token.utf8.allSatisfy { byte in
            (0x30...0x39).contains(byte) || (0x61...0x66).contains(byte)
        }
    }
}

/// Where a tapped notification leads. It carries identifiers only: no name, no copy, and
/// nothing that could reveal a decision.
enum NotificationRoute: Equatable, Sendable {
    enum Kind: String, Sendable {
        case introductionReady = "introduction_ready"
        case mutualInterest = "mutual_interest"
        case newMessage = "new_message"
        case meetupReminder = "meetup_reminder"
        case feedbackDue = "feedback_due"
    }

    case introduction(UUID?)
    case conversation(UUID?, kind: Kind)

    /// Parses the top-level keys `apnsPayload` writes (`kind`, `introduction_id`,
    /// `conversation_id`). An unknown kind is ignored; a malformed id still selects the tab.
    init?(userInfo: [AnyHashable: Any]) {
        guard let rawKind = userInfo["kind"] as? String, let kind = Kind(rawValue: rawKind) else { return nil }
        switch kind {
        case .introductionReady:
            self = .introduction(Self.identifier("introduction_id", in: userInfo))
        case .mutualInterest, .newMessage, .meetupReminder, .feedbackDue:
            self = .conversation(Self.identifier("conversation_id", in: userInfo), kind: kind)
        }
    }

    private static func identifier(_ key: String, in userInfo: [AnyHashable: Any]) -> UUID? {
        (userInfo[key] as? String).flatMap { UUID(uuidString: $0) }
    }
}

/// An item that is on screen, whose delivered notifications can leave the phone's list.
enum NotificationItem: Equatable, Sendable {
    case introduction(UUID)
    case conversation(UUID)

    /// Compares only the identifier the backend put in the payload; the alert text is never read.
    func matches(userInfo: [AnyHashable: Any]) -> Bool {
        let key: String
        let id: UUID
        switch self {
        case .introduction(let value):
            key = "introduction_id"
            id = value
        case .conversation(let value):
            key = "conversation_id"
            id = value
        }
        guard let raw = userInfo[key] as? String else { return false }
        return raw.caseInsensitiveCompare(id.uuidString) == .orderedSame
    }
}

/// Decides whether Today offers the one explanation that precedes the phone's permission
/// dialog: after onboarding, while introductions can arrive, while Today has nothing to decide,
/// while the phone has never been asked, and never again after "Not now".
enum NotificationInvitePolicy {
    static func shouldOffer(
        authorization: NotificationAuthorizationStatus,
        hasAuthenticated: Bool,
        hasCompletedOnboarding: Bool,
        canReceiveIntroductions: Bool,
        phase: IntroductionPhase,
        hasDeclined: Bool
    ) -> Bool {
        authorization == .notDetermined
            && hasAuthenticated
            && hasCompletedOnboarding
            && canReceiveIntroductions
            && !hasDeclined
            && (phase == .searching || phase == .waiting)
    }
}
