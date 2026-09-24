import SwiftUI

/// 中栏：设置（日历、通知、外观、历史保留、数据管理）
public struct SettingsView: View {
    @EnvironmentObject private var app: AppViewModel
    @ObservedObject private var model: SettingsViewModel
    @State private var showClearHistoryConfirmation = false
    @State private var showClearCompletedConfirmation = false

    public init(model: SettingsViewModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            calendarSection
            timingSection
            appearanceSection
            historySection
            dataSection
        }
        .formStyle(.grouped)
        .background(FrostTheme.background)
        .navigationTitle("设置")
        .confirmationDialog("确认清空全部历史记录？", isPresented: $showClearHistoryConfirmation, titleVisibility: .visible) {
            Button("清空历史", role: .destructive) {
                try? model.clearHistory()
                try? app.historyModel.reload()
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("确认删除全部已完成任务？", isPresented: $showClearCompletedConfirmation, titleVisibility: .visible) {
            Button("删除已完成任务", role: .destructive) {
                _ = try? model.clearCompletedTasks()
                try? app.taskList.reload()
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var calendarSection: some View {
        Section {
            toggleRow("写入日历", keyPath: \.writeToCalendar)
            toggleRow("开始计时时创建日历事件", keyPath: \.createEventOnStart)
            toggleRow("任务完成时创建完成事件", keyPath: \.createCompletionEvent)

            Picker("默认日历", selection: Binding(
                get: { model.settings.defaultCalendarID ?? "" },
                set: { newValue in
                    try? model.update { $0.defaultCalendarID = newValue.isEmpty ? nil : newValue }
                }
            )) {
                Text("自动（FrostTodo 专用日历）").tag("")
                ForEach(app.writableCalendars()) { calendar in
                    Text(calendar.title).tag(calendar.id)
                }
            }

            HStack {
                Text("日历权限")
                Spacer()
                switch app.calendarAccess {
                case .granted:
                    Label("已授权", systemImage: "checkmark.circle.fill").foregroundStyle(FrostTheme.success)
                case .notDetermined:
                    Button("请求授权") {
                        Task { await app.requestCalendarAccessIfNeeded() }
                    }
                case .denied, .restricted, .writeOnly:
                    VStack(alignment: .trailing) {
                        Label("未授权", systemImage: "exclamationmark.triangle").foregroundStyle(FrostTheme.warning)
                        Text("任务与计时不受影响；如需日历联动，请到系统设置开启日历权限")
                            .font(.caption)
                            .foregroundStyle(FrostTheme.secondaryText)
                    }
                }
            }
        } header: {
            Text("日历联动")
        } footer: {
            if app.calendarAccess == .denied {
                Text("系统设置 - 隐私与安全性 - 日历")
            }
        }
    }

    private var timingSection: some View {
        Section("计时") {
            Stepper("默认预计时长：\(model.settings.defaultEstimatedMinutes) 分钟",
                    value: Binding(
                        get: { model.settings.defaultEstimatedMinutes },
                        set: { newValue in
                            try? model.update { $0.defaultEstimatedMinutes = newValue }
                        }
                    ), in: 5...240, step: 5)
        }
    }

    private var appearanceSection: some View {
        Section("外观") {
            Picker("模式", selection: Binding(
                get: { model.settings.appearanceValue },
                set: { newValue in
                    try? model.update { $0.appearanceValue = newValue }
                }
            )) {
                Text("跟随系统").tag(AppearanceMode.system)
                Text("浅色").tag(AppearanceMode.light)
                Text("深色").tag(AppearanceMode.dark)
            }
            .pickerStyle(.segmented)
        }
    }

    private var historySection: some View {
        Section("历史记录") {
            Picker("保留策略", selection: Binding(
                get: { model.settings.historyRetentionPolicyValue },
                set: { newValue in
                    try? model.update { $0.historyRetentionPolicyValue = newValue }
                }
            )) {
                Text("永久").tag(HistoryRetentionPolicy.forever)
                Text("按天数").tag(HistoryRetentionPolicy.byDays)
                Text("按条数").tag(HistoryRetentionPolicy.byCount)
            }

            if model.settings.historyRetentionPolicyValue == .byDays {
                Stepper("保留 \(model.settings.historyRetentionDays) 天",
                        value: Binding(
                            get: { model.settings.historyRetentionDays },
                            set: { newValue in
                                try? model.update { $0.historyRetentionDays = newValue }
                            }
                        ), in: 7...730, step: 1)
            }
            if model.settings.historyRetentionPolicyValue == .byCount {
                Stepper("保留 \(model.settings.historyRetentionCount) 条",
                        value: Binding(
                            get: { model.settings.historyRetentionCount },
                            set: { newValue in
                                try? model.update { $0.historyRetentionCount = newValue }
                            }
                        ), in: 100...100_000, step: 100)
            }

            Button("立即应用保留策略") {
                _ = try? model.applyRetentionPolicy()
                try? app.historyModel.reload()
            }
        }
    }

    private var dataSection: some View {
        Section {
            Button("导出全部数据为 JSON") {
                ExportService.savePanelExport(persistence: app.persistence)
            }
            Button("清除已完成任务", role: .destructive) {
                showClearCompletedConfirmation = true
            }
            Button("清空历史记录", role: .destructive) {
                showClearHistoryConfirmation = true
            }
        } header: {
            Text("数据管理")
        } footer: {
            Text("数据保存在本机，不上传服务器。")
        }
    }

    private func toggleRow(_ title: String, keyPath: ReferenceWritableKeyPath<AppSettings, Bool>) -> some View {
        Toggle(title, isOn: Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { newValue in
                try? model.update { $0[keyPath: keyPath] = newValue }
            }
        ))
    }
}
