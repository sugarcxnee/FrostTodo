import Foundation

/// 通知服务：调度本地通知并写 notification.sent 历史
@MainActor
public final class NotificationService {
    public let center: NotificationCentering
    private let history: HistoryRecording
    private let persistence: PersistenceService
    private let clock: ClockProviding

    public init(
        center: NotificationCentering = UserNotificationCenter(),
        history: HistoryRecording,
        persistence: PersistenceService,
        clock: ClockProviding = SystemClock()
    ) {
        self.center = center
        self.history = history
        self.persistence = persistence
        self.clock = clock
    }

    public func requestAuthorization() async -> Bool {
        await center.requestAuthorization()
    }

    /// 调度通知并记录历史
    public func schedule(_ request: NotificationRequest) async throws {
        try await center.add(
            identifier: request.identifier,
            title: request.title,
            body: request.body,
            triggerAfter: request.triggerAfter
        )
        do {
            try history.record(HistoryEventInput(
                type: .notificationSent,
                title: "通知已发送：\(request.title)",
                detail: request.body,
                payload: [
                    "identifier": request.identifier,
                    "triggerAfter": request.triggerAfter.map { String(Int($0)) } ?? "0",
                ],
                source: .system
            ))
            try persistence.save()
        } catch {
            persistence.rollback()
            throw error
        }
    }

    public func cancel(identifier: String) {
        center.removePending(identifier: identifier)
    }

    public func cancelAll() {
        center.removeAllPending()
    }

    // MARK: - 业务提醒

    /// 任务截止提醒：在截止时间到达时通知（已过期或无截止不调度）
    public func scheduleDueReminder(for task: TodoTask) async throws {
        guard let due = task.dueDate else { return }
        let interval = due.timeIntervalSince(clock.now)
        guard interval > 0 else { return }
        try await schedule(NotificationRequest(
            identifier: "due-\(task.id.uuidString)",
            title: "任务即将到期",
            body: "任务：\(task.title)，已到截止时间",
            triggerAfter: interval
        ))
    }

    /// 计时达到预计时长提醒（无预计或已超时不调度）
    public func scheduleEstimatedReachedReminder(
        for session: TimeSession,
        task: TodoTask,
        elapsedSeconds: Int
    ) async throws {
        guard let estimated = task.estimatedMinutes else { return }
        let remaining = TimeInterval(estimated * 60) - TimeInterval(elapsedSeconds)
        guard remaining > 0 else { return }
        try await schedule(NotificationRequest(
            identifier: "estimated-\(session.id.uuidString)",
            title: "计时达到预计时长",
            body: "任务：\(task.title)，已计时 \(estimated) 分钟",
            triggerAfter: remaining
        ))
    }

    /// 取消任务的截止提醒
    public func cancelDueReminder(for task: TodoTask) {
        cancel(identifier: "due-\(task.id.uuidString)")
    }
}
