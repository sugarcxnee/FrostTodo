import Foundation

/// 时钟抽象：业务服务统一通过协议取当前时间，测试注入可控时钟
public protocol ClockProviding: AnyObject {
    var now: Date { get }
}

/// 系统真实时钟
public final class SystemClock: ClockProviding {
    public init() {}
    public var now: Date { Date() }
}

/// 手动推进的时钟，仅用于测试
public final class ManualClock: ClockProviding {
    public var now: Date

    public init(_ now: Date = Date()) {
        self.now = now
    }

    public func advance(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}
