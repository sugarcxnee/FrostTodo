import Foundation
import SwiftData

/// 倒计时错误
public enum CountdownError: Error, Equatable {
    case alreadyRunning
    case notRunning
}

/// 倒计时服务：类番茄钟的阶段状态机，通过驱动 TimerService 复用
/// 全部计时、历史与日历记录机制。
///
/// 阶段映射：
/// - 专注（work）：任务计时 running，倒计时递减
/// - 专注到点：计时暂停（Session 结束，日历更新为计时记录），进入休息
/// - 休息到点：计时恢复（新 Session，日历新建计时中事件），回到专注
/// - 休息为 0：纯倒计时，专注到点即自然结束（计时停止，日历更新）
/// - 手动结束：随时可结束（计时停止，日历更新，剩余时间记录到历史）
///
/// 恢复策略：剩余时间由 targetEndAt 推导；应用关闭期间到期时恢复阶段
/// 仅单步追赶（进入下一阶段并以当前时间重新起算），不回补多个周期。
@MainActor
public final class CountdownService: ObservableObject {
    private let persistence: PersistenceService
    private let timer: TimerService
    private let history: HistoryRecording
    private let clock: ClockProviding
    private var snapshot: CountdownSnapshot

    public init(
        persistence: PersistenceService,
        timer: TimerService,
        history: HistoryRecording,
        clock: ClockProviding = SystemClock()
    ) {
        self.persistence = persistence
        self.timer = timer
        self.history = history
        self.clock = clock
        self.snapshot = persistence.countdownSnapshot()
        restoreIfNeeded()
    }

    // MARK: - 状态

    public var phase: CountdownPhase { snapshot.phaseValue }

    public var isActive: Bool { snapshot.phaseValue != .idle }

    public var cyclesCompleted: Int { snapshot.cyclesCompleted }

    public var workSeconds: Int { snapshot.workSeconds }

    public var restSeconds: Int { snapshot.restSeconds }

    /// 本次倒计时总轮数
    public var totalRounds: Int { snapshot.totalRounds }

    /// 是否为纯倒计时（休息为 0）
    public var isPureCountdown: Bool { snapshot.restSeconds == 0 }

    public var activeTaskID: UUID? { snapshot.taskID }

    /// 当前阶段剩余秒数
    public func remainingSeconds(now: Date? = nil) -> Int {
        guard isActive else { return 0 }
        let reference = now ?? clock.now
        return max(0, Int(snapshot.targetEndAt.timeIntervalSince(reference)))
    }

    /// 剩余的专注总时长：当前段剩余 + 之后各整段专注（不含休息）
    public func remainingTotalWorkSeconds(now: Date? = nil) -> Int {
        guard isActive else { return 0 }
        let current = remainingSeconds(now: now)
        let futureRounds: Int
        if snapshot.phaseValue == .work {
            futureRounds = max(0, snapshot.totalRounds - snapshot.cyclesCompleted - 1)
        } else {
            futureRounds = max(0, snapshot.totalRounds - snapshot.cyclesCompleted)
        }
        return current + futureRounds * snapshot.workSeconds
    }

    // MARK: - 操作

    /// 解析任务的生效配置：任务自定义优先，未设置项各自回落设置默认
    public static func effectiveConfiguration(
        for task: TodoTask,
        settings: AppSettings
    ) -> (workMinutes: Int, restMinutes: Int, rounds: Int) {
        let work = task.countdownWorkMinutes ?? settings.countdownWorkMinutes
        let rest = task.countdownRestMinutes ?? settings.countdownRestMinutes
        let rounds = task.countdownRounds ?? settings.countdownRounds
        return (max(1, work), max(0, rest), max(1, rounds))
    }

    /// 启动倒计时（rounds 为专注段个数，至少 1）。
    /// 若该任务已在正计时中则复用当前 Session。
    public func start(task: TodoTask, workMinutes: Int, restMinutes: Int, rounds: Int = 1) throws {
        guard !isActive else { throw CountdownError.alreadyRunning }
        if !(timer.activeTaskID == task.id && timer.phase == .running) {
            try timer.start(task: task)
        }

        let now = clock.now
        let prior = snapshot.captureState()
        snapshot.taskID = task.id
        snapshot.phaseValue = .work
        snapshot.workSeconds = workMinutes * 60
        snapshot.restSeconds = max(0, restMinutes) * 60
        snapshot.totalRounds = max(1, rounds)
        snapshot.targetEndAt = now.addingTimeInterval(TimeInterval(workMinutes * 60))
        snapshot.startedAt = now
        snapshot.cyclesCompleted = 0
        snapshot.updatedAt = now

        do {
            try history.record(HistoryEventInput(
                type: .countdownStarted, taskID: task.id,
                title: "开始倒计时：\(task.title)",
                payload: [
                    "workMinutes": "\(workMinutes)",
                    "restMinutes": "\(restMinutes)",
                    "rounds": "\(max(1, rounds))",
                ],
                source: .user
            ))
            try persistence.save()
        } catch {
            persistence.rollback()
            snapshot.restore(prior)
            throw error
        }
    }

    /// 手动结束倒计时（随时可调用）
    public func end() throws {
        try end(reason: "manual")
    }

    /// 推进阶段：由 UI 每秒驱动；到期则转换阶段或自然结束。幂等。
    public func advanceIfNeeded() throws {
        guard isActive else { return }
        while remainingSeconds() == 0 {
            let prior = snapshot.captureState()
            switch snapshot.phaseValue {
            case .work:
                snapshot.cyclesCompleted += 1
                do {
                    try history.record(HistoryEventInput(
                        type: .countdownPhaseCompleted, taskID: snapshot.taskID,
                        title: "倒计时专注完成",
                        detail: "第 \(snapshot.cyclesCompleted) 轮专注 \(snapshot.workSeconds / 60) 分钟",
                        payload: ["phase": "work", "cycle": "\(snapshot.cyclesCompleted)"],
                        source: .system
                    ))
                } catch {
                    persistence.rollback()
                    snapshot.restore(prior)
                    throw error
                }
                if snapshot.cyclesCompleted >= snapshot.totalRounds {
                    // 最后一轮专注完成：自然结束（不再进入休息）
                    try end(reason: "natural")
                    return
                }
                if snapshot.restSeconds > 0 {
                    if timer.phase == .running {
                        try timer.pause()
                    }
                    snapshot.phaseValue = .rest
                    snapshot.targetEndAt = clock.now.addingTimeInterval(TimeInterval(snapshot.restSeconds))
                    snapshot.updatedAt = clock.now
                    try persistence.save()
                } else {
                    // 纯倒计时：直接进入下一轮专注，不切段
                    snapshot.phaseValue = .work
                    snapshot.targetEndAt = clock.now.addingTimeInterval(TimeInterval(snapshot.workSeconds))
                    snapshot.updatedAt = clock.now
                    try persistence.save()
                }
            case .rest:
                do {
                    try history.record(HistoryEventInput(
                        type: .countdownPhaseCompleted, taskID: snapshot.taskID,
                        title: "倒计时休息结束",
                        detail: "休息 \(snapshot.restSeconds / 60) 分钟",
                        payload: ["phase": "rest"],
                        source: .system
                    ))
                } catch {
                    persistence.rollback()
                    snapshot.restore(prior)
                    throw error
                }
                if timer.phase == .paused {
                    try timer.resume()
                }
                snapshot.phaseValue = .work
                snapshot.targetEndAt = clock.now.addingTimeInterval(TimeInterval(snapshot.workSeconds))
                snapshot.updatedAt = clock.now
                try persistence.save()
            case .idle:
                return
            }
        }
    }

    // MARK: - 私有

    private func end(reason: String) throws {
        guard isActive else { throw CountdownError.notRunning }
        let remaining = remainingSeconds()
        let taskID = snapshot.taskID
        let cycles = snapshot.cyclesCompleted
        let prior = snapshot.captureState()

        if timer.isTracking {
            try timer.stop()
        }
        snapshot.phaseValue = .idle
        snapshot.targetEndAt = .distantPast
        snapshot.startedAt = nil
        snapshot.updatedAt = clock.now

        do {
            try history.record(HistoryEventInput(
                type: .countdownEnded, taskID: taskID,
                title: "结束倒计时",
                detail: reason == "manual" ? "手动结束，剩余 \(remaining) 秒" : "倒计时自然结束",
                payload: [
                    "reason": reason,
                    "remainingSeconds": "\(remaining)",
                    "cyclesCompleted": "\(cycles)",
                    "totalRounds": "\(snapshot.totalRounds)",
                ],
                source: .user
            ))
            try persistence.save()
        } catch {
            persistence.rollback()
            snapshot.restore(prior)
            throw error
        }
    }

    /// 应用启动时恢复：关闭期间到期则单步追赶
    private func restoreIfNeeded() {
        guard isActive else { return }
        if remainingSeconds() == 0 {
            try? advanceIfNeeded()
        }
    }
}

// MARK: - 回滚用状态捕获

struct CountdownStateCapture {
    let taskID: UUID?
    let phase: String
    let workSeconds: Int
    let restSeconds: Int
    let targetEndAt: Date
    let startedAt: Date?
    let cyclesCompleted: Int
    let totalRounds: Int
    let updatedAt: Date
}

extension CountdownSnapshot {
    func captureState() -> CountdownStateCapture {
        CountdownStateCapture(
            taskID: taskID,
            phase: phase,
            workSeconds: workSeconds,
            restSeconds: restSeconds,
            targetEndAt: targetEndAt,
            startedAt: startedAt,
            cyclesCompleted: cyclesCompleted,
            totalRounds: totalRounds,
            updatedAt: updatedAt
        )
    }

    func restore(_ capture: CountdownStateCapture) {
        taskID = capture.taskID
        phase = capture.phase
        workSeconds = capture.workSeconds
        restSeconds = capture.restSeconds
        targetEndAt = capture.targetEndAt
        startedAt = capture.startedAt
        cyclesCompleted = capture.cyclesCompleted
        totalRounds = capture.totalRounds
        updatedAt = capture.updatedAt
    }
}
