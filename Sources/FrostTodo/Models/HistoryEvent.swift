import Foundation
import SwiftData

/// 历史事件来源
public enum HistorySource: String, Codable, CaseIterable {
    case user
    case system
    case calendar
    case migration
}

/// 历史事件类型
public enum HistoryEventType: String, Codable, CaseIterable {
    // 任务历史
    case taskCreated = "task.created"
    /// 遗留类型：仅用于显示旧数据，新版不再写入（任务信息修改不记录）
    case taskUpdated = "task.updated"
    case taskCompleted = "task.completed"
    case taskUncompleted = "task.uncompleted"
    case taskDeleted = "task.deleted"
    // 计时历史
    case timerStarted = "timer.started"
    case timerPaused = "timer.paused"
    case timerResumed = "timer.resumed"
    case timerStopped = "timer.stopped"
    // 时间段历史
    case sessionStarted = "session.started"
    case sessionEnded = "session.ended"
    // 日历历史
    case calendarEventCreated = "calendar.eventCreated"
    case calendarEventUpdated = "calendar.eventUpdated"
    case calendarEventDeleted = "calendar.eventDeleted"
    case calendarEventRebuilt = "calendar.eventRebuilt"
    case calendarSyncFailed = "calendar.syncFailed"
    // 设置历史
    case settingsChanged = "settings.changed"
    // 通知历史
    case notificationSent = "notification.sent"
    // 倒计时历史
    case countdownStarted = "countdown.started"
    case countdownPhaseCompleted = "countdown.phaseCompleted"
    case countdownEnded = "countdown.ended"
    // 历史管理
    case historyCleared = "history.cleared"
    case historyPruned = "history.pruned"

    public var isTaskEvent: Bool {
        rawValue.hasPrefix("task.")
    }

    public var isTimerEvent: Bool {
        rawValue.hasPrefix("timer.")
    }

    public var isCalendarEvent: Bool {
        rawValue.hasPrefix("calendar.")
    }

    public var displayName: String {
        switch self {
        case .taskCreated: return "创建任务"
        case .taskUpdated: return "编辑任务"
        case .taskCompleted: return "完成任务"
        case .taskUncompleted: return "取消完成"
        case .taskDeleted: return "删除任务"
        case .timerStarted: return "开始计时"
        case .timerPaused: return "暂停计时"
        case .timerResumed: return "继续计时"
        case .timerStopped: return "停止计时"
        case .sessionStarted: return "时间段开始"
        case .sessionEnded: return "时间段结束"
        case .calendarEventCreated: return "日历事件创建"
        case .calendarEventUpdated: return "日历事件更新"
        case .calendarEventDeleted: return "日历事件删除"
        case .calendarEventRebuilt: return "日历事件重建"
        case .calendarSyncFailed: return "日历同步失败"
        case .settingsChanged: return "设置变更"
        case .notificationSent: return "通知发送"
        case .countdownStarted: return "开始倒计时"
        case .countdownPhaseCompleted: return "倒计时阶段完成"
        case .countdownEnded: return "结束倒计时"
        case .historyCleared: return "历史已清空"
        case .historyPruned: return "历史清理"
        }
    }
}

/// 历史事件模型：一旦写入默认不可修改
@Model
public final class HistoryEvent {
    @Attribute(.unique) public var id: UUID
    public var type: String
    public var taskID: UUID?
    public var sessionID: UUID?
    public var calendarEventID: String?
    public var title: String
    public var detail: String?
    public var payloadJSON: String?
    public var createdAt: Date
    public var source: String
    public var isUndoable: Bool

    public init(
        id: UUID = UUID(),
        type: String,
        taskID: UUID? = nil,
        sessionID: UUID? = nil,
        calendarEventID: String? = nil,
        title: String,
        detail: String? = nil,
        payloadJSON: String? = nil,
        createdAt: Date = Date(),
        source: String = HistorySource.user.rawValue,
        isUndoable: Bool = false
    ) {
        self.id = id
        self.type = type
        self.taskID = taskID
        self.sessionID = sessionID
        self.calendarEventID = calendarEventID
        self.title = title
        self.detail = detail
        self.payloadJSON = payloadJSON
        self.createdAt = createdAt
        self.source = source
        self.isUndoable = isUndoable
    }

    public var typeValue: HistoryEventType? {
        HistoryEventType(rawValue: type)
    }

    public var sourceValue: HistorySource? {
        HistorySource(rawValue: source)
    }
}
