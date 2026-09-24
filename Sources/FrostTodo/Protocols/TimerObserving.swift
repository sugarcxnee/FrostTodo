import Foundation

/// 计时观察者：监听 Session 生命周期，供日历联动（Phase 4）等外部模块挂接
public protocol TimerObserving: AnyObject {
    /// 一个时间段开始（start 或 resume 触发）
    func timerDidStartSession(_ session: TimeSession, task: TodoTask)

    /// 一个时间段结束（pause、stop、完成或切换任务触发）
    func timerDidEndSession(_ session: TimeSession, task: TodoTask)

    /// 计时中的任务被完成
    func timerDidCompleteTask(_ task: TodoTask)
}

/// 计时器错误
public enum TimerError: Error, Equatable {
    /// 已在计时同一任务，拒绝重复开始
    case alreadyTrackingTask
    /// 没有进行中的计时
    case noActiveTimer
    /// 暂停要求计时进行中
    case timerNotRunning
    /// 继续要求处于暂停状态
    case timerNotPaused
    /// 任务已完成，不能开始计时
    case taskAlreadyCompleted
}
