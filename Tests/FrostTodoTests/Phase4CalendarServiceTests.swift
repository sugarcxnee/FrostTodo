import Testing
import Foundation
import EventKit
@testable import FrostTodo

@MainActor
@Suite("Phase 4: 日历联动")
struct Phase4CalendarServiceTests {

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private struct Environment {
        let clock: ManualClock
        let persistence: PersistenceService
        let history: HistoryService
        let tasks: TaskService
        let timer: TimerService
        let provider: MockCalendarProvider
        let calendarSync: CalendarSyncService
        let settings: AppSettings
    }

    private func makeEnvironment(
        configureProvider: (MockCalendarProvider) -> Void = { _ in }
    ) throws -> Environment {
        let clock = ManualClock(epoch)
        let persistence = try PersistenceService(inMemory: true)
        let history = HistoryService(persistence: persistence, clock: clock)
        let tasks = TaskService(persistence: persistence, history: history, clock: clock)
        let timer = TimerService(persistence: persistence, clock: clock, history: history)
        let provider = MockCalendarProvider()
        configureProvider(provider)
        let calendarSync = CalendarSyncService(
            provider: provider, persistence: persistence, history: history, clock: clock
        )
        timer.observer = calendarSync
        tasks.timerService = timer
        return Environment(
            clock: clock, persistence: persistence, history: history,
            tasks: tasks, timer: timer, provider: provider,
            calendarSync: calendarSync, settings: persistence.settings()
        )
    }

    private func calendarHistory(_ env: Environment, _ type: HistoryEventType) throws -> [HistoryEvent] {
        try env.history.events(matching: HistoryFilter(types: [type]))
    }

    // MARK: - 权限映射

    @Test("权限状态映射：EKAuthorizationStatus 全部五个取值")
    func authorizationStatusMapping() {
        #expect(CalendarAccessStatus.from(.notDetermined) == .notDetermined)
        #expect(CalendarAccessStatus.from(.fullAccess) == .granted)
        #expect(CalendarAccessStatus.from(.writeOnly) == .writeOnly)
        #expect(CalendarAccessStatus.from(.denied) == .denied)
        #expect(CalendarAccessStatus.from(.restricted) == .restricted)
    }

    // MARK: - 事件创建

    @Test("开始计时创建日历事件：标题、起止时间、备注、URL 字段正确")
    func startCreatesCalendarEventWithCorrectFields() throws {
        let env = try makeEnvironment()
        let task = try env.tasks.create(title: "写周报", notes: "本周进展", estimatedMinutes: 30)

        try env.timer.start(task: task)

        #expect(env.provider.createdDrafts.count == 1)
        let draft = try #require(env.provider.createdDrafts.first)
        #expect(draft.title == "[计时中] 写周报")
        #expect(draft.startDate == epoch)
        #expect(draft.endDate == epoch.addingTimeInterval(30 * 60))

        let url = try #require(draft.url)
        #expect(url == TaskLink.url(for: task.id))
        #expect(TaskLink.taskID(from: url) == task.id)

        #expect(draft.notes.contains("任务 ID: \(task.id.uuidString)"))
        #expect(draft.notes.contains("状态: 计时中"))
        #expect(draft.notes.contains("备注: 本周进展"))

        // Session 与任务均记录事件 ID
        #expect(task.calendarEventIDs.count == 1)
        let session = try #require(task.sessions.first)
        #expect(session.calendarEventID == draft.storedID)

        // 历史记录 calendar.eventCreated
        let created = try calendarHistory(env, .calendarEventCreated)
        #expect(created.count == 1)
        #expect(created.first?.taskID == task.id)
    }

    @Test("无预计时长时默认结束时间为开始后 15 分钟")
    func defaultEndWithoutEstimate() throws {
        let env = try makeEnvironment()
        let task = try env.tasks.create(title: "无预估任务")

        try env.timer.start(task: task)

        let draft = try #require(env.provider.createdDrafts.first)
        #expect(draft.endDate == epoch.addingTimeInterval(15 * 60))
    }

    @Test("回跳 URL 与任务 ID 双向映射")
    func taskLinkRoundTrip() throws {
        let id = UUID()
        let url = TaskLink.url(for: id)
        #expect(url.absoluteString == "frosttodo://task/\(id.uuidString)")
        #expect(TaskLink.taskID(from: url) == id)
        #expect(TaskLink.taskID(from: URL(string: "frosttodo://task/not-a-uuid")!) == nil)
        #expect(TaskLink.taskID(from: URL(string: "https://example.com")!) == nil)
    }

    // MARK: - 事件更新

    @Test("暂停时更新事件结束时间、标题与备注（含实际时长）")
    func pauseUpdatesEvent() throws {
        let env = try makeEnvironment()
        let task = try env.tasks.create(title: "更新验证", estimatedMinutes: 30)

        try env.timer.start(task: task)
        env.clock.advance(by: 1_200)
        try env.timer.pause()

        let eventID = try #require(task.sessions.first?.calendarEventID)
        let event = try #require(env.provider.events[eventID])
        #expect(event.title == "[计时记录] 更新验证")
        #expect(event.endDate == epoch.addingTimeInterval(1_200))
        #expect(event.notes.contains("实际时长: 1200 秒"))
        #expect(event.notes.contains("状态: 已结束"))

        let updated = try calendarHistory(env, .calendarEventUpdated)
        #expect(updated.count == 1)
        #expect(updated.first?.calendarEventID == eventID)
    }

    @Test("事件被用户手动删除：暂停时重建事件并记录 calendar.eventRebuilt")
    func rebuildWhenEventDeleted() throws {
        let env = try makeEnvironment()
        let task = try env.tasks.create(title: "重建验证", estimatedMinutes: 30)

        try env.timer.start(task: task)
        let originalID = try #require(task.sessions.first?.calendarEventID)
        env.provider.events.removeValue(forKey: originalID) // 模拟用户在日历中删除

        env.clock.advance(by: 600)
        try env.timer.pause()

        let rebuilt = try calendarHistory(env, .calendarEventRebuilt)
        #expect(rebuilt.count == 1)
        let newID = try #require(task.sessions.first?.calendarEventID)
        #expect(newID != originalID)
        #expect(env.provider.events[newID] != nil)
        #expect(task.calendarEventIDs.contains(newID))
        let event = try #require(env.provider.events[newID])
        #expect(event.endDate == epoch.addingTimeInterval(600))
    }

    // MARK: - 日历选择与降级

    @Test("设置的默认日历失效时：自动创建 FrostTodo 专用日历并记忆")
    func createsDedicatedCalendarWhenDefaultInvalid() throws {
        let env = try makeEnvironment { provider in
            provider.calendars = [] // 默认日历已被删除，可用列表为空
        }
        env.settings.defaultCalendarID = "CAL-OLD"
        let task = try env.tasks.create(title: "专用日历验证")

        try env.timer.start(task: task)

        #expect(env.provider.createdCalendarNames == ["FrostTodo"])
        let newID = try #require(env.provider.lastCreatedCalendarID)
        #expect(env.settings.defaultCalendarID == newID)
        let draft = try #require(env.provider.createdDrafts.first)
        #expect(draft.calendarID == newID)
    }

    @Test("日历只读且无法创建：优雅降级，不崩溃，写 calendar.syncFailed")
    func readonlyCalendarDegradesGracefully() throws {
        let env = try makeEnvironment { provider in
            provider.calendars = [CalendarInfo(id: "CAL-RO", title: "只读日历", isWritable: false)]
            provider.createCalendarThrows = true
        }
        let task = try env.tasks.create(title: "降级验证")

        try env.timer.start(task: task) // 不抛错
        #expect(env.provider.createdDrafts.isEmpty)

        let failed = try calendarHistory(env, .calendarSyncFailed)
        #expect(failed.count >= 1)
        #expect(failed.first?.sourceValue == .calendar)

        // 本地计时不受影响
        #expect(env.timer.phase == .running)
        #expect(task.sessions.count == 1)
    }

    @Test("日历权限被拒绝：不写日历、不写失败历史刷屏，本地功能正常")
    func deniedAccessSkipsSync() throws {
        let env = try makeEnvironment { provider in
            provider.status = .denied
        }
        let task = try env.tasks.create(title: "权限拒绝")

        try env.timer.start(task: task)
        #expect(env.provider.createdDrafts.isEmpty)
        #expect(try calendarHistory(env, .calendarSyncFailed).isEmpty)
        #expect(env.timer.phase == .running)
    }

    // MARK: - 设置开关

    @Test("关闭写入日历：不创建事件也不产生日历历史")
    func writeToCalendarDisabled() throws {
        let env = try makeEnvironment()
        env.settings.writeToCalendar = false
        let task = try env.tasks.create(title: "关闭日历")

        try env.timer.start(task: task)
        env.clock.advance(by: 60)
        try env.timer.pause()

        #expect(env.provider.createdDrafts.isEmpty)
        #expect(try calendarHistory(env, .calendarEventCreated).isEmpty)
        #expect(try calendarHistory(env, .calendarEventUpdated).isEmpty)
    }

    @Test("关闭开始即建事件：开始不建事件，暂停也不更新")
    func createEventOnStartDisabled() throws {
        let env = try makeEnvironment()
        env.settings.createEventOnStart = false
        let task = try env.tasks.create(title: "延迟建事件")

        try env.timer.start(task: task)
        env.clock.advance(by: 60)
        try env.timer.pause()

        #expect(env.provider.createdDrafts.isEmpty)
        #expect(try calendarHistory(env, .calendarEventCreated).isEmpty)
    }

    // MARK: - 完成

    @Test("任务完成且最近事件存在：更新标题为已完成")
    func completeUpdatesLatestEvent() throws {
        let env = try makeEnvironment()
        let task = try env.tasks.create(title: "完成更新", estimatedMinutes: 30)

        try env.timer.start(task: task)
        env.clock.advance(by: 300)
        _ = try env.timer.completeActiveTask()

        let eventID = try #require(task.calendarEventIDs.first)
        let event = try #require(env.provider.events[eventID])
        #expect(event.title == "[已完成] 完成更新")
        #expect(event.notes.contains("状态: 已完成"))
        let updated = try calendarHistory(env, .calendarEventUpdated)
        #expect(updated.contains { $0.calendarEventID == eventID })
    }

    @Test("任务完成且无关联事件：创建完成记录事件（完成时间起，5 分钟止）")
    func completeCreatesCompletionEvent() throws {
        let env = try makeEnvironment()
        env.settings.createEventOnStart = false // 不产生计时事件
        let task = try env.tasks.create(title: "完成创建")

        try env.timer.start(task: task)
        env.clock.advance(by: 120)
        _ = try env.timer.completeActiveTask()

        #expect(env.provider.createdDrafts.count == 1)
        let draft = try #require(env.provider.createdDrafts.first)
        #expect(draft.title == "[完成记录] 完成创建")
        #expect(draft.startDate == epoch.addingTimeInterval(120))
        #expect(draft.endDate == epoch.addingTimeInterval(120 + 300))
        #expect(draft.notes.contains("状态: 已完成"))
        let created = try calendarHistory(env, .calendarEventCreated)
        #expect(created.contains { $0.title.contains("完成记录") })
    }

    @Test("关闭完成事件设置：完成任务不创建完成事件")
    func completionEventDisabled() throws {
        let env = try makeEnvironment()
        env.settings.createEventOnStart = false
        env.settings.createCompletionEvent = false
        let task = try env.tasks.create(title: "关闭完成事件")

        try env.timer.start(task: task)
        _ = try env.timer.completeActiveTask()

        #expect(env.provider.createdDrafts.isEmpty)
    }

    // MARK: - 同步失败

    @Test("日历创建失败：本地计时成功并写入 calendar.syncFailed 历史")
    func createFailureWritesSyncFailedHistory() throws {
        let env = try makeEnvironment { provider in
            provider.failNextCreate = true
        }
        let task = try env.tasks.create(title: "失败验证")

        try env.timer.start(task: task)

        #expect(env.timer.phase == .running)
        #expect(task.sessions.first?.calendarEventID == nil)
        let failed = try calendarHistory(env, .calendarSyncFailed)
        #expect(failed.count == 1)
        #expect(failed.first?.taskID == task.id)
    }

    @Test("今日日程读取：普通事件与全天事件均返回")
    func fetchTodayEvents() throws {
        let env = try makeEnvironment()
        let now = env.clock.now
        env.provider.todayEvents = [
            CalendarEventInfo(
                id: "E1", title: "晨会", startDate: now, endDate: now.addingTimeInterval(1_800),
                isAllDay: false, notes: nil, url: nil
            ),
            CalendarEventInfo(
                id: "E2", title: "出差", startDate: now, endDate: now, isAllDay: true,
                notes: nil, url: nil
            ),
        ]

        let events = env.provider.fetchEvents(on: now)
        #expect(events.count == 2)
        #expect(events.contains { $0.isAllDay })
    }
}
