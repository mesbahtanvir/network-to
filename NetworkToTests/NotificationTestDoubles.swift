import Foundation
@testable import NetworkTo

/// Stands in for the phone's notification centre. A `@MainActor` class satisfies the async
/// requirements without locks and lets tests read what happened directly.
@MainActor
final class MockNotificationCenterClient: NotificationCenterClient {
    var status: NotificationAuthorizationStatus
    var grantsOnRequest = true
    private(set) var requestCount = 0
    private(set) var registerCalls = 0
    private(set) var removedItems: [NotificationItem] = []

    init(status: NotificationAuthorizationStatus = .notDetermined) {
        self.status = status
    }

    func authorizationStatus() async -> NotificationAuthorizationStatus { status }

    /// Mirrors iOS: the dialog decides once; later requests return the same answer with no UI.
    func requestAuthorization() async -> NotificationAuthorizationStatus {
        requestCount += 1
        if status == .notDetermined {
            status = grantsOnRequest ? .authorized : .denied
        }
        return status
    }

    func registerForRemoteNotifications() {
        registerCalls += 1
    }

    func removeDeliveredNotifications(about item: NotificationItem) async {
        removedItems.append(item)
    }
}

extension DeviceRegistration {
    /// A valid 32-byte token made of one repeated hex character, for tests.
    static func fixture(_ character: Character = "a", environment: PushEnvironment = .sandbox) -> DeviceRegistration {
        DeviceRegistration(token: String(repeating: character, count: 64), environment: environment)!
    }
}

/// Polls a condition on the main actor until it holds or the timeout passes.
@MainActor
func eventually(timeout: Duration = .seconds(2), _ condition: () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await condition()
}
