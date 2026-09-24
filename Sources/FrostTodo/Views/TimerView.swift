import SwiftUI

/// 右栏计时器：当前任务、大号用时与操作
public struct TimerView: View {
    @ObservedObject private var model: TimerViewModel
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public init(model: TimerViewModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 16) {
            if model.isTracking {
                trackedContent
            } else {
                ContentUnavailableView(
                    "未在计时",
                    systemImage: "timer",
                    description: Text("从任务列表选择一个任务开始计时")
                )
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FrostTheme.background)
        .onReceive(ticker) { _ in
            model.refresh()
        }
    }

    @ViewBuilder
    private var trackedContent: some View {
        VStack(spacing: 8) {
            Text(model.activeTaskTitle ?? "")
                .font(.headline)
                .foregroundStyle(FrostTheme.text)
            Text(model.elapsedText)
                .font(.system(size: 44, weight: .light, design: .monospaced))
                .foregroundStyle(FrostTheme.primary)
                .contentTransition(.numericText())
            Text(phaseLabel)
                .font(.caption)
                .foregroundStyle(FrostTheme.secondaryText)
        }
        .padding(.top, 8)

        Spacer()

        HStack(spacing: 12) {
            switch model.phase {
            case .running:
                controlButton("暂停", symbol: "pause.fill") { try? model.pause() }
                controlButton("停止", symbol: "stop.fill") { try? model.stop() }
                controlButton("完成任务", symbol: "checkmark", prominent: true) { try? model.complete() }
            case .paused:
                controlButton("继续", symbol: "play.fill", prominent: true) { try? model.resume() }
                controlButton("停止", symbol: "stop.fill") { try? model.stop() }
                controlButton("完成任务", symbol: "checkmark") { try? model.complete() }
            case .idle:
                EmptyView()
            }
        }
        .padding(.bottom, 8)
    }

    private var phaseLabel: String {
        switch model.phase {
        case .running: return "计时中"
        case .paused: return "已暂停"
        case .idle: return "空闲"
        }
    }

    private func controlButton(_ title: String, symbol: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .frame(minWidth: 88)
        }
        .buttonStyle(.borderedProminent)
        .tint(prominent ? FrostTheme.primary : FrostTheme.accent)
    }
}
