import UIKit
import UserNotifications

/// The phone's notification centre as the store sees it. Implementations touch the system only
/// inside these methods, so constructing a store never presents anything.
protocol NotificationCenterClient: Sendable {
    func authorizationStatus() async -> NotificationAuthorizationStatus
    /// Presents the phone's dialog while it has never been asked; returns the fresh status either way.
    func requestAuthorization() async -> NotificationAuthorizationStatus
    @MainActor func registerForRemoteNotifications()
    func removeDeliveredNotifications(about item: NotificationItem) async
}

struct SystemNotificationCenterClient: NotificationCenterClient {
    func authorizationStatus() async -> NotificationAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return Self.status(from: settings.authorizationStatus)
    }

    func requestAuthorization() async -> NotificationAuthorizationStatus {
        // Alerts and the system sound only: no icon badge, no provisional or time-sensitive options.
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        return await authorizationStatus()
    }

    @MainActor
    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    func removeDeliveredNotifications(about item: NotificationItem) async {
        let center = UNUserNotificationCenter.current()
        let identifiers = await center.deliveredNotifications()
            .filter { item.matches(userInfo: $0.request.content.userInfo) }
            .map(\.request.identifier)
        guard !identifiers.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private static func status(from status: UNAuthorizationStatus) -> NotificationAuthorizationStatus {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized, .provisional, .ephemeral: .authorized
        @unknown default: .denied
        }
    }
}
