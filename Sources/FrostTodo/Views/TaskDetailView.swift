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
    @State private var useCustomCountdown = false
    @State private var countdownWork = 25
    @State private var countdownRest = 5
    @State private var countdownRounds = 4
    @State private var taskHistory: [HistoryEvent] = []
    @State private var pendingSaveTask: Task<Void, Never>?
    @State private var hasPendingChanges = false
    @State private var showsSavedIndicator = false

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
        .onDisappear { flushPendingSave() }
        .onChange(of: title) { _ in scheduleAutosave() }
        .onChange(of: notes) { _ in scheduleAutosave() }
        .onChange(of: hasDueDate) { _ in scheduleAutosave() }
        .onChange(of: dueDate) { _ in scheduleAutosave() }
        .onChange(of: hasStartDate) { _ in scheduleAutosave() }
        .onChange(of: startDate) { _ in scheduleAutosave() }
        .onChange(of: estimatedMinutes) { _ in scheduleAutosave() }
        .onChange(of: priority) { _ in scheduleAutosave() }
        .onChange(of: tagsText) { _ in scheduleAutosave() }
        .onChange(of: projectName) { _ in scheduleAutosave() }
        .onChange(of: useCustomCountdown) { _ in scheduleAutosave() }
        .onChange(of: countdownWork) { _ in scheduleAutosave() }
        .onChange(of: countdownRest) { _ in scheduleAutosave() }
        .onChange(of: countdownRounds) { _ in scheduleAutosave() }
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
                .help("优先使用本任务自定义时长，未自定义时用设置默认；休息为 0 表示纯倒计时")
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
            countdownSection
        }
        .padding()
        .background(FrostTheme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private var countdownSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("自定义倒计时时长", isOn: $useCustomCountdown)
            if useCustomCountdown {
                HStack {
                    field("专注时长") {
                        Stepper("\(countdownWork) 分钟", value: $countdownWork, in: 5...180, step: 5)
                            .frame(width: 150)
                    }
                    field("休息时长（0 为纯倒计时）") {
                        Stepper("\(countdownRest) 分钟", value: $countdownRest, in: 0...60, step: 1)
                            .frame(width: 150)
                    }
                }
                HStack {
                    field("轮数") {
                        Stepper("\(countdownRounds) 轮", value: $countdownRounds, in: 1...12, step: 1)
                            .frame(width: 150)
                    }
                    if countdownRest == 0 {
                        Text("总时长 \(countdownWork * countdownRounds) 分钟")
                            .font(.caption)
                            .foregroundStyle(FrostTheme.secondaryText)
                    }
                }
            } else {
                Text("跟随设置默认：专注 \(app.settingsModel.settings.countdownWorkMinutes) 分钟，休息 \(app.settingsModel.settings.countdownRestMinutes) 分钟，\(app.settingsModel.settings.countdownRounds) 轮")
                    .font(.caption)
                    .foregroundStyle(FrostTheme.secondaryText)
            }
        }
        .padding(10)
        .background(FrostTheme.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
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
        HStack {
            Text(text)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(FrostTheme.secondaryText)
            Spacer()
            Label("已自动保存", systemImage: "checkmark.circle")
                .font(.caption2)
                .foregroundStyle(FrostTheme.success)
                .opacity(showsSavedIndicator ? 1 : 0)
                .animation(.easeInOut(duration: 0.3), value: showsSavedIndicator)
        }
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
        if task.countdownWorkMinutes != nil || task.countdownRestMinutes != nil || task.countdownRounds != nil {
            useCustomCountdown = true
            countdownWork = task.countdownWorkMinutes ?? app.settingsModel.settings.countdownWorkMinutes
            countdownRest = task.countdownRestMinutes ?? app.settingsModel.settings.countdownRestMinutes
            countdownRounds = task.countdownRounds ?? app.settingsModel.settings.countdownRounds
        } else {
            useCustomCountdown = false
            countdownWork = app.settingsModel.settings.countdownWorkMinutes
            countdownRest = app.settingsModel.settings.countdownRestMinutes
            countdownRounds = app.settingsModel.settings.countdownRounds
        }
        taskHistory = (try? app.history.events(matching: HistoryFilter(taskID: task.id, limit: 30))) ?? []
    }

    /// 防抖自动保存：停止编辑约 0.8 秒后保存，避免逐键写历史
    private func scheduleAutosave() {
        hasPendingChanges = true
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            performSave()
        }
    }

    /// 离开详情页时立即保存未落盘的修改
    private func flushPendingSave() {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        if hasPendingChanges {
            performSave()
        }
    }

    private func performSave() {
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
            $0.countdownWorkMinutes = useCustomCountdown ? countdownWork : nil
            $0.countdownRestMinutes = useCustomCountdown ? countdownRest : nil
            $0.countdownRounds = useCustomCountdown ? countdownRounds : nil
        }
        hasPendingChanges = false
        try? app.taskList.reload()
        // 仅刷新历史时间线，不重写输入态，避免打断输入
        taskHistory = (try? app.history.events(matching: HistoryFilter(taskID: task.id, limit: 30))) ?? []
        flashSavedIndicator()
    }

    private func flashSavedIndicator() {
        withAnimation { showsSavedIndicator = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation { showsSavedIndicator = false }
        }
    }
}
