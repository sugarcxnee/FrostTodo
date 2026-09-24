import Foundation
import SwiftData

/// 历史写入错误
public enum HistoryWriteError: Error, Equatable {
    case writeFailed
    case payloadEncodingFailed
}

/// 历史导出 DTO（ISO8601 时间）
public struct HistoryEventDTO: Codable, Equatable {
    public var id: UUID
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

    public init(event: HistoryEvent) {
        id = event.id
        type = event.type
        taskID = event.taskID
        sessionID = event.sessionID
        calendarEventID = event.calendarEventID
        title = event.title
        detail = event.detail
        payloadJSON = event.payloadJSON
        createdAt = event.createdAt
        source = event.source
        isUndoable = event.isUndoable
    }
}

/// 历史查询筛选条件
public struct HistoryFilter {
    /// 为空表示全部类型
    public var types: Set<HistoryEventType>
    public var taskID: UUID?
    /// 标题与详情的大小写不敏感搜索
    public var searchText: String
    public var dateRange: ClosedRange<Date>?
    /// 匹配任务事件 payload 中的 tags
    public var tag: String?
    /// 匹配任务事件 payload 中的 project
    public var project: String?
    public var limit: Int?
    /// 默认按时间倒序（最新在前）
    public var ascending: Bool

    public init(
        types: Set<HistoryEventType> = [],
        taskID: UUID? = nil,
        searchText: String = "",
        dateRange: ClosedRange<Date>? = nil,
        tag: String? = nil,
        project: String? = nil,
        limit: Int? = nil,
        ascending: Bool = false
    ) {
        self.types = types
        self.taskID = taskID
        self.searchText = searchText
        self.dateRange = dateRange
        self.tag = tag
        self.project = project
        self.limit = limit
        self.ascending = ascending
    }
}

/// 历史服务：统一的历史写入、查询、筛选、导出与清理。
///
/// 事务约定：record 只写入上下文不保存，由业务服务在同一逻辑单元内
/// 统一调用 save；保存失败由业务方 rollback，实现“操作与历史同生共死”。
@MainActor
public final class HistoryService: HistoryRecording {
    private let persistence: PersistenceService
    private let clock: ClockProviding
    /// 同一服务实例内保证时间戳严格递增（+1ms），使同批写入顺序稳定
    private var lastCreatedAt: Date?

    public init(persistence: PersistenceService, clock: ClockProviding = SystemClock()) {
        self.persistence = persistence
        self.clock = clock
        self.lastCreatedAt = (try? persistence.fetch(FetchDescriptor<HistoryEvent>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )))?.first?.createdAt
    }

    // MARK: - HistoryRecording

    public func record(_ input: HistoryEventInput) throws {
        let payloadJSON: String?
        if input.payload.isEmpty {
            payloadJSON = nil
        } else {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            guard let data = try? encoder.encode(input.payload),
                  let json = String(data: data, encoding: .utf8) else {
                throw HistoryWriteError.payloadEncodingFailed
            }
            payloadJSON = json
        }

        let base = input.createdAt ?? clock.now
        let createdAt: Date
        if let last = lastCreatedAt, base <= last {
            createdAt = last.addingTimeInterval(0.001)
        } else {
            createdAt = base
        }
        lastCreatedAt = createdAt

        let event = HistoryEvent(
            type: input.type.rawValue,
            taskID: input.taskID,
            sessionID: input.sessionID,
            calendarEventID: input.calendarEventID,
            title: input.title,
            detail: input.detail,
            payloadJSON: payloadJSON,
            createdAt: createdAt,
            source: input.source.rawValue,
            isUndoable: input.isUndoable
        )
        persistence.insert(event)
    }

    // MARK: - 查询

    public func events(matching filter: HistoryFilter) throws -> [HistoryEvent] {
        var descriptor = FetchDescriptor<HistoryEvent>()
        switch (filter.taskID, filter.dateRange) {
        case (nil, nil):
            break
        case (.some(let id), nil):
            descriptor.predicate = #Predicate { $0.taskID == id }
        case (nil, .some(let range)):
            let lower = range.lowerBound
            let upper = range.upperBound
            descriptor.predicate = #Predicate { $0.createdAt >= lower && $0.createdAt <= upper }
        case (.some(let id), .some(let range)):
            let lower = range.lowerBound
            let upper = range.upperBound
            descriptor.predicate = #Predicate {
                $0.taskID == id && $0.createdAt >= lower && $0.createdAt <= upper
            }
        }
        descriptor.sortBy = [SortDescriptor(\.createdAt, order: filter.ascending ? .forward : .reverse)]

        var events = try persistence.fetch(descriptor)

        if !filter.types.isEmpty {
            events = events.filter { event in
                event.typeValue.map { filter.types.contains($0) } ?? false
            }
        }
        if !filter.searchText.isEmpty {
            let text = filter.searchText
            events = events.filter { event in
                event.title.localizedCaseInsensitiveContains(text)
                    || (event.detail?.localizedCaseInsensitiveContains(text) ?? false)
            }
        }
        if let tag = filter.tag {
            events = events.filter { event in
                event.payload["tags"]?
                    .split(separator: ",")
                    .contains(Substring(tag)) == true
            }
        }
        if let project = filter.project {
            events = events.filter { $0.payload["project"] == project }
        }
        if let limit = filter.limit {
            events = Array(events.prefix(limit))
        }
        return events
    }

    /// 全部历史数量
    public func totalCount() throws -> Int {
        try persistence.fetchCount(FetchDescriptor<HistoryEvent>())
    }

    // MARK: - 清理

    /// 清空全部历史，仅保留一条“历史已清空”记录
    public func clearAll() throws {
        _ = try persistence.deleteAll(HistoryEvent.self)
        try record(HistoryEventInput(
            type: .historyCleared, title: "历史已清空", source: .system
        ))
        try persistence.save()
    }

    /// 按设置应用保留策略，返回清理条数并写入清理记录
    @discardableResult
    public func applyRetentionPolicy(_ settings: AppSettings) throws -> Int {
        let pruned: Int
        switch settings.historyRetentionPolicyValue {
        case .forever:
            return 0
        case .byDays:
            let cutoff = clock.now.addingTimeInterval(-Double(settings.historyRetentionDays) * 86_400)
            let descriptor = FetchDescriptor<HistoryEvent>(predicate: #Predicate { $0.createdAt < cutoff })
            let stale = try persistence.fetch(descriptor)
            for event in stale {
                persistence.delete(event)
            }
            pruned = stale.count
        case .byCount:
            let keep = settings.historyRetentionCount
            let all = try persistence.fetch(FetchDescriptor<HistoryEvent>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            ))
            let stale = Array(all.dropFirst(keep))
            for event in stale {
                persistence.delete(event)
            }
            pruned = stale.count
        }

        if pruned > 0 {
            try record(HistoryEventInput(
                type: .historyPruned, title: "历史清理",
                detail: "按保留策略清理了 \(pruned) 条记录", source: .system
            ))
            try persistence.save()
        }
        return pruned
    }

    // MARK: - 导出

    public func exportJSON(matching filter: HistoryFilter) throws -> Data {
        let events = try self.events(matching: filter)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(events.map(HistoryEventDTO.init(event:)))
    }

    public func exportCSV(matching filter: HistoryFilter) throws -> String {
        let events = try self.events(matching: filter)
        let formatter = ISO8601DateFormatter()
        let header = "id,type,taskID,sessionID,calendarEventID,createdAt,source,title,detail"
        let rows = events.map { event -> String in
            let fields: [String] = [
                event.id.uuidString,
                event.type,
                event.taskID?.uuidString ?? "",
                event.sessionID?.uuidString ?? "",
                event.calendarEventID ?? "",
                formatter.string(from: event.createdAt),
                event.source,
                event.title,
                event.detail ?? "",
            ]
            return fields.map(Self.csvEscape).joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    private static func csvEscape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}

// MARK: - 便捷扩展

extension HistoryEvent {
    /// 解析 payloadJSON 为键值对
    public var payload: [String: String] {
        guard let payloadJSON,
              let data = payloadJSON.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }
}

extension Array where Element == HistoryEvent {
    /// 按天分组（保持输入顺序内的事件次序），返回 [(当天起点, 当天事件)]
    public func groupedByDay(calendar: Calendar = .current) -> [(day: Date, events: [HistoryEvent])] {
        var order: [Date] = []
        var buckets: [Date: [HistoryEvent]] = [:]
        for event in self {
            let day = calendar.startOfDay(for: event.createdAt)
            if buckets[day] == nil {
                order.append(day)
            }
            buckets[day, default: []].append(event)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }
}
