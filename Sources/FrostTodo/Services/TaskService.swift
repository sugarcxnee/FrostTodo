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

    /// 编辑任务并在历史中记录变更字段
    public func update(_ task: TodoTask, applying: (TodoTask) -> Void) throws {
        let before = TaskFieldSnapshot(task)
        applying(task)
        let changes = before.diff(with: task)
        guard !changes.isEmpty else { return }

        do {
            try history.record(HistoryEventInput(
                type: .taskUpdated, taskID: task.id,
                title: "编辑任务：\(task.title)",
                detail: "变更字段：" + changes.map(\.name).joined(separator: "、"),
                payload: Dictionary(uniqueKeysWithValues: changes.map { ($0.name, "\($0.oldValue) -> \($0.newValue)") }),
                source: .user
            ))
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

/// 任务字段快照：编辑前后对比得出变更字段
struct TaskFieldSnapshot {
    let title: String
    let notes: String?
    let dueDate: Date?
    let startDate: Date?
    let estimatedMinutes: Int?
    let priority: Int
    let tags: [String]
    let projectName: String?
    let countdownWorkMinutes: Int?
    let countdownRestMinutes: Int?
    let countdownRounds: Int?

    init(_ task: TodoTask) {
        title = task.title
        notes = task.notes
        dueDate = task.dueDate
        startDate = task.startDate
        estimatedMinutes = task.estimatedMinutes
        priority = task.priority
        tags = task.tags
        projectName = task.projectName
        countdownWorkMinutes = task.countdownWorkMinutes
        countdownRestMinutes = task.countdownRestMinutes
        countdownRounds = task.countdownRounds
    }

    struct Change {
        let name: String
        let oldValue: String
        let newValue: String
    }

    private static func value(_ any: Any?) -> String {
        switch any {
        case .some(let value): return String(describing: value)
        case .none: return "无"
        }
    }

    private static func minutes(_ value: Int?) -> String {
        value.map { "\($0) 分钟" } ?? "跟随默认"
    }

    private static func rounds(_ value: Int?) -> String {
        value.map { "\($0) 轮" } ?? "跟随默认"
    }

    func diff(with task: TodoTask) -> [Change] {
        var changes: [Change] = []
        if title != task.title {
            changes.append(Change(name: "标题", oldValue: title, newValue: task.title))
        }
        if notes != task.notes {
            changes.append(Change(name: "备注", oldValue: Self.value(notes), newValue: Self.value(task.notes)))
        }
        if dueDate != task.dueDate {
            changes.append(Change(name: "截止日期", oldValue: Self.value(dueDate), newValue: Self.value(task.dueDate)))
        }
        if startDate != task.startDate {
            changes.append(Change(name: "开始日期", oldValue: Self.value(startDate), newValue: Self.value(task.startDate)))
        }
        if estimatedMinutes != task.estimatedMinutes {
            changes.append(Change(name: "预计时长", oldValue: Self.value(estimatedMinutes), newValue: Self.value(task.estimatedMinutes)))
        }
        if priority != task.priority {
            changes.append(Change(name: "优先级", oldValue: String(priority), newValue: String(task.priority)))
        }
        if tags != task.tags {
            changes.append(Change(name: "标签", oldValue: tags.joined(separator: ","), newValue: task.tags.joined(separator: ",")))
        }
        if projectName != task.projectName {
            changes.append(Change(name: "项目", oldValue: Self.value(projectName), newValue: Self.value(task.projectName)))
        }
        if countdownWorkMinutes != task.countdownWorkMinutes {
            changes.append(Change(name: "倒计时专注时长", oldValue: Self.minutes(countdownWorkMinutes), newValue: Self.minutes(task.countdownWorkMinutes)))
        }
        if countdownRestMinutes != task.countdownRestMinutes {
            changes.append(Change(name: "倒计时休息时长", oldValue: Self.minutes(countdownRestMinutes), newValue: Self.minutes(task.countdownRestMinutes)))
        }
        if countdownRounds != task.countdownRounds {
            changes.append(Change(name: "倒计时轮数", oldValue: Self.rounds(countdownRounds), newValue: Self.rounds(task.countdownRounds)))
        }
        return changes
    }
}
