import Foundation
import UserNotifications
#if os(iOS)
import BackgroundTasks
#endif

extension AppModel {
    var isReminderPreview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["BGMORI_PREVIEW_REMINDERS"] == "1"
        #else
        false
        #endif
    }

    var reminderInput: AiringReminderInput {
        #if DEBUG
        if isReminderPreview {
            let calendar = Calendar.current
            let day = calendar.startOfDay(for: reminderPreviewNow)
            let anchor = calendar.date(bySettingHour: 21, minute: 30, second: 0, of: day)!
            let midnight = calendar.date(byAdding: .minute, value: 180, to: anchor)!
            return AiringReminderInput(owner: "preview", options: settings.reminders, shows: [
                ReminderShow(id: 101, title: "星海列车", weekday: nil, anchor: anchor, end: nil),
                ReminderShow(id: 102, title: "雨后的咖啡馆", weekday: nil, anchor: midnight, end: nil),
                ReminderShow(id: 103, title: "星期五的约定", weekday: ((calendar.component(.weekday, from: day) + 5) % 7) + 1, anchor: nil, end: nil)
            ], calendarUpdatedAt: reminderPreviewNow, timesUpdatedAt: reminderPreviewNow)
        }
        #endif
        let owner = auth.isLoggedIn ? auth.username : nil
        let available = Dictionary(calendar.flatMap { day in day.items.map { ($0.id, (day.weekday.id, $0)) } }, uniquingKeysWith: { first, _ in first })
        let shows = library.loadedUsername == owner ? library.watching.filter { $0.subjectType == 2 }.compactMap { collection -> ReminderShow? in
            let entry = available[collection.subjectId]
            let airing = reminderAirings[collection.subjectId] ?? calendarAirings[collection.subjectId]
            return ReminderShow(id: collection.subjectId, title: collection.title, weekday: entry?.0,
                                anchor: airing?.anchor, end: airing?.end)
        } : []
        return AiringReminderInput(owner: owner, options: settings.reminders, shows: shows,
                                   calendarUpdatedAt: calendarUpdatedAt, timesUpdatedAt: calendarTimesUpdatedAt)
    }

    var reminderPlan: [PlannedAiringReminder] {
        AiringReminderPlanner.plan(reminderInput, now: isReminderPreview ? reminderPreviewNow : .now)
    }

    var scheduledReminders: [PlannedAiringReminder] { isReminderPreview ? reminderPlan : notifications.pending }

    func updateDailyReminder() async {
        guard !isReminderPreview, reminderAccountReady || !settings.dailyReminder else { return }
        if !auth.isLoggedIn || !settings.dailyReminder { scheduleReminderBackgroundRefresh() }
        // A restored token whose user lookup is temporarily offline is not a
        // logout. Keep the bounded existing schedule until the account is known.
        guard !settings.dailyReminder || !auth.isLoggedIn || auth.username != nil else {
            await notifications.refreshStatus()
            return
        }
        let input = reminderInput
        let eligible = Set(input.shows.filter {
            !input.options.excludedSubjectIDs.contains($0.id) && ($0.end.map { $0 > Date() } ?? true)
        }.map(\.id))
        let versions = Dictionary(input.shows.filter { show in
            let updated = show.anchor == nil ? input.calendarUpdatedAt : input.timesUpdatedAt
            let lifetime: TimeInterval = show.anchor == nil ? 7 * 86400 : 48 * 3600
            return updated.map { Date().timeIntervalSince($0) <= lifetime } ?? false
        }.map { ($0.id, $0.sourceVersion) }, uniquingKeysWith: { first, _ in first })
        await notifications.reconcile(plan: AiringReminderPlanner.plan(input), owner: input.owner, eligible: eligible,
                                      options: input.options, sourceVersions: versions)
    }

    func setRemindersEnabled(_ enabled: Bool) async {
        if enabled, !isReminderPreview {
            guard await notifications.requestAuthorization() else { return }
        }
        settings.reminders.enabled = enabled
        if enabled { await refreshReminderData() }
        else { await updateDailyReminder() }
        scheduleReminderBackgroundRefresh()
    }

    func refreshReminderData(force: Bool = false) async {
        guard !isReminderPreview else { return }
        await notifications.refreshStatus()
        if settings.dailyReminder, reminderAccountReady {
            let now = Date()
            let refreshList = force || (calendarUpdatedAt.map { now.timeIntervalSince($0) > 6 * 3600 } ?? true)
            let refreshTimes = force || (calendarTimesUpdatedAt.map { now.timeIntervalSince($0) > 6 * 3600 } ?? true)
            async let list: Void = loadCalendar(force: refreshList, silently: true)
            async let times: Void = loadCalendarTimes(force: refreshTimes)
            _ = await (list, times)
        }
        await updateDailyReminder()
        scheduleReminderBackgroundRefresh()
    }

    func receiveReminder(_ response: AiringReminderResponse, allowBeforeBootstrap: Bool = false) async {
        guard response.reminder.payload.kind != .test else { return }
        guard reminderAccountReady || allowBeforeBootstrap else {
            pendingReminderResponse = response
            hasFinishedStartup = true
            return
        }
        let payload = response.reminder.payload
        guard payload.owner == auth.username, auth.isLoggedIn, payload.expiresAt > .now else {
            showToast("这条提醒已过期，或不属于当前登录账号", isError: true)
            return
        }
        if response.action == UNNotificationDefaultActionIdentifier {
            // Opening public detail content does not mutate notification or
            // collection state and need not wait for hidden home-page requests.
            showSettings = false
            showLogin = false
            hasFinishedStartup = true
            router.openReminder(payload)
            return
        }
        let eligible = Set(reminderInput.shows.filter {
            !settings.reminders.excludedSubjectIDs.contains($0.id) && ($0.end.map { $0 > Date() } ?? true)
        }.map(\.id))
        let modeEnabled = payload.kind == .summary ? settings.reminders.dailySummary : settings.reminders.individual
        guard settings.dailyReminder, modeEnabled, Set(payload.subjectIDs).isSubset(of: eligible) else {
            showToast("相关作品已停止提醒")
            return
        }
        if response.action == NotificationManager.muteAction, payload.subjectIDs.count == 1 {
            settings.reminders.excludedSubjectIDs.formUnion(payload.subjectIDs)
            await updateDailyReminder()
            showToast("已关闭本作提醒，可在提醒设置中恢复")
            return
        }
        if response.action == NotificationManager.snoozeAction {
            await notifications.snooze(response.reminder, options: settings.reminders)
            showToast(notifications.lastError ?? "已安排 30 分钟后提醒", isError: notifications.lastError != nil)
            return
        }
    }

    func scheduleReminderBackgroundRefresh() {
        #if os(iOS)
        guard !isReminderPreview else { return }
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: "com.yaron.bgmori.refresh-reminders")
        guard settings.dailyReminder, auth.isLoggedIn else { return }
        // The async submission API must not run on the main thread; the old
        // synchronous `submit(_:)` is deprecated in iOS 27.
        let earliest = Date().addingTimeInterval(6 * 3600)
        Task.detached(priority: .utility) {
            let request = BGAppRefreshTaskRequest(identifier: "com.yaron.bgmori.refresh-reminders")
            request.earliestBeginDate = earliest
            // Background execution is opportunistic; the actual reminders are
            // already scheduled with UserNotifications and never rely on this.
            do { try await BGTaskScheduler.shared.submitTaskRequest(request) }
            catch { /* Foreground refresh remains available; delivery is unaffected. */ }
        }
        #endif
    }

    func refreshRemindersInBackground() async {
        guard settings.dailyReminder, !isReminderPreview else { return }
        await auth.restore()
        guard !Task.isCancelled else { return }
        if let username = auth.username { _ = await library.loadAll(username: username) }
        reminderAccountReady = true
        guard !Task.isCancelled else { return }
        await refreshReminderData(force: true)
    }
}
