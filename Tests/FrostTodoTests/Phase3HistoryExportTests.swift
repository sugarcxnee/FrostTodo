import Testing
import Foundation
@testable import FrostTodo

@MainActor
@Suite("Phase 3: 历史导出与保留策略")
struct Phase3HistoryExportTests {

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeService() throws -> (HistoryService, PersistenceService, ManualClock) {
        let clock = ManualClock(epoch)
        let persistence = try PersistenceService(inMemory: true)
        let service = HistoryService(persistence: persistence, clock: clock)
        return (service, persistence, clock)
    }

    private func seedHistory(_ history: HistoryService, _ clock: ManualClock) throws -> (UUID, UUID) {
        let taskID = UUID()
        let sessionID = UUID()
        try history.record(HistoryEventInput(
            type: .taskCreated, taskID: taskID,
            title: "创建任务：导出验证", detail: nil,
            payload: ["tags": "工作"], source: .user
        ))
        clock.advance(by: 60)
        try history.record(HistoryEventInput(
            type: .sessionEnded, taskID: taskID, sessionID: sessionID,
            title: "时间段结束", detail: "时长 60 秒, 含逗号与\"引号\"", source: .system
        ))
        return (taskID, sessionID)
    }

    @Test("JSON 导出结构与字段完整")
    func jsonExportStructure() throws {
        let (history, persistence, clock) = try makeService()
        let (taskID, sessionID) = try seedHistory(history, clock)
        try persistence.save()

        let data = try history.exportJSON(matching: HistoryFilter(ascending: true))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([HistoryEventDTO].self, from: data)
        #expect(decoded.count == 2)

        let first = try #require(decoded.first)
        #expect(first.id != UUID())
        #expect(first.type == HistoryEventType.taskCreated.rawValue)
        #expect(first.taskID == taskID)
        #expect(first.title == "创建任务：导出验证")
        #expect(first.source == HistorySource.user.rawValue)

        let second = try #require(decoded.last)
        #expect(second.sessionID == sessionID)
        #expect(second.type == HistoryEventType.sessionEnded.rawValue)
        #expect(second.source == HistorySource.system.rawValue)
    }

    @Test("JSON 导出往返一致：解码后关键字段与模型一致")
    func jsonRoundTripConsistency() throws {
        let (history, persistence, clock) = try makeService()
        _ = try seedHistory(history, clock)
        try persistence.save()

        let originals = try history.events(matching: HistoryFilter(ascending: true))
        let data = try history.exportJSON(matching: HistoryFilter(ascending: true))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([HistoryEventDTO].self, from: data)

        #expect(decoded.count == originals.count)
        for (dto, model) in zip(decoded, originals) {
            #expect(dto.id == model.id)
            #expect(dto.type == model.type)
            #expect(dto.taskID == model.taskID)
            #expect(dto.sessionID == model.sessionID)
            #expect(dto.title == model.title)
            #expect(dto.detail == model.detail)
            #expect(dto.createdAt == model.createdAt)
            #expect(dto.source == model.source)
        }
    }

    @Test("CSV 导出：表头、行数、转义与换行")
    func csvExport() throws {
        let (history, persistence, clock) = try makeService()
        _ = try seedHistory(history, clock)
        try persistence.save()

        let csv = try history.exportCSV(matching: HistoryFilter(ascending: true))
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        #expect(lines.count == 3) // 表头 + 2 行

        let header = try #require(lines.first)
        #expect(header.contains("id"))
        #expect(header.contains("type"))
        #expect(header.contains("taskID"))
        #expect(header.contains("createdAt"))
        #expect(header.contains("title"))

        let detailRow = try #require(lines.last)
        #expect(detailRow.contains("\"时长 60 秒, 含逗号与\"\"引号\"\"\""))
    }

    @Test("按条数保留策略：清理旧记录并写入 history.pruned")
    func retentionByCount() throws {
        let (history, persistence, clock) = try makeService()
        for index in 0..<10 {
            clock.advance(by: 10)
            try history.record(HistoryEventInput(type: .taskCreated, title: "事件 \(index)"))
        }
        try persistence.save()

        var settings = persistence.settings()
        settings.historyRetentionPolicyValue = .byCount
        settings.historyRetentionCount = 3
        clock.advance(by: 1) // 确保清理记录时间戳晚于被保留的记录
        let pruned = try history.applyRetentionPolicy(settings)
        #expect(pruned == 7)

        let events = try history.events(matching: HistoryFilter())
        // 保留最新 3 条 + 1 条清理记录
        #expect(events.count == 4)
        #expect(events.first?.typeValue == .historyPruned)
        let kept = events.dropFirst()
        #expect(kept.allSatisfy { $0.title.contains("事件") })
        #expect(kept.map(\.title).contains("事件 9"))
        #expect(!kept.map(\.title).contains("事件 0"))
    }

    @Test("按天数保留策略：清理截止日期之前的记录")
    func retentionByDays() throws {
        let (history, persistence, clock) = try makeService()
        // 30 天前的事件与今天的事件
        try history.record(HistoryEventInput(
            type: .taskCreated, title: "旧事件",
            createdAt: clock.now.addingTimeInterval(-30 * 86_400)
        ))
        try history.record(HistoryEventInput(type: .taskCreated, title: "新事件"))
        try persistence.save()

        var settings = persistence.settings()
        settings.historyRetentionPolicyValue = .byDays
        settings.historyRetentionDays = 7
        let pruned = try history.applyRetentionPolicy(settings)
        #expect(pruned == 1)

        let titles = try history.events(matching: HistoryFilter()).map(\.title)
        #expect(!titles.contains("旧事件"))
        #expect(titles.contains("新事件"))
        #expect(titles.contains(where: { $0.contains("清理") }))
    }

    @Test("永久保留策略：不清理")
    func retentionForeverKeepsAll() throws {
        let (history, persistence, clock) = try makeService()
        for index in 0..<5 {
            clock.advance(by: 86_400)
            try history.record(HistoryEventInput(type: .taskCreated, title: "事件 \(index)"))
        }
        try persistence.save()

        let settings = persistence.settings() // 默认 forever
        let pruned = try history.applyRetentionPolicy(settings)
        #expect(pruned == 0)
        #expect(try history.events(matching: HistoryFilter()).count == 5)
    }
}
