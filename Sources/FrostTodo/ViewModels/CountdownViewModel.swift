import Foundation

/// 倒计时 ViewModel：展示状态与操作入口（时长取自设置）
@MainActor
public final class CountdownViewModel: ObservableObject {
    @Published public private(set) var now: Date

    private let countdown: CountdownService
    private let persistence: PersistenceService
    private let clock: ClockProviding

    public init(countdown: CountdownService, persistence: PersistenceService, clock: ClockProviding) {
        self.countdown = countdown
        self.persistence = persistence
        self.clock = clock
        now = clock.now
    }

    // MARK: - 展示状态

    public var isActive: Bool { countdown.isActive }

    public var phase: CountdownPhase { countdown.phase }

    public var phaseLabel: String {
        switch countdown.phase {
        case .work: return "专注"
        case .rest: return "休息"
        case .idle: return ""
        }
    }

    public var activeTaskID: UUID? { countdown.activeTaskID }

    /// 已完成的专注轮次
    public var cyclesCompleted: Int { countdown.cyclesCompleted }

    public var remainingSeconds: Int {
        countdown.remainingSeconds(now: now)
    }

    public var remainingText: String {
        TimerViewModel.format(seconds: remainingSeconds)
    }

    /// 当前阶段进度：1 为满（刚开始），0 为到点
    public var progress: Double {
        let total: Int
        switch countdown.phase {
        case .work: total = countdown.workSeconds
        case .rest: total = countdown.restSeconds
        case .idle: return 0
        }
        guard total > 0 else { return 0 }
        return Double(remainingSeconds) / Double(total)
    }

    /// 刷新展示时间并推进阶段（由视图层秒级计时器驱动）
    public func refresh() {
        now = clock.now
        try? countdown.advanceIfNeeded()
    }

    // MARK: - 操作

    /// 按设置中的专注与休息时长启动倒计时
    public func start(task: TodoTask) throws {
        let settings = persistence.settings()
        try countdown.start(
            task: task,
            workMinutes: settings.countdownWorkMinutes,
            restMinutes: settings.countdownRestMinutes
        )
        refresh()
    }

    /// 随时结束倒计时
    public func end() throws {
        try countdown.end()
        refresh()
    }
}
