import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var store: AppStore

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
            if let message = store.transientMessage {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(NTColor.textPrimary)
                    .padding(.horizontal, NTSpacing.md)
                    .padding(.vertical, NTSpacing.sm)
                    .background(.regularMaterial)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                    .padding(.top, NTSpacing.sm)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: message) {
                        try? await Task.sleep(for: .seconds(2.2))
                        if store.transientMessage == message { store.transientMessage = nil }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.transientMessage)
    }
}
