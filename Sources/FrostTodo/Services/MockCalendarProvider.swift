import Foundation

/// Mock 日历提供方：测试与 SwiftUI 预览使用，完全离线
public final class MockCalendarProvider: CalendarProviding {
    /// Mock 存储中的事件
    public final class MockEvent {
        public var title: String
        public var startDate: Date
        public var endDate: Date
        public var notes: String
        public var url: URL

        init(draft: CalendarEventDraft) {
            title = draft.title
            startDate = draft.startDate
            endDate = draft.endDate
            notes = draft.notes
            url = draft.url
        }
    }

    public var status: CalendarAccessStatus = .granted
    public var calendars: [CalendarInfo] = [
        CalendarInfo(id: "CAL-DEFAULT", title: "默认日历", isWritable: true)
    ]
    public var events: [String: MockEvent] = [:]
    public var todayEvents: [CalendarEventInfo] = []

    /// 记录创建过的事件草稿（含生成的 storedID）
    public private(set) var createdDrafts: [CalendarEventDraft] = []
    public private(set) var createdCalendarNames: [String] = []
    public private(set) var lastCreatedCalendarID: String?
    public private(set) var updatedEventIDs: [String] = []
    public private(set) var deletedEventIDs: [String] = []

    /// 下一次 createEvent 抛错（模拟同步失败）
    public var failNextCreate = false
    /// createCalendar 抛错（模拟无可写日历）
    public var createCalendarThrows = false

    private var nextEventNumber = 0
    private var nextCalendarNumber = 0

    public init() {}

    public func authorizationStatus() -> CalendarAccessStatus { status }

    public func requestAccess() async -> Bool { status == .granted }

    public func availableCalendars() -> [CalendarInfo] {
        guard status == .granted else { return [] }
        return calendars
    }

    public func createCalendar(named name: String) throws -> String {
        if createCalendarThrows {
            throw CalendarError.noWritableCalendar
        }
        nextCalendarNumber += 1
        let id = "CAL-MOCK-\(nextCalendarNumber)"
        calendars.append(CalendarInfo(id: id, title: name, isWritable: true))
        createdCalendarNames.append(name)
        lastCreatedCalendarID = id
        return id
    }

    public func createEvent(_ draft: CalendarEventDraft) throws -> String {
        if failNextCreate {
            failNextCreate = false
            throw CalendarError.saveFailed("模拟创建失败")
        }
        nextEventNumber += 1
        let id = "EVT-\(nextEventNumber)"
        var stored = draft
        stored.storedID = id
        createdDrafts.append(stored)
        events[id] = MockEvent(draft: stored)
        return id
    }

    public func updateEvent(id: String, newTitle: String?, newEndDate: Date?, newNotes: String?) throws {
        guard let event = events[id] else {
            throw CalendarError.eventNotFound(id)
        }
        if let newTitle { event.title = newTitle }
        if let newEndDate { event.endDate = newEndDate }
        if let newNotes { event.notes = newNotes }
        updatedEventIDs.append(id)
    }

    public func deleteEvent(id: String) throws {
        guard events[id] != nil else {
            throw CalendarError.eventNotFound(id)
        }
        events.removeValue(forKey: id)
        deletedEventIDs.append(id)
    }

    public func eventExists(id: String) -> Bool {
        events[id] != nil
    }

    public func fetchEvents(on date: Date) -> [CalendarEventInfo] {
        todayEvents
    }
}
