import SwiftUI

/// 主界面：三栏 NavigationSplitView
public struct MainView: View {
    @EnvironmentObject private var app: AppViewModel
    @State private var selection: SidebarSelection = .smart(.inbox)
    @State private var selectedTask: TodoTask?

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
            HistoryView()
        case .settings:
            SettingsView()
        default:
            TaskListView(selection: $selection, selectedTask: $selectedTask)
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        switch selection {
        case .history, .settings:
            TimerView()
        default:
            if let task = selectedTask {
                TaskDetailView(task: task)
            } else {
                TimerView()
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
