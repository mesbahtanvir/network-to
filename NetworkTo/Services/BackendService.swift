import Foundation

struct BackendSnapshot: Sendable {
    let verifiedWorkEmail: String
    let member: ProfessionalProfile
    let introduction: Introduction?
    let conversation: Conversation?
    let connections: [Connection]
    let networkingPreferences: NetworkingPreferences
    let meetingPreferences: MeetingPreferences
    let safetyPreferences: SafetyPreferences
    let availability: TodayAvailability?
    let onboardingComplete: Bool
    let waitingForReciprocalInterest: Bool
    let membership: MembershipStatus
}

struct MagicLinkRequest: Codable, Equatable, Sendable {
    let id: UUID
    let claimSecret: String
    let email: String
    let createdAt: Date
    let isSignUp: Bool

    init(
        id: UUID,
        claimSecret: String,
        email: String,
        createdAt: Date = Date(),
        isSignUp: Bool = false
    ) {
        self.id = id
        self.claimSecret = claimSecret
        self.email = email
        self.createdAt = createdAt
        self.isSignUp = isSignUp
    }
}

enum BackendIntroductionResult: Sendable {
    case waiting
    case mutual(conversationID: UUID)
    case notMutual
}

protocol BackendService: Sendable {
    var isLive: Bool { get }

    func hasValidSession() async -> Bool
    func bootstrap() async throws -> BackendSnapshot
    func validateCompany(email: String) async throws -> CompanyDomainDecision
    func sendMagicLink(to email: String, shouldCreateUser: Bool) async throws -> MagicLinkRequest
    func pendingMagicLinkRequest() async -> MagicLinkRequest?
    func clearPendingMagicLinkRequest() async
    func claimMagicLink(_ request: MagicLinkRequest) async throws -> Bool
    func acceptMagicLinkCallback(_ url: URL) async throws
    func signOut() async throws
    func updateStream() async throws -> AsyncStream<Void>

    func saveProfile(_ profile: ProfessionalProfile, onboardingComplete: Bool) async throws
    func saveNetworkingPreferences(_ preferences: NetworkingPreferences) async throws
    func saveMeetingPreferences(_ preferences: MeetingPreferences) async throws
    func saveAvailability(_ availability: TodayAvailability?) async throws
    func respondToIntroduction(_ id: UUID, interested: Bool) async throws -> BackendIntroductionResult
    func deliverMessage(_ body: String, conversationID: UUID?, idempotencyKey: UUID) async throws
    func createMeetup(conversationID: UUID, detail: String) async throws
    func recordMeetupFeedback(conversationID: UUID, outcome: MeetupOutcome, stayConnected: Bool) async throws
    func endConversation(_ id: UUID) async throws
    func blockMember(_ id: UUID) async throws
    func unblockMember(named name: String) async throws
    func removeConnection(_ id: UUID) async throws
    func processResume(
        fileURL: URL,
        progress: @escaping @Sendable (ResumeImportStage) async -> Void
    ) async throws -> ProfileImportSuggestions?
    func submitReport(category: ReportCategory, note: String, subjectID: UUID?, conversationID: UUID?) async throws
    func deleteAccount() async throws
    func synchronizeAppStoreTransaction(_ signedTransaction: String) async throws
}

extension BackendService {
    func updateStream() async throws -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }
    func saveProfile(_ profile: ProfessionalProfile, onboardingComplete: Bool) async throws {}
    func saveNetworkingPreferences(_ preferences: NetworkingPreferences) async throws {}
    func saveMeetingPreferences(_ preferences: MeetingPreferences) async throws {}
    func saveAvailability(_ availability: TodayAvailability?) async throws {}
    func pendingMagicLinkRequest() async -> MagicLinkRequest? { nil }
    func clearPendingMagicLinkRequest() async {}
    func claimMagicLink(_ request: MagicLinkRequest) async throws -> Bool { false }
    func acceptMagicLinkCallback(_ url: URL) async throws {}
    func respondToIntroduction(_ id: UUID, interested: Bool) async throws -> BackendIntroductionResult {
        interested ? .waiting : .notMutual
    }
    func createMeetup(conversationID: UUID, detail: String) async throws {}
    func recordMeetupFeedback(conversationID: UUID, outcome: MeetupOutcome, stayConnected: Bool) async throws {}
    func endConversation(_ id: UUID) async throws {}
    func blockMember(_ id: UUID) async throws {}
    func unblockMember(named name: String) async throws {}
    func removeConnection(_ id: UUID) async throws {}
    func deleteAccount() async throws {}
    func synchronizeAppStoreTransaction(_ signedTransaction: String) async throws {}
}

struct SupabaseConfiguration: Sendable {
    let url: URL
    let publishableKey: String

    static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main
    ) -> SupabaseConfiguration? {
        let rawURL = (environment["SUPABASE_URL"]
            ?? bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawKey = (environment["SUPABASE_PUBLISHABLE_KEY"]
            ?? bundle.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY") as? String
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawURL,
              let rawKey,
              !rawURL.isEmpty,
              !rawKey.isEmpty,
              !rawURL.contains("$("),
              !rawKey.contains("$("),
              let url = URL(string: rawURL),
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              scheme == "https" || (scheme == "http" && ["127.0.0.1", "localhost"].contains(host)),
              rawKey.hasPrefix("sb_publishable_") || rawKey.hasPrefix("eyJ") else { return nil }
        return SupabaseConfiguration(url: url, publishableKey: rawKey)
    }
}

private actor UnavailableBackendService: BackendService {
    nonisolated let isLive = true

    func hasValidSession() async -> Bool { false }
    func bootstrap() async throws -> BackendSnapshot { throw BackendConfigurationError.invalid }
    func validateCompany(email: String) async throws -> CompanyDomainDecision { throw BackendConfigurationError.invalid }
    func sendMagicLink(to email: String, shouldCreateUser: Bool) async throws -> MagicLinkRequest { throw BackendConfigurationError.invalid }
    func signOut() async throws {}
    func deliverMessage(_ body: String, conversationID: UUID?, idempotencyKey: UUID) async throws { throw BackendConfigurationError.invalid }
    func processResume(
        fileURL: URL,
        progress: @escaping @Sendable (ResumeImportStage) async -> Void
    ) async throws -> ProfileImportSuggestions? { throw BackendConfigurationError.invalid }
    func submitReport(category: ReportCategory, note: String, subjectID: UUID?, conversationID: UUID?) async throws {
        throw BackendConfigurationError.invalid
    }
}

private enum BackendConfigurationError: LocalizedError {
    case invalid

    var errorDescription: String? {
        "network.to could not connect securely. Install the latest build or contact support."
    }
}

enum BackendFactory {
    static func make() -> any BackendService {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--mock-backend") ||
            arguments.contains(where: { $0.hasSuffix("-preview") || $0.hasPrefix("--onboarding-step=") || $0.hasPrefix("--auth-") }) {
            return MockBackendService()
        }
        #endif
        guard let configuration = SupabaseConfiguration.load() else { return UnavailableBackendService() }
        return SupabaseBackendService(configuration: configuration)
    }
}
