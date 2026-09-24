import Testing
import Foundation
import SwiftData
@testable import FrostTodo

@Suite("Phase 1: 迁移占位")
struct Phase1MigrationTests {

    @Test("Schema V1 标识与模型清单")
    func schemaV1IdentifierAndModels() {
        #expect(FrostTodoSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(FrostTodoSchemaV1.models.count == 5)
        let modelNames = Set(FrostTodoSchemaV1.models.map { String(describing: $0) })
        #expect(modelNames.contains("TodoTask"))
        #expect(modelNames.contains("TimeSession"))
        #expect(modelNames.contains("HistoryEvent"))
        #expect(modelNames.contains("AppSettings"))
        #expect(modelNames.contains("TimerSnapshot"))
    }

    @Test("迁移计划当前为占位（无迁移阶段）")
    func migrationPlanPlaceholder() {
        #expect(FrostTodoMigrationPlan.stages.isEmpty)
        #expect(FrostTodoMigrationPlan.schemas.count == 1)
    }
}
