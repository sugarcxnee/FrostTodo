import Testing
import Foundation
@testable import FrostTodo

@MainActor
@Suite("Phase 3: HistoryService 查询与筛选")
struct Phase3HistoryServiceTests {

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeService() throws -> (HistoryService, PersistenceService, ManualClock) {
        let clock = ManualClock(epoch)
        let persistence = try PersistenceService(inMemory: true)
        let service = HistoryService(persistence: persistence, clock: clock)
        return (service, persistence, clock)
    }

    private func seed(_ history: HistoryService, _ types: [HistoryEventType]) throws {
        for type in types {
            try history.record(HistoryEventInput(
                type: type, title: "事件 \(type.rawValue)",
                detail: "详情 \(type.rawValue)", source: .user
            ))
        }
    }

    @Test("写入单条历史：字段正确且 payload 序列化")
    func recordSingleEventFields() throws {
        let (history, persistence, clock) = try makeService()
        let taskID = UUID()
        let sessionID = UUID()
        try history.record(HistoryEventInput(
            type: .timerStarted, taskID: taskID, sessionID: sessionID,
            title: "开始计时：写报告", detail: "来自测试",
            payload: ["taskTitle": "写报告", "duration": "0"], source: .user
        ))
        try persistence.save()

        let events = try history.events(matching: HistoryFilter())
        #expect(events.count == 1)
        let event = try #require(events.first)
        #expect(event.typeValue == .timerStarted)
        #expect(event.taskID == taskID)
        #expect(event.sessionID == sessionID)
        #expect(event.title == "开始计时：写报告")
        #expect(event.detail == "来自测试")
        #expect(event.createdAt == clock.now)
        #expect(event.sourceValue == .user)
        #expect(event.payload["taskTitle"] == "写报告")
        #expect(event.payload["duration"] == "0")
    }

    @Test("批量写入后默认按时间倒序，正序参数生效")
    func batchOrderAndSortDirection() throws {
        let (history, _, clock) = try makeService()
        try seed(history, [.taskCreated, .taskUpdated, .taskCompleted])

        let descending = try history.events(matching: HistoryFilter())
        #expect(descending.map(\.typeValue) == [.taskCompleted, .taskUpdated, .taskCreated])

        clock.advance(by: 1) // 确保后续写入时间严格递增
        let ascending = try history.events(matching: HistoryFilter(ascending: true))
        #expect(ascending.map(\.typeValue) == [.taskCreated, .taskUpdated, .taskCompleted])
    }

    @Test("按类型筛选")
    func filterByType() throws {
        let (history, _, _) = try makeService()
        try seed(history, [.taskCreated, .taskUpdated, .taskCompleted, .timerStarted, .timerPaused])

        let result = try history.events(matching: HistoryFilter(types: [.taskCreated, .taskCompleted]))
        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.typeValue == .taskCreated || $0.typeValue == .taskCompleted })
    }

    @Test("按任务筛选")
    func filterByTask() throws {
        let (history, _, _) = try makeService()
        let taskA = UUID()
        let taskB = UUID()
        try history.record(HistoryEventInput(type: .taskCreated, taskID: taskA, title: "A 创建"))
        try history.record(HistoryEventInput(type: .taskCreated, taskID: taskB, title: "B 创建"))
        try history.record(HistoryEventInput(type: .taskCompleted, taskID: taskA, title: "A 完成"))

        let result = try history.events(matching: HistoryFilter(taskID: taskA))
        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.taskID == taskA })
    }

    @Test("按日期范围筛选（闭区间）")
    func filterByDateRange() throws {
        let (history, persistence, clock) = try makeService()
        try history.record(HistoryEventInput(type: .taskCreated, title: "第一天"))
        clock.advance(by: 86_400)
        try history.record(HistoryEventInput(type: .taskUpdated, title: "第二天"))
        clock.advance(by: 86_400)
        try history.record(HistoryEventInput(type: .taskCompleted, title: "第三天"))
        try persistence.save()

        let range = epoch.addingTimeInterval(86_400)...epoch.addingTimeInterval(86_400 + 3_600)
        let result = try history.events(matching: HistoryFilter(dateRange: range))
        #expect(result.count == 1)
        #expect(result.first?.title == "第二天")

        // 边界值包含
        let edge = epoch...epoch
        let edgeResult = try history.events(matching: HistoryFilter(dateRange: edge))
        #expect(edgeResult.count == 1)
        #expect(edgeResult.first?.title == "第一天")
    }

    @Test("搜索标题与详情，大小写不敏感")
    func searchTitleAndDetail() throws {
        let (history, _, _) = try makeService()
        try history.record(HistoryEventInput(type: .taskCreated, title: "Write Report", detail: "工作内容"))
        try history.record(HistoryEventInput(type: .timerStarted, title: "开始计时", detail: "WRITE REPORT session"))

        let byTitle = try history.events(matching: HistoryFilter(searchText: "report"))
        #expect(byTitle.count == 2)

        let byDetail = try history.events(matching: HistoryFilter(searchText: "工作"))
        #expect(byDetail.count == 1)
        #expect(byDetail.first?.title == "Write Report")
    }

    @Test("limit 限制返回条数（倒序下保留最新）")
    func limitKeepsNewest() throws {
        let (history, _, clock) = try makeService()
        for index in 0..<10 {
            clock.advance(by: 10)
            try history.record(HistoryEventInput(type: .taskCreated, title: "事件 \(index)"))
        }
        let result = try history.events(matching: HistoryFilter(limit: 3))
        #expect(result.count == 3)
        #expect(result.map(\.title) == ["事件 9", "事件 8", "事件 7"])
    }

    @Test("清空历史后仅保留一条 history.cleared 记录")
    func clearAllKeepsMarker() throws {
        let (history, _, _) = try makeService()
        try seed(history, [.taskCreated, .timerStarted, .settingsChanged])
        #expect(try history.events(matching: HistoryFilter()).count == 3)

        try history.clearAll()

        let remaining = try history.events(matching: HistoryFilter())
        #expect(remaining.count == 1)
        #expect(remaining.first?.typeValue == .historyCleared)
    }

    @Test("按标签与项目筛选：命中任务事件 payload")
    func filterByTagAndProject() throws {
        let (history, _, _) = try makeService()
        try history.record(HistoryEventInput(
            type: .taskCreated, title: "带标签任务",
            payload: ["tags": "工作,写作", "project": "FrostTodo"]
        ))
        try history.record(HistoryEventInput(
            type: .taskCreated, title: "无标签任务", payload: [:]
        ))
        try history.record(HistoryEventInput(
            type: .timerStarted, title: "计时事件", payload: [:]
        ))

        let byTag = try history.events(matching: HistoryFilter(tag: "写作"))
        #expect(byTag.count == 1)
        #expect(byTag.first?.title == "带标签任务")

        let byProject = try history.events(matching: HistoryFilter(project: "FrostTodo"))
        #expect(byProject.count == 1)
        #expect(byProject.first?.title == "带标签任务")
    }

    @Test("空历史查询不崩溃且返回空")
    func emptyHistorySafe() throws {
        let (history, _, _) = try makeService()
        #expect(try history.events(matching: HistoryFilter()).isEmpty)
        #expect(try history.events(matching: HistoryFilter(searchText: "任意")).isEmpty)
        #expect(try history.exportJSON(matching: HistoryFilter()).count > 0) // 空数组 JSON
    }

    @Test("组合筛选：类型 + 任务 + 搜索")
    func combinedFilter() throws {
        let (history, _, _) = try makeService()
        let taskA = UUID()
        try history.record(HistoryEventInput(type: .taskCreated, taskID: taskA, title: "创建报告任务"))
        try history.record(HistoryEventInput(type: .taskUpdated, taskID: taskA, title: "更新报告任务"))
        try history.record(HistoryEventInput(type: .taskCreated, taskID: taskA, title: "创建其他任务"))

        let result = try history.events(matching: HistoryFilter(
            types: [.taskCreated], taskID: taskA, searchText: "报告"
        ))
        #expect(result.count == 1)
        #expect(result.first?.title == "创建报告任务")
    }

    @Test("大数据量下筛选与排序性能可接受")
    func largeDatasetPerformance() throws {
        let (history, persistence, clock) = try makeService()
        for index in 0..<1_500 {
            clock.advance(by: 1)
            try history.record(HistoryEventInput(
                type: index % 2 == 0 ? .taskCreated : .timerStarted,
                title: "批量事件 \(index % 100)"
            ))
        }
        try persistence.save()

        let start = DispatchTime.now()
        let result = try history.events(matching: HistoryFilter(
            types: [.taskCreated], searchText: "批量事件", limit: 50
        ))
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
        #expect(result.count == 50)
        #expect(elapsed < 2.0, "筛选耗时 \(elapsed) 秒，超过阈值")
    }

    @Test("时区变化后按天分组正确")
    func dayGroupingAcrossTimeZones() throws {
        let (history, _, _) = try makeService()
        // 上海时间 2026-09-25 00:30（UTC 时间为 09-24 16:30）
        var shanghaiComponents = DateComponents()
        shanghaiComponents.year = 2026; shanghaiComponents.month = 9; shanghaiComponents.day = 25
        shanghaiComponents.hour = 0; shanghaiComponents.minute = 30
        var shanghaiCalendar = Calendar(identifier: .gregorian)
        shanghaiCalendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let date = shanghaiCalendar.date(from: shanghaiComponents)!

        try history.record(HistoryEventInput(type: .taskCreated, title: "跨时区事件", createdAt: date))

        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        let utcGroups = try history.events(matching: HistoryFilter()).groupedByDay(calendar: utcCalendar)
        #expect(utcGroups.count == 1)
        #expect(utcCalendar.component(.day, from: utcGroups[0].day) == 24)

        let shanghaiGroups = try history.events(matching: HistoryFilter()).groupedByDay(calendar: shanghaiCalendar)
        #expect(shanghaiGroups.count == 1)
        #expect(shanghaiCalendar.component(.day, from: shanghaiGroups[0].day) == 25)
    }

    @Test("按天分组：多天事件各自成组且组内倒序")
    func groupByDayMultipleDays() throws {
        let (history, _, clock) = try makeService()
        try history.record(HistoryEventInput(type: .taskCreated, title: "第一天事件 A"))
        clock.advance(by: 3_600)
        try history.record(HistoryEventInput(type: .taskCreated, title: "第一天事件 B"))
        clock.advance(by: 86_400)
        try history.record(HistoryEventInput(type: .taskCreated, title: "第二天事件"))

        let groups = try history.events(matching: HistoryFilter(ascending: true)).groupedByDay()
        #expect(groups.count == 2)
        #expect(groups[0].events.count == 2)
        #expect(groups[0].events.map(\.title) == ["第一天事件 A", "第一天事件 B"])
        #expect(groups[1].events.count == 1)
    }
}
