import Foundation
import SwiftData

/// 任务状态：进行中 / 已完成
public enum TaskStatus: String, Codable, CaseIterable {
    case active
    case completed
}

/// 任务优先级：无、低、中、高
public enum TaskPriority: Int, Codable, CaseIterable, Comparable {
    case none = 0
    case low = 1
    case medium = 2
    case high = 3

    public static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var label: String {
        switch self {
        case .none: return "无优先级"
        case .low: return "低"
        case .medium: return "中"
        case .high: return "高"
        }
    }
}

/// 任务模型
@Model
public final class TodoTask {
    @Attribute(.unique) public var id: UUID
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
    @Relationship(deleteRule: .cascade, inverse: \TimeSession.task)
    public var sessions: [TimeSession]

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        dueDate: Date? = nil,
        startDate: Date? = nil,
        estimatedMinutes: Int? = nil,
        priority: Int = TaskPriority.none.rawValue,
        tags: [String] = [],
        projectName: String? = nil,
        status: String = TaskStatus.active.rawValue,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        calendarEventIDs: [String] = []
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.startDate = startDate
        self.estimatedMinutes = estimatedMinutes
        self.priority = priority
        self.tags = tags
        self.projectName = projectName
        self.status = status
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.calendarEventIDs = calendarEventIDs
        self.sessions = []
    }

    public var statusValue: TaskStatus {
        get { TaskStatus(rawValue: status) ?? .active }
        set { status = newValue.rawValue }
    }

    public var priorityValue: TaskPriority {
        get { TaskPriority(rawValue: priority) ?? .none }
        set { priority = newValue.rawValue }
    }

    public var isCompleted: Bool { statusValue == .completed }

    /// 标记完成（幂等），并写入完成时间
    public func complete(at date: Date) {
        guard statusValue != .completed else { return }
        statusValue = .completed
        completedAt = date
    }

    /// 取消完成（幂等），清空完成时间
    public func uncomplete() {
        guard statusValue == .completed else { return }
        statusValue = .active
        completedAt = nil
    }

    /// 全部 Session 的累计实际时长（秒）
    public var totalAccumulatedSeconds: Int {
        sessions.reduce(0) { $0 + $1.durationSeconds }
    }
}
