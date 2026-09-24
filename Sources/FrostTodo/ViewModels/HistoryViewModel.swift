import Foundation

/// 历史视图 ViewModel：筛选数据源、分页、清空与导出
@MainActor
public final class HistoryViewModel: ObservableObject {
    @Published public var filter = HistoryFilter()
    @Published public private(set) var visibleEvents: [HistoryEvent] = []
    @Published public private(set) var totalCount = 0

    public var pageSize = 50
    private var loadedPages = 1
    private let history: HistoryService

    public init(history: HistoryService) {
        self.history = history
    }

    /// 重置分页并按当前筛选加载
    public func reload() throws {
        loadedPages = 1
        filter.limit = pageSize * loadedPages
        visibleEvents = try history.events(matching: filter)
        totalCount = try history.totalCount()
    }

    /// 加载下一页
    public func loadMore() throws {
        guard visibleEvents.count >= pageSize * loadedPages else { return }
        loadedPages += 1
        filter.limit = pageSize * loadedPages
        visibleEvents = try history.events(matching: filter)
    }

    /// 是否还有更多数据
    public var canLoadMore: Bool {
        visibleEvents.count < totalCount
    }

    /// 按天分组的数据源
    public var dayGroups: [(day: Date, events: [HistoryEvent])] {
        visibleEvents.groupedByDay()
    }

    /// 清空全部历史（保留清空记录）
    public func clearAll() throws {
        try history.clearAll()
        try reload()
    }

    public func exportJSON() throws -> Data {
        try history.exportJSON(matching: filter)
    }

    public func exportCSV() throws -> String {
        try history.exportCSV(matching: filter)
    }
}
