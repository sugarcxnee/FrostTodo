import Testing
import Foundation
import SwiftData
@testable import FrostTodo

// MARK: - TaskListViewModel

@MainActor
@Suite("Phase 5: TaskListViewModel 筛选搜索排序")
struct Phase5TaskListViewModelTests {

    private var calendar: Calendar { Calendar(identifier: .gregorian) }

    private func makeEnvironment(clock: ManualClock) throws -> (TaskListViewModel, PersistenceService) {
        let persistence = try PersistenceService(inMemory: true)
        let history = HistoryService(persistence: persistence, clock: clock)
        let tasks = TaskService(persistence: persistence, history: history, clock: clock)
        let viewModel = TaskListViewModel(persistence: persistence, tasks: tasks, clock: clock)
        return (viewModel, persistence)
    }

    /// 以 day 为“今天”，构造日期
    private func at(dayOffset: Int, hour: Int = 12, from base: Date, calendar: Calendar) -> Date {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: base)!
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
    }

    @Test("收件箱视图：未完成且无开始与截止日期")
    func inboxView() throws {
        let clock = ManualClock(Date(timeIntervalSince1970: 1_700_000_000))
        let (vm, persistence) = try makeEnvironment(clock: clock)
        let history = HistoryService(persistence: persistence, clock: clock)
        let tasks = TaskService(persistence: persistence, history: history, clock: clock)
        let today = calendar.startOfDay(for: clock.now)

        _ = try tasks.create(title: "未安排任务") // 收件箱
        _ = try tasks.create(title: "今天任务", startDate: at(dayOffset: 0, from: today, calendar: calendar))
        _ = try tasks.create(title: "已截止任务", dueDate: at(dayOffset: 0, from: today, calendar: calendar))

        vm.selectedView = .inbox
        try vm.reload()
        #expect(vm.visibleTasks.map(\.title) == ["未安排任务"])
    }

    @Test("今天视图：已开始或将到期，且未完成")
    func todayView() throws {
        let clock = ManualClock(Date(timeIntervalSince1970: 1_700_000_000))
        let (vm, persistence) = try makeEnvironment(clock: clock)
        let history = HistoryService(persistence: persistence, clock: clock)
        let tasks = TaskService(persistence: persistence, history: history, clock: clock)
        let today = calendar.startOfDay(for: clock.now)

        _ = try tasks.create(title: "今天开始", startDate: today)
        _ = try tasks.create(title: "昨天开始", startDate: at(dayOffset: -1, from: today, calendar: calendar))
        _ = try tasks.create(title: "明天开始", startDate: at(dayOffset: 1, from: today, calendar: calendar))
        _ = try tasks.create(title: "今天到期", dueDate: today.addingTimeInterval(3_600))

        vm.selectedView = .today
        try vm.reload()
        let titles = vm.visibleTasks.map(\.title)
        #expect(titles.contains("今天开始"))
        #expect(titles.contains("昨天开始"))
        #expect(titles.contains("今天到期"))
        #expect(!titles.contains("明天开始"))
    }

    @Test("计划视图：开始日期在未来")
    func plannedView() throws {
        let clock = ManualClock(Date(timeIntervalSince1970: 1_700_000_000))
        let (vm, persistence) = try makeEnvironment(clock: clock)
        let history = HistoryService(persistence: persistence, clock: clock)
        let tasks = TaskService(persistence: persistence, history: history, clock: clock)
        let today = calendar.startOfDay(for: clock.now)

        _ = try tasks.create(title: "未来任务", startDate: at(dayOffset: 3, from: today, calendar: calendar))
        _ = try tasks.create(title: "今天任务", startDate: today)

        vm.selectedView = .planned
        try vm.reload()
        #expect(vm.visibleTasks.map(\.title) == ["未来任务"])
    }

    @Test("已完成视图与完成切换")
    func completedViewAndToggle() throws {
        let clock = ManualClock(Date(timeIntervalSince1970: 1_700_000_000))
        let (vm, persistence) = try makeEnvironment(clock: clock)
        let history = HistoryService(persistence: persistence, clock: clock)
        let tasks = TaskService(persistence: persistence, history: history, clock: clock)

        let task = try tasks.create(title: "将被完成")
        let other = try tasks.create(title: "保持未完成")
        try vm.toggleComplete(task)

        vm.selectedView = .completed
        try vm.reload()
        #expect(vm.visibleTasks.map(\.title) == ["将被完成"])
        #expect(task.isCompleted)
        #expect(!other.isCompleted)

        // 再次切换：取消完成
        try vm.toggleComplete(task)
        try vm.reload()
        #expect(vm.visibleTasks.isEmpty)
    }

    @Test("标签视图与项目视图")
    func tagAndProjectViews() throws {
        let clock = ManualClock(Date(timeIntervalSince1970: 1_700_000_000))
        let (vm, persistence) = try makeEnvironment(clock: clock)
        let history = HistoryService(persistence: persistence, clock: clock)
        let tasks = TaskService(persistence: persistence, history: history, clock: clock)

        _ = try tasks.create(title: "写作任务", tags: ["写作", "工作"])
        _ = try tasks.create(title: "阅读任务", tags: ["阅读"])
        _ = try tasks.create(title: "项目任务", projectName: "FrostTodo")
        _ = try tasks.create(title: "无所属")

        vm.selectedView = .tag
        vm.selectedTag = "写作"
        try vm.reload()
        #expect(vm.visibleTasks.map(\.title) == ["写作任务"])

        vm.selectedView = .project
        vm.selectedProject = "FrostTodo"
        try vm.reload()
        #expect(vm.visibleTasks.map(\.title) == ["项目任务"])

        // 标签与项目清单
        vm.selectedView = .tag
        try vm.reload()
        #expect(Set(vm.availableTags) == ["写作", "工作", "阅读"])
        #expect(vm.availableProjects == ["FrostTodo"])
    }

    @Test("搜索：标题大小写不敏感过滤")
    func searchFilter() throws {
        let clock = ManualClock(Date(timeIntervalSince1970: 1_700_000_000))
        let (vm, persistence) = try makeEnvironment(clock: clock)
        let history = HistoryService(persistence: persistence, clock: clock)
        let tasks = TaskService(persistence: persistence, history: history, clock: clock)
        _ = try tasks.create(title: "Write Report")
        _ = try tasks.create(title: "Read Book")

        vm.searchText = "report"
        try vm.reload()
        #expect(vm.visibleTasks.map(\.title) == ["Write Report"])
    }

    @Test("四种排序：手动、创建时间、截止日期、优先级")
    func sortOrders() throws {
        let clock = ManualClock(Date(timeIntervalSince1970: 1_700_000_000))
        let (vm, persistence) = try makeEnvironment(clock: clock)
        let history = HistoryService(persistence: persistence, clock: clock)
        let tasks = TaskService(persistence: persistence, history: history, clock: clock)

        // 用标签视图承载全部被测任务（智能视图会按日期过滤）
        _ = try tasks.create(title: "低优先", dueDate: clock.now.addingTimeInterval(86_400 * 2), priority: .low, tags: ["排序"])
        _ = try tasks.create(title: "高优先", dueDate: clock.now.addingTimeInterval(86_400), priority: .high, tags: ["排序"])
        _ = try tasks.create(title: "无优先无截止", tags: ["排序"])
        vm.selectedView = .tag
        vm.selectedTag = "排序"

        // 手动：sortOrder 递增（创建顺序）
        vm.sortOrder = .manual
        try vm.reload()
        #expect(vm.visibleTasks.map(\.title) == ["低优先", "高优先", "无优先无截止"])

        // 创建时间：新在前
        vm.sortOrder = .created
        try vm.reload()
        #expect(vm.visibleTasks.first?.title == "无优先无截止")

        // 截止日期：近在前，无截止在后
        vm.sortOrder = .due
        try vm.reload()
        #expect(vm.visibleTasks.map(\.title) == ["高优先", "低优先", "无优先无截止"])

        // 优先级：高在前
        vm.sortOrder = .priority
        try vm.reload()
        #expect(vm.visibleTasks.map(\.title) == ["高优先", "低优先", "无优先无截止"])
    }

    @Test("快速添加与删除")
    func quickAddAndDelete() throws {
        let clock = ManualClock(Date(timeIntervalSince1970: 1_700_000_000))
        let (vm, _) = try makeEnvironment(clock: clock)

        let task = try vm.quickAdd(title: "快速任务")
        try vm.reload()
        #expect(vm.visibleTasks.map(\.title) == ["快速任务"])

        try vm.delete(task)
        try vm.reload()
        #expect(vm.visibleTasks.isEmpty)
    }

    @Test("手动排序：移动任务后顺序持久化")
    func manualMove() throws {
        let clock = ManualClock(Date(timeIntervalSince1970: 1_700_000_000))
        let (vm, persistence) = try makeEnvironment(clock: clock)
        let history = HistoryService(persistence: persistence, clock: clock)
        let tasks = TaskService(persistence: persistence, history: history, clock: clock)
        _ = try tasks.create(title: "A")
        _ = try tasks.create(title: "B")
        _ = try tasks.create(title: "C")

        vm.sortOrder = .manual
        try vm.reload()
        try vm.move(from: IndexSet(integer: 2), to: 0) // C 移到最前
        try vm.reload()
        #expect(vm.visibleTasks.map(\.title) == ["C", "A", "B"])
    }
}

// MARK: - HistoryViewModel

@MainActor
@Suite("Phase 5: HistoryViewModel 数据源")
struct Phase5HistoryViewModelTests {

    private func makeVM() throws -> (HistoryViewModel, HistoryService, ManualClock, PersistenceService) {
        let clock = ManualClock(Date(timeIntervalSince1970: 1_700_000_000))
        let persistence = try PersistenceService(inMemory: true)
        let history = HistoryService(persistence: persistence, clock: clock)
        let vm = HistoryViewModel(history: history)
        return (vm, history, clock, persistence)
    }

    @Test("筛选与搜索作用于数据源")
    func filtersApply() throws {
        let (vm, history, clock, _) = try makeVM()
        let taskID = UUID()
        try history.record(HistoryEventInput(type: .taskCreated, taskID: taskID, title: "创建 A"))
        clock.advance(by: 10)
        try history.record(HistoryEventInput(type: .timerStarted, taskID: taskID, title: "计时 A"))
        clock.advance(by: 10)
        try history.record(HistoryEventInput(type: .settingsChanged, title: "设置变更"))

        vm.filter.types = [.timerStarted]
        try vm.reload()
        #expect(vm.visibleEvents.map(\.title) == ["计时 A"])

        vm.filter.types = []
        vm.filter.taskID = taskID
        try vm.reload()
        #expect(vm.visibleEvents.count == 2)

        vm.filter.taskID = nil
        vm.filter.searchText = "设置"
        try vm.reload()
        #expect(vm.visibleEvents.map(\.title) == ["设置变更"])
    }

    @Test("按天分组数量与内容")
    func dayGroups() throws {
        let (vm, history, clock, _) = try makeVM()
        try history.record(HistoryEventInput(type: .taskCreated, title: "今日 A"))
        clock.advance(by: 3_600)
        try history.record(HistoryEventInput(type: .taskCreated, title: "今日 B"))
        clock.advance(by: 86_400)
        try history.record(HistoryEventInput(type: .taskCreated, title: "明日 C"))

        vm.filter.ascending = true
        try vm.reload()
        #expect(vm.dayGroups.count == 2)
        #expect(vm.dayGroups[0].events.count == 2)
        #expect(vm.dayGroups[1].events.map(\.title) == ["明日 C"])
    }

    @Test("分页加载：默认页大小，loadMore 扩容")
    func pagination() throws {
        let (vm, history, clock, _) = try makeVM()
        for index in 0..<25 {
            clock.advance(by: 1)
            try history.record(HistoryEventInput(type: .taskCreated, title: "事件 \(index)"))
        }

        vm.pageSize = 10
        try vm.reload()
        #expect(vm.visibleEvents.count == 10)

        try vm.loadMore()
        #expect(vm.visibleEvents.count == 20)

        try vm.loadMore()
        #expect(vm.visibleEvents.count == 25) // 不足一页时取全部
    }

    @Test("清空历史后数据源只剩清空记录")
    func clearAllResetsDataSource() throws {
        let (vm, history, _, _) = try makeVM()
        try history.record(HistoryEventInput(type: .taskCreated, title: "A"))
        try history.record(HistoryEventInput(type: .timerStarted, title: "B"))

        try vm.clearAll()
        try vm.reload()
        #expect(vm.visibleEvents.count == 1)
        #expect(vm.visibleEvents.first?.typeValue == .historyCleared)
    }

    @Test("导出 JSON 与 CSV 非空")
    func exports() throws {
        let (vm, history, _, _) = try makeVM()
        try history.record(HistoryEventInput(type: .taskCreated, title: "导出源"))
        try vm.reload()

        let json = try vm.exportJSON()
        #expect(json.count > 2)

        let csv = try vm.exportCSV()
        #expect(csv.contains("导出源"))
        #expect(csv.contains("id,type"))
    }
}

// MARK: - SettingsViewModel

@MainActor
@Suite("Phase 5: SettingsViewModel 行为影响")
struct Phase5SettingsViewModelTests {

    @Test("设置变更持久化并写入 settings.changed 历史")
    func updatePersistsAndRecords() throws {
        let clock = ManualClock(Date(timeIntervalSince1970: 1_700_000_000))
        let persistence = try PersistenceService(inMemory: true)
        let history = HistoryService(persistence: persistence, clock: clock)
        let settingsService = SettingsService(persistence: persistence, history: history, clock: clock)
        let vm = SettingsViewModel(settings: settingsService, history: history, persistence: persistence)

        try vm.update { $0.writeToCalendar = false; $0.defaultEstimatedMinutes = 45 }

        #expect(vm.settings.writeToCalendar == false)
        #expect(vm.settings.defaultEstimatedMinutes == 45)
        // 持久化（跨 context）
        let other = ModelContext(persistence.container)
        let reloaded = try #require(other.fetch(FetchDescriptor<AppSettings>()).first)
        #expect(reloaded.writeToCalendar == false)
        #expect(reloaded.defaultEstimatedMinutes == 45)
        // 历史
        #expect(try history.events(matching: HistoryFilter(types: [.settingsChanged])).count == 1)
    }

    @Test("关闭写入日历后：计时不再产生日历事件")
    func writeToCalendarOffStopsSync() throws {
        let clock = ManualClock(Date(timeIntervalSince1970: 1_700_000_000))
        let persistence = try PersistenceService(inMemory: true)
        let history = HistoryService(persistence: persistence, clock: clock)
        let tasks = TaskService(persistence: persistence, history: history, clock: clock)
        let timer = TimerService(persistence: persistence, clock: clock, history: history)
        let provider = MockCalendarProvider()
        let sync = CalendarSyncService(provider: provider, persistence: persistence, history: history, clock: clock)
        timer.observer = sync
        let settingsService = SettingsService(persistence: persistence, history: history, clock: clock)
        let vm = SettingsViewModel(settings: settingsService, history: history, persistence: persistence)

        try vm.update { $0.writeToCalendar = false }
        let task = try tasks.create(title: "不写日历")
        try timer.start(task: task)

        #expect(provider.createdDrafts.isEmpty)
        #expect(timer.phase == .running)
    }

    @Test("立即应用保留策略并清空历史")
    func retentionAndClear() throws {
        let clock = ManualClock(Date(timeIntervalSince1970: 1_700_000_000))
        let persistence = try PersistenceService(inMemory: true)
        let history = HistoryService(persistence: persistence, clock: clock)
        let settingsService = SettingsService(persistence: persistence, history: history, clock: clock)
        let vm = SettingsViewModel(settings: settingsService, history: history, persistence: persistence)

        for index in 0..<8 {
            clock.advance(by: 1)
            try history.record(HistoryEventInput(type: .taskCreated, title: "事件 \(index)"))
        }
        try persistence.save()

        try vm.update { $0.historyRetentionPolicyValue = .byCount; $0.historyRetentionCount = 3 }
        // 共 9 条（8 条事件 + 1 条 settings.changed），保留最新 3 条
        let pruned = try vm.applyRetentionPolicy()
        #expect(pruned == 6)
        #expect(try history.events(matching: HistoryFilter()).count == 4) // 3 保留 + 1 清理记录

        try vm.clearHistory()
        #expect(try history.events(matching: HistoryFilter()).count == 1)
    }
}

// MARK: - TimerViewModel

@MainActor
@Suite("Phase 5: TimerViewModel 状态与格式化")
struct Phase5TimerViewModelTests {

    @Test("时长格式化")
    func formatDurations() {
        #expect(TimerViewModel.format(seconds: 0) == "00:00")
        #expect(TimerViewModel.format(seconds: 59) == "00:59")
        #expect(TimerViewModel.format(seconds: 65) == "01:05")
        #expect(TimerViewModel.format(seconds: 3_600) == "1:00:00")
        #expect(TimerViewModel.format(seconds: 3_672) == "1:01:12")
    }

    @Test("开始与暂停后的展示状态")
    func startAndPauseDisplay() throws {
        let clock = ManualClock(Date(timeIntervalSince1970: 1_700_000_000))
        let persistence = try PersistenceService(inMemory: true)
        let history = HistoryService(persistence: persistence, clock: clock)
        let tasks = TaskService(persistence: persistence, history: history, clock: clock)
        let timer = TimerService(persistence: persistence, clock: clock, history: history)
        let vm = TimerViewModel(timer: timer, clock: clock)
        let task = try tasks.create(title: "展示任务")

        #expect(vm.phase == .idle)
        #expect(vm.activeTaskTitle == nil)

        try vm.start(task: task)
        clock.advance(by: 90)
        vm.refresh()
        #expect(vm.phase == .running)
        #expect(vm.activeTaskTitle == "展示任务")
        #expect(vm.elapsedText == "01:30")

        try vm.pause()
        vm.refresh()
        #expect(vm.phase == .paused)
        #expect(vm.elapsedText == "01:30") // 暂停期间不再增长
        clock.advance(by: 300)
        vm.refresh()
        #expect(vm.elapsedText == "01:30")
    }
}
