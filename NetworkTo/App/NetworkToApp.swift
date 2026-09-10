import SwiftUI

@main
struct NetworkToApp: App {
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
                async let restore: Void = store.restoreBackendSession()
                await subscriptions.prepare()
                await restore
                if store.hasAuthenticated, let signedTransaction = subscriptions.latestSignedTransaction {
                    await store.synchronizeAppStoreTransaction(signedTransaction)
                }
            }
            .onOpenURL { url in
                Task { await store.acceptMagicLinkCallback(url) }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, store.isUsingLiveBackend else { return }
                Task { await store.restoreBackendSession() }
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
