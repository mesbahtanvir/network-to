import Foundation

actor MockBackendService: BackendService {
    /// Tests may flag the mock as live to exercise the live-only paths (session restore, device
    /// registration) deterministically; mock-only conveniences stay guarded by `!isLive`.
    nonisolated let isLive: Bool
    private let latency: Duration
    private let hasSession: Bool
    private(set) var registeredDevices: [DeviceRegistration] = []
    private(set) var unregisteredDeviceTokens: [String] = []
    /// Ordered record of the calls tests assert on: `register:<token>`, `unregister:<token>`, `signOut`.
    private(set) var events: [String] = []

    init(latency: Duration = .milliseconds(280), isLive: Bool = false, hasSession: Bool = false) {
        self.latency = latency
        self.isLive = isLive
        self.hasSession = hasSession
    }

    func hasValidSession() async -> Bool { hasSession }

    func bootstrap() async throws -> BackendSnapshot {
        try await pause()
        return MockData.bootstrap
    }

    func validateCompany(email: String) async throws -> CompanyDomainDecision {
        try await pause()
        if email.contains("offline") { throw MockServiceError.offline }

        let domain = email.split(separator: "@").last.map(String.init)?.lowercased() ?? ""
        let knownCompanies = [
            "orbitsystems.com": "Orbit Systems",
            "northstar.ai": "Northstar AI",
            "harbourlabs.com": "Harbour Labs",
            "apple.com": "Apple",
            "google.com": "Google",
            "microsoft.com": "Microsoft",
            "amazon.com": "Amazon",
            "meta.com": "Meta",
            "netflix.com": "Netflix",
            "nvidia.com": "NVIDIA",
            "openai.com": "OpenAI",
            "anthropic.com": "Anthropic",
            "shopify.com": "Shopify",
            "stripe.com": "Stripe",
            "uber.com": "Uber",
            "airbnb.com": "Airbnb",
            "cloudflare.com": "Cloudflare",
            "datadoghq.com": "Datadog",
            "snowflake.com": "Snowflake",
            "mongodb.com": "MongoDB",
            "github.com": "GitHub",
            "linkedin.com": "LinkedIn",
            "salesforce.com": "Salesforce",
            "adobe.com": "Adobe",
            "slack.com": "Slack",
            "twilio.com": "Twilio",
            "coinbase.com": "Coinbase",
            "figma.com": "Figma",
            "atlassian.com": "Atlassian",
            "dropbox.com": "Dropbox",
            "doordash.com": "DoorDash",
            "lyft.com": "Lyft",
            "pinterest.com": "Pinterest",
            "snap.com": "Snap",
            "intel.com": "Intel",
            "amd.com": "AMD",
            "ibm.com": "IBM",
            "oracle.com": "Oracle",
            "wealthsimple.com": "Wealthsimple",
            "1password.com": "1Password",
            "clio.com": "Clio",
            "cohere.com": "Cohere",
            "thomsonreuters.com": "Thomson Reuters",
            "servicenow.com": "ServiceNow",
            "databricks.com": "Databricks",
            "tenstorrent.com": "Tenstorrent",
            "celestica.com": "Celestica"
        ]

        if let company = knownCompanies[domain] {
            return .eligible(company: company, domain: domain)
        }
        if domain.hasSuffix(".edu") || domain.hasSuffix(".ca") || domain.contains("tech") || domain.contains("labs") {
            return .reviewRequired(domain: domain)
        }
        return .ineligible(reason: "We couldn’t confirm that this domain belongs to an eligible technology company.")
    }

    func sendMagicLink(to email: String, shouldCreateUser: Bool) async throws -> MagicLinkRequest {
        try await pause()
        if email.contains("offline") { throw MockServiceError.offline }
        return MagicLinkRequest(
            id: UUID(),
            claimSecret: "mock-magic-link-claim",
            email: email,
            isSignUp: shouldCreateUser
        )
    }

    func claimMagicLink(_ request: MagicLinkRequest) async throws -> Bool {
        try await pause()
        if request.email.contains("offline") { throw MockServiceError.offline }
        return false
    }

    func acceptMagicLinkCallback(_ url: URL) async throws {}

    func signOut() async throws {
        events.append("signOut")
    }

    func registerDeviceToken(_ token: String, environment: PushEnvironment) async throws {
        try await pause()
        if token.hasPrefix("dead") { throw MockServiceError.requestFailed }
        if let registration = DeviceRegistration(token: token, environment: environment) {
            registeredDevices.append(registration)
        }
        events.append("register:\(token)")
    }

    func unregisterDeviceToken(_ token: String) async throws {
        try await pause()
        unregisteredDeviceTokens.append(token)
        events.append("unregister:\(token)")
    }

    func deliverMessage(_ body: String, conversationID: UUID?, idempotencyKey: UUID) async throws {
        try await pause()
        if body.lowercased().contains("fail") { throw MockServiceError.requestFailed }
    }

    func processResume(
        fileURL: URL,
        progress: @escaping @Sendable (ResumeImportStage) async -> Void
    ) async throws -> ProfileImportSuggestions? {
        await progress(.readingDocument)
        try await Task.sleep(for: .milliseconds(180))
        await progress(.protectingPrivacy)
        try await Task.sleep(for: .milliseconds(180))
        await progress(.buildingProfile)
        try await Task.sleep(for: .milliseconds(260))
        await progress(.readyToReview)
        return MockData.resumeDraft
    }

    func submitReport(category: ReportCategory, note: String, subjectID: UUID?, conversationID: UUID?) async throws {
        try await pause()
    }

    func loadCompanyMark(_ reference: CompanyMarkReference) async throws -> Data? {
        try await pause()
        guard reference.key == "northstar-ai" else { return nil }
        return MockData.sampleMarkPNG
    }

    private func pause() async throws {
        try await Task.sleep(for: latency)
    }
}

enum MockData {
    /// A fixed 128 x 128 solid PNG standing in for Northstar AI's published icon in previews.
    static let sampleMarkPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAIAAABMXPacAAAAyUlEQVR42u3RMQ0AAAgEsdfIggj878iAockpuKamdVgsAABAAAAIAAABACAAAAQAgAAAEAAAAgBAAAAIAAABACAAAAQAgAAAEAAAAgBAAAAIAAABACAAAAQAgAAAEAAAAgBAAAAIAAABACAAAAQAgAAAEAAAAFwAAEAAAAgAAAEAIAAABACAAAAQAAACAEAAAAgAAAEAIAAABACAAAAQAAACAEAAAAgAAAEAIAAABACAAAAQAAACAEAAAAgAAAEAIAAABACAAHxoAbn8BAyRRrRLAAAAAElFTkSuQmCC") ?? Data()

    static let resumeDraft = ProfileImportSuggestions(
        name: "Alex Morgan",
        role: "Engineering Director",
        city: "Toronto, ON",
        roleScope: "Leads platform engineering across reliability, developer experience, and core services.",
        yearsExperience: "10–15 years",
        currentFocus: "Scaling platform reliability while improving engineering teams' delivery experience.",
        education: "BSc, Computer Science",
        topics: ["Platform leadership", "Distributed systems", "Developer experience", "Team scaling"],
        professionalHistory: [
            ProfessionalExperience(id: UUID(), role: "Engineering Director", company: "Orbit Systems", period: "2022–Present"),
            ProfessionalExperience(id: UUID(), role: "Senior Engineering Manager", company: "Maple Cloud", period: "2018–2022")
        ],
        contributionAreas: ["Distributed systems", "Engineering leadership", "Scaling teams"],
        experienceSummary: "Leading platform organizations through reliability and team-scaling transitions."
    )

    static let introduction = Introduction(
        id: UUID(uuidString: "6B78A00B-A439-45C2-942F-9C1E811D0479")!,
        person: .sarah,
        reasonForYou: "Sarah is growing toward organization-wide technical leadership in production AI. Her journey could help you shape an engineering organization that turns emerging AI capabilities into dependable products.",
        reasonForThem: "Your experience running distributed systems and leading a platform organization could help Sarah expand her influence without losing technical depth.",
        meetingContext: "You both live in Toronto and prefer weekday coffee chats near the city centre.",
        createdAt: Date()
    )

    static let priorConnection = Connection(
        id: UUID(uuidString: "B6D2F8AE-E01F-4DB8-8405-1C091148773E")!,
        person: .maya,
        connectedAt: Calendar.current.date(byAdding: .day, value: -24, to: Date()) ?? Date(),
        origin: "Introduced through complementary product and platform leadership experience.",
        meetingHistory: [
            MeetupRecord(
                id: UUID(uuidString: "AD0B57A6-4349-462D-AEE5-635708C481A9")!,
                date: Calendar.current.date(byAdding: .day, value: -25, to: Date()) ?? Date(),
                summary: "Coffee near King and Spadina"
            )
        ]
    )

    static let bootstrap = BackendSnapshot(
        verifiedWorkEmail: "alex@orbitsystems.com",
        member: .currentMember,
        introduction: introduction,
        conversation: nil,
        connections: [priorConnection],
        networkingPreferences: NetworkingPreferences(),
        meetingPreferences: MeetingPreferences(),
        safetyPreferences: SafetyPreferences(),
        availability: nil,
        onboardingComplete: true,
        waitingForReciprocalInterest: false,
        membership: .trial()
    )
}
