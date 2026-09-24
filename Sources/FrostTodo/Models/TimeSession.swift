import Foundation
import SwiftData

/// 时间段状态：进行中 / 已结束
public enum SessionState: String, Codable, CaseIterable {
    case running
    case ended
}

/// 时间段模型：一次“开始到结束”的计时记录
@Model
public final class TimeSession {
    @Attribute(.unique) public var id: UUID
    public var taskID: UUID
    public var startAt: Date
    public var endAt: Date?
    public var durationSeconds: Int
    public var calendarEventID: String?
    public var calendarIdentifier: String?
    public var state: String
    public var task: TodoTask?

    public init(
        id: UUID = UUID(),
        taskID: UUID,
        startAt: Date,
        endAt: Date? = nil,
        durationSeconds: Int = 0,
        calendarEventID: String? = nil,
        calendarIdentifier: String? = nil,
        state: String = SessionState.running.rawValue
    ) {
        self.id = id
        self.taskID = taskID
        self.startAt = startAt
        self.endAt = endAt
        self.durationSeconds = durationSeconds
        self.calendarEventID = calendarEventID
        self.calendarIdentifier = calendarIdentifier
        self.state = state
        self.task = nil
    }

    public var stateValue: SessionState {
        get { SessionState(rawValue: state) ?? .running }
        set { state = newValue.rawValue }
    }

    public var isRunning: Bool { stateValue == .running }

    /// 结束当前时间段，返回实际时长（秒）；对已结束的时间段是幂等的
    @discardableResult
    public func end(at date: Date) -> Int {
        guard stateValue == .running else { return durationSeconds }
        endAt = date
        durationSeconds = max(0, Int(date.timeIntervalSince(startAt)))
        stateValue = .ended
        return durationSeconds
    }

    /// 当前用时：进行中按 now - startAt 计算，已结束返回记录时长
    public func currentElapsedSeconds(at now: Date) -> Int {
        if isRunning {
            return max(0, Int(now.timeIntervalSince(startAt)))
        }
        return durationSeconds
    }
}
