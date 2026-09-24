import Foundation
import SwiftData

/// 设置 ViewModel：设置读写、保留策略应用与历史清理
@MainActor
public final class SettingsViewModel: ObservableObject {
    @Published public private(set) var settings: AppSettings

    private let settingsService: SettingsService
    private let history: HistoryService
    private let persistence: PersistenceService

    public init(settings: SettingsService, history: HistoryService, persistence: PersistenceService) {
        self.settingsService = settings
        self.history = history
        self.persistence = persistence
        self.settings = settings.settings()
    }

    /// 修改设置（写入 settings.changed 历史并持久化）
    public func update(_ apply: @escaping (AppSettings) -> Void) throws {
        try settingsService.update(apply)
        settings = settingsService.settings()
    }

    /// 立即应用历史保留策略，返回清理条数
    @discardableResult
    public func applyRetentionPolicy() throws -> Int {
        try history.applyRetentionPolicy(settingsService.settings())
    }

    /// 清空历史记录
    public func clearHistory() throws {
        try history.clearAll()
    }

    /// 清除已完成任务，返回删除数量
    @discardableResult
    public func clearCompletedTasks() throws -> Int {
        let completed = try persistence.fetch(FetchDescriptor<TodoTask>(predicate: #Predicate { $0.status == "completed" }))
        for task in completed {
            persistence.delete(task)
        }
        try persistence.save()
        return completed.count
    }
}
