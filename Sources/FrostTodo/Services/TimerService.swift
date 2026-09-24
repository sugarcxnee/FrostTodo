import Foundation
import SwiftData

/// 计时服务：管理任务计时状态机与 TimeSession 生命周期。
///
/// 状态机：idle -> running -> (paused -> running)* -> idle
/// - start：创建 running Session；若正在计时其他任务则先自动停止
/// - pause：结束当前 Session，保留 activeTaskID
/// - resume：创建新的 running Session
/// - stop / complete：结束 Session 并复位为 idle
///
/// 事务约定：每次操作内的数据变更与历史写入在同一逻辑单元中一次保存；
/// 任一环节失败即回滚。由于 ModelContext.rollback 不保证还原已注册模型的
/// 内存属性，回滚时额外手动恢复快照与 Session 的内存状态。
///
/// 恢复策略：快照记录 activeTaskID、phase、runStartedAt；
/// 累计时长总是从数据推导（runStartedAt 之后该任务全部已结束 Session 之和），
/// 崩溃导致的脏快照（Session 已结束但快照仍为 running）会安全降级为 paused。
@MainActor
public final class TimerService {
    private let persistence: PersistenceService
    private let clock: ClockProviding
    private let history: HistoryRecording

    /// 日历联动等外部观察者（Phase 4 接入）
    public weak var observer: (any TimerObserving)?

    private var snapshot: TimerSnapshot
    public private(set) var currentSession: TimeSession?

    public init(
        persistence: PersistenceService,
        clock: ClockProviding = SystemClock(),
        history: HistoryRecording = NullHistoryRecorder()
    ) {
        self.persistence = persistence
        self.clock = clock
        self.history = history
        self.snapshot = persistence.timerSnapshot()
        restoreIfNeeded()
    }

    // MARK: - 状态

    public var phase: TimerPhase { snapshot.phaseValue }

    public var activeTaskID: UUID? { snapshot.activeTaskID }

    public var isTracking: Bool { snapshot.phaseValue != .idle }

    /// 当前活动任务（按 activeTaskID 查询）
    public var activeTask: TodoTask? {
        guard let id = snapshot.activeTaskID else { return nil }
        return try? fetchTask(id: id)
    }

    /// 当前累计用时：已完成段之和 + 进行中 Session 的实时用时
    public func elapsedSeconds(now: Date? = nil) -> Int {
        let reference = now ?? clock.now
        return accumulatedSeconds + (currentSession?.currentElapsedSeconds(at: reference) ?? 0)
    }

    /// runStartedAt 之后该任务全部已结束 Session 的时长之和
    private var accumulatedSeconds: Int {
        guard let taskID = snapshot.activeTaskID,
              let runStartedAt = snapshot.runStartedAt else { return 0 }
        let descriptor = FetchDescriptor<TimeSession>(
            predicate: #Predicate { $0.taskID == taskID && $0.startAt >= runStartedAt && $0.state == "ended" }
        )
        let sessions = (try? persistence.fetch(descriptor)) ?? []
        return sessions.reduce(0) { $0 + $1.durationSeconds }
    }

    // MARK: - 操作

    /// 开始为一个任务计时。已在计时同一任务时抛出 alreadyTrackingTask。
    @discardableResult
    public func start(task: TodoTask) throws -> TimeSession {
        if snapshot.activeTaskID == task.id, snapshot.phaseValue != .idle {
            throw TimerError.alreadyTrackingTask
        }
        guard !task.isCompleted else {
            throw TimerError.taskAlreadyCompleted
        }
        // 正在计时其他任务：先自动停止（独立事务）
        if snapshot.phaseValue != .idle {
            try stopInternal(emitHistory: true)
        }

        let now = clock.now
        let priorSnapshot = snapshot.captureState()
        let session = TimeSession(taskID: task.id, startAt: now)
        session.task = task
        persistence.insert(session)

        snapshot.activeTaskID = task.id
        snapshot.currentSessionID = session.id
        snapshot.phaseValue = .running
        snapshot.runStartedAt = now
        snapshot.updatedAt = now

        do {
            try history.record(HistoryEventInput(
                type: .timerStarted, taskID: task.id, sessionID: session.id,
                title: "开始计时：\(task.title)", source: .user
            ))
            try history.record(HistoryEventInput(
                type: .sessionStarted, taskID: task.id, sessionID: session.id,
                title: "时间段开始", source: .system
            ))
            try persistence.save()
        } catch {
            persistence.rollback()
            snapshot.restore(priorSnapshot)
            currentSession = nil
            throw error
        }
        currentSession = session
        observer?.timerDidStartSession(session, task: task)
        return session
    }

    /// 暂停：结束当前 Session
    @discardableResult
    public func pause() throws -> TimeSession {
        guard snapshot.phaseValue != .idle else { throw TimerError.noActiveTimer }
        guard snapshot.phaseValue == .running else { throw TimerError.timerNotRunning }
        guard let session = currentSession else { throw TimerError.noActiveTimer }

        let now = clock.now
        let priorSnapshot = snapshot.captureState()
        let priorSession = session.captureState()
        let duration = session.end(at: now)
        snapshot.phaseValue = .paused
        snapshot.currentSessionID = nil
        snapshot.updatedAt = now

        do {
            try history.record(HistoryEventInput(
                type: .sessionEnded, taskID: session.taskID, sessionID: session.id,
                title: "时间段结束", detail: "时长 \(duration) 秒", source: .system
            ))
            try history.record(HistoryEventInput(
                type: .timerPaused, taskID: session.taskID, sessionID: session.id,
                title: "暂停计时", detail: "时长 \(duration) 秒", source: .user
            ))
            try persistence.save()
        } catch {
            persistence.rollback()
            snapshot.restore(priorSnapshot)
            session.restore(priorSession)
            throw error
        }
        currentSession = nil
        snapshot.accumulatedSeconds = accumulatedSeconds
        if let task = try fetchTask(id: session.taskID) {
            observer?.timerDidEndSession(session, task: task)
        }
        return session
    }

    /// 继续：创建新的 Session
    @discardableResult
    public func resume() throws -> TimeSession {
        guard snapshot.phaseValue != .idle else { throw TimerError.noActiveTimer }
        guard snapshot.phaseValue == .paused else { throw TimerError.timerNotPaused }

        guard let taskID = snapshot.activeTaskID,
              let task = try fetchTask(id: taskID) else {
            resetToIdle()
            try? persistence.save()
            throw TimerError.noActiveTimer
        }

        let now = clock.now
        let priorSnapshot = snapshot.captureState()
        let session = TimeSession(taskID: taskID, startAt: now)
        session.task = task
        persistence.insert(session)

        snapshot.currentSessionID = session.id
        snapshot.phaseValue = .running
        snapshot.updatedAt = now

        do {
            try history.record(HistoryEventInput(
                type: .timerResumed, taskID: taskID, sessionID: session.id,
                title: "继续计时", source: .user
            ))
            try history.record(HistoryEventInput(
                type: .sessionStarted, taskID: taskID, sessionID: session.id,
                title: "时间段开始", source: .system
            ))
            try persistence.save()
        } catch {
            persistence.rollback()
            snapshot.restore(priorSnapshot)
            currentSession = nil
            throw error
        }
        currentSession = session
        observer?.timerDidStartSession(session, task: task)
        return session
    }

    /// 停止当前计时（任务保持未完成状态）
    public func stop() throws {
        guard snapshot.phaseValue != .idle else { throw TimerError.noActiveTimer }
        try stopInternal(emitHistory: true)
    }

    /// 完成当前计时中的任务：结束 Session、标记完成、复位
    @discardableResult
    public func completeActiveTask() throws -> TodoTask? {
        guard snapshot.phaseValue != .idle else { throw TimerError.noActiveTimer }
        guard let taskID = snapshot.activeTaskID,
              let task = try fetchTask(id: taskID) else {
            resetToIdle()
            try? persistence.save()
            throw TimerError.noActiveTimer
        }

        let now = clock.now
        let priorSnapshot = snapshot.captureState()
        var endedSession: TimeSession?
        var priorSessionState: SessionStateCapture?
        if snapshot.phaseValue == .running, let session = currentSession {
            let prior = session.captureState()
            priorSessionState = prior
            let duration = session.end(at: now)
            endedSession = session
            do {
                try history.record(HistoryEventInput(
                    type: .sessionEnded, taskID: taskID, sessionID: session.id,
                    title: "时间段结束", detail: "时长 \(duration) 秒", source: .system
                ))
            } catch {
                persistence.rollback()
                snapshot.restore(priorSnapshot)
                session.restore(prior)
                throw error
            }
        }
        let priorTaskState = task.captureState()
        task.complete(at: now)
        snapshot.activeTaskID = nil
        snapshot.currentSessionID = nil
        snapshot.phaseValue = .idle
        snapshot.runStartedAt = nil
        snapshot.accumulatedSeconds = 0
        snapshot.updatedAt = now

        do {
            try history.record(HistoryEventInput(
                type: .timerStopped, taskID: taskID,
                title: "停止计时", source: .user
            ))
            try history.record(HistoryEventInput(
                type: .taskCompleted, taskID: taskID,
                title: "完成任务：\(task.title)",
                payload: ["completedAt": String(now.timeIntervalSince1970)], source: .user
            ))
            try persistence.save()
        } catch {
            persistence.rollback()
            snapshot.restore(priorSnapshot)
            task.restore(priorTaskState)
            if let endedSession, let priorSessionState {
                endedSession.restore(priorSessionState)
            }
            throw error
        }
        currentSession = nil
        if let endedSession {
            observer?.timerDidEndSession(endedSession, task: task)
        }
        observer?.timerDidCompleteTask(task)
        return task
    }

    // MARK: - 私有

    /// 停止并复位到 idle
    private func stopInternal(emitHistory: Bool) throws {
        let now = clock.now
        let priorSnapshot = snapshot.captureState()
        var endedSession: TimeSession?
        var priorSessionState: SessionStateCapture?
        if snapshot.phaseValue == .running, let session = currentSession {
            let prior = session.captureState()
            priorSessionState = prior
            let duration = session.end(at: now)
            endedSession = session
            do {
                try history.record(HistoryEventInput(
                    type: .sessionEnded, taskID: session.taskID, sessionID: session.id,
                    title: "时间段结束", detail: "时长 \(duration) 秒", source: .system
                ))
            } catch {
                persistence.rollback()
                snapshot.restore(priorSnapshot)
                session.restore(prior)
                throw error
            }
        }

        let taskID = snapshot.activeTaskID
        snapshot.activeTaskID = nil
        snapshot.currentSessionID = nil
        snapshot.phaseValue = .idle
        snapshot.runStartedAt = nil
        snapshot.accumulatedSeconds = 0
        snapshot.updatedAt = now

        do {
            if emitHistory, let taskID {
                try history.record(HistoryEventInput(
                    type: .timerStopped, taskID: taskID,
                    title: "停止计时", source: .user
                ))
            }
            try persistence.save()
        } catch {
            persistence.rollback()
            snapshot.restore(priorSnapshot)
            if let endedSession, let priorSessionState {
                endedSession.restore(priorSessionState)
            }
            throw error
        }
        currentSession = nil
        if let endedSession, let taskID, let task = try fetchTask(id: taskID) {
            observer?.timerDidEndSession(endedSession, task: task)
        }
    }

    private func resetToIdle() {
        snapshot.activeTaskID = nil
        snapshot.currentSessionID = nil
        snapshot.phaseValue = .idle
        snapshot.runStartedAt = nil
        snapshot.accumulatedSeconds = 0
        snapshot.updatedAt = clock.now
        currentSession = nil
    }

    private func fetchTask(id: UUID) throws -> TodoTask? {
        let descriptor = FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == id })
        return try persistence.fetch(descriptor).first
    }

    /// 应用启动 / 服务初始化时恢复计时状态
    private func restoreIfNeeded() {
        guard snapshot.phaseValue != .idle else { return }

        // 活动任务已被删除：复位
        guard let taskID = snapshot.activeTaskID,
              (try? fetchTask(id: taskID)) != nil else {
            resetToIdle()
            try? persistence.save()
            return
        }

        if snapshot.phaseValue == .running {
            let session = restoreRunningSession(taskID: taskID)
            if let session {
                currentSession = session
            } else {
                // 崩溃残留的脏快照：Session 已结束但快照仍为 running，降级为 paused
                snapshot.phaseValue = .paused
                snapshot.currentSessionID = nil
            }
        } else {
            currentSession = nil
            snapshot.currentSessionID = nil
        }
        snapshot.accumulatedSeconds = accumulatedSeconds
        snapshot.updatedAt = clock.now
        try? persistence.save()
    }

    /// 找回 runStartedAt 之后该任务仍在进行的 Session
    private func restoreRunningSession(taskID: UUID) -> TimeSession? {
        let runStartedAt = snapshot.runStartedAt ?? .distantPast
        let descriptor = FetchDescriptor<TimeSession>(
            predicate: #Predicate {
                $0.taskID == taskID && $0.startAt >= runStartedAt && $0.state == "running"
            },
            sortBy: [SortDescriptor(\.startAt, order: .reverse)]
        )
        let session = (try? persistence.fetch(descriptor))?.first
        if let session {
            snapshot.currentSessionID = session.id
        }
        return session
    }
}

// MARK: - 回滚用状态捕获

/// 快照内存状态捕获（rollback 不还原模型内存属性，需手动恢复）
struct SnapshotStateCapture {
    let activeTaskID: UUID?
    let currentSessionID: UUID?
    let phase: String
    let runStartedAt: Date?
    let accumulatedSeconds: Int
    let updatedAt: Date
}

/// Session 内存状态捕获
struct SessionStateCapture {
    let state: String
    let endAt: Date?
    let durationSeconds: Int
}

/// 任务内存状态捕获
struct TaskStateCapture {
    let status: String
    let completedAt: Date?
}

extension TimerSnapshot {
    /// 本轮计时开始时间（用于从数据推导累计时长）
    public var runStartedAt: Date? {
        get { startedAt }
        set { startedAt = newValue }
    }

    func captureState() -> SnapshotStateCapture {
        SnapshotStateCapture(
            activeTaskID: activeTaskID,
            currentSessionID: currentSessionID,
            phase: phase,
            runStartedAt: runStartedAt,
            accumulatedSeconds: accumulatedSeconds,
            updatedAt: updatedAt
        )
    }

    func restore(_ capture: SnapshotStateCapture) {
        activeTaskID = capture.activeTaskID
        currentSessionID = capture.currentSessionID
        phase = capture.phase
        runStartedAt = capture.runStartedAt
        accumulatedSeconds = capture.accumulatedSeconds
        updatedAt = capture.updatedAt
    }
}

extension TimeSession {
    func captureState() -> SessionStateCapture {
        SessionStateCapture(state: state, endAt: endAt, durationSeconds: durationSeconds)
    }

    func restore(_ capture: SessionStateCapture) {
        state = capture.state
        endAt = capture.endAt
        durationSeconds = capture.durationSeconds
    }
}

extension TodoTask {
    func captureState() -> TaskStateCapture {
        TaskStateCapture(status: status, completedAt: completedAt)
    }

    func restore(_ capture: TaskStateCapture) {
        status = capture.status
        completedAt = capture.completedAt
    }
}
