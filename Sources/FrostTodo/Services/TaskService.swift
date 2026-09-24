import Foundation
import SwiftData

/// 任务操作错误
public enum TaskError: Error, Equatable {
    case emptyTitle
}

/// 任务服务：任务 CRUD 与历史写入在同一逻辑单元内完成
@MainActor
public final class TaskService {
    private let persistence: PersistenceService
    private let history: HistoryRecording
    private let clock: ClockProviding
    /// 完成或删除计时中的任务前需要先停止计时
    public weak var timerService: TimerService?

    public init(persistence: PersistenceService, history: HistoryRecording, clock: ClockProviding = SystemClock()) {
        self.persistence = persistence
        self.history = history
        self.clock = clock
    }

    // MARK: - 创建

    @discardableResult
    public func create(
        title: String,
        notes: String? = nil,
        dueDate: Date? = nil,
        startDate: Date? = nil,
        estimatedMinutes: Int? = nil,
        priority: TaskPriority = .none,
        tags: [String] = [],
        projectName: String? = nil,
        countdownWorkMinutes: Int? = nil,
        countdownRestMinutes: Int? = nil,
        countdownRounds: Int? = nil
    ) throws -> TodoTask {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TaskError.emptyTitle
        }

        let maxOrder = (try? persistence.fetch(FetchDescriptor<TodoTask>()))?.map(\.sortOrder).max() ?? -1
        let task = TodoTask(
            title: trimmed,
            notes: notes,
            dueDate: dueDate,
            startDate: startDate,
            estimatedMinutes: estimatedMinutes,
            priority: priority.rawValue,
            tags: tags,
            projectName: projectName,
            sortOrder: maxOrder + 1,
            countdownWorkMinutes: countdownWorkMinutes,
            countdownRestMinutes: countdownRestMinutes,
            countdownRounds: countdownRounds
        )
        persistence.insert(task)

        do {
            try history.record(HistoryEventInput(
                type: .taskCreated, taskID: task.id,
                title: "创建任务：\(trimmed)",
                payload: historyPayload(for: task), source: .user
            ))
            try persistence.save()
        } catch {
            persistence.rollback()
            throw error
        }
        return task
    }

    // MARK: - 编辑

    /// 编辑任务信息。按需求约定：任务信息修改不写历史，仅进程事件
    /// （创建、完成、取消完成、删除）与计时相关事件入历史。
    public func update(_ task: TodoTask, applying: (TodoTask) -> Void) throws {
        applying(task)
        do {
            try persistence.save()
        } catch {
            persistence.rollback()
            throw error
        }
    }

    // MARK: - 完成

    public func complete(_ task: TodoTask) throws {
        guard !task.isCompleted else { return }
        // 计时中的任务先停止计时（timer 历史由 TimerService 写入）
        if timerService?.activeTaskID == task.id, timerService?.isTracking == true {
            try timerService?.stop()
        }
        let now = clock.now
        task.complete(at: now)

        do {
            try history.record(HistoryEventInput(
                type: .taskCompleted, taskID: task.id,
                title: "完成任务：\(task.title)",
                payload: ["completedAt": String(now.timeIntervalSince1970)], source: .user
            ))
            try persistence.save()
        } catch {
            persistence.rollback()
            throw error
        }
    }

    public func uncomplete(_ task: TodoTask) throws {
        guard task.isCompleted else { return }
        task.uncomplete()

        do {
            try history.record(HistoryEventInput(
                type: .taskUncompleted, taskID: task.id,
                title: "取消完成：\(task.title)", source: .user
            ))
            try persistence.save()
        } catch {
            persistence.rollback()
            throw error
        }
    }

    // MARK: - 删除

    public func delete(_ task: TodoTask) throws {
        if timerService?.activeTaskID == task.id, timerService?.isTracking == true {
            try timerService?.stop()
        }
        let title = task.title
        do {
            try history.record(HistoryEventInput(
                type: .taskDeleted, taskID: task.id,
                title: "删除任务：\(title)",
                payload: ["title": title], source: .user
            ))
            persistence.delete(task)
            try persistence.save()
        } catch {
            persistence.rollback()
            throw error
        }
    }

    // MARK: - 私有

    private func historyPayload(for task: TodoTask) -> [String: String] {
        var payload: [String: String] = ["title": task.title]
        if !task.tags.isEmpty {
            payload["tags"] = task.tags.joined(separator: ",")
        }
        if let project = task.projectName, !project.isEmpty {
            payload["project"] = project
        }
        return payload
    }
}
