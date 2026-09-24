import SwiftUI

/// 主界面：三栏 NavigationSplitView
public struct MainView: View {
    @EnvironmentObject private var app: AppViewModel
    @State private var selection: SidebarSelection = .smart(.inbox)
    @State private var selectedTaskID: UUID?

    public init() {}

    public var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } content: {
            contentColumn
        } detail: {
            detailColumn
        }
        .frame(minWidth: 1_000, minHeight: 640)
        .preferredColorScheme(colorScheme)
        .onAppear {
            app.refreshAll()
        }
    }

    @ViewBuilder
    private var contentColumn: some View {
        switch selection {
        case .history:
            HistoryView(model: app.historyModel)
        case .settings:
            SettingsView(model: app.settingsModel)
        default:
            TaskListView(model: app.taskList, selection: $selection, selectedTaskID: $selectedTaskID)
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        switch selection {
        case .history, .settings:
            TimerView(model: app.timerModel)
        default:
            if let taskID = selectedTaskID, let task = app.task(byID: taskID) {
                TaskDetailView(task: task)
            } else {
                TimerView(model: app.timerModel)
            }
        }
    }

    private var colorScheme: ColorScheme? {
        switch app.settingsModel.settings.appearanceValue {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
