import Foundation
import SwiftData

/// 外观模式：跟随系统 / 浅色 / 深色
public enum AppearanceMode: String, Codable, CaseIterable {
    case system
    case light
    case dark
}

/// 历史保留策略：永久 / 按天数 / 按条数
public enum HistoryRetentionPolicy: String, Codable, CaseIterable {
    case forever
    case byDays
    case byCount
}

/// 应用设置模型（单例存储）
@Model
public final class AppSettings {
    public var defaultCalendarID: String?
    public var writeToCalendar: Bool
    public var createEventOnStart: Bool
    public var createCompletionEvent: Bool
    public var defaultEstimatedMinutes: Int
    public var appearance: String
    public var historyRetentionPolicy: String
    public var historyRetentionDays: Int
    public var historyRetentionCount: Int
    /// 倒计时专注时长（分钟）；内联默认值保证轻量迁移可用
    public var countdownWorkMinutes: Int = 25
    /// 倒计时休息时长（分钟），0 表示纯倒计时
    public var countdownRestMinutes: Int = 5

    public init(
        defaultCalendarID: String? = nil,
        writeToCalendar: Bool = true,
        createEventOnStart: Bool = true,
        createCompletionEvent: Bool = true,
        defaultEstimatedMinutes: Int = 25,
        appearance: String = AppearanceMode.system.rawValue,
        historyRetentionPolicy: String = HistoryRetentionPolicy.forever.rawValue,
        historyRetentionDays: Int = 365,
        historyRetentionCount: Int = 10_000,
        countdownWorkMinutes: Int = 25,
        countdownRestMinutes: Int = 5
    ) {
        self.defaultCalendarID = defaultCalendarID
        self.writeToCalendar = writeToCalendar
        self.createEventOnStart = createEventOnStart
        self.createCompletionEvent = createCompletionEvent
        self.defaultEstimatedMinutes = defaultEstimatedMinutes
        self.appearance = appearance
        self.historyRetentionPolicy = historyRetentionPolicy
        self.historyRetentionDays = historyRetentionDays
        self.historyRetentionCount = historyRetentionCount
        self.countdownWorkMinutes = countdownWorkMinutes
        self.countdownRestMinutes = countdownRestMinutes
    }

    public var appearanceValue: AppearanceMode {
        get { AppearanceMode(rawValue: appearance) ?? .system }
        set { appearance = newValue.rawValue }
    }

    public var historyRetentionPolicyValue: HistoryRetentionPolicy {
        get { HistoryRetentionPolicy(rawValue: historyRetentionPolicy) ?? .forever }
        set { historyRetentionPolicy = newValue.rawValue }
    }
}
