import SwiftUI

/// 中栏：历史列表（筛选、搜索、排序、分页、清空、导出）
public struct HistoryView: View {
    @EnvironmentObject private var app: AppViewModel
    @State private var searchText = ""
    @State private var typeFilter: HistoryEventType?
    @State private var ascending = false
    @State private var showClearConfirmation = false

    public var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            if app.historyModel.visibleEvents.isEmpty {
                Spacer()
                ContentUnavailableView("暂无历史", systemImage: "clock.arrow.circlepath")
                Spacer()
            } else {
                historyList
            }
        }
        .background(FrostTheme.background)
        .navigationTitle("历史")
        .onAppear(perform: reload)
        .onChange(of: searchText, perform: { _ in reload() })
        .searchable(text: $searchText, placement: .toolbar, prompt: "搜索标题与详情")
        .confirmationDialog("确认清空全部历史？该操作不可撤销。", isPresented: $showClearConfirmation, titleVisibility: .visible) {
            Button("清空历史", role: .destructive) {
                try? app.historyModel.clearAll()
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            Picker("类型", selection: $typeFilter) {
                Text("全部类型").tag(HistoryEventType?.none)
                ForEach(groupedTypes, id: \.self) { type in
                    Text(type.displayName).tag(HistoryEventType?.some(type))
                }
            }
            .pickerStyle(.menu)
            .frame(width: 170)

            Button {
                ascending.toggle()
                reload()
            } label: {
                Label(ascending ? "正序" : "倒序", systemImage: ascending ? "arrow.up" : "arrow.down")
            }

            Spacer()

            Button {
                exportHistory(json: true)
            } label: {
                Label("导出 JSON", systemImage: "square.and.arrow.up")
            }
            Button {
                exportHistory(json: false)
            } label: {
                Label("导出 CSV", systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive) {
                showClearConfirmation = true
            } label: {
                Label("清空", systemImage: "trash")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(FrostTheme.card)
    }

    private var historyList: some View {
        List {
            ForEach(app.historyModel.dayGroups, id: \.day) { group in
                Section(Formatters.day.string(from: group.day)) {
                    ForEach(group.events) { event in
                        HistoryRowView(event: event)
                            .listRowBackground(FrostTheme.card)
                    }
                }
            }
            if app.historyModel.canLoadMore {
                Button("加载更多") {
                    try? app.historyModel.loadMore()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    private var groupedTypes: [HistoryEventType] {
        [.taskCreated, .taskUpdated, .taskCompleted, .taskDeleted,
         .timerStarted, .timerPaused, .timerStopped,
         .sessionStarted, .sessionEnded,
         .calendarEventCreated, .calendarEventUpdated, .calendarEventRebuilt, .calendarSyncFailed,
         .settingsChanged, .notificationSent, .historyCleared]
    }

    private func reload() {
        app.historyModel.filter.types = typeFilter.map { [$0] } ?? []
        app.historyModel.filter.searchText = searchText
        app.historyModel.filter.ascending = ascending
        try? app.historyModel.reload()
    }

    private func exportHistory(json: Bool) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = json ? [.json] : [.commaSeparatedText]
        panel.nameFieldStringValue = json ? "FrostTodoHistory.json" : "FrostTodoHistory.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if json {
                try app.historyModel.exportJSON().write(to: url)
            } else {
                try app.historyModel.exportCSV().write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            // 导出失败时保持界面可用即可；失败原因不包含敏感信息
        }
    }
}

/// 单条历史记录
struct HistoryRowView: View {
    let event: HistoryEvent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.callout)
                if let detail = event.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(FrostTheme.secondaryText)
                        .lineLimit(2)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Formatters.time.string(from: event.createdAt))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(FrostTheme.secondaryText)
                Text(event.typeValue?.displayName ?? event.type)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(tint.opacity(0.18), in: Capsule())
                    .foregroundStyle(tint)
            }
        }
        .padding(.vertical, 3)
    }

    private var symbol: String {
        switch event.typeValue {
        case .taskCreated: return "plus.circle"
        case .taskUpdated: return "pencil.circle"
        case .taskCompleted, .taskUncompleted: return "checkmark.circle"
        case .taskDeleted: return "trash"
        case .timerStarted, .timerResumed: return "play.circle"
        case .timerPaused: return "pause.circle"
        case .timerStopped: return "stop.circle"
        case .sessionStarted, .sessionEnded: return "timer"
        case .calendarEventCreated: return "calendar.badge.plus"
        case .calendarEventUpdated: return "calendar.badge.clock"
        case .calendarEventDeleted: return "calendar.badge.minus"
        case .calendarEventRebuilt: return "calendar.badge.exclamationmark"
        case .calendarSyncFailed: return "exclamationmark.triangle"
        case .settingsChanged: return "gearshape"
        case .notificationSent: return "bell"
        case .historyCleared, .historyPruned: return "archivebox"
        case nil: return "circle"
        }
    }

    private var tint: Color {
        switch event.typeValue {
        case .taskCompleted: return FrostTheme.success
        case .taskDeleted, .calendarSyncFailed: return FrostTheme.warning
        case .timerStarted, .timerResumed, .sessionStarted: return FrostTheme.primary
        case .calendarEventCreated, .calendarEventUpdated, .calendarEventRebuilt: return FrostTheme.secondary
        default: return FrostTheme.secondaryText
        }
    }
}
