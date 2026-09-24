import Foundation
import SwiftData

/// 应用组合根：构建并接线全部服务与子 ViewModel
@MainActor
public final class AppViewModel: ObservableObject {
    public let persistence: PersistenceService
    public let history: HistoryService
    public let tasks: TaskService
    public let timer: TimerService
    public let countdown: CountdownService
    public let settingsService: SettingsService
    public let notifications: NotificationService
    public let calendarSync: CalendarSyncService
    public let provider: CalendarProviding

    public let taskList: TaskListViewModel
    public let historyModel: HistoryViewModel
    public let settingsModel: SettingsViewModel
    public let timerModel: TimerViewModel
    public let countdownModel: CountdownViewModel

    @Published public private(set) var calendarAccess: CalendarAccessStatus = .notDetermined
    @Published public private(set) var todaySchedule: [CalendarEventInfo] = []

    public init(
        persistence: PersistenceService? = nil,
        provider: (any CalendarProviding)? = nil,
        notificationCenter: (any NotificationCentering)? = nil,
        clock: ClockProviding = SystemClock()
    ) throws {
        let persistence = try persistence ?? PersistenceService()
        self.persistence = persistence
        let history = HistoryService(persistence: persistence, clock: clock)
        self.history = history
        let tasks = TaskService(persistence: persistence, history: history, clock: clock)
        self.tasks = tasks
        let timer = TimerService(persistence: persistence, clock: clock, history: history)
        self.timer = timer
        let countdown = CountdownService(persistence: persistence, timer: timer, history: history, clock: clock)
        self.countdown = countdown
        self.settingsService = SettingsService(persistence: persistence, history: history, clock: clock)
        let notificationCenter = notificationCenter ?? UserNotificationCenter()
        self.notifications = NotificationService(
            center: notificationCenter, history: history, persistence: persistence, clock: clock
        )
        let provider = provider ?? EventKitCalendarProvider()
        let calendarSync = CalendarSyncService(
            provider: provider, persistence: persistence, history: history, clock: clock
        )
        self.calendarSync = calendarSync
        self.provider = provider

        self.taskList = TaskListViewModel(persistence: persistence, tasks: tasks, clock: clock)
        self.historyModel = HistoryViewModel(history: history)
        self.settingsModel = SettingsViewModel(
            settings: settingsService, history: history, persistence: persistence
        )
        self.timerModel = TimerViewModel(timer: timer, clock: clock)
        self.countdownModel = CountdownViewModel(countdown: countdown, persistence: persistence, clock: clock)

        timer.observer = calendarSync
        tasks.timerService = timer
        calendarAccess = provider.authorizationStatus()
    }

    /// 刷新各数据源
    public func refreshAll() {
        try? taskList.reload()
        try? historyModel.reload()
        refreshCalendarStatus()
        refreshTodaySchedule()
    }

    public func refreshCalendarStatus() {
        calendarAccess = provider.authorizationStatus()
    }

    /// 首次使用请求日历权限
    public func requestCalendarAccessIfNeeded() async {
        if provider.authorizationStatus() == .notDetermined {
            _ = await provider.requestAccess()
        }
        refreshCalendarStatus()
    }

    public func refreshTodaySchedule() {
        todaySchedule = provider.fetchEvents(on: Date())
    }

    /// 可写日历清单（供设置页选择）
    public func writableCalendars() -> [CalendarInfo] {
        provider.availableCalendars().filter(\.isWritable)
    }

    /// 按 ID 取任务（右栏详情解析用；同一上下文内返回同一模型实例）
    public func task(byID id: UUID) -> TodoTask? {
        let descriptor = FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == id })
        return (try? persistence.fetch(descriptor))?.first
    }
}
