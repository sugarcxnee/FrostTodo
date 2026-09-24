import Foundation
import SwiftData

/// 计时器阶段：空闲 / 计时中 / 已暂停
public enum TimerPhase: String, Codable, CaseIterable {
    case idle
    case running
    case paused
}

/// 计时器状态快照：用于应用重启或崩溃后恢复计时状态。
/// accumulatedSeconds 不包含当前进行中 Session 的时长。
@Model
public final class TimerSnapshot {
    @Attribute(.unique) public var id: UUID
    public var activeTaskID: UUID?
    public var currentSessionID: UUID?
    public var phase: String
    public var accumulatedSeconds: Int
    public var startedAt: Date?
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        activeTaskID: UUID? = nil,
        currentSessionID: UUID? = nil,
        phase: String = TimerPhase.idle.rawValue,
        accumulatedSeconds: Int = 0,
        startedAt: Date? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.activeTaskID = activeTaskID
        self.currentSessionID = currentSessionID
        self.phase = phase
        self.accumulatedSeconds = accumulatedSeconds
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }

    public var phaseValue: TimerPhase {
        get { TimerPhase(rawValue: phase) ?? .idle }
        set { phase = newValue.rawValue }
    }
}
