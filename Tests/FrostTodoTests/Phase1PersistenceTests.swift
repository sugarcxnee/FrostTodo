import Testing
import Foundation
import SwiftData
@testable import FrostTodo

@MainActor
@Suite("Phase 1: 持久化服务")
struct Phase1PersistenceTests {

    @Test("内存容器初始化成功且包含全部模型")
    func inMemoryContainerContainsAllModels() throws {
        let service = try PersistenceService(inMemory: true)
        #expect(try service.fetch(FetchDescriptor<TodoTask>()).isEmpty)
        #expect(try service.fetch(FetchDescriptor<TimeSession>()).isEmpty)
        #expect(try service.fetch(FetchDescriptor<HistoryEvent>()).isEmpty)
        #expect(try service.fetch(FetchDescriptor<AppSettings>()).isEmpty)
        #expect(try service.fetch(FetchDescriptor<TimerSnapshot>()).isEmpty)
    }

    @Test("插入、保存、按标题查询、删除任务")
    func insertFetchDeleteTask() throws {
        let service = try PersistenceService(inMemory: true)
        let task = TodoTask(title: "待删除任务")
        service.insert(task)
        try service.save()

        var fetched = try service.fetch(FetchDescriptor<TodoTask>(predicate: #Predicate { $0.title == "待删除任务" }))
        #expect(fetched.count == 1)

        service.delete(fetched[0])
        try service.save()
        fetched = try service.fetch(FetchDescriptor<TodoTask>(predicate: #Predicate { $0.title == "待删除任务" }))
        #expect(fetched.isEmpty)
    }

    @Test("settings 单例：首次创建，之后返回同一实例")
    func settingsSingleton() throws {
        let service = try PersistenceService(inMemory: true)
        let first = service.settings()
        try service.save()
        let second = service.settings()
        #expect(first === second)
        #expect(try service.fetch(FetchDescriptor<AppSettings>()).count == 1)
    }

    @Test("数据在容器内跨 context 可见（持久化生效）")
    func dataVisibleAcrossContexts() throws {
        let service = try PersistenceService(inMemory: true)
        let task = TodoTask(title: "跨 context 任务")
        service.insert(task)
        try service.save()

        let otherContext = ModelContext(service.container)
        let fetched = try otherContext.fetch(FetchDescriptor<TodoTask>(predicate: #Predicate { $0.title == "跨 context 任务" }))
        #expect(fetched.count == 1)
    }

    @Test("批量删除指定模型类型")
    func deleteAllOfType() throws {
        let service = try PersistenceService(inMemory: true)
        service.insert(TodoTask(title: "A"))
        service.insert(TodoTask(title: "B"))
        service.insert(HistoryEvent(type: HistoryEventType.taskCreated.rawValue, title: "A 创建"))
        try service.save()

        let removed = try service.deleteAll(TodoTask.self)
        #expect(removed == 2)
        #expect(try service.fetch(FetchDescriptor<TodoTask>()).isEmpty)
        #expect(try service.fetch(FetchDescriptor<HistoryEvent>()).count == 1)
    }
}
