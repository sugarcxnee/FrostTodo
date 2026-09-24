import SwiftUI
import AppKit

/// 菜单栏内容：当前计时任务、用时与快捷操作、快速添加
public struct MenuBarTimerView: View {
    @EnvironmentObject private var app: AppViewModel
    @ObservedObject private var timerModel: TimerViewModel
    @State private var quickAddText = ""
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public init(timerModel: TimerViewModel) {
        self.timerModel = timerModel
    }

    public var body: some View {
        VStack(spacing: 10) {
            if timerModel.isTracking {
                VStack(spacing: 4) {
                    Text(timerModel.activeTaskTitle ?? "")
                        .font(.headline)
                        .lineLimit(1)
                    Text(timerModel.elapsedText)
                        .font(.system(size: 28, weight: .light, design: .monospaced))
                        .foregroundStyle(FrostTheme.primary)
                    Text(timerModel.phase == .running ? "[计时中]" : "[已暂停]")
                        .font(.caption)
                        .foregroundStyle(FrostTheme.secondaryText)
                }
                HStack {
                    switch timerModel.phase {
                    case .running:
                        menuButton("暂停", "pause.fill") { try? timerModel.pause() }
                        menuButton("停止", "stop.fill") { try? timerModel.stop() }
                        menuButton("完成", "checkmark") { try? timerModel.complete() }
                    case .paused:
                        menuButton("继续", "play.fill") { try? timerModel.resume() }
                        menuButton("停止", "stop.fill") { try? timerModel.stop() }
                        menuButton("完成", "checkmark") { try? timerModel.complete() }
                    case .idle:
                        EmptyView()
                    }
                }
            } else {
                Text("未在计时")
                    .font(.callout)
                    .foregroundStyle(FrostTheme.secondaryText)
            }

            Divider()

            HStack {
                Image(systemName: "plus")
                    .foregroundStyle(FrostTheme.secondaryText)
                TextField("快速添加任务", text: $quickAddText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addQuickTask)
            }

            Divider()

            Button("退出 FrostTodo") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(minWidth: 260)
        .onReceive(ticker) { _ in
            timerModel.refresh()
        }
    }

    private func menuButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(FrostTheme.accent)
    }

    private func addQuickTask() {
        let title = quickAddText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        _ = try? app.taskList.quickAdd(title: title)
        quickAddText = ""
        try? app.taskList.reload()
    }
}

/// 菜单栏标签：计时中显示任务与用时
public struct MenuBarLabelView: View {
    @ObservedObject private var timerModel: TimerViewModel
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public init(timerModel: TimerViewModel) {
        self.timerModel = timerModel
    }

    public var body: some View {
        if timerModel.isTracking {
            Text("[\(timerModel.elapsedText)] \(timerModel.activeTaskTitle ?? "")")
                .onReceive(ticker) { _ in
                    timerModel.refresh()
                }
        } else {
            Image(systemName: "circle.dashed")
        }
    }
}
