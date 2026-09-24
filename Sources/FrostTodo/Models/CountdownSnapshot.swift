import Foundation
import SwiftData

/// 倒计时阶段：空闲 / 专注 / 休息
public enum CountdownPhase: String, Codable, CaseIterable {
    case idle
    case work
    case rest
}

/// 倒计时状态快照：支持应用重启后恢复。
/// 剩余时间总是由 targetEndAt - now 推导，不依赖增量计数。
@Model
public final class CountdownSnapshot {
    @Attribute(.unique) public var id: UUID
    public var taskID: UUID?
    public var phase: String
    public var workSeconds: Int
    public var restSeconds: Int
    public var targetEndAt: Date
    public var startedAt: Date?
    public var cyclesCompleted: Int
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        taskID: UUID? = nil,
        phase: String = CountdownPhase.idle.rawValue,
        workSeconds: Int = 0,
        restSeconds: Int = 0,
        targetEndAt: Date = .distantPast,
        startedAt: Date? = nil,
        cyclesCompleted: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.taskID = taskID
        self.phase = phase
        self.workSeconds = workSeconds
        self.restSeconds = restSeconds
        self.targetEndAt = targetEndAt
        self.startedAt = startedAt
        self.cyclesCompleted = cyclesCompleted
        self.updatedAt = updatedAt
    }

    public var phaseValue: CountdownPhase {
        get { CountdownPhase(rawValue: phase) ?? .idle }
        set { phase = newValue.rawValue }
    }
}
