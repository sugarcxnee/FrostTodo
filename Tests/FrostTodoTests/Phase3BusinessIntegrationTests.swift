import Testing
import Foundation
import SwiftData
@testable import FrostTodo

@MainActor
@Suite("Phase 3: 业务联动历史写入")
struct Phase3BusinessIntegrationTests {

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeEnvironment() throws -> Environment {
        let clock = ManualClock(epoch)
        let persistence = try PersistenceService(inMemory: true)
        let history = HistoryService(persistence: persistence, clock: clock)
        let tasks = TaskService(persistence: persistence, history: history, clock: clock)
        let timer = TimerService(persistence: persistence, clock: clock, history: history)
        let settings = SettingsService(persistence: persistence, history: history, clock: clock)
        let notifications = NotificationService(
            center: MockNotificationCenter(),
            history: history,
            persistence: persistence,
            clock: clock
        )
        tasks.timerService = timer
        return Environment(
            clock: clock, persistence: persistence, history: history,
            tasks: tasks, timer: timer, settings: settings, notifications: notifications
        )
    }

    private struct Environment {
        let clock: ManualClock
        let persistence: PersistenceService
        let history: HistoryService
        let tasks: TaskService
        let timer: TimerService
        let settings: SettingsService
        let notifications: NotificationService
    }

    private func types(_ history: HistoryService, taskID: UUID? = nil) throws -> [HistoryEventType] {
        try history.events(matching: HistoryFilter(taskID: taskID, ascending: true)).compactMap(\.typeValue)
    }

    // MARK: - 任务联动

    @Test("创建任务产生 task.created 历史")
    func createTaskWritesHistory() throws {
        let env = try makeEnvironment()
        let task = try env.tasks.create(title: "新任务", tags: ["工作"], projectName: "项目一")

        let events = try env.history.events(matching: HistoryFilter(taskID: task.id))
        #expect(events.count == 1)
        let event = try #require(events.first)
        #expect(event.typeValue == .taskCreated)
        #expect(event.title == "创建任务：新任务")
        #expect(event.payload["tags"] == "工作")
        #expect(event.payload["project"] == "项目一")
    }

    @Test("编辑任务产生 task.updated 历史且 detail 包含变更字段")
    func updateTaskWritesChangedFields() throws {
        let env = try makeEnvironment()
        let task = try env.tasks.create(title: "原标题")

        env.clock.advance(by: 10)
        try env.tasks.update(task) { $0.title = "新标题"; $0.projectName = "新项目" }

        let events = try env.history.events(matching: HistoryFilter(types: [.taskUpdated], taskID: task.id))
        #expect(events.count == 1)
        let event = try #require(events.first)
        #expect(event.detail?.contains("标题") == true)
        #expect(event.detail?.contains("项目") == true)
        #expect(event.payload["标题"] == "原标题 -> 新标题")
    }

    @Test("完成任务产生 task.completed 历史并写入完成时间")
    func completeTaskWritesHistory() throws {
        let env = try makeEnvironment()
        let task = try env.tasks.create(title: "待完成")
        env.clock.advance(by: 100)

        try env.tasks.complete(task)

        let event = try #require(
            env.history.events(matching: HistoryFilter(types: [.taskCompleted], taskID: task.id)).first
        )
        #expect(event.payload["completedAt"] == String(epoch.addingTimeInterval(100).timeIntervalSince1970))
        #expect(task.completedAt == epoch.addingTimeInterval(100))
    }

    @Test("取消完成产生 task.uncompleted 历史")
    func uncompleteTaskWritesHistory() throws {
        let env = try makeEnvironment()
        let task = try env.tasks.create(title: "再完成一次")
        try env.tasks.complete(task)
        try env.tasks.uncomplete(task)

        let types = try types(env.history, taskID: task.id)
        #expect(types.contains(.taskUncompleted))
        #expect(task.completedAt == nil)
    }

    @Test("删除任务产生 task.deleted 历史且历史仍可按 taskID 查询")
    func deleteTaskKeepsQueryableHistory() throws {
        let env = try makeEnvironment()
        let task = try env.tasks.create(title: "将被删除")
        try env.tasks.complete(task)

        try env.tasks.delete(task)

        let types = try types(env.history, taskID: task.id)
        #expect(types.contains(.taskCreated))
        #expect(types.contains(.taskCompleted))
        #expect(types.contains(.taskDeleted))
        let remaining = try env.persistence.fetch(FetchDescriptor<TodoTask>())
        #expect(remaining.isEmpty)
    }

    // MARK: - 计时联动

    @Test("计时全流程历史：started/paused/resumed/stopped 与 session 对应")
    func timerLifecycleWritesHistory() throws {
        let env = try makeEnvironment()
        let task = try env.tasks.create(title: "计时任务")

        try env.timer.start(task: task)
        env.clock.advance(by: 60)
        try env.timer.pause()
        env.clock.advance(by: 10)
        try env.timer.resume()
        env.clock.advance(by: 30)
        try env.timer.stop()

        let types = try types(env.history, taskID: task.id)
        #expect(types.filter { $0 == .timerStarted }.count == 1)
        #expect(types.filter { $0 == .sessionStarted }.count == 2)
        #expect(types.filter { $0 == .timerPaused }.count == 1)
        #expect(types.filter { $0 == .sessionEnded }.count == 2)
        #expect(types.filter { $0 == .timerResumed }.count == 1)
        #expect(types.filter { $0 == .timerStopped }.count == 1)
    }

    @Test("计时中完成任务：task.completed 与 timer.stopped、session.ended 同时产生")
    func completeWhileTimingWritesAll() throws {
        let env = try makeEnvironment()
        let task = try env.tasks.create(title: "计时完成")

        try env.timer.start(task: task)
        env.clock.advance(by: 45)
        _ = try env.timer.completeActiveTask()

        let types = try types(env.history, taskID: task.id)
        #expect(types.contains(.sessionEnded))
        #expect(types.contains(.timerStopped))
        #expect(types.contains(.taskCompleted))
    }

    @Test("手动完成计时中的任务：计时器自动停止并留下历史")
    func manuallyCompleteTrackedTaskStopsTimer() throws {
        let env = try makeEnvironment()
        let task = try env.tasks.create(title: "手动完成")

        try env.timer.start(task: task)
        env.clock.advance(by: 20)
        try env.tasks.complete(task)

        #expect(env.timer.phase == .idle)
        let types = try types(env.history, taskID: task.id)
        #expect(types.contains(.taskCompleted))
        #expect(types.contains(.timerStopped))
        #expect(task.totalAccumulatedSeconds == 20)
    }

    // MARK: - 设置与通知联动

    @Test("设置变更产生 settings.changed 历史")
    func settingsChangeWritesHistory() throws {
        let env = try makeEnvironment()
        try env.settings.update { $0.writeToCalendar = false; $0.defaultEstimatedMinutes = 45 }

        let events = try env.history.events(matching: HistoryFilter(types: [.settingsChanged]))
        #expect(events.count == 1)
        let event = try #require(events.first)
        #expect(event.detail?.contains("写入日历") == true)
        #expect(event.detail?.contains("默认预计时长") == true)
        #expect(env.persistence.settings().writeToCalendar == false)
        #expect(env.persistence.settings().defaultEstimatedMinutes == 45)
    }

    @Test("通知发送产生 notification.sent 历史且内容无 emoji")
    func notificationSentWritesHistory() async throws {
        let env = try makeEnvironment()
        try await env.notifications.schedule(NotificationRequest(
            identifier: "due-1", title: "任务即将到期", body: "请及时处理", triggerAfter: 300
        ))

        let event = try #require(
            env.history.events(matching: HistoryFilter(types: [.notificationSent])).first
        )
        #expect(event.title == "通知已发送：任务即将到期")
        #expect(event.payload["identifier"] == "due-1")
        let mock = try #require(env.notifications.center as? MockNotificationCenter)
        #expect(mock.captured.count == 1)
        #expect(mock.captured.first?.title == "任务即将到期")
    }

    // MARK: - 数据一致性

    @Test("历史写入失败：业务操作回滚，无 Session 无历史")
    func historyFailureRollsBackBusinessOp() throws {
        let clock = ManualClock(epoch)
        let persistence = try PersistenceService(inMemory: true)
        let realHistory = HistoryService(persistence: persistence, clock: clock)
        let failing = SelectiveFailureRecorder(wrapped: realHistory, failOn: .timerStarted)
        let timer = TimerService(persistence: persistence, clock: clock, history: failing)
        let task = TodoTask(title: "回滚验证")
        persistence.insert(task)
        try persistence.save()

        #expect(throws: HistoryWriteError.writeFailed) {
            try timer.start(task: task)
        }

        // 回滚后：没有 Session、快照复位、没有任何历史
        let sessions = try persistence.fetch(FetchDescriptor<TimeSession>())
        #expect(sessions.isEmpty)
        #expect(timer.phase == .idle)
        #expect(try realHistory.events(matching: HistoryFilter()).isEmpty)
    }
}

/// 选择性失败的历史记录器：命中指定类型时抛错
final class SelectiveFailureRecorder: HistoryRecording {
    let wrapped: HistoryRecording
    let failOn: HistoryEventType

    init(wrapped: HistoryRecording, failOn: HistoryEventType) {
        self.wrapped = wrapped
        self.failOn = failOn
    }

    func record(_ input: HistoryEventInput) throws {
        if input.type == failOn {
            throw HistoryWriteError.writeFailed
        }
        try wrapped.record(input)
    }
}

// MARK: - 自动保存契约

@MainActor
@Suite("自动保存契约：无变更不写历史")
struct AutosaveContractTests {

    @Test("update 应用相同值时不产生 task.updated 历史")
    func updateWithNoEffectiveChangeWritesNoHistory() throws {
        let clock = ManualClock(Date(timeIntervalSince1970: 1_700_000_000))
        let persistence = try PersistenceService(inMemory: true)
        let history = HistoryService(persistence: persistence, clock: clock)
        let tasks = TaskService(persistence: persistence, history: history, clock: clock)
        let task = try tasks.create(title: "自动保存任务")

        // 自动保存可能多次触发；值未变化时不得产生编辑历史
        try tasks.update(task) { $0.title = "自动保存任务" }
        try tasks.update(task) { $0.title = "自动保存任务" }

        let updated = try history.events(matching: HistoryFilter(types: [.taskUpdated], taskID: task.id))
        #expect(updated.isEmpty)
    }
}
