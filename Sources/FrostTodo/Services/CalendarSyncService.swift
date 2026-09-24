import Foundation

/// 日历联动服务：监听计时事件，将 Session 与完成状态写入系统日历。
///
/// 事件标题约定（无 emoji）：
/// - 计时中创建：`[计时中] 任务名`
/// - 暂停/停止更新：`[计时记录] 任务名`
/// - 完成更新：`[已完成] 任务名`
/// - 完成新建：`[完成记录] 任务名`（完成时间起 5 分钟止）
///
/// 所有失败均降级处理：不影响本地计时，写入 calendar.syncFailed 历史。
@MainActor
public final class CalendarSyncService: TimerObserving {
    private let provider: CalendarProviding
    private let persistence: PersistenceService
    private let history: HistoryRecording
    private let clock: ClockProviding

    public init(
        provider: CalendarProviding,
        persistence: PersistenceService,
        history: HistoryRecording,
        clock: ClockProviding = SystemClock()
    ) {
        self.provider = provider
        self.persistence = persistence
        self.history = history
        self.clock = clock
    }

    // MARK: - TimerObserving

    public func timerDidStartSession(_ session: TimeSession, task: TodoTask) {
        let settings = persistence.settings()
        guard settings.writeToCalendar, settings.createEventOnStart else { return }
        guard provider.authorizationStatus() == .granted else { return }
        guard let calendarID = resolveTargetCalendar() else {
            recordSyncFailed(task: task, detail: "没有可写日历，无法创建计时事件")
            return
        }

        let estimated = task.estimatedMinutes.map { TimeInterval($0) * 60 } ?? 15 * 60
        let draft = CalendarEventDraft(
            calendarID: calendarID,
            title: "[计时中] \(task.title)",
            startDate: session.startAt,
            endDate: session.startAt.addingTimeInterval(estimated),
            notes: buildNotes(task: task, session: session, status: "计时中", actualDuration: nil),
            url: TaskLink.url(for: task.id)
        )
        do {
            let eventID = try provider.createEvent(draft)
            session.calendarEventID = eventID
            session.calendarIdentifier = calendarID
            task.calendarEventIDs.append(eventID)
            try record(.calendarEventCreated, task: task, session: session, eventID: eventID,
                       title: "创建日历事件：\(draft.title)")
        } catch {
            recordSyncFailed(task: task, detail: "创建计时事件失败：\(describe(error))")
        }
    }

    public func timerDidEndSession(_ session: TimeSession, task: TodoTask) {
        guard persistence.settings().writeToCalendar else { return }
        guard provider.authorizationStatus() == .granted else { return }
        guard let endAt = session.endAt else { return }
        guard let originalEventID = session.calendarEventID else { return }

        if provider.eventExists(id: originalEventID) {
            let notes = buildNotes(task: task, session: session, status: "已结束",
                                   actualDuration: session.durationSeconds)
            do {
                try provider.updateEvent(
                    id: originalEventID,
                    newTitle: "[计时记录] \(task.title)",
                    newEndDate: endAt,
                    newNotes: notes
                )
                try record(.calendarEventUpdated, task: task, session: session, eventID: originalEventID,
                           title: "更新日历事件：\(task.title)")
            } catch {
                recordSyncFailed(task: task, detail: "更新计时事件失败：\(describe(error))")
            }
        } else {
            // 事件被用户手动删除：重建覆盖实际时间段的替代事件
            guard let calendarID = resolveTargetCalendar() else {
                recordSyncFailed(task: task, detail: "没有可写日历，无法重建计时事件")
                return
            }
            let draft = CalendarEventDraft(
                calendarID: calendarID,
                title: "[计时记录] \(task.title)",
                startDate: session.startAt,
                endDate: endAt,
                notes: buildNotes(task: task, session: session, status: "已结束",
                                  actualDuration: session.durationSeconds),
                url: TaskLink.url(for: task.id)
            )
            do {
                let newEventID = try provider.createEvent(draft)
                session.calendarEventID = newEventID
                session.calendarIdentifier = calendarID
                task.calendarEventIDs.append(newEventID)
                try record(.calendarEventRebuilt, task: task, session: session, eventID: newEventID,
                           title: "重建日历事件：\(task.title)")
            } catch {
                recordSyncFailed(task: task, detail: "重建计时事件失败：\(describe(error))")
            }
        }
    }

    public func timerDidCompleteTask(_ task: TodoTask) {
        let settings = persistence.settings()
        guard settings.writeToCalendar, settings.createCompletionEvent else { return }
        guard provider.authorizationStatus() == .granted else { return }

        let completedAt = task.completedAt ?? clock.now

        // 最近的关联事件仍存在：更新标题与备注
        if let latestID = task.calendarEventIDs.last(where: { provider.eventExists(id: $0) }) {
            let notes = buildNotes(task: task, session: nil, status: "已完成",
                                   actualDuration: task.totalAccumulatedSeconds)
            do {
                try provider.updateEvent(
                    id: latestID,
                    newTitle: "[已完成] \(task.title)",
                    newEndDate: nil,
                    newNotes: notes
                )
                try record(.calendarEventUpdated, task: task, session: nil, eventID: latestID,
                           title: "更新日历事件：[已完成] \(task.title)")
            } catch {
                recordSyncFailed(task: task, detail: "更新完成事件失败：\(describe(error))")
            }
            return
        }

        // 没有关联事件：创建完成记录事件（完成时间起 5 分钟止）
        guard let calendarID = resolveTargetCalendar() else {
            recordSyncFailed(task: task, detail: "没有可写日历，无法创建完成记录事件")
            return
        }
        let draft = CalendarEventDraft(
            calendarID: calendarID,
            title: "[完成记录] \(task.title)",
            startDate: completedAt,
            endDate: completedAt.addingTimeInterval(5 * 60),
            notes: buildNotes(task: task, session: nil, status: "已完成",
                              actualDuration: task.totalAccumulatedSeconds),
            url: TaskLink.url(for: task.id)
        )
        do {
            let eventID = try provider.createEvent(draft)
            task.calendarEventIDs.append(eventID)
            try record(.calendarEventCreated, task: task, session: nil, eventID: eventID,
                       title: "创建日历事件：\(draft.title)")
        } catch {
            recordSyncFailed(task: task, detail: "创建完成记录事件失败：\(describe(error))")
        }
    }

    // MARK: - 私有

    /// 解析目标日历：设置的有效可写日历优先，否则创建/复用专用日历 FrostTodo
    private func resolveTargetCalendar() -> String? {
        let settings = persistence.settings()
        if let id = settings.defaultCalendarID {
            let valid = provider.availableCalendars().first { $0.id == id && $0.isWritable }
            if let valid {
                return valid.id
            }
        }
        do {
            let id = try provider.createCalendar(named: EventKitCalendarProvider.dedicatedCalendarName)
            settings.defaultCalendarID = id
            try? persistence.save()
            return id
        } catch {
            return nil
        }
    }

    private func buildNotes(task: TodoTask, session: TimeSession?, status: String, actualDuration: Int?) -> String {
        var lines: [String] = ["任务 ID: \(task.id.uuidString)"]
        if let session {
            lines.append("Session ID: \(session.id.uuidString)")
        }
        if let actualDuration {
            lines.append("实际时长: \(actualDuration) 秒")
        }
        lines.append("状态: \(status)")
        if let notes = task.notes, !notes.isEmpty {
            lines.append("备注: \(String(notes.prefix(50)))")
        }
        return lines.joined(separator: "\n")
    }

    private func record(
        _ type: HistoryEventType,
        task: TodoTask?,
        session: TimeSession?,
        eventID: String,
        title: String
    ) throws {
        try history.record(HistoryEventInput(
            type: type, taskID: task?.id, sessionID: session?.id,
            calendarEventID: eventID, title: title, source: .calendar
        ))
        try persistence.save()
    }

    private func recordSyncFailed(task: TodoTask?, detail: String) {
        try? history.record(HistoryEventInput(
            type: .calendarSyncFailed, taskID: task?.id,
            title: "日历同步失败", detail: detail, source: .calendar
        ))
        try? persistence.save()
    }

    private func describe(_ error: Error) -> String {
        if let calendarError = error as? CalendarError {
            return "\(calendarError)"
        }
        return error.localizedDescription
    }
}
