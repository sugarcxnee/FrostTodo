import Foundation
import SwiftData
import AppKit

/// 导出用任务 DTO
public struct ExportTaskDTO: Codable, Equatable {
    public var id: UUID
    public var title: String
    public var notes: String?
    public var dueDate: Date?
    public var startDate: Date?
    public var estimatedMinutes: Int?
    public var priority: Int
    public var tags: [String]
    public var projectName: String?
    public var status: String
    public var sortOrder: Int
    public var createdAt: Date
    public var completedAt: Date?
    public var calendarEventIDs: [String]
    public var sessions: [ExportSessionDTO]

    public init(task: TodoTask) {
        id = task.id
        title = task.title
        notes = task.notes
        dueDate = task.dueDate
        startDate = task.startDate
        estimatedMinutes = task.estimatedMinutes
        priority = task.priority
        tags = task.tags
        projectName = task.projectName
        status = task.status
        sortOrder = task.sortOrder
        createdAt = task.createdAt
        completedAt = task.completedAt
        calendarEventIDs = task.calendarEventIDs
        sessions = task.sessions
            .sorted { $0.startAt < $1.startAt }
            .map(ExportSessionDTO.init(session:))
    }
}

/// 导出用时间段 DTO
public struct ExportSessionDTO: Codable, Equatable {
    public var id: UUID
    public var taskID: UUID
    public var startAt: Date
    public var endAt: Date?
    public var durationSeconds: Int
    public var calendarEventID: String?
    public var state: String

    public init(session: TimeSession) {
        id = session.id
        taskID = session.taskID
        startAt = session.startAt
        endAt = session.endAt
        durationSeconds = session.durationSeconds
        calendarEventID = session.calendarEventID
        state = session.state
    }
}

/// 导出用设置 DTO
public struct ExportSettingsDTO: Codable, Equatable {
    public var defaultCalendarID: String?
    public var writeToCalendar: Bool
    public var createEventOnStart: Bool
    public var createCompletionEvent: Bool
    public var defaultEstimatedMinutes: Int
    public var appearance: String
    public var historyRetentionPolicy: String
    public var historyRetentionDays: Int
    public var historyRetentionCount: Int

    public init(settings: AppSettings) {
        defaultCalendarID = settings.defaultCalendarID
        writeToCalendar = settings.writeToCalendar
        createEventOnStart = settings.createEventOnStart
        createCompletionEvent = settings.createCompletionEvent
        defaultEstimatedMinutes = settings.defaultEstimatedMinutes
        appearance = settings.appearance
        historyRetentionPolicy = settings.historyRetentionPolicy
        historyRetentionDays = settings.historyRetentionDays
        historyRetentionCount = settings.historyRetentionCount
    }
}

/// 导出包：全量数据的 JSON 结构
public struct ExportBundle: Codable, Equatable {
    public var version: Int
    public var exportedAt: Date
    public var tasks: [ExportTaskDTO]
    public var settings: ExportSettingsDTO
    public var history: [HistoryEventDTO]

    public init(
        version: Int = 1,
        exportedAt: Date,
        tasks: [ExportTaskDTO],
        settings: ExportSettingsDTO,
        history: [HistoryEventDTO]
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.tasks = tasks
        self.settings = settings
        self.history = history
    }
}

/// 数据导出服务：任务、时间段、设置与历史打包为 JSON
@MainActor
public final class ExportService {
    private let persistence: PersistenceService
    private let clock: ClockProviding

    public init(persistence: PersistenceService, clock: ClockProviding = SystemClock()) {
        self.persistence = persistence
        self.clock = clock
    }

    /// 组装导出包
    public func bundle() throws -> ExportBundle {
        let tasks = try persistence.fetch(FetchDescriptor<TodoTask>(sortBy: [SortDescriptor(\.createdAt)]))
        let history = try persistence.fetch(FetchDescriptor<HistoryEvent>(sortBy: [SortDescriptor(\.createdAt)]))
        return ExportBundle(
            exportedAt: clock.now,
            tasks: tasks.map(ExportTaskDTO.init(task:)),
            settings: ExportSettingsDTO(settings: persistence.settings()),
            history: history.map(HistoryEventDTO.init(event:))
        )
    }

    /// 导出全部数据为 JSON
    public func exportAll() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(try bundle())
    }

    /// 保存面板导出（应用内使用）
    public static func savePanelExport(persistence: PersistenceService, clock: ClockProviding = SystemClock()) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "FrostTodoExport.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let service = ExportService(persistence: persistence, clock: clock)
        do {
            try service.exportAll().write(to: url)
        } catch {
            // 写盘失败时保持应用可用；错误信息不包含敏感路径
        }
    }
}
