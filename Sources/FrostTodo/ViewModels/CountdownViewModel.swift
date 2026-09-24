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

    /// 本次倒计时总轮数
    public var totalRounds: Int { countdown.totalRounds }

    /// 是否为纯倒计时（休息为 0，多轮连续进行）
    public var isPureCountdown: Bool { countdown.isPureCountdown }

    public var remainingSeconds: Int {
        countdown.remainingSeconds(now: now)
    }

    public var remainingText: String {
        TimerViewModel.format(seconds: remainingSeconds)
    }

    /// 剩余专注总时长（跨轮求和，不含休息）
    public var totalWorkRemainingSeconds: Int {
        countdown.remainingTotalWorkSeconds(now: now)
    }

    /// 面板展示的剩余时间：纯倒计时显示专注乘轮数的总时长，否则显示当前阶段
    public var displayRemainingText: String {
        TimerViewModel.format(seconds: displayRemainingSeconds)
    }

    /// 面板展示的剩余秒数
    public var displayRemainingSeconds: Int {
        isPureCountdown ? totalWorkRemainingSeconds : remainingSeconds
    }

    /// 面板展示的进度：纯倒计时按总时长计算
    public var displayProgress: Double {
        if isPureCountdown {
            let total = max(1, countdown.workSeconds * max(1, countdown.totalRounds))
            return Double(totalWorkRemainingSeconds) / Double(total)
        }
        return progress
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

    /// 启动倒计时：任务自定义配置优先，未设置项用设置默认值
    public func start(task: TodoTask) throws {
        let configuration = CountdownService.effectiveConfiguration(
            for: task,
            settings: persistence.settings()
        )
        try countdown.start(
            task: task,
            workMinutes: configuration.workMinutes,
            restMinutes: configuration.restMinutes,
            rounds: configuration.rounds
        )
        refresh()
    }

    /// 随时结束倒计时
    public func end() throws {
        try countdown.end()
        refresh()
    }
}
