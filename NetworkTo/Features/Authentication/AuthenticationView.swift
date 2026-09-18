import SwiftUI

struct AuthenticationView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var stage: Stage
    @State private var email = ""
    @State private var magicLinkRequest: MagicLinkRequest?
    @State private var emailError: String?
    @State private var serviceError: String?
    @State private var submissionOperation: SubmissionOperation?
    @State private var submissionID: UUID?
    @State private var submissionTask: Task<Void, Never>?
    @State private var isSubmissionTakingLonger = false
    @State private var verificationConnectionInterrupted = false
    @State private var verificationExpired = false
    @State private var resendSecondsRemaining = 60
    @FocusState private var focusedField: Field?

    private enum Stage: Equatable {
        case welcome
        case email(AuthenticationIntent)
        case magicLinkSent(AuthenticationIntent)
        case companyReview(String)
        case recovery
    }

    private enum Field { case email }

    private enum SubmissionOperation: Equatable {
        case checkingCompany
        case sendingLink
        case resendingLink

        var title: String {
            switch self {
            case .checkingCompany: "Checking your company…"
            case .sendingLink, .resendingLink: "Sending secure link…"
            }
        }
    }

    private var isSubmitting: Bool { submissionOperation != nil }

    init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--auth-signin-loading") {
            _stage = State(initialValue: .email(.signIn))
            _email = State(initialValue: "you@company.com")
            _submissionOperation = State(initialValue: .checkingCompany)
            _isSubmissionTakingLonger = State(initialValue: true)
        } else if arguments.contains("--auth-signup-email") {
            _stage = State(initialValue: .email(.signUp))
        } else if arguments.contains("--auth-signin-email") {
            _stage = State(initialValue: .email(.signIn))
        } else if arguments.contains("--auth-signup-verification") || arguments.contains("--auth-signup-verification-offline") {
            _stage = State(initialValue: .magicLinkSent(.signUp))
            _email = State(initialValue: "alex@orbitsystems.com")
            _magicLinkRequest = State(initialValue: MagicLinkRequest(
                id: UUID(), claimSecret: "preview-magic-link-request", email: "alex@orbitsystems.com"
            ))
            if arguments.contains("--auth-signup-verification-offline") {
                _verificationConnectionInterrupted = State(initialValue: true)
            }
        } else {
            _stage = State(initialValue: .welcome)
        }
        #else
        _stage = State(initialValue: .welcome)
        #endif
    }

    var body: some View {
        ZStack {
            NTColor.background.ignoresSafeArea()
            Group {
                switch stage {
                case .welcome:
                    welcome
                case .email(let intent):
                    emailEntry(intent)
                case .magicLinkSent(let intent):
                    magicLinkSent(intent)
                case .companyReview(let domain):
                    companyReview(domain)
                case .recovery:
                    accountRecovery
                }
            }
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
        .foregroundStyle(NTColor.textPrimary)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: stage)
        .task { await restorePendingMagicLinkIfNeeded() }
        .onDisappear { cancelSubmission() }
        .overlay(alignment: .top) {
            if let notice = store.authenticationNotice {
                NTInlineNotice(
                    notice: notice,
                    dismiss: { store.dismissAuthenticationNotice(id: notice.id) }
                )
                .padding(.horizontal, NTSpacing.md)
                .padding(.top, NTSpacing.sm)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.authenticationNotice)
    }

    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NTSpacing.xxl) {
                HStack(spacing: NTSpacing.sm) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.title3)
                        .foregroundStyle(NTColor.meeting)
                        .frame(width: 44, height: 44)
                        .background(NTColor.meeting.opacity(0.09))
                        .clipShape(Circle())
                    Text("network.to")
                        .font(.headline.weight(.semibold))
                }

                VStack(alignment: .leading, spacing: NTSpacing.md) {
                    Text("Move toward your goals through people worth knowing.")
                        .font(.largeTitle.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Thoughtful local 1:1 introductions across companies and industries—built for ambitious people who want to move faster together.")
                        .font(.body)
                        .foregroundStyle(NTColor.textSecondary)
                        .lineSpacing(3)
                }

                VStack(alignment: .leading, spacing: NTSpacing.lg) {
                    welcomePoint("scope", "Your direction comes first", "Introductions are shaped by what each person is working toward.")
                    welcomePoint("arrow.triangle.branch", "Beyond your usual circle", "Learn across companies, disciplines, and adjacent industries.")
                    welcomePoint("cup.and.saucer", "Same city. Same energy.", "Both people choose before a focused, in-person 1:1 coffee chat.")
                }
                .padding(NTSpacing.lg)
                .ntSurface(radius: NTRadius.hero)

                VStack(spacing: NTSpacing.sm) {
                    Button("Create account") { stage = .email(.signUp) }
                        .buttonStyle(NTPrimaryButtonStyle())
                    Button("Sign in") { stage = .email(.signIn) }
                        .buttonStyle(NTSecondaryButtonStyle())
                }

                Text("North American cities · Verified work email · Private by default")
                    .font(.caption)
                    .foregroundStyle(NTColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Available across North American cities. Work email verification. Private by default.")
            }
            .padding(.horizontal, NTSpacing.lg)
            .padding(.top, NTSpacing.xl)
            .padding(.bottom, NTSpacing.xxl)
        }
    }

    private func welcomePoint(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: NTSpacing.md) {
            Image(systemName: symbol)
                .foregroundStyle(NTColor.accent)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: NTSpacing.xxs) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(NTColor.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func emailEntry(_ intent: AuthenticationIntent) -> some View {
        VStack(spacing: 0) {
            authenticationHeader {
                cancelSubmission()
                stage = .welcome
            }
            ScrollView {
                VStack(alignment: .leading, spacing: NTSpacing.xl) {
                    authenticationTitle(
                        intent == .signUp ? "Create your account" : "Welcome back",
                        intent == .signUp
                            ? "Start with your work email. It verifies professional affiliation and stays private."
                            : "Use the work email connected to your account."
                    )

                    VStack(alignment: .leading, spacing: NTSpacing.xs) {
                        Text("Work email").font(.headline)
                        TextField("you@company.com", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .email)
                            .padding(NTSpacing.md)
                            .background(NTColor.surface)
                            .clipShape(RoundedRectangle(cornerRadius: NTRadius.field, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: NTRadius.field, style: .continuous)
                                    .stroke(emailError == nil ? NTColor.separator : NTColor.destructive, lineWidth: 1)
                            }
                            .onSubmit { continueFromEmail(intent) }

                        if let emailError {
                            Label(emailError, systemImage: "exclamationmark.circle.fill")
                                .font(.footnote)
                                .foregroundStyle(NTColor.destructive)
                        } else if intent == .signUp {
                            Text("Personal email providers aren’t eligible for the first release.")
                                .font(.footnote)
                                .foregroundStyle(NTColor.textSecondary)
                        }
                    }

                    NTPrivacyNote(text: "Members see your verified company, never your email address. Verification does not imply employer endorsement.")

                    if intent == .signIn {
                        Button("Having trouble signing in?") { stage = .recovery }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(NTColor.accentStrong)
                    }

                    if let serviceError {
                        Label(serviceError, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(NTColor.destructive)
                    }
                    if isSubmissionTakingLonger {
                        connectionDelayNote
                    }
                }
                .padding(.horizontal, NTSpacing.lg)
                .padding(.top, NTSpacing.xl)
            }

            Button { continueFromEmail(intent) } label: {
                submissionButtonLabel(defaultTitle: "Continue")
            }
                .buttonStyle(NTPrimaryButtonStyle())
                .disabled(isSubmitting || email.isEmpty)
                .padding(.horizontal, NTSpacing.lg)
                .padding(.vertical, NTSpacing.md)
                .background(.ultraThinMaterial)
        }
        .onAppear { focusedField = .email }
    }

    private func magicLinkSent(_ intent: AuthenticationIntent) -> some View {
        VStack(spacing: 0) {
            authenticationHeader { abandonMagicLink(andReturnTo: intent) }
            ScrollView {
                VStack(alignment: .leading, spacing: NTSpacing.xl) {
                    authenticationTitle("Check your work inbox", "We sent a secure sign-in link to \(email).")

                    VStack(alignment: .leading, spacing: NTSpacing.lg) {
                        magicLinkPath(
                            symbol: "iphone",
                            title: "Inbox on this iPhone",
                            detail: "Open the link in your email. You’ll return here automatically."
                        )
                        Divider()
                        magicLinkPath(
                            symbol: "laptopcomputer",
                            title: "Inbox on a work laptop",
                            detail: "Open the link there and keep this screen open. Verification will return securely to this phone—nothing to copy or type."
                        )
                    }
                    .padding(NTSpacing.lg)
                    .ntSurface()

                    HStack(spacing: NTSpacing.sm) {
                        Group {
                            if verificationExpired {
                                Image(systemName: "clock.badge.exclamationmark")
                                    .foregroundStyle(NTColor.warning)
                            } else if verificationConnectionInterrupted {
                                Image(systemName: "wifi.exclamationmark")
                                    .foregroundStyle(NTColor.warning)
                            } else {
                                ProgressView().tint(NTColor.accent)
                            }
                        }
                        .frame(width: 22)
                        VStack(alignment: .leading, spacing: NTSpacing.xxs) {
                            Text(verificationExpired ? "This link expired" : (verificationConnectionInterrupted ? "Connection interrupted" : "Waiting for verification"))
                                .font(.subheadline.weight(.semibold))
                            Text(verificationExpired
                                 ? "Send a new secure link to continue."
                                 : (verificationConnectionInterrupted
                                    ? "We’ll keep checking automatically when the connection returns."
                                    : "This request expires shortly and works only with this iPhone."))
                                .font(.footnote)
                                .foregroundStyle(NTColor.textSecondary)
                        }
                    }
                    .padding(NTSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background((verificationExpired || verificationConnectionInterrupted ? NTColor.warning : NTColor.accent).opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: NTRadius.field, style: .continuous))
                    .accessibilityElement(children: .combine)

                    if let serviceError {
                        Label(serviceError, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(NTColor.destructive)
                    }
                    if isSubmissionTakingLonger {
                        connectionDelayNote
                    }
                }
                .padding(.horizontal, NTSpacing.lg)
                .padding(.top, NTSpacing.xl)
            }

            VStack(spacing: NTSpacing.xs) {
                Button { resendMagicLink(intent) } label: {
                    if submissionOperation == .resendingLink {
                        submissionButtonLabel(defaultTitle: "Send a new link")
                    } else {
                        Text(resendSecondsRemaining > 0 ? "Send a new link in \(resendSecondsRemaining)s" : "Send a new link")
                    }
                }
                .buttonStyle(NTSecondaryButtonStyle())
                .disabled(isSubmitting || resendSecondsRemaining > 0)

                Button("Use a different email") {
                    abandonMagicLink(andReturnTo: intent)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(NTColor.accentStrong)

                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--auth-signup-verification") {
                    Button("Complete preview") { store.completeAuthentication(intent) }
                        .font(.caption)
                        .foregroundStyle(NTColor.textSecondary)
                }
                #endif
            }
            .padding(.horizontal, NTSpacing.lg)
            .padding(.vertical, NTSpacing.md)
            .background(.ultraThinMaterial)
        }
        .task(id: magicLinkRequest?.id) {
            guard let magicLinkRequest else { return }
            await waitForMagicLink(magicLinkRequest)
        }
        .task(id: magicLinkRequest?.id.uuidString) {
            guard magicLinkRequest != nil else { return }
            await runResendCountdown()
        }
    }

    private func magicLinkPath(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: NTSpacing.md) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(NTColor.accent)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: NTSpacing.xxs) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(NTColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func authenticationHeader(back: @escaping () -> Void) -> some View {
        HStack {
            Button(action: back) {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Back")
            Spacer()
            Text("network.to").font(.subheadline.weight(.semibold))
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, NTSpacing.sm)
    }

    private func companyReview(_ domain: String) -> some View {
        VStack(spacing: 0) {
            authenticationHeader { stage = .email(.signUp) }
            ScrollView {
                VStack(alignment: .leading, spacing: NTSpacing.xl) {
                    Image(systemName: "building.2.crop.circle")
                        .font(.system(size: 46))
                        .foregroundStyle(NTColor.accent)
                    authenticationTitle(
                        "We’re reviewing your company",
                        "We don’t recognize \(domain) yet. New technology-company domains receive a short eligibility review."
                    )
                    VStack(alignment: .leading, spacing: NTSpacing.md) {
                        Label("Your request is saved", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(NTColor.success)
                        Text("We’ll email you after review. Your profile and work email have not been shared with other members.")
                            .foregroundStyle(NTColor.textSecondary)
                    }
                    .padding(NTSpacing.lg)
                    .ntSurface()
                    NTPrivacyNote(text: "Company review protects the professional-only boundary of the network.")
                }
                .padding(NTSpacing.lg)
            }
            Button("Return to welcome") { stage = .welcome }
                .buttonStyle(NTSecondaryButtonStyle())
                .padding(NTSpacing.lg)
        }
    }

    private var accountRecovery: some View {
        VStack(spacing: 0) {
            authenticationHeader {
                cancelSubmission()
                stage = .email(.signIn)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: NTSpacing.xl) {
                    authenticationTitle("Recover your account", "Enter your verified work email and we’ll send a secure recovery link.")
                    VStack(alignment: .leading, spacing: NTSpacing.xs) {
                        Text("Work email").font(.headline)
                        TextField("you@company.com", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .email)
                            .padding(NTSpacing.md)
                            .background(NTColor.surface)
                            .clipShape(RoundedRectangle(cornerRadius: NTRadius.field, style: .continuous))
                    }
                    NTPrivacyNote(text: "Recovery links expire and can only be used once.")
                    if let serviceError {
                        Label(serviceError, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(NTColor.destructive)
                    }
                    if isSubmissionTakingLonger {
                        connectionDelayNote
                    }
                }
                .padding(NTSpacing.lg)
            }
            Button { continueFromEmail(.signIn) } label: {
                submissionButtonLabel(defaultTitle: "Send secure sign-in link")
            }
                .buttonStyle(NTPrimaryButtonStyle())
                .disabled(!email.contains("@") || isSubmitting)
                .padding(NTSpacing.lg)
        }
        .onAppear { focusedField = .email }
    }

    private func authenticationTitle(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: NTSpacing.sm) {
            Text(title).font(.largeTitle.weight(.semibold))
            Text(detail)
                .font(.body)
                .foregroundStyle(NTColor.textSecondary)
                .lineSpacing(2)
        }
    }

    private var connectionDelayNote: some View {
        Label("This is taking longer than usual. Keep network.to open; it’s safe to try again if the request doesn’t finish.", systemImage: "hourglass")
            .font(.footnote)
            .foregroundStyle(NTColor.textSecondary)
            .padding(NTSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NTColor.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: NTRadius.context, style: .continuous))
            .accessibilityLabel("This is taking longer than usual. Keep network.to open. It is safe to try again if the request does not finish.")
    }

    private func submissionButtonLabel(defaultTitle: String) -> some View {
        HStack(spacing: NTSpacing.xs) {
            if submissionOperation != nil {
                ProgressView()
                    .tint(NTColor.textSecondary)
                    .controlSize(.small)
            }
            Text(submissionOperation?.title ?? defaultTitle)
        }
    }

    private func beginSubmission(_ operation: SubmissionOperation) -> UUID {
        cancelSubmission()
        store.clearAuthenticationNotice()
        let id = UUID()
        submissionID = id
        submissionOperation = operation
        scheduleLongRequestMessage(for: id, operation: operation)
        return id
    }

    private func updateSubmission(_ id: UUID, to operation: SubmissionOperation) {
        guard submissionID == id else { return }
        submissionOperation = operation
        isSubmissionTakingLonger = false
        scheduleLongRequestMessage(for: id, operation: operation)
    }

    private func finishSubmission(_ id: UUID) {
        guard submissionID == id else { return }
        submissionTask = nil
        submissionID = nil
        submissionOperation = nil
        isSubmissionTakingLonger = false
    }

    private func cancelSubmission() {
        submissionTask?.cancel()
        submissionTask = nil
        submissionID = nil
        submissionOperation = nil
        isSubmissionTakingLonger = false
    }

    private func scheduleLongRequestMessage(for id: UUID, operation: SubmissionOperation) {
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, submissionID == id, submissionOperation == operation else { return }
            isSubmissionTakingLonger = true
        }
    }

    private func requestFailureMessage(action: String) -> String {
        "We couldn’t \(action). Check your connection and try again."
    }

    private func continueFromEmail(_ intent: AuthenticationIntent) {
        let normalized = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let consumerDomains = ["gmail.com", "outlook.com", "hotmail.com", "icloud.com", "yahoo.com"]
        let components = normalized.split(separator: "@")
        let domain = components.count == 2 ? String(components[1]) : ""

        guard components.count == 2, domain.contains("."), !consumerDomains.contains(domain) else {
            emailError = intent == .signUp
                ? "Use a qualifying company email address."
                : "Enter the work email connected to your account."
            focusedField = .email
            return
        }

        email = normalized
        emailError = nil
        serviceError = nil
        focusedField = nil
        guard !isSubmitting else { return }
        let id = beginSubmission(.checkingCompany)
        submissionTask = Task {
            defer { finishSubmission(id) }
            do {
                let decision = try await store.validateCompany(for: normalized)
                guard !Task.isCancelled, submissionID == id else { return }
                switch decision {
                case .eligible:
                    updateSubmission(id, to: .sendingLink)
                    let request = try await store.requestMagicLink(for: normalized, intent: intent)
                    guard !Task.isCancelled, submissionID == id else { return }
                    magicLinkRequest = request
                    verificationConnectionInterrupted = false
                    verificationExpired = false
                    stage = .magicLinkSent(intent)
                case .reviewRequired(let domain):
                    if intent == .signUp {
                        stage = .companyReview(domain)
                    } else {
                        serviceError = "We couldn’t find an account for this work email."
                    }
                case .ineligible(let reason):
                    serviceError = reason
                }
            } catch {
                guard !Task.isCancelled, submissionID == id else { return }
                serviceError = requestFailureMessage(action: "continue")
            }
        }
    }

    private func resendMagicLink(_ intent: AuthenticationIntent) {
        guard !isSubmitting, resendSecondsRemaining == 0 else { return }
        serviceError = nil
        let id = beginSubmission(.resendingLink)
        submissionTask = Task {
            defer { finishSubmission(id) }
            do {
                let request = try await store.requestMagicLink(for: email, intent: intent)
                guard !Task.isCancelled, submissionID == id else { return }
                magicLinkRequest = request
                verificationConnectionInterrupted = false
                verificationExpired = false
                resendSecondsRemaining = 60
            } catch {
                guard !Task.isCancelled, submissionID == id else { return }
                serviceError = requestFailureMessage(action: "send a new link")
            }
        }
    }

    private func waitForMagicLink(_ request: MagicLinkRequest) async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--auth-signup-verification-offline") { return }
        #endif
        while !Task.isCancelled {
            guard request.createdAt.addingTimeInterval(10 * 60) > Date() else {
                verificationExpired = true
                verificationConnectionInterrupted = false
                await store.clearPendingMagicLinkRequest()
                return
            }
            do {
                if try await store.claimMagicLink(request) { return }
                verificationConnectionInterrupted = false
            } catch {
                guard !Task.isCancelled else { return }
                verificationConnectionInterrupted = true
                serviceError = nil
                do {
                    try await Task.sleep(for: .seconds(4))
                } catch {
                    return
                }
                continue
            }

            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
        }
    }

    private func restorePendingMagicLinkIfNeeded() async {
        guard stage == .welcome, let request = await store.pendingMagicLinkRequest() else { return }
        email = request.email
        magicLinkRequest = request
        stage = .magicLinkSent(request.isSignUp ? .signUp : .signIn)
    }

    private func abandonMagicLink(andReturnTo intent: AuthenticationIntent) {
        cancelSubmission()
        magicLinkRequest = nil
        verificationConnectionInterrupted = false
        verificationExpired = false
        Task { await store.clearPendingMagicLinkRequest() }
        stage = .email(intent)
    }

    private func runResendCountdown() async {
        resendSecondsRemaining = 60
        while resendSecondsRemaining > 0, !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(1))
                resendSecondsRemaining -= 1
            } catch {
                return
            }
        }
    }
}
