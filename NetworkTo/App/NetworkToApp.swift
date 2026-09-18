import SwiftUI

@main
struct NetworkToApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()
    @StateObject private var subscriptions = SubscriptionStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if isMembershipPreview {
                    NavigationStack { MembershipView() }
                } else {
                    switch store.sessionGateState {
                    case .restoring:
                        SessionRestoringView()
                    case .unavailable:
                        SessionUnavailableView(retry: store.retrySessionRestore)
                    case .signedOut:
                        AuthenticationView()
                    case .authenticated:
                        if store.hasCompletedOnboarding {
                            MainTabView()
                        } else {
                            OnboardingView()
                        }
                    }
                }
            }
            .environmentObject(store)
            .environmentObject(subscriptions)
            .tint(NTColor.accentStrong)
            .task {
                appDelegate.attach(store)
                guard !isSessionGatePreview else { return }
                async let restore: Void = store.restoreBackendSession()
                await subscriptions.prepare()
                await restore
                if store.hasAuthenticated, let signedTransaction = subscriptions.latestSignedTransaction {
                    await store.synchronizeAppStoreTransaction(signedTransaction)
                }
                await store.registerForRemoteNotificationsIfAllowed()
            }
            .onOpenURL { url in
                Task { await store.acceptMagicLinkCallback(url) }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task {
                    if store.isUsingLiveBackend, store.sessionGateState != .signedOut {
                        await store.restoreBackendSession()
                    }
                    // Re-reads the phone's permission (iOS gives no callback when Settings change)
                    // and refreshes the registration's last-confirmed time while allowed.
                    await store.registerForRemoteNotificationsIfAllowed()
                }
            }
        }
    }

    private var isMembershipPreview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--membership-preview")
        #else
        false
        #endif
    }

    private var isSessionGatePreview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--session-restoring-preview") ||
            ProcessInfo.processInfo.arguments.contains("--session-unavailable-preview")
        #else
        false
        #endif
    }
}

private struct SessionRestoringView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTakingLonger = false
    @State private var breathes = false

    var body: some View {
        ZStack {
            NTColor.background.ignoresSafeArea()
            VStack(spacing: NTSpacing.xl) {
                ZStack {
                    Circle()
                        .fill(NTColor.accent.opacity(0.09))
                        .frame(width: 92, height: 92)
                        .scaleEffect(breathes ? 1.04 : 0.96)
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(NTColor.accentStrong)
                }
                .accessibilityHidden(true)

                VStack(spacing: NTSpacing.xs) {
                    Text("network.to")
                        .font(.title2.weight(.semibold))
                    Text(isTakingLonger ? "Still connecting securely…" : "Bringing your network back…")
                        .font(.subheadline)
                        .foregroundStyle(NTColor.textSecondary)
                        .contentTransition(.opacity)
                }

                ProgressView()
                    .tint(NTColor.accentStrong)
                    .accessibilityLabel(isTakingLonger ? "Still connecting securely" : "Restoring your session")
            }
            .padding(NTSpacing.xl)
        }
        .foregroundStyle(NTColor.textPrimary)
        .task {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                breathes = true
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                isTakingLonger = true
            }
        }
    }
}

private struct SessionUnavailableView: View {
    let retry: () -> Void

    var body: some View {
        ZStack {
            NTColor.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: NTSpacing.xl) {
                Spacer()
                Image(systemName: "wifi.slash")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(NTColor.accentStrong)
                    .frame(width: 68, height: 68)
                    .background(NTColor.accent.opacity(0.09))
                    .clipShape(Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: NTSpacing.sm) {
                    Text("We couldn’t connect")
                        .font(.largeTitle.weight(.semibold))
                    Text("Check your connection and try again. If you already have an account, your saved session is still on this iPhone.")
                        .font(.body)
                        .foregroundStyle(NTColor.textSecondary)
                        .lineSpacing(3)
                }

                Button("Try again", action: retry)
                    .buttonStyle(NTPrimaryButtonStyle())
                    .accessibilityHint("Checks your saved session again")

                NTPrivacyNote(text: "A temporary connection problem won’t sign you out or erase your progress.")
                Spacer()
            }
            .padding(NTSpacing.xl)
            .frame(maxWidth: 520)
        }
        .foregroundStyle(NTColor.textPrimary)
    }
}
