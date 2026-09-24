import Testing
import Foundation
@testable import FrostTodo

// MARK: - 通知调度参数

@MainActor
@Suite("Phase 6: 通知调度参数")
struct Phase6NotificationTests {

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeEnvironment() throws -> (NotificationService, MockNotificationCenter, ManualClock, PersistenceService) {
        let clock = ManualClock(epoch)
        let persistence = try PersistenceService(inMemory: true)
        let history = HistoryService(persistence: persistence, clock: clock)
        let center = MockNotificationCenter()
        let service = NotificationService(center: center, history: history, persistence: persistence, clock: clock)
        return (service, center, clock, persistence)
    }

    @Test("截止提醒：identifier、标题与触发延迟正确")
    func dueReminderSchedulingParameters() async throws {
        let (service, center, clock, persistence) = try makeEnvironment()
        let history = HistoryService(persistence: persistence, clock: clock)
        let tasks = TaskService(persistence: persistence, history: history, clock: clock)
        let task = try tasks.create(title: "带截止的任务", dueDate: clock.now.addingTimeInterval(600))

        try await service.scheduleDueReminder(for: task)

        let captured = try #require(center.captured.first)
        #expect(captured.identifier == "due-\(task.id.uuidString)")
        #expect(captured.title == "任务即将到期")
        #expect(captured.body.contains("带截止的任务"))
        #expect(captured.triggerAfter == 600)
        // 通知发送历史
        let events = try history.events(matching: HistoryFilter(types: [.notificationSent]))
        #expect(events.count == 1)
    }

    @Test("截止时间已过：不调度")
    func pastDueNotScheduled() async throws {
        let (service, center, clock, persistence) = try makeEnvironment()
        let history = HistoryService(persistence: persistence, clock: clock)
        let tasks = TaskService(persistence: persistence, history: history, clock: clock)
        let task = try tasks.create(title: "已过期", dueDate: clock.now.addingTimeInterval(-60))

        try await service.scheduleDueReminder(for: task)
        #expect(center.captured.isEmpty)
    }

    @Test("无截止日期：不调度")
    func noDueDateNotScheduled() async throws {
        let (service, center, _, persistence) = try makeEnvironment()
        let clock = ManualClock(epoch)
        let history = HistoryService(persistence: persistence, clock: clock)
        let tasks = TaskService(persistence: persistence, history: history, clock: clock)
        let task = try tasks.create(title: "无截止")

        try await service.scheduleDueReminder(for: task)
        #expect(center.captured.isEmpty)
    }

    @Test("预计时长提醒：延迟为预计减去已计时")
    func estimatedReminderParameters() async throws {
        let (service, center, clock, persistence) = try makeEnvironment()
        let history = HistoryService(persistence: persistence, clock: clock)
        let tasks = TaskService(persistence: persistence, history: history, clock: clock)
        let task = try tasks.create(title: "预计 30 分钟", estimatedMinutes: 30)
        let session = TimeSession(taskID: task.id, startAt: clock.now.addingTimeInterval(-600))

        try await service.scheduleEstimatedReachedReminder(for: session, task: task, elapsedSeconds: 600)

        let captured = try #require(center.captured.first)
        #expect(captured.identifier == "estimated-\(session.id.uuidString)")
        #expect(captured.title == "计时达到预计时长")
        #expect(captured.triggerAfter == TimeInterval(30 * 60 - 600))
    }

    @Test("无预计时长或已超时：不调度")
    func estimatedReminderSkips() async throws {
        let (service, center, clock, persistence) = try makeEnvironment()
        let history = HistoryService(persistence: persistence, clock: clock)
        let tasks = TaskService(persistence: persistence, history: history, clock: clock)

        let noEstimate = try tasks.create(title: "无预计")
        let sessionA = TimeSession(taskID: noEstimate.id, startAt: clock.now)
        try await service.scheduleEstimatedReachedReminder(for: sessionA, task: noEstimate, elapsedSeconds: 0)
        #expect(center.captured.isEmpty)

        let finished = try tasks.create(title: "已超时", estimatedMinutes: 10)
        let sessionB = TimeSession(taskID: finished.id, startAt: clock.now)
        try await service.scheduleEstimatedReachedReminder(for: sessionB, task: finished, elapsedSeconds: 20 * 60)
        #expect(center.captured.isEmpty)
    }

    @Test("取消通知：按 identifier 移除")
    func cancelNotification() async throws {
        let (service, center, _, _) = try makeEnvironment()
        service.cancel(identifier: "due-1")
        #expect(center.removedIdentifiers == ["due-1"])
    }
}

// MARK: - 快捷键映射

@MainActor
@Suite("Phase 6: 快捷键动作映射")
struct Phase6ShortcutTests {

    @Test("默认映射与未知键")
    func defaultMappings() {
        let router = ShortcutRouter()
        #expect(router.action(for: "n", modifiers: ["command"]) == .quickAdd)
        #expect(router.action(for: "t", modifiers: ["command", "shift"]) == .toggleTimer)
        #expect(router.action(for: "d", modifiers: ["command", "shift"]) == .completeCurrent)
        #expect(router.action(for: "x", modifiers: ["command"]) == nil)
        #expect(router.action(for: "n", modifiers: ["shift"]) == nil)
        #expect(router.action(for: "t", modifiers: ["command"]) == nil)
    }

    @Test("toggleTimer：运行中暂停，暂停后继续，空闲不动作")
    func toggleTimerTransitions() throws {
        let clock = ManualClock(Date(timeIntervalSince1970: 1_700_000_000))
        let persistence = try PersistenceService(inMemory: true)
        let history = HistoryService(persistence: persistence, clock: clock)
        let tasks = TaskService(persistence: persistence, history: history, clock: clock)
        let timer = TimerService(persistence: persistence, clock: clock, history: history)
        let router = ShortcutRouter()
        let task = try tasks.create(title: "快捷键任务")

        // 空闲：不动作
        router.perform(.toggleTimer, timer: timer)
        #expect(timer.phase == .idle)

        try timer.start(task: task)
        router.perform(.toggleTimer, timer: timer)
        #expect(timer.phase == .paused)

        router.perform(.toggleTimer, timer: timer)
        #expect(timer.phase == .running)
    }

    @Test("completeCurrent：完成计时中的任务")
    func completeCurrentAction() throws {
        let clock = ManualClock(Date(timeIntervalSince1970: 1_700_000_000))
        let persistence = try PersistenceService(inMemory: true)
        let history = HistoryService(persistence: persistence, clock: clock)
        let tasks = TaskService(persistence: persistence, history: history, clock: clock)
        let timer = TimerService(persistence: persistence, clock: clock, history: history)
        let router = ShortcutRouter()
        let task = try tasks.create(title: "完成验证")

        try timer.start(task: task)
        clock.advance(by: 30)
        router.perform(.completeCurrent, timer: timer)

        #expect(task.isCompleted)
        #expect(timer.phase == .idle)
    }
}

// MARK: - 数据导出

@MainActor
@Suite("Phase 6: JSON 数据导出")
struct Phase6ExportTests {

    @Test("导出结构与字段完整，往返解码一致")
    func exportStructureAndRoundTrip() throws {
        let clock = ManualClock(Date(timeIntervalSince1970: 1_700_000_000))
        let persistence = try PersistenceService(inMemory: true)
        let history = HistoryService(persistence: persistence, clock: clock)
        let tasks = TaskService(persistence: persistence, history: history, clock: clock)
        let timer = TimerService(persistence: persistence, clock: clock, history: history)

        let task = try tasks.create(
            title: "导出任务", notes: "备注内容",
            dueDate: clock.now.addingTimeInterval(3_600),
            estimatedMinutes: 45, priority: .high,
            tags: ["工作"], projectName: "FrostTodo"
        )
        try timer.start(task: task)
        clock.advance(by: 120)
        try timer.pause()
        try tasks.complete(task)

        let export = ExportService(persistence: persistence)
        let data = try export.exportAll()
        #expect(data.count > 0)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(ExportBundle.self, from: data)

        // 版本与导出时间
        #expect(bundle.version == 1)
        #expect(bundle.exportedAt > .distantPast)

        // 任务与嵌套 Session
        #expect(bundle.tasks.count == 1)
        let taskDTO = try #require(bundle.tasks.first)
        #expect(taskDTO.id == task.id)
        #expect(taskDTO.title == "导出任务")
        #expect(taskDTO.notes == "备注内容")
        #expect(taskDTO.priority == TaskPriority.high.rawValue)
        #expect(taskDTO.tags == ["工作"])
        #expect(taskDTO.projectName == "FrostTodo")
        #expect(taskDTO.status == TaskStatus.completed.rawValue)
        #expect(taskDTO.sessions.count == 1)
        let sessionDTO = try #require(taskDTO.sessions.first)
        #expect(sessionDTO.taskID == task.id)
        #expect(sessionDTO.durationSeconds == 120)

        // 设置
        #expect(bundle.settings.writeToCalendar == persistence.settings().writeToCalendar)
        #expect(bundle.settings.defaultEstimatedMinutes == persistence.settings().defaultEstimatedMinutes)

        // 历史（创建、计时、完成等多类事件）
        #expect(bundle.history.count >= 3)
        let historyTypes = Set(bundle.history.map(\.type))
        #expect(historyTypes.contains(HistoryEventType.taskCreated.rawValue))
        #expect(historyTypes.contains(HistoryEventType.timerStarted.rawValue))
        #expect(historyTypes.contains(HistoryEventType.taskCompleted.rawValue))
    }

    @Test("空数据导出与往返")
    func emptyExportRoundTrip() throws {
        let persistence = try PersistenceService(inMemory: true)
        let export = ExportService(persistence: persistence)
        let data = try export.exportAll()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(ExportBundle.self, from: data)
        #expect(bundle.tasks.isEmpty)
        #expect(bundle.history.isEmpty)
    }
}
