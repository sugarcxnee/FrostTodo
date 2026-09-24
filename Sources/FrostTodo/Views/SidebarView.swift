import SwiftUI

/// 侧边栏选择
public enum SidebarSelection: Hashable {
    case smart(SmartView)
    case tag(String)
    case project(String)
    case history
    case settings
}

/// 左栏：计时面板、智能视图、标签、项目、历史与设置入口
public struct SidebarView: View {
    @EnvironmentObject private var app: AppViewModel
    @ObservedObject private var timerModel: TimerViewModel
    @ObservedObject private var countdownModel: CountdownViewModel
    @Binding var selection: SidebarSelection

    public init(
        selection: Binding<SidebarSelection>,
        timerModel: TimerViewModel,
        countdownModel: CountdownViewModel
    ) {
        _selection = selection
        self.timerModel = timerModel
        self.countdownModel = countdownModel
    }

    public var body: some View {
        VStack(spacing: 8) {
            if countdownModel.isActive || timerModel.isTracking {
                VStack(spacing: 8) {
                    if countdownModel.isActive {
                        CountdownPanelCard(model: countdownModel)
                    }
                    if timerModel.isTracking {
                        CountUpPanelCard(model: timerModel)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
            }

            List(selection: $selection) {
                Section("任务") {
                    ForEach([SmartView.inbox, .today, .planned, .completed]) { view in
                        NavigationLink(value: SidebarSelection.smart(view)) {
                            Label(view.title, systemImage: view.symbol)
                        }
                    }
                }

                if !app.taskList.availableTags.isEmpty {
                    Section("标签") {
                        ForEach(app.taskList.availableTags, id: \.self) { tag in
                            NavigationLink(value: SidebarSelection.tag(tag)) {
                                Label(tag, systemImage: "tag")
                            }
                        }
                    }
                }

                if !app.taskList.availableProjects.isEmpty {
                    Section("项目") {
                        ForEach(app.taskList.availableProjects, id: \.self) { project in
                            NavigationLink(value: SidebarSelection.project(project)) {
                                Label(project, systemImage: "folder")
                            }
                        }
                    }
                }

                Section("记录") {
                    NavigationLink(value: SidebarSelection.history) {
                        Label("历史", systemImage: "clock.arrow.circlepath")
                    }
                }

                if !app.todaySchedule.isEmpty {
                    Section("今日日程") {
                        ForEach(app.todaySchedule) { event in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title)
                                    .font(.callout)
                                    .lineLimit(1)
                                if event.isAllDay {
                                    Text("全天")
                                        .font(.caption)
                                        .foregroundStyle(FrostTheme.secondaryText)
                                } else {
                                    Text("\(Formatters.time.string(from: event.startDate)) - \(Formatters.time.string(from: event.endDate))")
                                        .font(.caption)
                                        .foregroundStyle(FrostTheme.secondaryText)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Section {
                    NavigationLink(value: SidebarSelection.settings) {
                        Label("设置", systemImage: "gearshape")
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
    }
}

// MARK: - 倒计时面板

/// 左栏倒计时卡片：阶段、剩余时间、进度条与结束按钮
struct CountdownPanelCard: View {
    @ObservedObject var model: CountdownViewModel
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var phaseColor: Color {
        model.phase == .rest ? FrostTheme.secondary : FrostTheme.primary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Label(
                    model.phase == .rest ? "休息中" : "专注中",
                    systemImage: model.phase == .rest ? "cup.and.saucer" : "target"
                )
                .font(.caption)
                .foregroundStyle(phaseColor)
                Spacer()
                Text(model.displayRemainingText)
                    .font(.system(.title3, design: .monospaced).weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(FrostTheme.text)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(FrostTheme.separator)
                    Capsule()
                        .fill(phaseColor)
                        .frame(width: max(3, proxy.size.width * model.displayProgress))
                }
            }
            .frame(height: 4)

            HStack {
                Text("倒计时 · 第 \(model.cyclesCompleted + (model.phase == .work ? 1 : 0))/\(model.totalRounds) 轮专注")
                    .font(.caption2)
                    .foregroundStyle(FrostTheme.secondaryText)
                Spacer()
                Button("结束") {
                    try? model.end()
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .tint(FrostTheme.warning)
            }
        }
        .padding(10)
        .background(FrostTheme.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(FrostTheme.separator)
        )
        .onReceive(ticker) { _ in
            model.refresh()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("倒计时\(model.phaseLabel)，剩余 \(model.displayRemainingText)")
    }
}

// MARK: - 正计时面板

/// 左栏正计时卡片：任务名与已用时间
struct CountUpPanelCard: View {
    @ObservedObject var model: TimerViewModel
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.activeTaskTitle ?? "")
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(FrostTheme.secondaryText)
                Text(model.elapsedText)
                    .font(.system(.title3, design: .monospaced).weight(.light))
                    .monospacedDigit()
                    .foregroundStyle(FrostTheme.text)
            }
            Spacer()
            Text(model.phase == .running ? "[计时中]" : "[已暂停]")
                .font(.caption2)
                .foregroundStyle(FrostTheme.secondaryText)
        }
        .padding(10)
        .background(FrostTheme.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(FrostTheme.separator)
        )
        .onReceive(ticker) { _ in
            model.refresh()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正计时 \(model.elapsedText)，\(model.phase == .running ? "计时中" : "已暂停")")
    }
}
