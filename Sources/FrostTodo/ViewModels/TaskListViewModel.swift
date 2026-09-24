import Foundation
import SwiftData
import SwiftUI

/// 侧边栏智能视图
public enum SmartView: String, CaseIterable, Identifiable {
    case inbox
    case today
    case planned
    case completed
    case tag
    case project

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .inbox: return "收件箱"
        case .today: return "今天"
        case .planned: return "计划"
        case .completed: return "已完成"
        case .tag: return "标签"
        case .project: return "项目"
        }
    }

    public var symbol: String {
        switch self {
        case .inbox: return "tray"
        case .today: return "sun.max"
        case .planned: return "calendar"
        case .completed: return "checkmark.circle"
        case .tag: return "tag"
        case .project: return "folder"
        }
    }
}

/// 任务排序方式
public enum TaskSortOrder: String, CaseIterable, Identifiable {
    case manual
    case created
    case due
    case priority

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .manual: return "手动"
        case .created: return "创建时间"
        case .due: return "截止日期"
        case .priority: return "优先级"
        }
    }
}

/// 任务列表 ViewModel：筛选、搜索、排序与基础操作
@MainActor
public final class TaskListViewModel: ObservableObject {
    @Published public var selectedView: SmartView = .inbox
    @Published public var selectedTag: String?
    @Published public var selectedProject: String?
    @Published public var searchText: String = ""
    @Published public var sortOrder: TaskSortOrder = .manual
    @Published public private(set) var visibleTasks: [TodoTask] = []
    @Published public private(set) var availableTags: [String] = []
    @Published public private(set) var availableProjects: [String] = []

    private let persistence: PersistenceService
    private let tasks: TaskService
    private let clock: ClockProviding

    public init(persistence: PersistenceService, tasks: TaskService, clock: ClockProviding) {
        self.persistence = persistence
        self.tasks = tasks
        self.clock = clock
    }

    /// 重新加载当前视图的任务并更新标签/项目清单
    public func reload() throws {
        let all = try persistence.fetch(FetchDescriptor<TodoTask>())
        availableTags = Array(Set(all.flatMap(\.tags))).sorted()
        availableProjects = Array(Set(all.compactMap(\.projectName))).sorted()

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: clock.now)

        var filtered: [TodoTask]
        switch selectedView {
        case .inbox:
            filtered = all.filter { !$0.isCompleted && $0.startDate == nil && $0.dueDate == nil }
        case .today:
            filtered = all.filter { task in
                guard !task.isCompleted else { return false }
                if let start = task.startDate, calendar.startOfDay(for: start) <= today { return true }
                if let due = task.dueDate, calendar.startOfDay(for: due) == today { return true }
                return false
            }
        case .planned:
            filtered = all.filter { task in
                guard !task.isCompleted, let start = task.startDate else { return false }
                return calendar.startOfDay(for: start) > today
            }
        case .completed:
            filtered = all.filter(\.isCompleted)
        case .tag:
            if let tag = selectedTag {
                filtered = all.filter { !$0.isCompleted && $0.tags.contains(tag) }
            } else {
                filtered = all.filter { !$0.isCompleted && !$0.tags.isEmpty }
            }
        case .project:
            if let project = selectedProject {
                filtered = all.filter { !$0.isCompleted && $0.projectName == project }
            } else {
                filtered = all.filter { !$0.isCompleted && $0.projectName != nil }
            }
        }

        if !searchText.isEmpty {
            let text = searchText
            filtered = filtered.filter { $0.title.localizedCaseInsensitiveContains(text) }
        }
        visibleTasks = Self.sort(filtered, by: sortOrder)
    }

    /// 完成或取消完成任务
    public func toggleComplete(_ task: TodoTask) throws {
        if task.isCompleted {
            try tasks.uncomplete(task)
        } else {
            try tasks.complete(task)
        }
    }

    /// 快速添加任务到当前上下文
    @discardableResult
    public func quickAdd(title: String) throws -> TodoTask {
        try tasks.create(title: title)
    }

    public func delete(_ task: TodoTask) throws {
        try tasks.delete(task)
    }

    /// 手动排序下拖拽移动
    public func move(from source: IndexSet, to destination: Int) throws {
        var ordered = visibleTasks
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, task) in ordered.enumerated() {
            task.sortOrder = index
        }
        try persistence.save()
    }

    static func sort(_ tasks: [TodoTask], by order: TaskSortOrder) -> [TodoTask] {
        switch order {
        case .manual:
            return tasks.sorted { $0.sortOrder < $1.sortOrder }
        case .created:
            return tasks.sorted { $0.createdAt > $1.createdAt }
        case .due:
            return tasks.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        case .priority:
            return tasks.sorted { $0.priority > $1.priority }
        }
    }
}
