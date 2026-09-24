import Foundation
import EventKit

/// EventKit 日历提供方：包装 EKEventStore。
/// EKEventStore 非 Sendable，本类型仅在主线程使用。
@MainActor
public final class EventKitCalendarProvider: CalendarProviding {
    private let store = EKEventStore()
    /// 专用日历名称
    public static let dedicatedCalendarName = "FrostTodo"

    public init() {}

    // MARK: - 权限

    public func authorizationStatus() -> CalendarAccessStatus {
        CalendarAccessStatus.from(EKEventStore.authorizationStatus(for: .event))
    }

    public func requestAccess() async -> Bool {
        let status = authorizationStatus()
        if status == .granted { return true }
        guard status == .notDetermined else { return false }
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    // MARK: - 日历

    public func availableCalendars() -> [CalendarInfo] {
        guard authorizationStatus() == .granted else { return [] }
        return store.calendars(for: .event)
            .map { calendar in
                CalendarInfo(
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    isWritable: calendar.allowsContentModifications
                )
            }
    }

    public func createCalendar(named name: String) throws -> String {
        guard authorizationStatus() == .granted else {
            throw CalendarError.accessDenied
        }
        // 已存在同名日历则复用
        if let existing = store.calendars(for: .event).first(where: { $0.title == name }) {
            return existing.calendarIdentifier
        }
        // 优先本地 Source，其次任意可创建日历的 Source（生日等只读 Source 除外）
        let candidates = store.sources.filter { $0.sourceType != .birthdays }
        let source = candidates.first { $0.sourceType == .local } ?? candidates.first
        guard let source else {
            throw CalendarError.noWritableCalendar
        }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = name
        calendar.source = source
        do {
            try store.saveCalendar(calendar, commit: true)
        } catch {
            throw CalendarError.saveFailed(error.localizedDescription)
        }
        return calendar.calendarIdentifier
    }

    private func writableCalendar(id: String) throws -> EKCalendar {
        guard let calendar = store.calendar(withIdentifier: id) else {
            throw CalendarError.eventNotFound(id)
        }
        return calendar
    }

    // MARK: - 事件

    public func createEvent(_ draft: CalendarEventDraft) throws -> String {
        guard authorizationStatus() == .granted else {
            throw CalendarError.accessDenied
        }
        let calendar = try writableCalendar(id: draft.calendarID)
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = draft.title
        event.startDate = draft.startDate
        event.endDate = draft.endDate
        event.notes = draft.notes
        event.url = draft.url
        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            throw CalendarError.saveFailed(error.localizedDescription)
        }
        return event.eventIdentifier
    }

    public func updateEvent(id: String, newTitle: String?, newEndDate: Date?, newNotes: String?) throws {
        guard let event = store.event(withIdentifier: id) else {
            throw CalendarError.eventNotFound(id)
        }
        if let newTitle { event.title = newTitle }
        if let newEndDate { event.endDate = newEndDate }
        if let newNotes { event.notes = newNotes }
        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            throw CalendarError.saveFailed(error.localizedDescription)
        }
    }

    public func deleteEvent(id: String) throws {
        guard let event = store.event(withIdentifier: id) else {
            throw CalendarError.eventNotFound(id)
        }
        do {
            try store.remove(event, span: .thisEvent, commit: true)
        } catch {
            throw CalendarError.saveFailed(error.localizedDescription)
        }
    }

    public func eventExists(id: String) -> Bool {
        store.event(withIdentifier: id) != nil
    }

    public func fetchEvents(on date: Date) -> [CalendarEventInfo] {
        guard authorizationStatus() == .granted || authorizationStatus() == .writeOnly else { return [] }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map { event in
            CalendarEventInfo(
                id: event.eventIdentifier ?? "",
                title: event.title ?? "",
                startDate: event.startDate,
                endDate: event.endDate,
                isAllDay: event.isAllDay,
                notes: event.notes,
                url: event.url
            )
        }
    }
}
