import Testing
import Foundation
import SwiftData
@testable import FrostTodo

// MARK: - CountdownService

@MainActor
@Suite("Phase 7: 倒计时引擎")
struct Phase7CountdownServiceTests {

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private struct Environment {
        let clock: ManualClock
        let persistence: PersistenceService
        let history: HistoryService
        let tasks: TaskService
        let timer: TimerService
        let countdown: CountdownService
        let provider: MockCalendarProvider
        let calendarSync: CalendarSyncService
        let settings: AppSettings
    }

    private func makeEnvironment() throws -> Environment {
        let clock = ManualClock(epoch)
        let persistence = try PersistenceService(inMemory: true)
        let history = HistoryService(persistence: persistence, clock: clock)
        let tasks = TaskService(persistence: persistence, history: history, clock: clock)
        let timer = TimerService(persistence: persistence, clock: clock, history: history)
        let provider = MockCalendarProvider()
        let calendarSync = CalendarSyncService(provider: provider, persistence: persistence, history: history, clock: clock)
        timer.observer = calendarSync
        tasks.timerService = timer
        let countdown = CountdownService(persistence: persistence, timer: timer, history: history, clock: clock)
        return Environment(
            clock: clock, persistence: persistence, history: history,
            tasks: tasks, timer: timer, countdown: countdown,
            provider: provider, calendarSync: calendarSync,
            settings: persistence.settings()
        )
    }

    @Test("启动倒计时：进入专注阶段，同时开始任务计时")
    func startBeginsWorkPhaseAndTimer() throws {
        let env = try makeEnvironment()
        let task = try env.tasks.create(title: "倒计时任务", estimatedMinutes: 30)

        try env.countdown.start(task: task, workMinutes: 25, restMinutes: 5)

        #expect(env.countdown.phase == .work)
        #expect(env.countdown.remainingSeconds() == 25 * 60)
        #expect(env.countdown.cyclesCompleted == 0)
        #expect(env.timer.phase == .running)
        #expect(task.sessions.count == 1)

        let started = try env.history.events(matching: HistoryFilter(types: [.countdownStarted]))
        #expect(started.count == 1)
        #expect(started.first?.payload["workMinutes"] == "25")
        #expect(started.first?.payload["restMinutes"] == "5")
    }

    @Test("已在正计时同一任务时启动倒计时：复用当前 Session 不报错")
    func startReusesExistingTracking() throws {
        let env = try makeEnvironment()
        let task = try env.tasks.create(title: "复用任务")
        try env.timer.start(task: task)

        try env.countdown.start(task: task, workMinutes: 10, restMinutes: 0)
        #expect(env.countdown.phase == .work)
        #expect(task.sessions.count == 1) // 未新建 Session
    }

    @Test("重复启动倒计时抛出错误")
    func doubleStartThrows() throws {
        let env = try makeEnvironment()
        let task = try env.tasks.create(title: "防重")
        try env.countdown.start(task: task, workMinutes: 10, restMinutes: 5)

        #expect(throws: CountdownError.alreadyRunning) {
            try env.countdown.start(task: task, workMinutes: 10, restMinutes: 5)
        }
    }

    @Test("专注到点进入休息：计时暂停、Session 结束、阶段历史写入")
    func workToRestTransition() throws {
        let env = try makeEnvironment()
        let task = try env.tasks.create(title: "番茄任务")
        try env.countdown.start(task: task, workMinutes: 25, restMinutes: 5, rounds: 4)

        env.clock.advance(by: 25 * 60)
        try env.countdown.advanceIfNeeded()

        #expect(env.countdown.phase == .rest)
        #expect(env.countdown.remainingSeconds() == 5 * 60)
        #expect(env.countdown.cyclesCompleted == 1)
        #expect(env.timer.phase == .paused)
        #expect(task.sessions.first?.isRunning == false)
        #expect(task.sessions.first?.durationSeconds == 25 * 60)

        let completed = try env.history.events(matching: HistoryFilter(types: [.countdownPhaseCompleted]))
        #expect(completed.count == 1)
        #expect(completed.first?.payload["phase"] == "work")
    }

    @Test("休息到点回到专注：计时恢复并开启新 Session")
    func restToWorkTransition() throws {
        let env = try makeEnvironment()
        let task = try env.tasks.create(title: "循环任务")
        try env.countdown.start(task: task, workMinutes: 25, restMinutes: 5, rounds: 4)

        env.clock.advance(by: 25 * 60)
        try env.countdown.advanceIfNeeded() // 专注结束进入休息
        env.clock.advance(by: 5 * 60)
        try env.countdown.advanceIfNeeded() // 休息结束回到专注

        #expect(env.countdown.phase == .work)
        #expect(env.countdown.cyclesCompleted == 1)
        #expect(env.timer.phase == .running)
        #expect(task.sessions.count == 2)
        let completed = try env.history.events(matching: HistoryFilter(types: [.countdownPhaseCompleted]))
        #expect(completed.map { $0.payload["phase"] } .contains("rest"))
    }

    @Test("纯倒计时（休息为 0）：到点自动结束并停止计时")
    func pureCountdownAutoEnds() throws {
        let env = try makeEnvironment()
        let task = try env.tasks.create(title: "纯倒计时")
        try env.countdown.start(task: task, workMinutes: 10, restMinutes: 0)

        env.clock.advance(by: 10 * 60)
        try env.countdown.advanceIfNeeded()

        #expect(env.countdown.phase == .idle)
        #expect(env.timer.phase == .idle)
        #expect(task.sessions.first?.durationSeconds == 10 * 60)
        let ended = try env.history.events(matching: HistoryFilter(types: [.countdownEnded]))
        #expect(ended.count == 1)
        #expect(ended.first?.payload["reason"] == "natural")
    }

    @Test("手动结束：专注阶段随时结束，剩余时间记录到历史")
    func manualEndDuringWork() throws {
        let env = try makeEnvironment()
        let task = try env.tasks.create(title: "手动结束")
        try env.countdown.start(task: task, workMinutes: 25, restMinutes: 5)

        env.clock.advance(by: 600)
        try env.countdown.end()

        #expect(env.countdown.phase == .idle)
        #expect(env.timer.phase == .idle)
        #expect(task.sessions.first?.durationSeconds == 600)
        let ended = try #require(
            env.history.events(matching: HistoryFilter(types: [.countdownEnded])).first
        )
        #expect(ended.payload["reason"] == "manual")
        #expect(ended.payload["remainingSeconds"] == "900")
    }

    @Test("手动结束：休息阶段同样可随时结束")
    func manualEndDuringRest() throws {
        let env = try makeEnvironment()
        let task = try env.tasks.create(title: "休息中结束")
        try env.countdown.start(task: task, workMinutes: 25, restMinutes: 5, rounds: 4)
        env.clock.advance(by: 25 * 60 + 1)
        try env.countdown.advanceIfNeeded()
        #expect(env.countdown.phase == .rest)

        env.clock.advance(by: 60)
        try env.countdown.end()

        #expect(env.countdown.phase == .idle)
        #expect(env.timer.phase == .idle)
    }

    @Test("空闲时结束抛出错误")
    func endWhenIdleThrows() throws {
        let env = try makeEnvironment()
        #expect(throws: CountdownError.notRunning) {
            try env.countdown.end()
        }
    }

    @Test("剩余时间随时钟递减，未到点不转换阶段")
    func remainingDecreasesWithoutTransition() throws {
        let env = try makeEnvironment()
        let task = try env.tasks.create(title: "递减")
        try env.countdown.start(task: task, workMinutes: 10, restMinutes: 5, rounds: 4)

        env.clock.advance(by: 60)
        try env.countdown.advanceIfNeeded()
        #expect(env.countdown.remainingSeconds() == 9 * 60)
        #expect(env.countdown.phase == .work)
        env.clock.advance(by: 9 * 60)
        try env.countdown.advanceIfNeeded()
        #expect(env.countdown.phase == .rest)
    }

    // MARK: - 重启恢复

    @Test("重启恢复：进行中的倒计时继续")
    func restoreRunningCountdown() throws {
        let env = try makeEnvironment()
        let task = try env.tasks.create(title: "恢复")
        try env.countdown.start(task: task, workMinutes: 25, restMinutes: 5)
        env.clock.advance(by: 300)
        try env.persistence.save()

        let persistence2 = try PersistenceService(container: env.persistence.container)
        let timer2 = TimerService(persistence: persistence2, clock: env.clock)
        let history2 = HistoryService(persistence: persistence2, clock: env.clock)
        let countdown2 = CountdownService(persistence: persistence2, timer: timer2, history: history2, clock: env.clock)

        #expect(countdown2.phase == .work)
        #expect(countdown2.remainingSeconds() == 25 * 60 - 300)
        #expect(timer2.phase == .running)
    }

    @Test("重启恢复：关闭期间专注段到期则进入休息")
    func restoreExpiredWorkEntersRest() throws {
        let env = try makeEnvironment()
        let task = try env.tasks.create(title: "过期专注")
        try env.countdown.start(task: task, workMinutes: 25, restMinutes: 5, rounds: 4)
        env.clock.advance(by: 30 * 60)
        try env.persistence.save()

        let persistence2 = try PersistenceService(container: env.persistence.container)
        let timer2 = TimerService(persistence: persistence2, clock: env.clock)
        let history2 = HistoryService(persistence: persistence2, clock: env.clock)
        let countdown2 = CountdownService(persistence: persistence2, timer: timer2, history: history2, clock: env.clock)

        #expect(countdown2.phase == .rest)
        #expect(timer2.phase == .paused)
    }

    @Test("重启恢复：纯倒计时关闭期间到期则结束并停止计时")
    func restoreExpiredPureCountdownEnds() throws {
        let env = try makeEnvironment()
        let task = try env.tasks.create(title: "过期纯倒计时")
        try env.countdown.start(task: task, workMinutes: 10, restMinutes: 0)
        env.clock.advance(by: 15 * 60)
        try env.persistence.save()

        let persistence2 = try PersistenceService(container: env.persistence.container)
        let timer2 = TimerService(persistence: persistence2, clock: env.clock)
        let history2 = HistoryService(persistence: persistence2, clock: env.clock)
        let countdown2 = CountdownService(persistence: persistence2, timer: timer2, history: history2, clock: env.clock)

        #expect(countdown2.phase == .idle)
        #expect(timer2.phase == .idle)
        // 计时 Session 覆盖整个关闭期间（15 分钟），倒计时自身按 10 分钟自然结束
        let taskID = task.id
        let session = try #require(
            try persistence2.fetch(FetchDescriptor<TimeSession>(predicate: #Predicate { $0.taskID == taskID })).first
        )
        #expect(session.durationSeconds == 15 * 60)
    }

    // MARK: - 日历联动

    @Test("纯倒计时自然结束：日历事件以计时记录更新（结束即记录到日历）")
    func naturalEndRecordsCalendar() throws {
        let env = try makeEnvironment()
        let task = try env.tasks.create(title: "日历倒计时")
        try env.countdown.start(task: task, workMinutes: 25, restMinutes: 0)

        env.clock.advance(by: 25 * 60)
        try env.countdown.advanceIfNeeded()

        let eventID = try #require(task.calendarEventIDs.first)
        let event = try #require(env.provider.events[eventID])
        #expect(event.title == "[计时记录] 日历倒计时")
        #expect(event.endDate == epoch.addingTimeInterval(25 * 60))
        #expect(event.notes.contains("实际时长: 1500 秒"))
    }

    @Test("手动结束倒计时：同样更新日历事件")
    func manualEndRecordsCalendar() throws {
        let env = try makeEnvironment()
        let task = try env.tasks.create(title: "手动日历")
        try env.countdown.start(task: task, workMinutes: 25, restMinutes: 5)

        env.clock.advance(by: 300)
        try env.countdown.end()

        let eventID = try #require(task.calendarEventIDs.first)
        let event = try #require(env.provider.events[eventID])
        #expect(event.title == "[计时记录] 手动日历")
        #expect(event.endDate == epoch.addingTimeInterval(300))
    }

    // MARK: - 设置

    @Test("倒计时设置：默认值、修改持久化与历史")
    func countdownSettings() throws {
        let env = try makeEnvironment()
        #expect(env.settings.countdownWorkMinutes == 25)
        #expect(env.settings.countdownRestMinutes == 5)
        #expect(env.settings.countdownRounds == 4)

        let settingsService = SettingsService(persistence: env.persistence, history: env.history, clock: env.clock)
        try settingsService.update {
            $0.countdownWorkMinutes = 50
            $0.countdownRestMinutes = 0
            $0.countdownRounds = 2
        }

        let other = ModelContext(env.persistence.container)
        let reloaded = try #require(other.fetch(FetchDescriptor<AppSettings>()).first)
        #expect(reloaded.countdownWorkMinutes == 50)
        #expect(reloaded.countdownRestMinutes == 0)
        #expect(reloaded.countdownRounds == 2)
        let changed = try #require(
            env.history.events(matching: HistoryFilter(types: [.settingsChanged])).first
        )
        #expect(changed.detail?.contains("倒计时专注时长") == true)
        #expect(changed.detail?.contains("倒计时休息时长") == true)
        #expect(changed.detail?.contains("倒计时轮数") == true)
    }
}

// MARK: - CountdownViewModel

@MainActor
@Suite("Phase 7: 倒计时 ViewModel")
struct Phase7CountdownViewModelTests {

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("展示状态：剩余时间、阶段标签、进度")
    func displayState() throws {
        let clock = ManualClock(epoch)
        let persistence = try PersistenceService(inMemory: true)
        let history = HistoryService(persistence: persistence, clock: clock)
        let tasks = TaskService(persistence: persistence, history: history, clock: clock)
        let timer = TimerService(persistence: persistence, clock: clock, history: history)
        let countdown = CountdownService(persistence: persistence, timer: timer, history: history, clock: clock)
        let viewModel = CountdownViewModel(countdown: countdown, persistence: persistence, clock: clock)

        #expect(viewModel.isActive == false)
        #expect(viewModel.phaseLabel == "")

        let task = try tasks.create(title: "展示")
        try viewModel.start(task: task) // 使用设置默认 25/5
        #expect(viewModel.isActive == true)
        #expect(viewModel.phaseLabel == "专注")

        clock.advance(by: 25 * 60)
        viewModel.refresh() // 推进阶段
        #expect(viewModel.phaseLabel == "休息")

        clock.advance(by: 2 * 60)
        viewModel.refresh()
        #expect(viewModel.remainingText == "03:00")
        #expect(abs(viewModel.progress - 0.6) < 0.001) // 休息 5 分钟已过 2 分钟

        try viewModel.end()
        #expect(viewModel.isActive == false)
    }

    @Test("休息为 0 的纯倒计时展示")
    func pureCountdownDisplay() throws {
        let clock = ManualClock(epoch)
        let persistence = try PersistenceService(inMemory: true)
        let history = HistoryService(persistence: persistence, clock: clock)
        let tasks = TaskService(persistence: persistence, history: history, clock: clock)
        let timer = TimerService(persistence: persistence, clock: clock, history: history)
        let countdown = CountdownService(persistence: persistence, timer: timer, history: history, clock: clock)
        let viewModel = CountdownViewModel(countdown: countdown, persistence: persistence, clock: clock)

        let settings = persistence.settings()
        settings.countdownRestMinutes = 0
        settings.countdownRounds = 1
        try persistence.save()

        let task = try tasks.create(title: "纯倒计时展示")
        try viewModel.start(task: task)
        clock.advance(by: 24 * 60)
        viewModel.refresh()
        #expect(viewModel.phaseLabel == "专注")
        #expect(viewModel.remainingText == "01:00")

        clock.advance(by: 61)
        viewModel.refresh() // 自然结束
        #expect(viewModel.isActive == false)
    }
}

// MARK: - 任务级倒计时时长

@MainActor
@Suite("Phase 7: 任务级倒计时时长")
struct Phase7TaskCountdownTests {

    private func makeEnvironment() throws -> (CountdownViewModel, CountdownService, TaskService, PersistenceService, ManualClock) {
        let clock = ManualClock(Date(timeIntervalSince1970: 1_700_000_000))
        let persistence = try PersistenceService(inMemory: true)
        let history = HistoryService(persistence: persistence, clock: clock)
        let tasks = TaskService(persistence: persistence, history: history, clock: clock)
        let timer = TimerService(persistence: persistence, clock: clock, history: history)
        let countdown = CountdownService(persistence: persistence, timer: timer, history: history, clock: clock)
        let viewModel = CountdownViewModel(countdown: countdown, persistence: persistence, clock: clock)
        return (viewModel, countdown, tasks, persistence, clock)
    }

    @Test("任务自定义专注与休息时长：启动倒计时优先生效")
    func taskCustomDurationsTakePrecedence() throws {
        let (viewModel, countdown, tasks, _, _) = try makeEnvironment()
        let task = try tasks.create(title: "自定义时长", countdownWorkMinutes: 50, countdownRestMinutes: 0)

        try viewModel.start(task: task)

        #expect(viewModel.isActive)
        #expect(countdown.remainingSeconds() == 50 * 60)
        #expect(countdown.restSeconds == 0)
    }

    @Test("任务未自定义：回落设置默认时长")
    func fallsBackToSettingsDefaults() throws {
        let (viewModel, countdown, tasks, _, _) = try makeEnvironment()
        let task = try tasks.create(title: "默认时长")

        try viewModel.start(task: task)

        #expect(countdown.remainingSeconds() == 25 * 60)
        #expect(countdown.restSeconds == 5 * 60)
    }

    @Test("部分自定义：仅专注生效，休息回落默认")
    func partialOverrideFallsBack() throws {
        let (viewModel, countdown, tasks, persistence, _) = try makeEnvironment()
        persistence.settings().countdownRestMinutes = 10
        try persistence.save()
        let task = try tasks.create(title: "部分自定义", countdownWorkMinutes: 40)

        try viewModel.start(task: task)

        #expect(countdown.remainingSeconds() == 40 * 60)
        #expect(countdown.restSeconds == 10 * 60)
    }

    @Test("设置默认值变更不影响已自定义的任务")
    func settingsChangeDoesNotAffectCustomTask() throws {
        let (viewModel, countdown, tasks, persistence, _) = try makeEnvironment()
        let task = try tasks.create(title: "独立任务", countdownWorkMinutes: 45, countdownRestMinutes: 15)
        persistence.settings().countdownWorkMinutes = 30
        persistence.settings().countdownRestMinutes = 30
        try persistence.save()

        try viewModel.start(task: task)

        #expect(countdown.remainingSeconds() == 45 * 60)
        #expect(countdown.restSeconds == 15 * 60)
    }

    @Test("编辑任务倒计时时长：产生 task.updated 历史且 detail 包含字段")
    func editingDurationsWritesHistory() throws {
        let (_, _, tasks, persistence, clock) = try makeEnvironment()
        let history = HistoryService(persistence: persistence, clock: clock)
        let task = try tasks.create(title: "编辑倒计时时长")

        try tasks.update(task) {
            $0.countdownWorkMinutes = 45
            $0.countdownRestMinutes = 10
        }

        let event = try #require(
            history.events(matching: HistoryFilter(types: [.taskUpdated], taskID: task.id)).first
        )
        #expect(event.detail?.contains("倒计时专注时长") == true)
        #expect(event.detail?.contains("倒计时休息时长") == true)
        #expect(event.payload["倒计时专注时长"] == "跟随默认 -> 45 分钟")
        #expect(event.payload["倒计时休息时长"] == "跟随默认 -> 10 分钟")
    }
}

// MARK: - 倒计时轮数

@MainActor
@Suite("Phase 7: 倒计时轮数")
struct Phase7CountdownRoundsTests {

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeEnvironment() throws -> (CountdownService, CountdownViewModel, TaskService, TimerService, PersistenceService, ManualClock) {
        let clock = ManualClock(epoch)
        let persistence = try PersistenceService(inMemory: true)
        let history = HistoryService(persistence: persistence, clock: clock)
        let tasks = TaskService(persistence: persistence, history: history, clock: clock)
        let timer = TimerService(persistence: persistence, clock: clock, history: history)
        let countdown = CountdownService(persistence: persistence, timer: timer, history: history, clock: clock)
        let viewModel = CountdownViewModel(countdown: countdown, persistence: persistence, clock: clock)
        return (countdown, viewModel, tasks, timer, persistence, clock)
    }

    @Test("纯倒计时多轮连续：总时长为专注乘轮数，轮间不切段")
    func pureCountdownMultipleRounds() throws {
        let (countdown, _, tasks, timer, _, clock) = try makeEnvironment()
        let task = try tasks.create(title: "多轮纯倒计时")
        try countdown.start(task: task, workMinutes: 10, restMinutes: 0, rounds: 3)

        #expect(countdown.remainingTotalWorkSeconds() == 30 * 60)

        clock.advance(by: 10 * 60)
        try countdown.advanceIfNeeded()
        #expect(countdown.phase == .work)
        #expect(countdown.cyclesCompleted == 1)
        #expect(countdown.remainingTotalWorkSeconds() == 20 * 60)
        // 休息为 0：轮间不暂停，Session 连续
        #expect(timer.phase == .running)
        #expect(task.sessions.count == 1)

        // 按轮边界逐段推进（阶段转换在 tick 时发生）
        clock.advance(by: 10 * 60)
        try countdown.advanceIfNeeded()
        clock.advance(by: 10 * 60)
        try countdown.advanceIfNeeded()
        #expect(countdown.phase == .idle)
        #expect(timer.phase == .idle)
        #expect(task.sessions.count == 1)
        #expect(task.sessions.first?.durationSeconds == 30 * 60)
    }

    @Test("休息模式轮数封顶：最后一轮专注完成后自然结束，不再进入休息")
    func roundsCapEndsWithoutFinalRest() throws {
        let (countdown, _, tasks, timer, _, clock) = try makeEnvironment()
        let task = try tasks.create(title: "两轮番茄")
        try countdown.start(task: task, workMinutes: 5, restMinutes: 5, rounds: 2)

        clock.advance(by: 5 * 60)
        try countdown.advanceIfNeeded()
        #expect(countdown.phase == .rest) // 第 1 轮后正常休息

        clock.advance(by: 5 * 60)
        try countdown.advanceIfNeeded()
        #expect(countdown.phase == .work) // 第 2 轮专注

        clock.advance(by: 5 * 60)
        try countdown.advanceIfNeeded()
        #expect(countdown.phase == .idle) // 最后一轮完成即结束
        #expect(countdown.cyclesCompleted == 2)
        #expect(timer.phase == .idle)
    }

    @Test("休息中的总剩余包含后续专注段")
    func totalRemainingDuringRest() throws {
        let (countdown, _, tasks, _, _, clock) = try makeEnvironment()
        let task = try tasks.create(title: "总剩余")
        try countdown.start(task: task, workMinutes: 5, restMinutes: 5, rounds: 2)

        clock.advance(by: 5 * 60)
        try countdown.advanceIfNeeded() // 进入休息
        clock.advance(by: 60)
        #expect(countdown.phase == .rest)
        // 剩余休息 4 分钟 + 最后一轮专注 5 分钟
        #expect(countdown.remainingTotalWorkSeconds() == 4 * 60 + 5 * 60)
    }

    @Test("展示层：休息为 0 显示总时长（专注乘轮数）并按总时长计算进度")
    func displayShowsTotalForPureCountdown() throws {
        let (_, viewModel, tasks, _, persistence, clock) = try makeEnvironment()
        let settings = persistence.settings()
        settings.countdownWorkMinutes = 25
        settings.countdownRestMinutes = 0
        settings.countdownRounds = 2
        try persistence.save()

        let task = try tasks.create(title: "总时长展示")
        try viewModel.start(task: task)

        #expect(viewModel.displayRemainingText == "50:00")
        #expect(abs(viewModel.displayProgress - 1.0) < 0.001)

        clock.advance(by: 10 * 60)
        viewModel.refresh()
        #expect(viewModel.displayRemainingText == "40:00")
        #expect(abs(viewModel.displayProgress - 0.8) < 0.001)
    }

    @Test("展示层：休息大于 0 时仍显示当前阶段剩余")
    func displayShowsCurrentPhaseWhenRestEnabled() throws {
        let (_, viewModel, tasks, _, persistence, clock) = try makeEnvironment()
        let settings = persistence.settings()
        settings.countdownWorkMinutes = 25
        settings.countdownRestMinutes = 5
        settings.countdownRounds = 4
        try persistence.save()

        let task = try tasks.create(title: "阶段展示")
        try viewModel.start(task: task)
        clock.advance(by: 10 * 60)
        viewModel.refresh()

        #expect(viewModel.displayRemainingText == "15:00")
        #expect(abs(viewModel.displayProgress - 0.6) < 0.001)
    }

    @Test("轮数解析：任务自定义优先，未设置回落设置默认")
    func roundsResolution() throws {
        let (_, viewModel, tasks, _, persistence, _) = try makeEnvironment()
        persistence.settings().countdownRounds = 4
        try persistence.save()

        let custom = try tasks.create(title: "自定义轮数", countdownRounds: 6)
        let durations = CountdownService.effectiveConfiguration(for: custom, settings: persistence.settings())
        #expect(durations.rounds == 6)

        let plain = try tasks.create(title: "默认轮数")
        let defaults = CountdownService.effectiveConfiguration(for: plain, settings: persistence.settings())
        #expect(defaults.rounds == 4)
        #expect(defaults.workMinutes == 25)
        #expect(defaults.restMinutes == 5)

        _ = try viewModel.start(task: custom)
    }

    @Test("编辑任务轮数产生 task.updated 历史且 payload 记录变更")
    func editingRoundsWritesHistory() throws {
        let (_, _, tasks, _, persistence, clock) = try makeEnvironment()
        let history = HistoryService(persistence: persistence, clock: clock)
        let task = try tasks.create(title: "编辑轮数")

        try tasks.update(task) { $0.countdownRounds = 3 }

        let event = try #require(
            history.events(matching: HistoryFilter(types: [.taskUpdated], taskID: task.id)).first
        )
        #expect(event.detail?.contains("倒计时轮数") == true)
        #expect(event.payload["倒计时轮数"] == "跟随默认 -> 3 轮")
    }
}
