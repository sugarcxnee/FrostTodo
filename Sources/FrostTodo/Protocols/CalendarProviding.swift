import Foundation
import EventKit

/// 应用内部的日历访问状态
public enum CalendarAccessStatus: Equatable {
    case notDetermined
    /// 完整访问（可读写）
    case granted
    case writeOnly
    case denied
    case restricted

    /// EventKit 权限映射
    public static func from(_ status: EKAuthorizationStatus) -> CalendarAccessStatus {
        switch status {
        case .notDetermined: return .notDetermined
        case .fullAccess: return .granted
        case .writeOnly: return .writeOnly
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .denied
        }
    }
}

/// 日历信息
public struct CalendarInfo: Equatable, Identifiable {
    public var id: String
    public var title: String
    public var isWritable: Bool

    public init(id: String, title: String, isWritable: Bool) {
        self.id = id
        self.title = title
        self.isWritable = isWritable
    }
}

/// 日历事件信息（读取展示用）
public struct CalendarEventInfo: Equatable, Identifiable {
    public var id: String
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var isAllDay: Bool
    public var notes: String?
    public var url: URL?

    public init(
        id: String, title: String, startDate: Date, endDate: Date,
        isAllDay: Bool, notes: String?, url: URL?
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.notes = notes
        self.url = url
    }
}

/// 待创建的日历事件草稿
public struct CalendarEventDraft {
    public var calendarID: String
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var notes: String
    public var url: URL
    /// 测试 Mock 生成的稳定事件 ID
    public var storedID: String

    public init(
        calendarID: String, title: String, startDate: Date, endDate: Date,
        notes: String, url: URL, storedID: String = ""
    ) {
        self.calendarID = calendarID
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.notes = notes
        self.url = url
        self.storedID = storedID
    }
}

/// 日历操作错误
public enum CalendarError: Error, Equatable {
    case accessDenied
    case noWritableCalendar
    case eventNotFound(String)
    case saveFailed(String)
}

/// 日历提供方抽象：生产环境包装 EKEventStore，测试使用 Mock
public protocol CalendarProviding: AnyObject {
    func authorizationStatus() -> CalendarAccessStatus
    func requestAccess() async -> Bool
    func availableCalendars() -> [CalendarInfo]
    /// 创建专用日历并返回其 ID
    func createCalendar(named name: String) throws -> String
    /// 创建事件，返回事件 ID
    func createEvent(_ draft: CalendarEventDraft) throws -> String
    func updateEvent(id: String, newTitle: String?, newEndDate: Date?, newNotes: String?) throws
    func deleteEvent(id: String) throws
    func eventExists(id: String) -> Bool
    func fetchEvents(on date: Date) -> [CalendarEventInfo]
}

/// 任务回跳链接：frosttodo://task/<taskID>
public enum TaskLink {
    public static func url(for taskID: UUID) -> URL {
        URL(string: "frosttodo://task/\(taskID.uuidString)")!
    }

    public static func taskID(from url: URL) -> UUID? {
        guard url.scheme == "frosttodo",
              url.host == "task",
              let last = url.lastPathComponent.split(separator: "/").last,
              let id = UUID(uuidString: String(last)) else {
            return nil
        }
        return id
    }
}
