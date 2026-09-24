import Foundation
import SwiftData

/// Schema V1：当前全部数据模型
public enum FrostTodoSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)
    public static let identifier = "FrostTodoSchemaV1"

    public static var models: [any PersistentModel.Type] {
        [
            TodoTask.self,
            TimeSession.self,
            HistoryEvent.self,
            AppSettings.self,
            TimerSnapshot.self,
        ]
    }
}

/// 迁移计划：V1 为首个版本，暂无迁移阶段（占位，后续版本在此追加）
public enum FrostTodoMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [FrostTodoSchemaV1.self]
    }

    public static var stages: [MigrationStage] {
        []
    }
}

/// 持久化服务：统一管理 ModelContainer 与 ModelContext。
/// ModelContext 非线程安全，本服务与业务服务统一在主线程使用。
@MainActor
public final class PersistenceService {
    public let container: ModelContainer
    public let context: ModelContext

    /// - Parameter inMemory: 测试使用内存存储
    public convenience init(inMemory: Bool = false) throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        let schema = Schema(versionedSchema: FrostTodoSchemaV1.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: FrostTodoMigrationPlan.self,
            configurations: configuration
        )
        self.init(container: container)
    }

    /// 复用已有容器（测试中模拟应用重启：同一存储、全新上下文）
    public init(container: ModelContainer) {
        self.container = container
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    public func insert(_ model: some PersistentModel) {
        context.insert(model)
    }

    public func delete(_ model: some PersistentModel) {
        context.delete(model)
    }

    public func save() throws {
        try context.save()
    }

    /// 丢弃未保存的更改（业务操作与历史写入的同一事务回滚）
    public func rollback() {
        context.rollback()
    }

    public func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] {
        try context.fetch(descriptor)
    }

    public func fetchCount<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> Int {
        try context.fetchCount(descriptor)
    }

    /// 删除指定类型的全部数据，返回删除数量
    @discardableResult
    public func deleteAll<T: PersistentModel>(_ type: T.Type) throws -> Int {
        let all = try context.fetch(FetchDescriptor<T>())
        for model in all {
            context.delete(model)
        }
        try context.save()
        return all.count
    }

    /// 获取设置单例（不存在则创建）
    public func settings() -> AppSettings {
        if let existing = (try? context.fetch(FetchDescriptor<AppSettings>()))?.first {
            return existing
        }
        let settings = AppSettings()
        context.insert(settings)
        return settings
    }

    /// 获取计时器状态快照单例（不存在则创建）
    public func timerSnapshot() -> TimerSnapshot {
        if let existing = (try? context.fetch(FetchDescriptor<TimerSnapshot>()))?.first {
            return existing
        }
        let snapshot = TimerSnapshot()
        context.insert(snapshot)
        return snapshot
    }
}
