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
                } else if !store.hasAuthenticated {
                    AuthenticationView()
                } else if store.hasCompletedOnboarding {
                    MainTabView()
                } else {
                    OnboardingView()
                }
            }
            .environmentObject(store)
            .environmentObject(subscriptions)
            .tint(NTColor.accentStrong)
            .task {
                appDelegate.attach(store)
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
                    if store.isUsingLiveBackend { await store.restoreBackendSession() }
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
}
