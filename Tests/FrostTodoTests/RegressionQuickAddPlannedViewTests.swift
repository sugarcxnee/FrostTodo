import Testing
import Foundation
import Combine
import SwiftData
@testable import FrostTodo

/// 回归测试：修复"计划视图下在快速添加输入内容导致任务列表清空"的缺陷。
/// 数据层契约：快速添加（含保存与重载）不得影响计划视图已有任务的可见性；
/// 视图层契约：reload 必须发布 objectWillChange，保证观察该 ViewModel 的视图刷新。
@MainActor
@Suite("回归：计划视图与快速添加")
struct RegressionQuickAddPlannedViewTests {

    private func makeEnvironment() throws -> (TaskListViewModel, TaskService, PersistenceService, ManualClock) {
        let clock = ManualClock(Date(timeIntervalSince1970: 1_700_000_000))
        let persistence = try PersistenceService(inMemory: true)
        let history = HistoryService(persistence: persistence, clock: clock)
        let tasks = TaskService(persistence: persistence, history: history, clock: clock)
        let viewModel = TaskListViewModel(persistence: persistence, tasks: tasks, clock: clock)
        return (viewModel, tasks, persistence, clock)
    }

    @Test("计划视图：快速添加无日期任务后，原计划任务仍然全部可见")
    func quickAddKeepsPlannedTasksVisible() throws {
        let (vm, tasks, _, _) = try makeEnvironment()
        let calendar = Calendar(identifier: .gregorian)
        let future = calendar.date(byAdding: .day, value: 3, to: calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000)))!

        _ = try tasks.create(title: "计划任务 A", startDate: future, tags: ["计划"])
        _ = try tasks.create(title: "计划任务 B", startDate: future, tags: ["计划"])

        vm.selectedView = .planned
        try vm.reload()
        #expect(vm.visibleTasks.count == 2)

        // 模拟在计划视图的快速添加（输入并提交）：新任务无日期，属收件箱
        _ = try vm.quickAdd(title: "快速添加的任务")
        try vm.reload()
        #expect(vm.visibleTasks.map(\.title).sorted() == ["计划任务 A", "计划任务 B"])

        // 再次重载保持稳定（输入过程不应引发数据层变化）
        try vm.reload()
        try vm.reload()
        #expect(vm.visibleTasks.count == 2)
    }

    @Test("reload 发布 objectWillChange：观察 ViewModel 的视图必定刷新")
    func reloadPublishesObjectWillChange() throws {
        let (vm, tasks, _, _) = try makeEnvironment()
        _ = try tasks.create(title: "触发变更")

        var changeCount = 0
        var cancellables = Set<AnyCancellable>()
        vm.objectWillChange.sink { _ in changeCount += 1 }.store(in: &cancellables)

        try vm.reload()
        #expect(changeCount >= 1) // reload 写入多个 @Published 属性，至少触发一次

        vm.searchText = "计划"
        #expect(changeCount >= 2)
    }

    @Test("快速添加后切回收件箱可见新任务，切回计划视图不受污染")
    func quickAddLandsInInboxOnly() throws {
        let (vm, tasks, _, _) = try makeEnvironment()
        let calendar = Calendar(identifier: .gregorian)
        let future = calendar.date(byAdding: .day, value: 5, to: calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000)))!
        _ = try tasks.create(title: "计划任务", startDate: future)
        _ = try vm.quickAdd(title: "收件箱新任务")

        vm.selectedView = .planned
        try vm.reload()
        #expect(vm.visibleTasks.map(\.title) == ["计划任务"])

        vm.selectedView = .inbox
        try vm.reload()
        #expect(vm.visibleTasks.map(\.title) == ["收件箱新任务"])
    }
}
