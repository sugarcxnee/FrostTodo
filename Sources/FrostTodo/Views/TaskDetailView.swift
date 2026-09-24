import SwiftUI
import SwiftData

/// 右栏：任务详情（编辑、计时、时间段、历史时间线）
public struct TaskDetailView: View {
    @EnvironmentObject private var app: AppViewModel
    let task: TodoTask

    @State private var title = ""
    @State private var notes = ""
    @State private var dueDate: Date = Date()
    @State private var hasDueDate = false
    @State private var startDate: Date = Date()
    @State private var hasStartDate = false
    @State private var estimatedMinutes = 25
    @State private var priority: TaskPriority = .none
    @State private var tagsText = ""
    @State private var projectName = ""
    @State private var taskHistory: [HistoryEvent] = []

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                editorCard
                sessionsCard
                historyCard
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(FrostTheme.background)
        .onAppear { loadState() }
        .onChange(of: task) { loadState() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.title2)
                    .foregroundStyle(FrostTheme.text)
                HStack(spacing: 10) {
                    if task.isCompleted {
                        Label("已完成", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(FrostTheme.success)
                    }
                    Label("累计 \(Formatters.duration(task.totalAccumulatedSeconds))", systemImage: "timer")
                    if !task.calendarEventIDs.isEmpty {
                        Label("\(task.calendarEventIDs.count) 个日历事件", systemImage: "calendar")
                    }
                }
                .font(.caption)
                .foregroundStyle(FrostTheme.secondaryText)
            }
            Spacer()
            if !task.isCompleted {
                if app.timer.activeTaskID == task.id {
                    Button("停止计时") { try? app.timerModel.stop() }
                        .buttonStyle(.bordered)
                } else {
                    Button {
                        try? app.timerModel.start(task: task)
                    } label: {
                        Label("开始计时", systemImage: "timer")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(FrostTheme.primary)
                }
                Button {
                    try? app.countdownModel.start(task: task)
                } label: {
                    Label("开始倒计时", systemImage: "hourglass")
                }
                .buttonStyle(.bordered)
                .tint(FrostTheme.secondary)
                .help("按设置中的专注与休息时长启动倒计时；休息为 0 表示纯倒计时")
            }
            Button {
                try? app.taskList.toggleComplete(task)
                try? app.taskList.reload()
            } label: {
                Label(task.isCompleted ? "取消完成" : "完成", systemImage: task.isCompleted ? "arrow.uturn.backward" : "checkmark")
            }
            .buttonStyle(.bordered)
        }
    }

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardTitle("基本信息")
            field("标题") {
                TextField("标题", text: $title)
            }
            field("备注") {
                TextEditor(text: $notes)
                    .frame(minHeight: 60)
                    .scrollContentBackground(.hidden)
                    .background(FrostTheme.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }
            HStack {
                Toggle("设置开始日期", isOn: $hasStartDate)
                if hasStartDate {
                    DatePicker("", selection: $startDate, displayedComponents: [.date])
                        .labelsHidden()
                }
            }
            HStack {
                Toggle("设置截止日期", isOn: $hasDueDate)
                if hasDueDate {
                    DatePicker("", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                }
            }
            HStack {
                field("预计时长（分钟）") {
                    Stepper(value: $estimatedMinutes, in: 5...600, step: 5) {
                        Text("\(estimatedMinutes) 分钟")
                    }
                }
                field("优先级") {
                    Picker("", selection: $priority) {
                        ForEach(TaskPriority.allCases, id: \.self) { level in
                            Text(level.label).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
            }
            HStack {
                field("标签（逗号分隔）") {
                    TextField("工作,写作", text: $tagsText)
                }
                field("项目") {
                    TextField("项目名", text: $projectName)
                }
            }
            HStack {
                Spacer()
                Button("保存修改") { saveChanges() }
                    .buttonStyle(.borderedProminent)
                    .tint(FrostTheme.primary)
            }
        }
        .padding()
        .background(FrostTheme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private var sessionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardTitle("时间段记录")
            if task.sessions.isEmpty {
                Text("暂无时间段")
                    .font(.callout)
                    .foregroundStyle(FrostTheme.secondaryText)
            } else {
                ForEach(task.sessions.sorted { $0.startAt > $1.startAt }) { session in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Formatters.dateTime.string(from: session.startAt)) - \(session.endAt.map { Formatters.time.string(from: $0) } ?? "进行中")")
                                .font(.callout)
                            if let eventID = session.calendarEventID {
                                Label("日历事件 \(String(eventID.suffix(8)))", systemImage: "calendar")
                                    .font(.caption)
                                    .foregroundStyle(FrostTheme.secondaryText)
                            }
                        }
                        Spacer()
                        Text(Formatters.duration(session.currentElapsedSeconds(at: session.endAt ?? Date())))
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(FrostTheme.primary)
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }
        }
        .padding()
        .background(FrostTheme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardTitle("历史时间线")
            if taskHistory.isEmpty {
                Text("暂无历史")
                    .font(.callout)
                    .foregroundStyle(FrostTheme.secondaryText)
            } else {
                ForEach(taskHistory) { event in
                    HStack(alignment: .top, spacing: 8) {
                        Text(Formatters.time.string(from: event.createdAt))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(FrostTheme.secondaryText)
                            .frame(width: 48, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                                .font(.callout)
                            if let detail = event.detail {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(FrostTheme.secondaryText)
                            }
                        }
                        Spacer()
                        Text(event.typeValue?.displayName ?? event.type)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(FrostTheme.accent.opacity(0.25), in: Capsule())
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .padding()
        .background(FrostTheme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 辅助

    private func cardTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(FrostTheme.secondaryText)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(FrostTheme.secondaryText)
            content()
        }
    }

    private func loadState() {
        title = task.title
        notes = task.notes ?? ""
        if let due = task.dueDate {
            hasDueDate = true
            dueDate = due
        } else {
            hasDueDate = false
        }
        if let start = task.startDate {
            hasStartDate = true
            startDate = start
        } else {
            hasStartDate = false
        }
        estimatedMinutes = task.estimatedMinutes ?? Int(app.settingsModel.settings.defaultEstimatedMinutes)
        priority = task.priorityValue
        tagsText = task.tags.joined(separator: ",")
        projectName = task.projectName ?? ""
        taskHistory = (try? app.history.events(matching: HistoryFilter(taskID: task.id, limit: 30))) ?? []
    }

    private func saveChanges() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let project = projectName.trimmingCharacters(in: .whitespaces)
        try? app.tasks.update(task) {
            if !trimmedTitle.isEmpty { $0.title = trimmedTitle }
            $0.notes = notes.isEmpty ? nil : notes
            $0.dueDate = hasDueDate ? dueDate : nil
            $0.startDate = hasStartDate ? startDate : nil
            $0.estimatedMinutes = estimatedMinutes
            $0.priorityValue = priority
            $0.tags = tags
            $0.projectName = project.isEmpty ? nil : project
        }
        try? app.taskList.reload()
        loadState()
    }
}
