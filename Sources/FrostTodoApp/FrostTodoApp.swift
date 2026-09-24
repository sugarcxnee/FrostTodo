import SwiftUI
import FrostTodo

@main
struct FrostTodoApp: App {
    @StateObject private var app = try! AppViewModel()
    private let shortcuts = ShortcutRouter()
    /// 作为测试宿主运行时不请求权限、不启动 UI 外逻辑，避免阻塞自动化测试
    private let isTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    var body: some Scene {
        WindowGroup("FrostTodo") {
            MainView()
                .environmentObject(app)
                .task {
                    guard !isTestHost else { return }
                    await app.requestCalendarAccessIfNeeded()
                    app.refreshAll()
                }
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            AppCommands(app: app, shortcuts: shortcuts)
        }

        MenuBarExtra {
            MenuBarTimerView()
                .environmentObject(app)
        } label: {
            MenuBarLabelView()
                .environmentObject(app)
        }
        .menuBarExtraStyle(.window)
    }
}

/// 全局快捷键命令
struct AppCommands: Commands {
    let app: AppViewModel
    let shortcuts: ShortcutRouter

    var body: some Commands {
        SidebarCommands()
        CommandGroup(after: .newItem) {
            Button("快速添加任务") {
                NotificationCenter.default.post(name: .frostTodoFocusQuickAdd, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("开始或暂停计时") {
                shortcuts.perform(.toggleTimer, timer: app.timer)
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])

            Button("完成当前任务") {
                shortcuts.perform(.completeCurrent, timer: app.timer)
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
        }
    }
}
