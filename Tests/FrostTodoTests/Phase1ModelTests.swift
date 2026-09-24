import Testing
import Foundation
import SwiftData
@testable import FrostTodo

@MainActor
@Suite("Phase 1: 数据模型")
struct Phase1ModelTests {

    private func makeService() throws -> PersistenceService {
        try PersistenceService(inMemory: true)
    }

    @Test("任务创建默认值正确")
    func taskCreationDefaults() throws {
        let task = TodoTask(title: "阅读技术文档")
        #expect(task.title == "阅读技术文档")
        #expect(task.statusValue == .active)
        #expect(task.priorityValue == .none)
        #expect(task.tags.isEmpty)
        #expect(task.sessions.isEmpty)
        #expect(task.calendarEventIDs.isEmpty)
        #expect(task.completedAt == nil)
        #expect(!task.isCompleted)
    }

    @Test("任务保存后可按 id 查询")
    func taskSaveAndFetchByID() throws {
        let service = try makeService()
        let task = TodoTask(title: "编写周报", tags: ["工作"], projectName: "团队")
        service.insert(task)
        try service.save()

        let id = task.id
        let fetched = try service.fetch(FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == id }))
        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "编写周报")
        #expect(fetched.first?.tags == ["工作"])
        #expect(fetched.first?.projectName == "团队")
    }

    @Test("任务状态流转：完成写入完成时间，取消完成清空")
    func taskStatusTransitions() throws {
        let service = try makeService()
        let task = TodoTask(title: "修复登录问题")
        service.insert(task)
        try service.save()

        let completedAt = Date(timeIntervalSince1970: 1_800_000_000)
        task.complete(at: completedAt)
        try service.save()
        #expect(task.isCompleted)
        #expect(task.completedAt == completedAt)
        #expect(task.status == TaskStatus.completed.rawValue)

        task.uncomplete()
        try service.save()
        #expect(!task.isCompleted)
        #expect(task.completedAt == nil)
        #expect(task.status == TaskStatus.active.rawValue)
    }

    @Test("重复完成或重复取消是幂等的")
    func taskStatusIdempotent() throws {
        let task = TodoTask(title: "幂等检查")
        let firstDate = Date(timeIntervalSince1970: 1_000)
        let secondDate = Date(timeIntervalSince1970: 2_000)
        task.complete(at: firstDate)
        task.complete(at: secondDate)
        #expect(task.completedAt == firstDate)

        task.uncomplete()
        task.uncomplete()
        #expect(!task.isCompleted)
        #expect(task.completedAt == nil)
    }

    @Test("删除任务级联删除关联 Session")
    func deleteTaskCascadesSessions() throws {
        let service = try makeService()
        let task = TodoTask(title: "计时任务")
        let session = TimeSession(taskID: task.id, startAt: Date(timeIntervalSince1970: 0))
        session.task = task
        service.insert(task)
        service.insert(session)
        try service.save()

        service.delete(task)
        try service.save()

        let remainingSessions = try service.fetch(FetchDescriptor<TimeSession>())
        #expect(remainingSessions.isEmpty)
        let remainingTasks = try service.fetch(FetchDescriptor<TodoTask>())
        #expect(remainingTasks.isEmpty)
    }

    @Test("Session 结束时计算实际时长")
    func sessionEndComputesDuration() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = start.addingTimeInterval(1_500)
        let session = TimeSession(taskID: UUID(), startAt: start)
        #expect(session.isRunning)
        #expect(session.endAt == nil)

        let duration = session.end(at: end)
        #expect(duration == 1_500)
        #expect(session.durationSeconds == 1_500)
        #expect(session.endAt == end)
        #expect(!session.isRunning)
        #expect(session.stateValue == .ended)
    }

    @Test("Session 跨天计时时长正确")
    func sessionCrossesMidnight() throws {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 23, minute: 0))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 1, minute: 30))!
        let session = TimeSession(taskID: UUID(), startAt: start)
        let duration = session.end(at: end)
        #expect(duration == 2 * 3600 + 30 * 60)
    }

    @Test("进行中 Session 的当前用时随时间增长")
    func sessionRunningElapsed() throws {
        let start = Date(timeIntervalSince1970: 5_000)
        let session = TimeSession(taskID: UUID(), startAt: start)
        #expect(session.currentElapsedSeconds(at: start) == 0)
        #expect(session.currentElapsedSeconds(at: start.addingTimeInterval(90)) == 90)
    }

    @Test("任务累计时长为全部 Session 之和")
    func taskAccumulatedDuration() throws {
        let task = TodoTask(title: "多段计时")
        let base = Date(timeIntervalSince1970: 10_000)
        let s1 = TimeSession(taskID: task.id, startAt: base)
        s1.end(at: base.addingTimeInterval(600))
        let s2 = TimeSession(taskID: task.id, startAt: base.addingTimeInterval(1_000))
        s2.end(at: base.addingTimeInterval(1_900))
        s1.task = task
        s2.task = task
        #expect(task.totalAccumulatedSeconds == 600 + 900)
    }
}
