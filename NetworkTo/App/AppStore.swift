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
    @Published private(set) var verifiedWorkEmail: String

    @Published private(set) var member: ProfessionalProfile
    @Published private(set) var introduction: Introduction
    /// Company marks this phone holds, keyed by reference. Never leaves the store; cleared with local state.
    @Published private(set) var companyMarks: [CompanyMarkReference: Data] = [:]
    /// The phone's permission state for this app, re-read on every activation; `.unknown` until read.
    @Published private(set) var notificationAuthorization: NotificationAuthorizationStatus = .unknown
    /// "Not now" for this member on this phone; survives sign-out and clears only after deletion.
    @Published private(set) var hasDeclinedNotificationInvite = false
    /// Navigation path of the Messages tab, owned here so a tapped notification can push the conversation.
    @Published var messagesPath: [MessagesDestination] = []
    private(set) var pendingNotificationRoute: NotificationRoute?
    private(set) var pendingDeviceRegistration: DeviceRegistration?
    private(set) var registeredDeviceRegistration: DeviceRegistration?
    private(set) var signOutTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private let backend: any BackendService
    private let markCache: CompanyMarkDiskCache
    private let notificationCenter: any NotificationCenterClient
    private var pendingCompany: String?
    private var backendUpdatesTask: Task<Void, Never>?
    private var companyMarkTasks: [CompanyMarkReference: Task<Void, Never>] = [:]
    private var refreshTask: Task<Void, Never>?
    private var hasAttemptedSessionRestore = false

    init(
        defaults: UserDefaults = .standard,
        startPhase: IntroductionPhase = .ready,
        hasAuthenticated: Bool? = nil,
        hasCompletedOnboarding: Bool? = nil,
        seedMockData: Bool = true,
        membership: MembershipStatus? = nil,
        backend: (any BackendService)? = nil,
        markCache: CompanyMarkDiskCache? = nil,
        notificationCenter: (any NotificationCenterClient)? = nil
    ) {
        let resolvedBackend = backend ?? BackendFactory.make()
        let usesMockBackend = !resolvedBackend.isLive
        self.defaults = defaults
        self.backend = resolvedBackend
        self.markCache = markCache ?? CompanyMarkDiskCache()
        self.notificationCenter = notificationCenter ?? (SystemNotificationCenterClient() as any NotificationCenterClient)
        self.phase = resolvedBackend.isLive ? .searching : startPhase
        self.hasAuthenticated = hasAuthenticated ?? (resolvedBackend.isLive ? false : defaults.bool(forKey: Self.authenticationKey))
        self.hasCompletedOnboarding = hasCompletedOnboarding ?? (resolvedBackend.isLive ? false : defaults.bool(forKey: Self.onboardingKey))
        self.verifiedWorkEmail = usesMockBackend ? "alex@orbitsystems.com" : ""
        self.connections = seedMockData && usesMockBackend ? MockData.bootstrap.connections : []
        self.member = usesMockBackend ? .currentMember : .empty
        self.networkingPreferences = MockData.bootstrap.networkingPreferences
        self.meetingPreferences = MockData.bootstrap.meetingPreferences
        self.safetyPreferences = MockData.bootstrap.safetyPreferences
        self.membership = membership ?? (usesMockBackend ? MockData.bootstrap.membership : .notStarted)
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
        self.introduction = usesMockBackend
            ? MockData.introduction
            : Introduction(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
                person: .empty,
                reasonForYou: "",
                reasonForThem: "",
                meetingContext: "",
                createdAt: .distantPast
            )
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
        reloadNotificationMemory()
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
            finishSessionRestore()
            return
        }
        hasAuthenticated = true
        await refreshFromBackend()
        startBackendUpdates()
        finishSessionRestore()
        await syncDeviceRegistration()
    }

    /// A tapped notification that arrived before the session was restored is applied, or
    /// discarded, only now, against restored and refreshed state.
    private func finishSessionRestore() {
        hasAttemptedSessionRestore = true
        applyPendingNotificationRouteIfReady()
    }

    /// Replaces domain state from one snapshot. Concurrent calls share the in-flight refresh so
    /// a tapped notification never applies to stale state. The silent variant reports nothing
    /// because it follows an arriving notification rather than a member action.
    func refreshFromBackend(silently: Bool = false) async {
        if let refreshTask {
            await refreshTask.value
            return
        }
        let task = Task { await performRefresh(silently: silently) }
        refreshTask = task
        await task.value
        if refreshTask == task { refreshTask = nil }
    }

    private func performRefresh(silently: Bool) async {
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
            availability = data.availability
            hasCompletedOnboarding = data.onboardingComplete
            if data.conversation != nil {
                phase = .conversation
            } else if data.introduction != nil {
                phase = data.waitingForReciprocalInterest ? .waiting : .ready
            } else {
                phase = .searching
            }
            prefetchCompanyMarks(for: data)
            reloadNotificationMemory()
        } catch {
            if !silently { transientMessage = error.localizedDescription }
        }
    }

    /// Fetches the marks for the companies on screen after a refresh so a monogram is replaced
    /// in place as soon as the copy arrives; failures leave the monogram and say nothing.
    private func prefetchCompanyMarks(for data: BackendSnapshot) {
        var references = [data.member.displayedCompanyMark, data.introduction?.person.displayedCompanyMark, data.conversation?.person.displayedCompanyMark]
        references.append(contentsOf: data.connections.map { $0.person.displayedCompanyMark })
        for reference in Set(references.compactMap { $0 }) {
            Task { await ensureCompanyMark(reference) }
        }
    }

    func companyMarkData(for reference: CompanyMarkReference?) -> Data? {
        guard let reference else { return nil }
        return companyMarks[reference]
    }

    /// Loads a mark from memory, then the phone's cache, then the product backend. One load runs
    /// per reference at a time; a mark that cannot be loaded simply stays a monogram.
    func ensureCompanyMark(_ reference: CompanyMarkReference?) async {
        guard let reference, companyMarks[reference] == nil else { return }
        if let inFlight = companyMarkTasks[reference] {
            await inFlight.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.loadCompanyMark(reference)
        }
        companyMarkTasks[reference] = task
        await task.value
        if companyMarkTasks[reference] == task { companyMarkTasks[reference] = nil }
    }

    private func loadCompanyMark(_ reference: CompanyMarkReference) async {
        if let cached = await markCache.read(reference), !cached.isEmpty {
            companyMarks[reference] = cached
            return
        }
        guard let data = try? await backend.loadCompanyMark(reference), !data.isEmpty else { return }
        companyMarks[reference] = data
        await markCache.write(data, for: reference)
    }

    /// Forgets every cached mark; part of clearing local state at sign-out and after deletion.
    func clearCompanyMarks() {
        for task in companyMarkTasks.values { task.cancel() }
        companyMarkTasks = [:]
        companyMarks = [:]
        let cache = markCache
        Task.detached(priority: .utility) { await cache.removeAll() }
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
        await registerForRemoteNotificationsIfAllowed()
        await syncDeviceRegistration()
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
                defaults.set(true, forKey: Self.onboardingKey)
                startBackendUpdates()
                await registerForRemoteNotificationsIfAllowed()
                await syncDeviceRegistration()
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
                    await registerForRemoteNotificationsIfAllowed()
                    await syncDeviceRegistration()
                }
            }
        }
    }

    /// Ends the session locally at once. This phone's registration is removed first, bounded to
    /// five seconds, and forgotten whatever the outcome; "Not now" is kept for this member.
    func signOut() {
        backendUpdatesTask?.cancel()
        backendUpdatesTask = nil
        let registration = registeredDeviceRegistration
        forgetDeviceRegistration()
        pendingNotificationRoute = nil
        messagesPath = []
        hasAuthenticated = false
        defaults.set(false, forKey: Self.authenticationKey)
        selectedTab = .today
        clearCompanyMarks()
        let backend = self.backend
        signOutTask = Task {
            if let registration {
                await Self.unregisterDeviceToken(registration.token, from: backend, timeout: .seconds(5))
            }
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

    func deleteAccount() {
        if backend.isLive {
            Task {
                do {
                    try await backend.deleteAccount()
                    clearNotificationMemory()
                    resetDemo(includeOnboarding: true)
                    hasAuthenticated = false
                    defaults.set(false, forKey: Self.authenticationKey)
                    transientMessage = nil
                } catch {
                    transientMessage = error.localizedDescription
                }
            }
        } else {
            clearNotificationMemory()
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
        messagesPath = []
        pendingNotificationRoute = nil
        membership = .trial()
        clearCompanyMarks()
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

    // MARK: - Notifications

    static let notificationSettingsFallbackNotice = "Notifications are managed in iPhone Settings under network.to"

    /// The single explanation that precedes the phone's dialog: only after onboarding, only while
    /// Today is searching or privately waiting, only while the phone has never been asked, and
    /// never again after "Not now" for this member on this phone.
    var shouldOfferNotificationInvite: Bool {
        NotificationInvitePolicy.shouldOffer(
            authorization: notificationAuthorization,
            hasAuthenticated: hasAuthenticated,
            hasCompletedOnboarding: hasCompletedOnboarding,
            canReceiveIntroductions: membership.hasAccess,
            phase: phase,
            hasDeclined: hasDeclinedNotificationInvite
        )
    }

    /// Registration needs a real account: never in demonstration mode, never signed out, never
    /// before onboarding is complete.
    var isReadyForDeviceRegistration: Bool {
        backend.isLive && hasAuthenticated && hasCompletedOnboarding
    }

    func declineNotificationInvite() {
        hasDeclinedNotificationInvite = true
        defaults.set(true, forKey: Self.notificationInviteDeclinedKey(for: member.id))
    }

    func refreshNotificationAuthorization() async {
        notificationAuthorization = await notificationCenter.authorizationStatus()
    }

    /// Presents the phone's dialog from the invitation card or the Profile row. Never twice: the
    /// phone decides once, and only iPhone Settings can change it afterwards.
    func requestNotificationAuthorization() async {
        guard notificationAuthorization.canPrompt else { return }
        notificationAuthorization = await notificationCenter.requestAuthorization()
        await registerForRemoteNotificationsIfAllowed()
    }

    /// Re-reads the phone's status, then asks iOS for the token when alerts are allowed and a
    /// member with complete onboarding is signed in on the live backend. iOS answers through the
    /// app delegate with the current token, which registers again so the last-confirmed time moves.
    func registerForRemoteNotificationsIfAllowed() async {
        await refreshNotificationAuthorization()
        guard notificationAuthorization.allowsDelivery, isReadyForDeviceRegistration else { return }
        notificationCenter.registerForRemoteNotifications()
    }

    func receiveDeviceRegistration(_ registration: DeviceRegistration) async {
        pendingDeviceRegistration = registration
        await syncDeviceRegistration()
    }

    /// Registers the pending token once the member is ready, remembers it for this member, and
    /// removes the previously remembered token when it changed. A failure stays silent and keeps
    /// the token pending for the next activation.
    func syncDeviceRegistration() async {
        guard isReadyForDeviceRegistration, let pending = pendingDeviceRegistration else { return }
        do {
            try await backend.registerDeviceToken(pending.token, environment: pending.environment)
        } catch {
            return
        }
        guard pendingDeviceRegistration == pending else { return }
        pendingDeviceRegistration = nil
        let previous = registeredDeviceRegistration
        rememberDeviceRegistration(pending)
        if let previous, previous.token != pending.token {
            _ = try? await backend.unregisterDeviceToken(previous.token)
        }
    }

    /// Buffers a tapped notification until the first session restore has been attempted, then
    /// applies it, or discards it when no signed-in, onboarded member can receive it.
    func handleNotificationRoute(_ route: NotificationRoute) {
        pendingNotificationRoute = route
        applyPendingNotificationRouteIfReady()
    }

    private func applyPendingNotificationRouteIfReady() {
        guard let route = pendingNotificationRoute, !backend.isLive || hasAttemptedSessionRestore else { return }
        pendingNotificationRoute = nil
        guard hasAuthenticated, hasCompletedOnboarding else { return }
        switch route {
        case .introduction:
            selectedTab = .today
        case .conversation(let id, _):
            selectedTab = .messages
            showConversation(matching: id)
        }
        guard backend.isLive else { return }
        Task {
            await refreshFromBackend(silently: true)
            if case .conversation(let id, _) = route { showConversation(matching: id) }
        }
    }

    /// Pushes the conversation a notification refers to, but only one the member can already
    /// open; a stale or foreign identifier leaves Messages in its current state.
    private func showConversation(matching id: UUID?) {
        guard canMessage, let conversation, id == nil || conversation.id == id else { return }
        let destination = MessagesDestination.conversation(conversation.id)
        if messagesPath.last != destination { messagesPath = [destination] }
    }

    func isViewingDestination(of route: NotificationRoute) -> Bool {
        guard hasAuthenticated, hasCompletedOnboarding else { return false }
        switch route {
        case .introduction:
            return selectedTab == .today
        case .conversation(let id, _):
            guard let id, selectedTab == .messages, let conversation, conversation.id == id else { return false }
            return messagesPath.last == .conversation(id)
        }
    }

    /// Called while the app is open. The phone shows its standard banner unless the member is
    /// already on the destination; either way the state refreshes quietly.
    func shouldPresentArrivingNotification(_ route: NotificationRoute?) -> Bool {
        if backend.isLive {
            Task { await refreshFromBackend(silently: true) }
        }
        guard let route else { return true }
        return !isViewingDestination(of: route)
    }

    /// Once an item is on screen, notifications about it leave the phone's list.
    func didViewNotificationItem(_ item: NotificationItem) {
        let center = notificationCenter
        Task { await center.removeDeliveredNotifications(about: item) }
    }

    static func notificationInviteDeclinedKey(for memberID: UUID) -> String {
        "networkto.notifications.invite.declined.\(memberID.uuidString)"
    }

    static func deviceRegistrationKey(for memberID: UUID) -> String {
        "networkto.notifications.registration.\(memberID.uuidString)"
    }

    /// Loads this member's phone memory; runs whenever the member is identified or replaced.
    private func reloadNotificationMemory() {
        hasDeclinedNotificationInvite = defaults.bool(forKey: Self.notificationInviteDeclinedKey(for: member.id))
        registeredDeviceRegistration = storedDeviceRegistration(for: member.id)
    }

    private func storedDeviceRegistration(for memberID: UUID) -> DeviceRegistration? {
        guard let stored = defaults.dictionary(forKey: Self.deviceRegistrationKey(for: memberID)),
              let token = stored["token"] as? String,
              let rawEnvironment = stored["environment"] as? String,
              let environment = PushEnvironment(rawValue: rawEnvironment)
        else { return nil }
        return DeviceRegistration(token: token, environment: environment)
    }

    private func rememberDeviceRegistration(_ registration: DeviceRegistration) {
        registeredDeviceRegistration = registration
        defaults.set(
            ["token": registration.token, "environment": registration.environment.rawValue],
            forKey: Self.deviceRegistrationKey(for: member.id)
        )
    }

    /// Sign-out forgets the registration (after the removal attempt) but keeps "Not now".
    private func forgetDeviceRegistration() {
        pendingDeviceRegistration = nil
        registeredDeviceRegistration = nil
        defaults.removeObject(forKey: Self.deviceRegistrationKey(for: member.id))
    }

    /// Only after the backend confirms account deletion.
    private func clearNotificationMemory() {
        forgetDeviceRegistration()
        hasDeclinedNotificationInvite = false
        defaults.removeObject(forKey: Self.notificationInviteDeclinedKey(for: member.id))
    }

    /// Removes this phone's registration before the session ends, waiting at most `timeout`.
    private nonisolated static func unregisterDeviceToken(
        _ token: String,
        from backend: any BackendService,
        timeout: Duration
    ) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { _ = try? await backend.unregisterDeviceToken(token) }
            group.addTask { _ = try? await Task.sleep(for: timeout) }
            _ = await group.next()
            group.cancelAll()
        }
    }
}

enum MainTab: Hashable, Sendable { case today, connections, messages, profile }

/// The Messages tab's navigation values; owned by the store so a tapped notification can push
/// the conversation exactly as a manual tap would.
enum MessagesDestination: Hashable, Sendable { case conversation(UUID) }

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
