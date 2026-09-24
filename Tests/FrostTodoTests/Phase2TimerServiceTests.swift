import Testing
import Foundation
import SwiftData
@testable import FrostTodo

@MainActor
@Suite("Phase 2: 计时与 Session")
struct Phase2TimerServiceTests {

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeEnvironment() throws -> (PersistenceService, ManualClock) {
        let clock = ManualClock(epoch)
        let persistence = try PersistenceService(inMemory: true)
        return (persistence, clock)
    }

    private func makeTask(_ service: PersistenceService, title: String) throws -> TodoTask {
        let task = TodoTask(title: title)
        service.insert(task)
        try service.save()
        return task
    }

    private func sessionsOf(_ task: TodoTask, in persistence: PersistenceService) throws -> [TimeSession] {
        let id = task.id
        let descriptor = FetchDescriptor<TimeSession>(
            predicate: #Predicate { $0.taskID == id },
            sortBy: [SortDescriptor(\.startAt)]
        )
        return try persistence.fetch(descriptor)
    }

    // MARK: - 开始 / 暂停 / 继续 / 停止

    @Test("开始计时：创建进行中的 Session，快照进入 running")
    func startCreatesRunningSession() throws {
        let (persistence, clock) = try makeEnvironment()
        let service = TimerService(persistence: persistence, clock: clock)
        let task = try makeTask(persistence, title: "写方案")

        let session = try service.start(task: task)
        try persistence.save()

        #expect(service.phase == .running)
        #expect(service.activeTaskID == task.id)
        #expect(session.isRunning)
        #expect(session.taskID == task.id)
        #expect(session.startAt == epoch)
        #expect(service.elapsedSeconds() == 0)

        let sessions = try sessionsOf(task, in: persistence)
        #expect(sessions.count == 1)
    }

    @Test("暂停：结束当前 Session 并计算时长，阶段进入 paused")
    func pauseEndsSession() throws {
        let (persistence, clock) = try makeEnvironment()
        let service = TimerService(persistence: persistence, clock: clock)
        let task = try makeTask(persistence, title: "复习功课")

        try service.start(task: task)
        clock.advance(by: 90)
        let ended = try service.pause()
        try persistence.save()

        #expect(service.phase == .paused)
        #expect(!ended.isRunning)
        #expect(ended.durationSeconds == 90)
        #expect(ended.endAt == epoch.addingTimeInterval(90))
        #expect(service.elapsedSeconds() == 90)
    }

    @Test("继续：创建新的 Session，阶段回到 running")
    func resumeCreatesNewSession() throws {
        let (persistence, clock) = try makeEnvironment()
        let service = TimerService(persistence: persistence, clock: clock)
        let task = try makeTask(persistence, title: "整理笔记")

        try service.start(task: task)
        clock.advance(by: 60)
        try service.pause()
        clock.advance(by: 30)
        let resumed = try service.resume()
        try persistence.save()

        #expect(service.phase == .running)
        #expect(resumed.isRunning)
        #expect(resumed.startAt == epoch.addingTimeInterval(90))
        #expect(service.elapsedSeconds() == 60)
    }

    @Test("停止：清除计时状态，任务保留")
    func stopClearsState() throws {
        let (persistence, clock) = try makeEnvironment()
        let service = TimerService(persistence: persistence, clock: clock)
        let task = try makeTask(persistence, title: "调研框架")

        try service.start(task: task)
        clock.advance(by: 120)
        try service.stop()
        try persistence.save()

        #expect(service.phase == .idle)
        #expect(service.activeTaskID == nil)
        #expect(service.elapsedSeconds() == 0)
        #expect(!task.isCompleted)
    }

    // MARK: - Session 拆分与时长

    @Test("多次暂停产生多个 Session，各段时长正确")
    func multiplePausesCreateMultipleSessions() throws {
        let (persistence, clock) = try makeEnvironment()
        let service = TimerService(persistence: persistence, clock: clock)
        let task = try makeTask(persistence, title: "长时间任务")

        try service.start(task: task)          // t0
        clock.advance(by: 60); try service.pause()   // 段 1: 60s
        clock.advance(by: 40); try service.resume()  // t=100
        clock.advance(by: 45); try service.pause()   // 段 2: 45s
        clock.advance(by: 15); try service.resume()  // t=160
        clock.advance(by: 20); try service.stop()    // 段 3: 20s
        try persistence.save()

        let sessions = try sessionsOf(task, in: persistence)
        #expect(sessions.count == 3)
        #expect(sessions.allSatisfy { !$0.isRunning })
        #expect(sessions[0].durationSeconds == 60)
        #expect(sessions[1].durationSeconds == 45)
        #expect(sessions[2].durationSeconds == 20)
    }

    @Test("累计实际时长为各 Session 之和，暂停期间不计时")
    func accumulatedDurationExcludesPause() throws {
        let (persistence, clock) = try makeEnvironment()
        let service = TimerService(persistence: persistence, clock: clock)
        let task = try makeTask(persistence, title: "净时长")

        try service.start(task: task)                 // t0
        clock.advance(by: 100); try service.pause()   // 100s
        clock.advance(by: 500)                        // 暂停期间不计
        #expect(service.elapsedSeconds() == 100)

        try service.resume()                          // t=600
        clock.advance(by: 50)
        #expect(service.elapsedSeconds() == 150)

        try service.stop()
        #expect(task.totalAccumulatedSeconds == 150)
    }

    @Test("跨天计时：Session 跨越午夜后时长与累计正确")
    func crossMidnightTiming() throws {
        let (persistence, clock) = try makeEnvironment()
        let service = TimerService(persistence: persistence, clock: clock)
        let task = try makeTask(persistence, title: "跨天任务")

        // 从 23:40 开始计时
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 23, minute: 40))!
        clock.now = start
        try service.start(task: task)
        // 推进到次日 00:25，共 45 分钟
        clock.now = start.addingTimeInterval(45 * 60)
        try service.pause()

        let sessions = try sessionsOf(task, in: persistence)
        #expect(sessions.count == 1)
        #expect(sessions[0].durationSeconds == 45 * 60)
        #expect(service.elapsedSeconds() == 45 * 60)
    }

    // MARK: - 并发与状态防护

    @Test("重复开始同一任务：抛出错误且不产生新 Session")
    func startingSameTaskTwiceThrows() throws {
        let (persistence, clock) = try makeEnvironment()
        let service = TimerService(persistence: persistence, clock: clock)
        let task = try makeTask(persistence, title: "防重任务")

        try service.start(task: task)
        #expect(throws: TimerError.alreadyTrackingTask) {
            try service.start(task: task)
        }
        #expect(try sessionsOf(task, in: persistence).count == 1)
        #expect(service.phase == .running)
    }

    @Test("开始另一任务：自动结束当前任务计时并开始新任务")
    func startingAnotherTaskStopsCurrent() throws {
        let (persistence, clock) = try makeEnvironment()
        let service = TimerService(persistence: persistence, clock: clock)
        let taskA = try makeTask(persistence, title: "任务 A")
        let taskB = try makeTask(persistence, title: "任务 B")

        try service.start(task: taskA)
        clock.advance(by: 30)
        try service.start(task: taskB)
        try persistence.save()

        #expect(service.phase == .running)
        #expect(service.activeTaskID == taskB.id)
        #expect(try sessionsOf(taskA, in: persistence).count == 1)
        #expect(try sessionsOf(taskA, in: persistence)[0].durationSeconds == 30)
        #expect(try sessionsOf(taskB, in: persistence).count == 1)
    }

    @Test("对已完成任务开始计时：抛出错误")
    func startingCompletedTaskThrows() throws {
        let (persistence, clock) = try makeEnvironment()
        let service = TimerService(persistence: persistence, clock: clock)
        let task = try makeTask(persistence, title: "已完成任务")
        task.complete(at: clock.now)
        try persistence.save()

        #expect(throws: TimerError.taskAlreadyCompleted) {
            try service.start(task: task)
        }
        #expect(try sessionsOf(task, in: persistence).isEmpty)
    }

    @Test("空闲时暂停、继续、停止、完成均抛出错误")
    func invalidActionsWhenIdle() throws {
        let (persistence, clock) = try makeEnvironment()
        let service = TimerService(persistence: persistence, clock: clock)

        #expect(throws: TimerError.noActiveTimer) { try service.pause() }
        #expect(throws: TimerError.noActiveTimer) { try service.resume() }
        #expect(throws: TimerError.noActiveTimer) { try service.stop() }
        #expect(throws: TimerError.noActiveTimer) { try service.completeActiveTask() }
    }

    @Test("暂停状态下再次暂停抛出错误，继续状态下继续抛出错误")
    func invalidPhaseTransitions() throws {
        let (persistence, clock) = try makeEnvironment()
        let service = TimerService(persistence: persistence, clock: clock)
        let task = try makeTask(persistence, title: "状态机")

        try service.start(task: task)
        try service.pause()
        #expect(throws: TimerError.timerNotRunning) { try service.pause() }
        try service.resume()
        #expect(throws: TimerError.timerNotPaused) { try service.resume() }
    }

    // MARK: - 完成任务

    @Test("完成当前任务：结束 Session、写完成时间、计时器复位")
    func completeActiveTaskEndsSession() throws {
        let (persistence, clock) = try makeEnvironment()
        let service = TimerService(persistence: persistence, clock: clock)
        let task = try makeTask(persistence, title: "待完成")

        try service.start(task: task)
        clock.advance(by: 75)
        let completed = try #require(try service.completeActiveTask())
        try persistence.save()

        #expect(completed.isCompleted)
        #expect(completed.completedAt == epoch.addingTimeInterval(75))
        #expect(service.phase == .idle)
        #expect(task.totalAccumulatedSeconds == 75)
    }

    // MARK: - 重启恢复

    @Test("重启后恢复 running 计时：累计时间延续")
    func restoreRunningAfterRestart() throws {
        let (persistence, clock) = try makeEnvironment()
        let task: TodoTask
        let container: ModelContainer
        do {
            let service = TimerService(persistence: persistence, clock: clock)
            task = try makeTask(persistence, title: "重启恢复")
            try service.start(task: task)
            clock.advance(by: 50)
            try persistence.save()
            container = persistence.container
        }

        // 模拟重启：同一容器的全新服务
        let restarted = try PersistenceService(container: container)
        let service2 = TimerService(persistence: restarted, clock: clock)
        #expect(service2.phase == .running)
        #expect(service2.activeTaskID == task.id)

        clock.advance(by: 30)
        #expect(service2.elapsedSeconds() == 80)

        try service2.pause()
        #expect(service2.elapsedSeconds() == 80)
    }

    @Test("重启后恢复 paused 状态：累计时长不含暂停间隙")
    func restorePausedAfterRestart() throws {
        let (persistence, clock) = try makeEnvironment()
        let task: TodoTask
        let container: ModelContainer
        do {
            let service = TimerService(persistence: persistence, clock: clock)
            task = try makeTask(persistence, title: "暂停重启")
            try service.start(task: task)
            clock.advance(by: 60)
            try service.pause()
            clock.advance(by: 600) // 应用关闭期间不计时
            try persistence.save()
            container = persistence.container
        }

        let service2 = TimerService(persistence: try PersistenceService(container: container), clock: clock)
        #expect(service2.phase == .paused)
        #expect(service2.activeTaskID == task.id)
        #expect(service2.elapsedSeconds() == 60)

        try service2.resume()
        clock.advance(by: 10)
        #expect(service2.elapsedSeconds() == 70)
    }

    @Test("崩溃后脏快照：Session 已结束但快照仍为 running，降级为 paused 不丢时长")
    func restoreAfterCrashWithStaleSnapshot() throws {
        let (persistence, clock) = try makeEnvironment()
        let task = try makeTask(persistence, title: "崩溃恢复")
        let service = TimerService(persistence: persistence, clock: clock)
        try service.start(task: task)
        clock.advance(by: 120)

        // 模拟崩溃后手动结束 Session，快照未更新
        let currentSession = try #require(service.currentSession)
        currentSession.end(at: clock.now)
        try persistence.save()

        let service2 = TimerService(persistence: try PersistenceService(container: persistence.container), clock: clock)
        #expect(service2.phase == .paused)
        #expect(service2.elapsedSeconds() == 120)
    }

    @Test("计时中任务被删除：重启后计时器复位为 idle")
    func restoreAfterActiveTaskDeleted() throws {
        let (persistence, clock) = try makeEnvironment()
        let task = try makeTask(persistence, title: "将被删除")
        let service = TimerService(persistence: persistence, clock: clock)
        try service.start(task: task)
        try persistence.save()

        // 直接删除任务（绕过服务，模拟外部删除）
        persistence.delete(task)
        try persistence.save()

        let service2 = TimerService(persistence: try PersistenceService(container: persistence.container), clock: clock)
        #expect(service2.phase == .idle)
        #expect(service2.activeTaskID == nil)
    }
}
