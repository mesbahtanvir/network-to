import UIKit
import UserNotifications
import os

/// The UIKit entry points the SwiftUI app cannot express: the notification-centre delegate,
/// assigned before launch finishes so a cold-launch tap is never lost, and APNs token delivery.
/// Everything it learns is handed to the store as a Sendable value; one route and one token are
/// buffered until the store attaches.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    private weak var store: AppStore?
    private var pendingRoute: NotificationRoute?
    private var pendingRegistration: DeviceRegistration?
    private let logger = Logger(subsystem: "com.mesbahtanvir.networkto", category: "notifications")

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Connects the store and flushes anything that arrived before the SwiftUI body ran.
    func attach(_ store: AppStore) {
        self.store = store
        flush()
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        guard let environment = PushEnvironment.current(),
              let registration = DeviceRegistration(deviceToken: deviceToken, environment: environment)
        else { return }
        pendingRegistration = registration
        flush()
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        // Notifications are optional: foreground refresh and the realtime stream keep working.
        logger.notice("Remote notification registration failed: \(error.localizedDescription, privacy: .public)")
    }

    private func flush() {
        guard let store else { return }
        if let route = pendingRoute {
            pendingRoute = nil
            store.handleNotificationRoute(route)
        }
        if let registration = pendingRegistration {
            pendingRegistration = nil
            Task { await store.receiveDeviceRegistration(registration) }
        }
    }

    private func receive(_ route: NotificationRoute) {
        pendingRoute = route
        flush()
    }

    private func presentationOptions(for route: NotificationRoute?) -> UNNotificationPresentationOptions {
        let standard: UNNotificationPresentationOptions = [.banner, .list, .sound]
        guard let store else { return standard }
        return store.shouldPresentArrivingNotification(route) ? standard : []
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Runs off the main actor; the non-Sendable response is parsed here and only the route
    /// crosses over. A tap only navigates; it never records anything.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let route = NotificationRoute(userInfo: response.notification.request.content.userInfo)
        else { return }
        await receive(route)
    }

    /// The phone shows its standard banner unless the member is already on the destination.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let route = NotificationRoute(userInfo: notification.request.content.userInfo)
        return await presentationOptions(for: route)
    }
}
