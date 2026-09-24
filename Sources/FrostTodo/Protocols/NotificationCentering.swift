import Foundation
import UserNotifications

/// 通知内容（禁止 emoji，由调用方保证）
public struct NotificationRequest: Equatable {
    public var identifier: String
    public var title: String
    public var body: String
    /// 延迟秒数；nil 表示立即发送
    public var triggerAfter: TimeInterval?

    public init(identifier: String, title: String, body: String, triggerAfter: TimeInterval? = nil) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.triggerAfter = triggerAfter
    }
}

/// 通知中心抽象：测试使用 Mock，生产包装 UNUserNotificationCenter
public protocol NotificationCentering: AnyObject {
    func requestAuthorization() async -> Bool
    func add(identifier: String, title: String, body: String, triggerAfter: TimeInterval?) async throws
    func removePending(identifier: String)
    func removeAllPending()
}

/// 系统通知中心包装
public final class UserNotificationCenter: NotificationCentering {
    private let center = UNUserNotificationCenter.current()

    public init() {}

    public func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    public func add(identifier: String, title: String, body: String, triggerAfter: TimeInterval?) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = triggerAfter.map { UNTimeIntervalNotificationTrigger(timeInterval: max(1, $0), repeats: false) }
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try await center.add(request)
    }

    public func removePending(identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    public func removeAllPending() {
        center.removeAllPendingNotificationRequests()
    }
}
