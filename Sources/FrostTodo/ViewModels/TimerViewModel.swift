import Foundation

/// 计时器 ViewModel：展示状态与操作入口
@MainActor
public final class TimerViewModel: ObservableObject {
    @Published public private(set) var now: Date

    private let timer: TimerService
    private let clock: ClockProviding

    public init(timer: TimerService, clock: ClockProviding) {
        self.timer = timer
        self.clock = clock
        now = clock.now
    }

    // MARK: - 展示状态

    public var phase: TimerPhase { timer.phase }

    public var isTracking: Bool { timer.isTracking }

    public var activeTaskTitle: String? { timer.activeTask?.title }

    public var activeTaskID: UUID? { timer.activeTaskID }

    public var elapsedSeconds: Int {
        timer.elapsedSeconds(now: now)
    }

    public var elapsedText: String {
        Self.format(seconds: elapsedSeconds)
    }

    /// 秒表格式：不足一小时 mm:ss，超过则 h:mm:ss
    public static func format(seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    /// 刷新展示时间（由视图层定时器驱动；测试中手动调用）
    public func refresh() {
        now = clock.now
    }

    // MARK: - 操作

    public func start(task: TodoTask) throws {
        try timer.start(task: task)
        refresh()
    }

    public func pause() throws {
        try timer.pause()
        refresh()
    }

    public func resume() throws {
        try timer.resume()
        refresh()
    }

    public func stop() throws {
        try timer.stop()
        refresh()
    }

    @discardableResult
    public func complete() throws -> TodoTask? {
        let task = try timer.completeActiveTask()
        refresh()
        return task
    }
}
