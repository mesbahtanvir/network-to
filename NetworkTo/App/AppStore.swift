import Foundation

enum SessionGateState: Equatable, Sendable {
    case restoring
    case signedOut
    case authenticated
    case unavailable
}

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var phase: IntroductionPhase
    @Published private(set) var conversation: Conversation?
    @Published private(set) var connections: [Connection]
    @Published var availability: TodayAvailability?
    @Published var selectedTab: MainTab
    @Published var hasAuthenticated: Bool
    @Published private(set) var sessionGateState: SessionGateState
    @Published var hasCompletedOnboarding: Bool
    @Published var networkingPreferences: NetworkingPreferences
    @Published var meetingPreferences: MeetingPreferences
    @Published var safetyPreferences: SafetyPreferences
    @Published private(set) var membership: MembershipStatus
    @Published private(set) var isRefreshing = false
    @Published private(set) var isCompletingOnboarding = false
    /// The single notice channel. Errors stay until dismissed, retried, or replaced.
    @Published private(set) var notice: AppNotice?
    @Published private(set) var authenticationNotice: AppNotice?
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
    /// The introduction this member chose Interested on, remembered so the ended state can be
    /// shown once at its expiry; the phone never learns why it ended.
    private(set) var waitedIntroductionID: UUID?
    private var pendingRetry: (@MainActor () -> Void)?
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
        let resolvedHasAuthenticated = hasAuthenticated ?? (resolvedBackend.isLive ? false : defaults.bool(forKey: Self.authenticationKey))
        self.hasAuthenticated = resolvedHasAuthenticated
        if resolvedBackend.isLive, hasAuthenticated == nil {
            self.sessionGateState = .restoring
        } else {
            self.sessionGateState = resolvedHasAuthenticated ? .authenticated : .signedOut
        }
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
            applyFeedback(.good, stayConnected: true)
        } else if launchArguments.contains("--introduction-nonmutual-preview") {
            self.phase = .notMutual
        }
        if launchArguments.contains("--subscription-expired-preview") {
            self.membership = .expired
            self.phase = .searching
        }
        #endif
        if usesMockBackend {
            self.sessionGateState = self.hasAuthenticated ? .authenticated : .signedOut
        }
        #if DEBUG
        if launchArguments.contains("--session-restoring-preview") {
            self.sessionGateState = .restoring
            self.hasAuthenticated = false
        } else if launchArguments.contains("--session-unavailable-preview") {
            self.sessionGateState = .unavailable
            self.hasAuthenticated = false
        }
        #endif
        reloadMemberMemory()
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
        guard backend.isLive else {
            sessionGateState = hasAuthenticated ? .authenticated : .signedOut
            return
        }
        let wasAuthenticated = hasAuthenticated
        if !wasAuthenticated { sessionGateState = .restoring }
        do {
            guard try await backend.hasValidSession() else {
                transitionToSignedOut()
                finishSessionRestore()
                return
            }
            let data = try await backend.bootstrap()
            applyBackendSnapshot(data)
            hasAuthenticated = true
            defaults.set(true, forKey: Self.authenticationKey)
            sessionGateState = .authenticated
            startBackendUpdates()
            finishSessionRestore()
            await syncDeviceRegistration()
        } catch {
            finishSessionRestore()
            if wasAuthenticated {
                sessionGateState = .authenticated
                presentInformation("You’re offline. We’ll refresh when the connection returns.")
            } else {
                hasAuthenticated = false
                sessionGateState = .unavailable
            }
        }
    }

    func retrySessionRestore() {
        guard sessionGateState == .unavailable else { return }
        sessionGateState = .restoring
        Task { await restoreBackendSession() }
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
            applyBackendSnapshot(data)
        } catch {
            // No member action waits on a refresh; foreground refresh remains the recovery path.
            if !silently { presentInformation("Couldn’t refresh right now.") }
        }
    }

    private func applyBackendSnapshot(_ data: BackendSnapshot) {
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
        reloadMemberMemory()
        applyIntroductionState(from: data)
        prefetchCompanyMarks(for: data)
    }

    /// Derives the phase from a snapshot. An introduction the member was waiting on that is no
    /// longer returned has ended (at its expiry, by mutual interest, or by a block); the phone
    /// shows the ended state once and never knows more than that.
    private func applyIntroductionState(from data: BackendSnapshot) {
        if data.conversation != nil {
            phase = .conversation
            forgetWaitedIntroduction()
        } else if let current = data.introduction {
            if data.waitingForReciprocalInterest {
                phase = .waiting
                rememberWaitedIntroduction(current.id)
            } else {
                phase = .ready
                forgetWaitedIntroduction()
            }
        } else if waitedIntroductionID != nil {
            phase = .notMutual
        } else {
            phase = .searching
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
            authenticationNotice = nil
            try await backend.acceptMagicLinkCallback(url)
            await completeLiveAuthentication(email: nil)
        } catch {
            authenticationNotice = AppNotice(
                kind: .error,
                text: "We couldn’t verify this link. Check your connection or request a new link."
            )
        }
    }

    func dismissAuthenticationNotice(id: UUID) {
        guard authenticationNotice?.id == id else { return }
        authenticationNotice = nil
    }

    func clearAuthenticationNotice() {
        authenticationNotice = nil
    }

    private func completeLiveAuthentication(email: String?) async {
        if let email { verifiedWorkEmail = email }
        if let pendingCompany { member.company = pendingCompany }
        sessionGateState = .restoring
        do {
            let data = try await backend.bootstrap()
            applyBackendSnapshot(data)
            hasAuthenticated = true
            defaults.set(true, forKey: Self.authenticationKey)
            sessionGateState = .authenticated
            startBackendUpdates()
            await registerForRemoteNotificationsIfAllowed()
            await syncDeviceRegistration()
        } catch {
            hasAuthenticated = false
            sessionGateState = .unavailable
        }
    }

    func completeOnboarding() {
        guard !isCompletingOnboarding else { return }
        isCompletingOnboarding = true
        Task { [self] in
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
            catch {
                presentError(error.localizedDescription) { [weak self] in self?.completeOnboarding() }
            }
        }
    }

    func completeAuthentication(_ intent: AuthenticationIntent) {
        hasAuthenticated = true
        sessionGateState = .authenticated
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
        transitionToSignedOut()
        selectedTab = .today
        dismissNotice()
        let backend = self.backend
        signOutTask = Task {
            if let registration {
                await Self.unregisterDeviceToken(registration.token, from: backend, timeout: .seconds(5))
            }
            // The session is already over on this phone; nothing the member can do depends on
            // the remote revocation, so its failure raises nothing.
            _ = try? await backend.signOut()
        }
    }

    private func transitionToSignedOut() {
        backendUpdatesTask?.cancel()
        backendUpdatesTask = nil
        // This key is member-scoped, so remove it before replacing the member with `.empty`.
        forgetDeviceRegistration()
        hasAuthenticated = false
        sessionGateState = .signedOut
        defaults.set(false, forKey: Self.authenticationKey)
        hasCompletedOnboarding = false
        defaults.set(false, forKey: Self.onboardingKey)
        verifiedWorkEmail = ""
        member = .empty
        conversation = nil
        connections = []
        networkingPreferences = NetworkingPreferences()
        meetingPreferences = MeetingPreferences()
        safetyPreferences = SafetyPreferences()
        availability = nil
        membership = .notStarted
        phase = .searching
        pendingCompany = nil
        authenticationNotice = nil
        pendingNotificationRoute = nil
        messagesPath = []
        clearCompanyMarks()
    }

    func synchronizeAppStoreTransaction(_ signedTransaction: String) async {
        do {
            try await backend.synchronizeAppStoreTransaction(signedTransaction)
            if backend.isLive {
                await refreshFromBackend()
            } else {
                membership = .subscribed()
            }
            presentSuccess("Membership activated")
        } catch {
            presentInformation("Apple confirmed the purchase, but account access is still syncing. We’ll retry when the app opens.")
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
        if hasCompletedOnboarding { saveProfileKeepingEdits() }
    }

    /// Edits stay on screen whatever the save does. A failed save says so and offers to run
    /// again with the text as it is at that moment.
    private func saveProfileKeepingEdits() {
        let profile = member
        Task { [self] in
            do { try await backend.saveProfile(profile, onboardingComplete: true) }
            catch {
                presentError("Profile changes weren’t saved.") { [weak self] in self?.saveProfileKeepingEdits() }
            }
        }
    }

    func respondInterested() {
        guard phase == .ready else { return }
        phase = .waiting
        let introductionID = introduction.id
        Task {
            do {
                switch try await backend.respondToIntroduction(introductionID, interested: true) {
                case .waiting: rememberWaitedIntroduction(introductionID)
                case .mutual: await refreshFromBackend()
                case .notMutual: phase = .notMutual
                }
            } catch {
                phase = .ready
                presentError(error.localizedDescription)
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
                presentError(error.localizedDescription)
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

    /// The plan appears only once the backend holds it, so the details on screen are the
    /// details the other member will be told about.
    func planMeetup(detail: String) {
        guard canMessage, let conversationID = conversation?.id else { return }
        Task { [self] in
            do {
                try await backend.createMeetup(conversationID: conversationID, detail: detail)
                guard conversation?.id == conversationID else { return }
                conversation?.meetupStatus = .planned(detail)
            } catch {
                presentError("Coffee plan wasn’t sent.") { [weak self] in self?.planMeetup(detail: detail) }
            }
        }
    }

    func requestFeedback() {
        guard canMessage else { return }
        conversation?.meetupStatus = .feedbackDue
        phase = .feedback
    }

    /// Feedback changes nothing until the backend holds it: no Connection, phase, or tab moves
    /// before confirmation, and a failure returns `false` so the sheet can say so and stay open.
    @discardableResult
    func recordFeedback(_ outcome: MeetupOutcome, stayConnected: Bool) async -> Bool {
        guard phase == .feedback, let conversation else { return false }
        do {
            try await backend.recordMeetupFeedback(conversationID: conversation.id, outcome: outcome, stayConnected: stayConnected)
        } catch {
            return false
        }
        if self.conversation?.id == conversation.id { applyFeedback(outcome, stayConnected: stayConnected) }
        return true
    }

    /// The state feedback produces once it is held; the demonstration preview seeds a completed
    /// meeting through the same path without a backend round trip.
    private func applyFeedback(_ outcome: MeetupOutcome, stayConnected: Bool) {
        guard let conversation else { return }
        self.conversation?.meetupStatus = .completed
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
            presentInformation("Membership is needed for new introductions.")
            return
        }
        let previous = availability
        let next = TodayAvailability(
            area: area,
            window: window,
            expiresAt: Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: Date())
                ?? Date().addingTimeInterval(14_400)
        )
        availability = next
        saveOptimistically(
            { try await self.backend.saveAvailability(next) },
            rollback: { self.availability = previous },
            failure: "Availability wasn’t saved.",
            retry: { $0.setAvailability(area: area, window: window) }
        )
    }

    func clearAvailability() {
        let previous = availability
        availability = nil
        saveOptimistically(
            { try await self.backend.saveAvailability(nil) },
            rollback: { self.availability = previous },
            failure: "Availability wasn’t saved.",
            retry: { $0.clearAvailability() }
        )
    }

    func saveNetworkingPreferences(_ preferences: NetworkingPreferences) {
        let previous = networkingPreferences
        networkingPreferences = preferences
        saveOptimistically(
            { try await self.backend.saveNetworkingPreferences(preferences) },
            rollback: { self.networkingPreferences = previous },
            failure: "Introduction preferences weren’t saved.",
            success: "Introduction preferences saved",
            retry: { $0.saveNetworkingPreferences(preferences) }
        )
    }

    func saveMeetingPreferences(_ preferences: MeetingPreferences) {
        let previous = meetingPreferences
        meetingPreferences = preferences
        saveOptimistically(
            { try await self.backend.saveMeetingPreferences(preferences) },
            rollback: { self.meetingPreferences = previous },
            failure: "Meeting preferences weren’t saved.",
            success: "Meeting preferences saved",
            retry: { $0.saveMeetingPreferences(preferences) }
        )
    }

    /// Kept only on this phone, so the change is complete the moment it is made.
    func saveSafetyPreferences(_ preferences: SafetyPreferences) {
        safetyPreferences = preferences
        presentSuccess("Safety settings saved")
    }

    func unblock(_ name: String) {
        let previous = safetyPreferences.blockedMembers
        safetyPreferences.blockedMembers.removeAll { $0 == name }
        saveOptimistically(
            { try await self.backend.unblockMember(named: name) },
            rollback: { self.safetyPreferences.blockedMembers = previous },
            failure: "\(name) wasn’t unblocked.",
            success: "\(name) was unblocked",
            retry: { $0.unblock(name) }
        )
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
        presentSuccess("Résumé draft applied—review it before saving")
        if hasCompletedOnboarding { saveProfileKeepingEdits() }
    }

    func endCurrentConversation() {
        guard let current = conversation else { return }
        let previousPhase = phase
        conversation?.isEnded = true
        phase = .searching
        saveOptimistically(
            { try await self.backend.endConversation(current.id) },
            rollback: {
                if self.conversation?.id == current.id { self.conversation?.isEnded = current.isEnded }
                self.phase = previousPhase
            },
            failure: "Conversation wasn’t ended.",
            success: "Conversation ended",
            retry: { $0.endCurrentConversation() }
        )
    }

    func blockCurrentPerson() {
        guard let person = conversation?.person else { return }
        block(person)
    }

    /// Blocking removes the person everywhere at once: the block list, Connections, and the
    /// conversation when it is with them. A failed block restores all of it.
    func block(_ person: ProfessionalProfile) {
        let previousBlocked = safetyPreferences.blockedMembers
        let previousConnections = connections
        let previousConversation = conversation
        let previousPhase = phase
        if !safetyPreferences.blockedMembers.contains(person.name) {
            safetyPreferences.blockedMembers.append(person.name)
        }
        connections.removeAll { $0.person.id == person.id }
        if conversation?.person.id == person.id {
            conversation?.isBlocked = true
            conversation?.isEnded = true
            phase = .searching
        }
        saveOptimistically(
            { try await self.backend.blockMember(person.id) },
            rollback: {
                self.safetyPreferences.blockedMembers = previousBlocked
                self.connections = previousConnections
                self.conversation = previousConversation
                self.phase = previousPhase
            },
            failure: "\(person.name) wasn’t blocked.",
            success: "\(person.name) was blocked",
            retry: { $0.block(person) }
        )
    }

    func submitReport(category: ReportCategory, note: String) async throws {
        try await backend.submitReport(
            category: category,
            note: note,
            subjectID: conversation?.person.id ?? introduction.person.id,
            conversationID: conversation?.id
        )
        presentSuccess("Report submitted privately")
    }

    func removeConnection(_ id: UUID) {
        guard let index = connections.firstIndex(where: { $0.id == id }) else { return }
        let removed = connections.remove(at: index)
        saveOptimistically(
            { try await self.backend.removeConnection(id) },
            rollback: { self.connections.insert(removed, at: min(index, self.connections.count)) },
            failure: "Connection wasn’t removed.",
            success: "Connection removed",
            retry: { $0.removeConnection(id) }
        )
    }

    func deleteAccount() {
        if backend.isLive {
            Task { [self] in
                do {
                    try await backend.deleteAccount()
                    clearMemberMemory()
                    resetDemo(includeOnboarding: true)
                    transitionToSignedOut()
                    dismissNotice()
                } catch {
                    presentError(error.localizedDescription) { [weak self] in self?.deleteAccount() }
                }
            }
        } else {
            clearMemberMemory()
            resetDemo(includeOnboarding: true)
            transitionToSignedOut()
            dismissNotice()
        }
    }

    /// Continue from an ended or passed introduction; the ended state is shown once.
    func lookAgain() {
        guard phase == .passed || phase == .notMutual else { return }
        forgetWaitedIntroduction()
        phase = .searching
    }

    func resolveWithoutMutualInterest() {
        guard phase == .waiting else { return }
        phase = .notMutual
    }

    func resetDemo(includeOnboarding: Bool = false) {
        phase = .ready
        forgetWaitedIntroduction()
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

    // MARK: - Notices

    /// A completed action the backend has confirmed, or a purely local change. Leaves on its own.
    func presentSuccess(_ text: String) {
        pendingRetry = nil
        notice = AppNotice(kind: .success, text: text)
    }

    /// Something worth knowing that asks nothing of the member. Leaves on its own.
    func presentInformation(_ text: String) {
        pendingRetry = nil
        notice = AppNotice(kind: .information, text: text)
    }

    /// A member's own action that did not happen. Stays until dismissed, retried, or replaced;
    /// a newer notice of any kind drops the older retry.
    func presentError(_ text: String, retry: (@MainActor () -> Void)? = nil) {
        pendingRetry = retry
        notice = AppNotice(kind: .error, text: text, canRetry: retry != nil)
    }

    func dismissNotice() {
        pendingRetry = nil
        notice = nil
    }

    /// The auto-dismiss timer's variant: clears only the notice it was started for.
    func dismissNotice(id: UUID) {
        guard notice?.id == id else { return }
        dismissNotice()
    }

    /// Runs the failed action again with its original values; the action raises its own
    /// notice if it fails once more.
    func retryFailedAction() {
        let retry = pendingRetry
        dismissNotice()
        retry?()
    }

    /// Applies a change at once and, when the backend refuses it, restores what was there,
    /// names the action that did not happen, and offers to run it again with the same values.
    /// A success notice, where the action has one, appears only after the backend confirms.
    private func saveOptimistically(
        _ operation: @escaping @MainActor () async throws -> Void,
        rollback: @escaping @MainActor () -> Void,
        failure: String,
        success: String? = nil,
        retry: @escaping @MainActor (AppStore) -> Void
    ) {
        Task { [weak self] in
            do {
                try await operation()
                guard let self, let success else { return }
                self.presentSuccess(success)
            } catch {
                guard let self else { return }
                rollback()
                self.presentError(failure) { [weak self] in
                    guard let self else { return }
                    retry(self)
                }
            }
        }
    }

    // MARK: - Ended introduction

    static func waitedIntroductionKey(for memberID: UUID) -> String {
        "networkto.introduction.waited.\(memberID.uuidString)"
    }

    /// Kept for this member on this phone so the ended state survives a relaunch.
    private func rememberWaitedIntroduction(_ id: UUID) {
        waitedIntroductionID = id
        defaults.set(id.uuidString, forKey: Self.waitedIntroductionKey(for: member.id))
    }

    private func forgetWaitedIntroduction() {
        waitedIntroductionID = nil
        defaults.removeObject(forKey: Self.waitedIntroductionKey(for: member.id))
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
    private func reloadMemberMemory() {
        hasDeclinedNotificationInvite = defaults.bool(forKey: Self.notificationInviteDeclinedKey(for: member.id))
        registeredDeviceRegistration = storedDeviceRegistration(for: member.id)
        waitedIntroductionID = defaults.string(forKey: Self.waitedIntroductionKey(for: member.id))
            .flatMap(UUID.init(uuidString:))
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
    private func clearMemberMemory() {
        forgetDeviceRegistration()
        forgetWaitedIntroduction()
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
