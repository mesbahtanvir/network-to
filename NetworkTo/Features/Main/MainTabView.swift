import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TabView(selection: $store.selectedTab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(MainTab.today)

            ConnectionsView()
                .tabItem { Label("Connections", systemImage: "person.2") }
                .tag(MainTab.connections)

            MessagesView()
                .tabItem { Label("Messages", systemImage: "message") }
                .badge(store.unreadMessageCount)
                .tag(MainTab.messages)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(MainTab.profile)
        }
        .overlay(alignment: .top) {
            if let notice = store.notice {
                NTInlineNotice(
                    notice: notice,
                    dismiss: { store.dismissNotice(id: notice.id) },
                    retry: retryAction(for: notice)
                )
                .padding(.horizontal, NTSpacing.md)
                .padding(.top, NTSpacing.sm)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                .task(id: notice.id) {
                    // Only a notice that asks nothing of the member leaves on its own.
                    guard !notice.persists else { return }
                    try? await Task.sleep(for: .seconds(2.2))
                    guard !Task.isCancelled else { return }
                    store.dismissNotice(id: notice.id)
                }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.notice)
    }

    private func retryAction(for notice: AppNotice) -> (() -> Void)? {
        guard notice.canRetry else { return nil }
        return { store.retryFailedAction() }
    }
}
