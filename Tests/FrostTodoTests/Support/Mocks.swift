import Foundation
@testable import FrostTodo

/// Mock 通知中心：捕获调度参数供测试断言
final class MockNotificationCenter: NotificationCentering {
    struct CapturedRequest: Equatable {
        var identifier: String
        var title: String
        var body: String
        var triggerAfter: TimeInterval?
    }

    var captured: [CapturedRequest] = []
    var authorizationGranted = true
    var removedIdentifiers: [String] = []
    var removeAllPendingCalled = false

    func requestAuthorization() async -> Bool {
        authorizationGranted
    }

    func add(identifier: String, title: String, body: String, triggerAfter: TimeInterval?) async throws {
        captured.append(CapturedRequest(
            identifier: identifier, title: title, body: body, triggerAfter: triggerAfter
        ))
    }

    func removePending(identifier: String) {
        removedIdentifiers.append(identifier)
    }

    func removeAllPending() {
        removeAllPendingCalled = true
    }
}
