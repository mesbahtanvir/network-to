import SwiftUI

struct AuthenticationView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var stage: Stage
    @State private var email = ""
    @State private var magicLinkRequest: MagicLinkRequest?
    @State private var emailError: String?
    @State private var serviceError: String?
    @State private var isSubmitting = false
    @State private var resendSecondsRemaining = 60
    @FocusState private var focusedField: Field?

    private enum Stage: Equatable {
        case welcome
        case email(AuthenticationIntent)
        case magicLinkSent(AuthenticationIntent)
        case companyReview(String)
        case recovery
        case recoverySent
    }

    private enum Field { case email }

    init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--auth-signup-email") {
            _stage = State(initialValue: .email(.signUp))
        } else if arguments.contains("--auth-signin-email") {
            _stage = State(initialValue: .email(.signIn))
        } else if arguments.contains("--auth-signup-verification") {
            _stage = State(initialValue: .magicLinkSent(.signUp))
            _email = State(initialValue: "alex@orbitsystems.com")
            _magicLinkRequest = State(initialValue: MagicLinkRequest(
                id: UUID(), claimSecret: "preview-magic-link-request", email: "alex@orbitsystems.com"
            ))
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
                case .recoverySent:
                    recoveryConfirmation
                }
            }
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
        .foregroundStyle(NTColor.textPrimary)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: stage)
        .task { await restorePendingMagicLinkIfNeeded() }
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
            authenticationHeader { stage = .welcome }
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
                }
                .padding(.horizontal, NTSpacing.lg)
                .padding(.top, NTSpacing.xl)
            }

            Button("Continue") { continueFromEmail(intent) }
                .buttonStyle(NTPrimaryButtonStyle())
                .disabled(isSubmitting)
                .overlay { if isSubmitting { ProgressView().tint(NTColor.background) } }
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
                        ProgressView().tint(NTColor.accent)
                        VStack(alignment: .leading, spacing: NTSpacing.xxs) {
                            Text("Waiting for verification")
                                .font(.subheadline.weight(.semibold))
                            Text("This request expires shortly and works only with this iPhone.")
                                .font(.footnote)
                                .foregroundStyle(NTColor.textSecondary)
                        }
                    }
                    .padding(NTSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NTColor.accent.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: NTRadius.field, style: .continuous))

                    if let serviceError {
                        Label(serviceError, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(NTColor.destructive)
                    }
                }
                .padding(.horizontal, NTSpacing.lg)
                .padding(.top, NTSpacing.xl)
            }

            VStack(spacing: NTSpacing.xs) {
                Button(resendSecondsRemaining > 0 ? "Send a new link in \(resendSecondsRemaining)s" : "Send a new link") {
                    resendMagicLink(intent)
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
            authenticationHeader { stage = .email(.signIn) }
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
                }
                .padding(NTSpacing.lg)
            }
            Button("Send secure sign-in link") { continueFromEmail(.signIn) }
                .buttonStyle(NTPrimaryButtonStyle())
                .disabled(!email.contains("@") || isSubmitting)
                .overlay { if isSubmitting { ProgressView().tint(NTColor.background) } }
                .padding(NTSpacing.lg)
        }
        .onAppear { focusedField = .email }
    }

    private var recoveryConfirmation: some View {
        VStack(alignment: .leading, spacing: NTSpacing.xl) {
            Spacer()
            Image(systemName: "envelope.badge.fill")
                .font(.system(size: 46))
                .foregroundStyle(NTColor.accent)
            authenticationTitle("Check your inbox", "If an account exists for \(email), a secure recovery link is on its way.")
            Button("Back to sign in") { stage = .email(.signIn) }
                .buttonStyle(NTPrimaryButtonStyle())
            Spacer()
        }
        .padding(NTSpacing.lg)
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
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                let decision = try await store.validateCompany(for: normalized)
                switch decision {
                case .eligible:
                    magicLinkRequest = try await store.requestMagicLink(for: normalized, intent: intent)
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
                serviceError = error.localizedDescription
            }
        }
    }

    private func resendMagicLink(_ intent: AuthenticationIntent) {
        magicLinkRequest = nil
        resendSecondsRemaining = 60
        serviceError = nil
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                magicLinkRequest = try await store.requestMagicLink(for: email, intent: intent)
            } catch {
                serviceError = error.localizedDescription
            }
        }
    }

    private func waitForMagicLink(_ request: MagicLinkRequest) async {
        while !Task.isCancelled {
            guard request.createdAt.addingTimeInterval(10 * 60) > Date() else {
                serviceError = "This sign-in link expired. Send a new link to continue."
                await store.clearPendingMagicLinkRequest()
                return
            }
            do {
                if try await store.claimMagicLink(request) { return }
            } catch {
                guard !Task.isCancelled else { return }
                serviceError = error.localizedDescription
                return
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
        magicLinkRequest = nil
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
