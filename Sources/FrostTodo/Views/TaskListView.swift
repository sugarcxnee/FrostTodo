import SwiftUI
import SwiftData

/// 快速添加输入通知（快捷键触发）
public extension Notification.Name {
    static let frostTodoFocusQuickAdd = Notification.Name("FrostTodoFocusQuickAdd")
}

/// 快速添加栏：独立持有输入状态。
/// 输入过程中的键盘事件只重算本视图，避免上层任务 List 因无关状态变化
/// 触发 SwiftUI 对 SwiftData 模型行的重新 diff（该场景曾导致列表整列消失）。
struct QuickAddBar: View {
    /// 提交回调，返回是否添加成功（用于清空输入框）
    let onSubmit: (String) -> Bool

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .foregroundStyle(FrostTheme.secondaryText)
            TextField("快速添加任务，回车确认", text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit(submit)
        }
        .onReceive(NotificationCenter.default.publisher(for: .frostTodoFocusQuickAdd)) { _ in
            focused = true
        }
    }

    private func submit() {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        if onSubmit(title) {
            text = ""
        }
    }
}

/// 中栏：任务列表（搜索、排序、快速添加、完成、删除、开始计时）
public struct TaskListView: View {
    @EnvironmentObject private var app: AppViewModel
    @ObservedObject private var model: TaskListViewModel
    @Binding var selection: SidebarSelection
    @Binding var selectedTaskID: UUID?

    public init(model: TaskListViewModel, selection: Binding<SidebarSelection>, selectedTaskID: Binding<UUID?>) {
        self.model = model
        _selection = selection
        _selectedTaskID = selectedTaskID
    }

    private var title: String {
        switch selection {
        case .smart(let view): return view.title
        case .tag(let tag): return "标签：\(tag)"
        case .project(let project): return "项目：\(project)"
        default: return "任务"
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if model.visibleTasks.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "暂无任务",
                    systemImage: "tray",
                    description: Text("在上方输入框快速添加一个任务")
                )
                Spacer()
            } else {
                taskTable
            }
        }
        .background(FrostTheme.background)
        .navigationTitle(title)
        .onAppear { syncSelection(); try? model.reload() }
        .onChange(of: selection) { syncSelection(); try? model.reload() }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            QuickAddBar { title in
                addQuickTask(title)
            }
            Spacer()
            Picker("排序", selection: Binding(
                get: { model.sortOrder },
                set: { newValue in
                    model.sortOrder = newValue
                    try? model.reload()
                }
            )) {
                ForEach(TaskSortOrder.allCases) { order in
                    Text(order.title).tag(order)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(FrostTheme.card)
    }

    private var taskTable: some View {
        List(selection: $selectedTaskID) {
            ForEach(model.visibleTasks) { task in
                TaskRowView(task: task)
                    .tag(task.id)
                    .listRowBackground(FrostTheme.card)
                    .contextMenu {
                        Button(task.isCompleted ? "取消完成" : "完成") {
                            try? app.taskList.toggleComplete(task)
                            try? app.taskList.reload()
                        }
                        if !task.isCompleted {
                            Button("开始计时") {
                                try? app.timerModel.start(task: task)
                            }
                        }
                        Divider()
                        Button("删除", role: .destructive) {
                            try? app.taskList.delete(task)
                            try? app.taskList.reload()
                        }
                    }
            }
            .onMove { source, destination in
                try? app.taskList.move(from: source, to: destination)
                try? app.taskList.reload()
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    @discardableResult
    private func addQuickTask(_ title: String) -> Bool {
        guard (try? app.taskList.quickAdd(title: title)) != nil else { return false }
        try? app.taskList.reload()
        return true
    }

    private func syncSelection() {
        switch selection {
        case .smart(let view):
            app.taskList.selectedView = view
            app.taskList.selectedTag = nil
            app.taskList.selectedProject = nil
        case .tag(let tag):
            app.taskList.selectedView = .tag
            app.taskList.selectedTag = tag
            app.taskList.selectedProject = nil
        case .project(let project):
            app.taskList.selectedView = .project
            app.taskList.selectedTag = nil
            app.taskList.selectedProject = project
        default:
            break
        }
        if !app.taskList.searchText.isEmpty {
            app.taskList.searchText = ""
        }
    }
}

/// 单行任务
struct TaskRowView: View {
    @EnvironmentObject private var app: AppViewModel
    let task: TodoTask

    var body: some View {
        HStack(spacing: 10) {
            Button {
                try? app.taskList.toggleComplete(task)
                try? app.taskList.reload()
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isCompleted ? FrostTheme.success : FrostTheme.secondaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "取消完成任务" : "完成任务")

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.body)
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? FrostTheme.secondaryText : FrostTheme.text)
                HStack(spacing: 6) {
                    if task.priorityValue != .none {
                        Text(task.priorityValue.label)
                            .font(.caption)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(priorityColor.opacity(0.18), in: Capsule())
                            .foregroundStyle(priorityColor)
                    }
                    if let project = task.projectName {
                        Label(project, systemImage: "folder")
                            .font(.caption)
                            .foregroundStyle(FrostTheme.secondaryText)
                    }
                    ForEach(task.tags, id: \.self) { tag in
                        Label(tag, systemImage: "tag")
                            .font(.caption)
                            .foregroundStyle(FrostTheme.secondaryText)
                    }
                    if let due = task.dueDate {
                        Label(Formatters.day.string(from: due), systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(isOverdue ? FrostTheme.warning : FrostTheme.secondaryText)
                    }
                }
            }
            Spacer()
            if app.timer.activeTaskID == task.id {
                Text("[计时中]")
                    .font(.caption)
                    .foregroundStyle(FrostTheme.primary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var isOverdue: Bool {
        guard let due = task.dueDate else { return false }
        return due < Date() && !task.isCompleted
    }

    private var priorityColor: Color {
        switch task.priorityValue {
        case .high: return FrostTheme.warning
        case .medium: return FrostTheme.primary
        default: return FrostTheme.secondaryText
        }
    }
}
