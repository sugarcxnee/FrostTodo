import Testing
import Foundation
import SwiftData
@testable import FrostTodo

@MainActor
@Suite("Phase 1: 设置持久化")
struct Phase1SettingsTests {

    @Test("默认设置值正确")
    func defaultSettingsValues() throws {
        let service = try PersistenceService(inMemory: true)
        let settings = service.settings()
        try service.save()

        #expect(settings.writeToCalendar == true)
        #expect(settings.createEventOnStart == true)
        #expect(settings.createCompletionEvent == true)
        #expect(settings.defaultEstimatedMinutes == 25)
        #expect(settings.appearanceValue == .system)
        #expect(settings.historyRetentionPolicyValue == .forever)
        #expect(settings.defaultCalendarID == nil)
    }

    @Test("设置修改后保存并重新加载")
    func settingsUpdateAndReload() throws {
        let service = try PersistenceService(inMemory: true)
        let settings = service.settings()
        settings.writeToCalendar = false
        settings.createEventOnStart = false
        settings.defaultEstimatedMinutes = 45
        settings.appearanceValue = .dark
        settings.historyRetentionPolicyValue = .byDays
        settings.historyRetentionDays = 30
        settings.defaultCalendarID = "CAL-123"
        try service.save()

        let otherContext = ModelContext(service.container)
        let reloaded = try #require(otherContext.fetch(FetchDescriptor<AppSettings>()).first)
        #expect(reloaded.writeToCalendar == false)
        #expect(reloaded.createEventOnStart == false)
        #expect(reloaded.defaultEstimatedMinutes == 45)
        #expect(reloaded.appearanceValue == .dark)
        #expect(reloaded.historyRetentionPolicyValue == .byDays)
        #expect(reloaded.historyRetentionDays == 30)
        #expect(reloaded.defaultCalendarID == "CAL-123")
    }

    @Test("按条数保留策略切换与阈值")
    func retentionByCountPolicy() throws {
        let service = try PersistenceService(inMemory: true)
        let settings = service.settings()
        settings.historyRetentionPolicyValue = .byCount
        settings.historyRetentionCount = 500
        try service.save()
        #expect(settings.historyRetentionPolicyValue == .byCount)
        #expect(settings.historyRetentionCount == 500)
    }
}
