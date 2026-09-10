import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var phase: IntroductionPhase
    @Published private(set) var conversation: Conversation?
    @Published private(set) var connections: [Connection]
    @Published var availability: TodayAvailability?
    @Published var selectedTab: MainTab
    @Published var hasAuthenticated: Bool
    @Published var hasCompletedOnboarding: Bool
    @Published var networkingPreferences: NetworkingPreferences
    @Published var meetingPreferences: MeetingPreferences
    @Published var safetyPreferences: SafetyPreferences
    @Published private(set) var membership: MembershipStatus
    @Published private(set) var isRefreshing = false
    @Published private(set) var isCompletingOnboarding = false
    @Published var transientMessage: String?
    @Published private(set) var resumeImportError: String?
    @Published private(set) var resumeImportStage: ResumeImportStage = .readingDocument
    @Published private(set) var verifiedWorkEmail = "alex@orbitsystems.com"

    @Published private(set) var member: ProfessionalProfile
    @Published private(set) var introduction: Introduction
    private let defaults: UserDefaults
    private let backend: any BackendService
    private var pendingCompany: String?
    private var backendUpdatesTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        startPhase: IntroductionPhase = .ready,
        hasAuthenticated: Bool? = nil,
        hasCompletedOnboarding: Bool? = nil,
        seedMockData: Bool = true,
        membership: MembershipStatus? = nil,
        backend: (any BackendService)? = nil
    ) {
        let resolvedBackend = backend ?? BackendFactory.make()
        self.defaults = defaults
        self.backend = resolvedBackend
        self.phase = startPhase
        self.hasAuthenticated = hasAuthenticated ?? (resolvedBackend.isLive ? false : defaults.bool(forKey: Self.authenticationKey))
        self.hasCompletedOnboarding = hasCompletedOnboarding ?? (resolvedBackend.isLive ? false : defaults.bool(forKey: Self.onboardingKey))
        self.connections = seedMockData ? MockData.bootstrap.connections : []
        self.member = .currentMember
        self.networkingPreferences = MockData.bootstrap.networkingPreferences
        self.meetingPreferences = MockData.bootstrap.meetingPreferences
        self.safetyPreferences = MockData.bootstrap.safetyPreferences
        self.membership = membership ?? MockData.bootstrap.membership
        #if DEBUG
        let launchArguments = ProcessInfo.processInfo.arguments
        let isOnboardingPreview = launchArguments.contains(where: { $0.hasPrefix("--onboarding-step=") })
        let isFeaturePreview = launchArguments.contains(where: { $0.hasSuffix("-preview") && !$0.hasPrefix("--auth-") })
        if isOnboardingPreview || isFeaturePreview {
            self.hasAuthenticated = true
        }
        if isOnboardingPreview {
            self.hasCompletedOnboarding = false
        } else if isFeaturePreview {
            self.hasCompletedOnboarding = true
        }
        if launchArguments.contains(where: { $0.hasPrefix("--auth-") }) {
            self.hasAuthenticated = false
        }
        if launchArguments.contains("--profile-preview") {
            self.selectedTab = .profile
        } else if launchArguments.contains("--messages-preview") || launchArguments.contains("--messages-populated-preview") {
            self.selectedTab = .messages
        } else if launchArguments.contains("--connections-preview") || launchArguments.contains("--connections-populated-preview") {
            self.selectedTab = .connections
        } else {
            self.selectedTab = .today
        }
        #else
        self.selectedTab = .today
        #endif
        self.introduction = MockData.introduction
        #if DEBUG
        if launchArguments.contains("--resume-review-preview") {
            self.hasAuthenticated = true
            self.hasCompletedOnboarding = false
            self.member.resumeStatus = .ready(MockData.resumeDraft)
        }
        if launchArguments.contains("--connections-preview") {
            self.connections = []
        } else if launchArguments.contains("--subscription-expired-preview") {
            self.membership = .expired
            self.phase = .searching
        } else if launchArguments.contains("--connections-populated-preview"), self.connections.isEmpty {
            self.connections = [MockData.priorConnection]
        }
        if launchArguments.contains("--messages-populated-preview") {
            self.phase = .waiting
            confirmMutualInterest()
        } else if launchArguments.contains("--connections-populated-preview") {
            self.phase = .waiting
            confirmMutualInterest()
            self.phase = .feedback
            recordFeedback(.good, stayConnected: true)
        } else if launchArguments.contains("--introduction-nonmutual-preview") {
            self.phase = .notMutual
        }
        if launchArguments.contains("--subscription-expired-preview") {
            self.membership = .expired
            self.phase = .searching
        }
        #endif
    }

    static let authenticationKey = "networkto.hasAuthenticated"
    static let onboardingKey = "networkto.hasCompletedOnboarding"

    var canMessage: Bool {
        conversation != nil && [.mutual, .conversation, .feedback, .connected].contains(phase)
    }

    var isUsingLiveBackend: Bool { backend.isLive }

    var canReceiveNewIntroductions: Bool { membership.hasAccess }

    var canStartNewMatching: Bool { membership.hasAccess }

    var unreadMessageCount: Int { conversation?.isUnread == true ? 1 : 0 }

    var activeAvailability: TodayAvailability? {
        guard let availability, availability.expiresAt > Date() else { return nil }
        return availability
    }

    func restoreBackendSession() async {
        guard backend.isLive else { return }
        guard await backend.hasValidSession() else {
            hasAuthenticated = false
            return
        }
        hasAuthenticated = true
        await refreshFromBackend()
        startBackendUpdates()
    }

    func refreshFromBackend() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let data = try await backend.bootstrap()
            verifiedWorkEmail = data.verifiedWorkEmail
            member = data.member
            if let backendIntroduction = data.introduction { introduction = backendIntroduction }
            conversation = data.conversation
            connections = data.connections
            networkingPreferences = data.networkingPreferences
            meetingPreferences = data.meetingPreferences
            safetyPreferences = data.safetyPreferences
            membership = data.membership
            membership = data.membership
            availability = data.availability
            hasCompletedOnboarding = data.onboardingComplete
            if data.conversation != nil {
                phase = .conversation
            } else if data.introduction != nil {
                phase = data.waitingForReciprocalInterest ? .waiting : .ready
            } else {
                phase = .searching
            }
        } catch {
            transientMessage = error.localizedDescription
        }
    }

    func validateCompany(for email: String) async throws -> CompanyDomainDecision {
        let decision = try await backend.validateCompany(email: email)
        if case .eligible(let company, _) = decision {
            pendingCompany = company
        }
        return decision
    }

    func requestMagicLink(for email: String, intent: AuthenticationIntent) async throws -> MagicLinkRequest {
        try await backend.sendMagicLink(to: email, shouldCreateUser: intent == .signUp)
    }

    func pendingMagicLinkRequest() async -> MagicLinkRequest? {
        await backend.pendingMagicLinkRequest()
    }

    func clearPendingMagicLinkRequest() async {
        await backend.clearPendingMagicLinkRequest()
    }

    func claimMagicLink(_ request: MagicLinkRequest) async throws -> Bool {
        guard try await backend.claimMagicLink(request) else { return false }
        await completeLiveAuthentication(email: request.email)
        return true
    }

    func acceptMagicLinkCallback(_ url: URL) async {
        guard backend.isLive else { return }
        do {
            try await backend.acceptMagicLinkCallback(url)
            await completeLiveAuthentication(email: nil)
        } catch {
            transientMessage = error.localizedDescription
        }
    }

    private func completeLiveAuthentication(email: String?) async {
        if let email { verifiedWorkEmail = email }
        if let pendingCompany { member.company = pendingCompany }
        hasAuthenticated = true
        defaults.set(true, forKey: Self.authenticationKey)
        await refreshFromBackend()
        startBackendUpdates()
    }

    func completeOnboarding() {
        guard !isCompletingOnboarding else { return }
        isCompletingOnboarding = true
        Task {
            defer { isCompletingOnboarding = false }
            do {
                try await backend.saveProfile(member, onboardingComplete: true)
                hasCompletedOnboarding = true
                if !backend.isLive { membership = .trial() }
                if !backend.isLive { membership = .trial() }
                defaults.set(true, forKey: Self.onboardingKey)
                startBackendUpdates()
            }
            catch { transientMessage = error.localizedDescription }
        }
    }

    func completeAuthentication(_ intent: AuthenticationIntent) {
        hasAuthenticated = true
        defaults.set(true, forKey: Self.authenticationKey)

        if intent == .signUp {
            hasCompletedOnboarding = false
            defaults.set(false, forKey: Self.onboardingKey)
        } else {
            hasCompletedOnboarding = true
            defaults.set(true, forKey: Self.onboardingKey)
            if backend.isLive {
                Task {
                    await refreshFromBackend()
                    startBackendUpdates()
                }
            }
        }
    }

    func signOut() {
        backendUpdatesTask?.cancel()
        backendUpdatesTask = nil
        hasAuthenticated = false
        defaults.set(false, forKey: Self.authenticationKey)
        selectedTab = .today
        Task {
            do { try await backend.signOut() }
            catch { transientMessage = error.localizedDescription }
        }
    }

    func synchronizeAppStoreTransaction(_ signedTransaction: String) async {
        do {
            try await backend.synchronizeAppStoreTransaction(signedTransaction)
            if backend.isLive {
                await refreshFromBackend()
            } else {
                membership = .subscribed()
            }
        } catch {
            transientMessage = "Apple confirmed the purchase, but account access is still syncing. We’ll retry when the app opens."
        }
    }

    func updateMemberContext(
        name: String,
        role: String,
        city: String,
        roleScope: String,
        currentFocus: String,
        yearsExperience: String,
        growthAreas: [String],
        professionalAmbition: String,
        growthInterest: String,
        contributionAreas: [String],
        helpFormats: [String],
        contribution: String,
        contributionBoundaries: String
    ) {
        member.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        member.role = role.trimmingCharacters(in: .whitespacesAndNewlines)
        member.city = city
        member.roleScope = roleScope.trimmingCharacters(in: .whitespacesAndNewlines)
        member.currentFocus = currentFocus.trimmingCharacters(in: .whitespacesAndNewlines)
        member.yearsExperience = yearsExperience
        member.growthAreas = growthAreas
        member.professionalAmbition = professionalAmbition.trimmingCharacters(in: .whitespacesAndNewlines)
        member.growthInterest = growthInterest.trimmingCharacters(in: .whitespacesAndNewlines)
        member.contributionAreas = contributionAreas
        member.helpFormats = helpFormats
        member.contribution = contribution.trimmingCharacters(in: .whitespacesAndNewlines)
        member.contributionBoundaries = contributionBoundaries.trimmingCharacters(in: .whitespacesAndNewlines)
        member.topics = Array((contributionAreas + growthAreas).uniqued().prefix(4))
        member.bio = member.roleScope
        if hasCompletedOnboarding {
            Task {
                do { try await backend.saveProfile(member, onboardingComplete: true) }
                catch { transientMessage = error.localizedDescription }
            }
        }
    }

    func respondInterested() {
        guard phase == .ready else { return }
        phase = .waiting
        Task {
            do {
                switch try await backend.respondToIntroduction(introduction.id, interested: true) {
                case .waiting: break
                case .mutual: await refreshFromBackend()
                case .notMutual: phase = .notMutual
                }
            } catch {
                phase = .ready
                transientMessage = error.localizedDescription
            }
        }
    }

    func passIntroduction() {
        guard phase == .ready else { return }
        phase = .passed
        Task {
            do { _ = try await backend.respondToIntroduction(introduction.id, interested: false) }
            catch {
                phase = .ready
                transientMessage = error.localizedDescription
            }
        }
    }

    func confirmMutualInterest() {
        guard !backend.isLive else { return }
        guard phase == .waiting else { return }
        phase = .mutual
        conversation = Conversation(
            id: UUID(),
            person: introduction.person,
            introductionReason: "You’re both building systems that need to scale without losing the human context.",
            messages: [ChatMessage(
                id: UUID(), author: .introduction,
                body: "Hi Alex — glad we connected. Coffee near Union next week?",
                sentAt: Date()
            )],
            isUnread: true,
            meetupStatus: .coordinating
        )
    }

    func openConversation() {
        guard canMessage else { return }
        phase = .conversation
        conversation?.isUnread = false
        selectedTab = .messages
    }

    func sendMessage(_ body: String) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canMessage, !trimmed.isEmpty else { return }
        let message = ChatMessage(
            id: UUID(), author: .member, body: trimmed, sentAt: Date(), delivery: .sending
        )
        conversation?.messages.append(message)
        Task {
            do {
                try await backend.deliverMessage(trimmed, conversationID: conversation?.id, idempotencyKey: message.id)
                setMessageDelivery(message.id, delivery: .delivered)
            } catch {
                setMessageDelivery(message.id, delivery: .failed)
            }
        }
    }

    func retryMessage(_ id: UUID) {
        guard let message = conversation?.messages.first(where: { $0.id == id }) else { return }
        setMessageDelivery(id, delivery: .sending)
        Task {
            do {
                try await backend.deliverMessage(
                    message.body.replacingOccurrences(of: "fail", with: "retry"),
                    conversationID: conversation?.id,
                    idempotencyKey: message.id
                )
                setMessageDelivery(id, delivery: .delivered)
            } catch {
                setMessageDelivery(id, delivery: .failed)
            }
        }
    }

    func planMeetup() {
        planMeetup(detail: "Thursday at 4:30 PM · Union Station")
    }

    func planMeetup(detail: String) {
        guard canMessage else { return }
        conversation?.meetupStatus = .planned(detail)
        if let conversationID = conversation?.id {
            Task {
                do { try await backend.createMeetup(conversationID: conversationID, detail: detail) }
                catch { transientMessage = error.localizedDescription }
            }
        }
    }

    func requestFeedback() {
        guard canMessage else { return }
        conversation?.meetupStatus = .feedbackDue
        phase = .feedback
    }

    func recordFeedback(_ outcome: MeetupOutcome, stayConnected: Bool) {
        guard phase == .feedback, let conversation else { return }
        self.conversation?.meetupStatus = .completed
        Task {
            do { try await backend.recordMeetupFeedback(conversationID: conversation.id, outcome: outcome, stayConnected: stayConnected) }
            catch { transientMessage = error.localizedDescription }
        }

        if outcome != .didNotMeet, stayConnected,
           !connections.contains(where: { $0.person.id == conversation.person.id }) {
            connections.append(Connection(
                id: UUID(), person: conversation.person, connectedAt: Date(),
                origin: "Introduced through shared infrastructure interests"
            ))
            phase = .connected
            selectedTab = .connections
        } else {
            phase = .searching
            selectedTab = .today
        }
    }

    func setAvailability(area: TodayAvailability.Area, window: TodayAvailability.Window) {
        guard canStartNewMatching else {
            transientMessage = "Membership is needed for new introductions."
            return
        }
        availability = TodayAvailability(
            area: area,
            window: window,
            expiresAt: Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: Date())
                ?? Date().addingTimeInterval(14_400)
        )
        let currentAvailability = availability
        Task {
            do { try await backend.saveAvailability(currentAvailability) }
            catch { transientMessage = error.localizedDescription }
        }
    }

    func clearAvailability() {
        availability = nil
        Task {
            do { try await backend.saveAvailability(nil) }
            catch { transientMessage = error.localizedDescription }
        }
    }

    func saveNetworkingPreferences(_ preferences: NetworkingPreferences) {
        networkingPreferences = preferences
        transientMessage = "Introduction preferences saved"
        Task {
            do { try await backend.saveNetworkingPreferences(preferences) }
            catch { transientMessage = error.localizedDescription }
        }
    }

    func saveMeetingPreferences(_ preferences: MeetingPreferences) {
        meetingPreferences = preferences
        transientMessage = "Meeting preferences saved"
        Task {
            do { try await backend.saveMeetingPreferences(preferences) }
            catch { transientMessage = error.localizedDescription }
        }
    }

    func saveSafetyPreferences(_ preferences: SafetyPreferences) {
        safetyPreferences = preferences
        transientMessage = "Safety settings saved"
    }

    func unblock(_ name: String) {
        safetyPreferences.blockedMembers.removeAll { $0 == name }
        transientMessage = "\(name) was unblocked"
        Task {
            do { try await backend.unblockMember(named: name) }
            catch { transientMessage = error.localizedDescription }
        }
    }

    func processResume(fileURL: URL) async {
        resumeImportError = nil
        resumeImportStage = .readingDocument
        member.resumeStatus = .processing
        do {
            if let suggestions = try await backend.processResume(
                fileURL: fileURL,
                progress: { [weak self] stage in
                    await MainActor.run { self?.resumeImportStage = stage }
                }
            ) {
                member.resumeStatus = .ready(suggestions)
            } else {
                member.resumeStatus = .uploaded
            }
        } catch {
            member.resumeStatus = .notAdded
            resumeImportError = error.localizedDescription
        }
    }

    func applyResumeSuggestions(_ suggestions: ProfileImportSuggestions) {
        if let name = suggestions.name?.trimmedNonEmpty { member.name = name }
        if let role = suggestions.role?.trimmedNonEmpty { member.role = role }
        if let city = suggestions.city?.trimmedNonEmpty { member.city = city }
        if let roleScope = suggestions.roleScope?.trimmedNonEmpty {
            member.roleScope = roleScope
            member.bio = roleScope
        }
        if let yearsExperience = suggestions.yearsExperience?.trimmedNonEmpty {
            member.yearsExperience = yearsExperience
        }
        if let currentFocus = suggestions.currentFocus?.trimmedNonEmpty {
            member.currentFocus = currentFocus
        }
        if let education = suggestions.education?.trimmedNonEmpty {
            member.education = education
        }
        member.topics = Array((member.topics + suggestions.topics).uniqued().prefix(8))
        if !suggestions.professionalHistory.isEmpty {
            member.professionalHistory = suggestions.professionalHistory
        }
        if !suggestions.contributionAreas.isEmpty {
            member.contributionAreas = Array((member.contributionAreas + suggestions.contributionAreas).uniqued().prefix(4))
        }
        if let experienceSummary = suggestions.experienceSummary?.trimmedNonEmpty {
            member.contribution = experienceSummary
        }
        member.resumeStatus = .applied
        transientMessage = "Résumé draft applied—review it before saving"
        if hasCompletedOnboarding {
            Task {
                do { try await backend.saveProfile(member, onboardingComplete: true) }
                catch { transientMessage = error.localizedDescription }
            }
        }
    }

    func endCurrentConversation() {
        let conversationID = conversation?.id
        conversation?.isEnded = true
        phase = .searching
        transientMessage = "Conversation ended"
        if let conversationID {
            Task {
                do { try await backend.endConversation(conversationID) }
                catch { transientMessage = error.localizedDescription }
            }
        }
    }

    func blockCurrentPerson() {
        guard let person = conversation?.person else { return }
        conversation?.isBlocked = true
        conversation?.isEnded = true
        block(person)
        phase = .searching
    }

    func block(_ person: ProfessionalProfile) {
        if !safetyPreferences.blockedMembers.contains(person.name) {
            safetyPreferences.blockedMembers.append(person.name)
        }
        connections.removeAll { $0.person.id == person.id }
        transientMessage = "\(person.name) was blocked"
        Task {
            do { try await backend.blockMember(person.id) }
            catch { transientMessage = error.localizedDescription }
        }
    }

    func submitReport(category: ReportCategory, note: String) async throws {
        try await backend.submitReport(
            category: category,
            note: note,
            subjectID: conversation?.person.id ?? introduction.person.id,
            conversationID: conversation?.id
        )
        transientMessage = "Report submitted privately"
    }

    func removeConnection(_ id: UUID) {
        connections.removeAll { $0.id == id }
        transientMessage = "Connection removed"
        Task {
            do { try await backend.removeConnection(id) }
            catch { transientMessage = error.localizedDescription }
        }
    }

    func deleteMockAccount() {
        if backend.isLive {
            Task {
                do {
                    try await backend.deleteAccount()
                    resetDemo(includeOnboarding: true)
                    hasAuthenticated = false
                    defaults.set(false, forKey: Self.authenticationKey)
                    transientMessage = nil
                } catch {
                    transientMessage = error.localizedDescription
                }
            }
        } else {
            resetDemo(includeOnboarding: true)
            hasAuthenticated = false
            defaults.set(false, forKey: Self.authenticationKey)
            transientMessage = nil
        }
    }

    func lookAgain() {
        guard phase == .passed || phase == .notMutual else { return }
        phase = .searching
    }

    func resolveWithoutMutualInterest() {
        guard phase == .waiting else { return }
        phase = .notMutual
    }

    func resetDemo(includeOnboarding: Bool = false) {
        phase = .ready
        conversation = nil
        connections = []
        availability = nil
        selectedTab = .today
        membership = .trial()
        if includeOnboarding {
            hasCompletedOnboarding = false
            defaults.set(false, forKey: Self.onboardingKey)
        }
    }

    private func setMessageDelivery(_ id: UUID, delivery: MessageDelivery) {
        guard let index = conversation?.messages.firstIndex(where: { $0.id == id }) else { return }
        conversation?.messages[index].delivery = delivery
        conversation?.messages[index].failed = delivery == .failed
    }

    private func startBackendUpdates() {
        guard backend.isLive else { return }
        backendUpdatesTask?.cancel()
        backendUpdatesTask = Task { [weak self] in
            guard let self else { return }
            do {
                let updates = try await backend.updateStream()
                for await _ in updates {
                    guard !Task.isCancelled else { return }
                    await refreshFromBackend()
                }
            } catch is CancellationError {
                return
            } catch {
                // Realtime is an enhancement; foreground refresh remains the recovery path.
            }
        }
    }
}

enum MainTab: Hashable, Sendable { case today, connections, messages, profile }

enum AuthenticationIntent: Hashable, Sendable { case signUp, signIn }

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
