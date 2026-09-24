import Foundation

/// 设置服务：设置读写与 settings.changed 历史写入
@MainActor
public final class SettingsService {
    private let persistence: PersistenceService
    private let history: HistoryRecording
    private let clock: ClockProviding

    public init(persistence: PersistenceService, history: HistoryRecording, clock: ClockProviding = SystemClock()) {
        self.persistence = persistence
        self.history = history
        self.clock = clock
    }

    public func settings() -> AppSettings {
        persistence.settings()
    }

    /// 修改设置并记录变更历史；detail 列出每个变更字段
    public func update(_ apply: (AppSettings) -> Void) throws {
        let settings = persistence.settings()
        let before = SettingsSnapshot(settings)
        apply(settings)
        let changes = before.diff(with: settings)
        guard !changes.isEmpty else {
            try persistence.save()
            return
        }

        do {
            try history.record(HistoryEventInput(
                type: .settingsChanged,
                title: "设置变更",
                detail: "变更：" + changes.map { "\($0.name)：\($0.oldValue) -> \($0.newValue)" }.joined(separator: "；"),
                payload: Dictionary(uniqueKeysWithValues: changes.map { ($0.name, "\($0.oldValue) -> \($0.newValue)") }),
                source: .user
            ))
            try persistence.save()
        } catch {
            persistence.rollback()
            throw error
        }
    }
}

/// 设置字段快照与差异
struct SettingsSnapshot {
    let writeToCalendar: Bool
    let createEventOnStart: Bool
    let createCompletionEvent: Bool
    let defaultEstimatedMinutes: Int
    let appearance: String
    let historyRetentionPolicy: String
    let historyRetentionDays: Int
    let historyRetentionCount: Int
    let defaultCalendarID: String?
    let countdownWorkMinutes: Int
    let countdownRestMinutes: Int

    init(_ settings: AppSettings) {
        writeToCalendar = settings.writeToCalendar
        createEventOnStart = settings.createEventOnStart
        createCompletionEvent = settings.createCompletionEvent
        defaultEstimatedMinutes = settings.defaultEstimatedMinutes
        appearance = settings.appearance
        historyRetentionPolicy = settings.historyRetentionPolicy
        historyRetentionDays = settings.historyRetentionDays
        historyRetentionCount = settings.historyRetentionCount
        defaultCalendarID = settings.defaultCalendarID
        countdownWorkMinutes = settings.countdownWorkMinutes
        countdownRestMinutes = settings.countdownRestMinutes
    }

    struct Change {
        let name: String
        let oldValue: String
        let newValue: String
    }

    func diff(with settings: AppSettings) -> [Change] {
        var changes: [Change] = []
        if writeToCalendar != settings.writeToCalendar {
            changes.append(Change(name: "写入日历", oldValue: "\(writeToCalendar)", newValue: "\(settings.writeToCalendar)"))
        }
        if createEventOnStart != settings.createEventOnStart {
            changes.append(Change(name: "开始计时时创建事件", oldValue: "\(createEventOnStart)", newValue: "\(settings.createEventOnStart)"))
        }
        if createCompletionEvent != settings.createCompletionEvent {
            changes.append(Change(name: "完成时创建事件", oldValue: "\(createCompletionEvent)", newValue: "\(settings.createCompletionEvent)"))
        }
        if defaultEstimatedMinutes != settings.defaultEstimatedMinutes {
            changes.append(Change(name: "默认预计时长", oldValue: "\(defaultEstimatedMinutes) 分钟", newValue: "\(settings.defaultEstimatedMinutes) 分钟"))
        }
        if appearance != settings.appearance {
            changes.append(Change(name: "外观", oldValue: appearance, newValue: settings.appearance))
        }
        if historyRetentionPolicy != settings.historyRetentionPolicy {
            changes.append(Change(name: "历史保留策略", oldValue: historyRetentionPolicy, newValue: settings.historyRetentionPolicy))
        }
        if historyRetentionDays != settings.historyRetentionDays {
            changes.append(Change(name: "历史保留天数", oldValue: "\(historyRetentionDays)", newValue: "\(settings.historyRetentionDays)"))
        }
        if historyRetentionCount != settings.historyRetentionCount {
            changes.append(Change(name: "历史保留条数", oldValue: "\(historyRetentionCount)", newValue: "\(settings.historyRetentionCount)"))
        }
        if defaultCalendarID != settings.defaultCalendarID {
            let oldID = defaultCalendarID ?? "无"
            let newID = settings.defaultCalendarID ?? "无"
            changes.append(Change(name: "默认日历", oldValue: oldID, newValue: newID))
        }
        if countdownWorkMinutes != settings.countdownWorkMinutes {
            changes.append(Change(name: "倒计时专注时长", oldValue: "\(countdownWorkMinutes) 分钟", newValue: "\(settings.countdownWorkMinutes) 分钟"))
        }
        if countdownRestMinutes != settings.countdownRestMinutes {
            changes.append(Change(name: "倒计时休息时长", oldValue: "\(countdownRestMinutes) 分钟", newValue: "\(settings.countdownRestMinutes) 分钟"))
        }
        return changes
    }
}
