import Foundation

/// 业务服务向历史服务提交的写入请求。
/// payload 为扁平键值对，由 HistoryService 序列化为 payloadJSON。
public struct HistoryEventInput {
    public var type: HistoryEventType
    public var taskID: UUID?
    public var sessionID: UUID?
    public var calendarEventID: String?
    public var title: String
    public var detail: String?
    public var payload: [String: String]
    public var source: HistorySource
    public var isUndoable: Bool
    /// 显式时间戳（默认由 HistoryService 取当前时钟，保证同批写入可排序）
    public var createdAt: Date?

    public init(
        type: HistoryEventType,
        taskID: UUID? = nil,
        sessionID: UUID? = nil,
        calendarEventID: String? = nil,
        title: String,
        detail: String? = nil,
        payload: [String: String] = [:],
        source: HistorySource = .user,
        isUndoable: Bool = false,
        createdAt: Date? = nil
    ) {
        self.type = type
        self.taskID = taskID
        self.sessionID = sessionID
        self.calendarEventID = calendarEventID
        self.title = title
        self.detail = detail
        self.payload = payload
        self.source = source
        self.isUndoable = isUndoable
        self.createdAt = createdAt
    }
}

/// 历史写入协议：所有业务服务通过该协议写历史，具体实现由 HistoryService 提供
public protocol HistoryRecording: AnyObject {
    /// 写入一条历史记录；返回失败说明业务操作应标记为部分失败
    func record(_ input: HistoryEventInput) throws
}

/// 空实现：Phase 2 期间 TimerService 在未接入 HistoryService 时使用
public final class NullHistoryRecorder: HistoryRecording {
    public init() {}
    public func record(_ input: HistoryEventInput) throws {}
}
