import Foundation
import UserNotifications

@MainActor
private final class ReminderDeliveryStub: ReminderNotificationDelivering {
    var authorization = ReminderPermission(status: .authorized)
    var requests: [String: UNNotificationRequest] = [:]
    var deliveredItems: [DeliveredAiringReminder] = []
    var additions = 0
    var failures: Set<String> = []
    var beforeAdd: (() async -> Void)?
    func permission() async -> ReminderPermission { authorization }
    func requestAuthorization() async throws -> Bool { authorization.canSchedule }
    func pending() async -> [UNNotificationRequest] { Array(requests.values) }
    func delivered() async -> [DeliveredAiringReminder] { deliveredItems }
    func add(_ request: UNNotificationRequest) async throws {
        let action = beforeAdd
        beforeAdd = nil
        await action?()
        if failures.contains(request.identifier) { throw CocoaError(.fileWriteUnknown) }
        requests[request.identifier] = request
        additions += 1
    }
    func removePending(_ identifiers: [String]) { identifiers.forEach { requests.removeValue(forKey: $0) } }
    func removeDelivered(_ identifiers: [String]) { deliveredItems.removeAll { identifiers.contains($0.id) } }
}

@main
struct AiringReminderTests {
    static func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    static var shanghai: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }

    @MainActor
    static func main() async throws {
        let now = date("2026-10-30T10:00:00+08:00")
        var options = AiringReminderOptions()
        options.enabled = true
        let a = ReminderShow(id: 1, title: "星期五作品", weekday: 5, anchor: date("2026-10-30T21:30:00+08:00"), end: nil)
        let b = ReminderShow(id: 2, title: "凌晨作品", weekday: 6, anchor: date("2026-10-31T00:30:00+08:00"), end: nil)
        let c = ReminderShow(id: 3, title: "时间待定作品", weekday: 6, anchor: nil, end: nil)
        func input(_ shows: [ReminderShow], _ config: AiringReminderOptions = options,
                   times: Date? = now, schedule: Date? = now, owner: String? = "sample") -> AiringReminderInput {
            AiringReminderInput(owner: owner, options: config, shows: shows, calendarUpdatedAt: schedule, timesUpdatedAt: times)
        }
        let plan = AiringReminderPlanner.plan(input([a,b,c]), now: now, calendar: shanghai)
        expect(plan.count == 2, "Different days get different summary contents, not one repeating count")
        expect(plan[0].payload.subjectIDs == [1,2] && plan[1].payload.subjectIDs == [3], "Midnight belongs to the preceding evening exactly once")
        expect(plan[0].body.contains("明日 00:30") && plan[1].body.contains("时间待定"), "No guessed times or episode numbers")
        expect(plan.allSatisfy { !$0.body.contains("已更新") && $0.date > now && $0.date < now.addingTimeInterval(7*86400) }, "Finite future schedule, honest language")
        expect(AiringReminderPlanner.plan(input([]), now: now).isEmpty, "No empty discovery notifications")
        expect(AiringReminderPlanner.plan(input([a], owner: nil), now: now).isEmpty, "No guest notifications")
        var disabled = options; disabled.enabled = false
        expect(AiringReminderPlanner.plan(input([a],disabled), now: now).isEmpty, "Off means no schedule")
        var excluded = options; excluded.excludedSubjectIDs = [1]
        expect(AiringReminderPlanner.plan(input([a],excluded), now: now).isEmpty, "Muting removes the subject from summaries too")
        let stale = AiringReminderPlanner.plan(input([a],times: now.addingTimeInterval(-49*3600)), now: now, calendar: shanghai)
        expect(stale.first?.body.contains("时间待定") == true, "Stale precise times fall back to date-only summary")
        expect(AiringReminderPlanner.plan(input([c],times: nil,schedule: now.addingTimeInterval(-8*86400)), now: now).isEmpty, "Expired calendar cannot generate new notifications")
        let future = ReminderShow(id: 4, title: "下月首播", weekday: 5, anchor: date("2026-11-20T21:00:00+08:00"), end: nil)
        expect(AiringReminderPlanner.plan(input([future]), now: now, calendar: shanghai).isEmpty, "Do not extrapolate before premiere")
        let ended = ReminderShow(id: 5,title: "已完结",weekday: 5,anchor: a.anchor,end: now.addingTimeInterval(-60))
        expect(AiringReminderPlanner.plan(input([ended]), now: now, calendar: shanghai).isEmpty, "Ended schedules stop")
        let ending = ReminderShow(id: 6,title: "即将完结",weekday: 5,anchor: a.anchor,end: now.addingTimeInterval(3600))
        expect(AiringReminderPlanner.plan(input([ending]), now: now, calendar: shanghai).isEmpty, "Known end also constrains future occurrences")

        var individual = options; individual.dailySummary = false; individual.individual = true
        let perShow = AiringReminderPlanner.plan(input([a,b,c],individual), now: now, calendar: shanghai)
        expect(perShow.count == 1 && perShow[0].date == a.anchor!.addingTimeInterval(-600), "Only reliable times, with lead time and overnight quiet hours")
        individual.quietAtNight = false
        expect(AiringReminderPlanner.plan(input([a,b,c],individual), now: now, calendar: shanghai).count == 2, "Quiet hours are configurable")
        let near = ReminderShow(id: 7,title: "邻近节目",weekday:5,anchor:a.anchor!.addingTimeInterval(180),end:nil)
        let merged = AiringReminderPlanner.plan(input([a,near],individual), now: now, calendar: shanghai)
        expect(merged.count == 1 && merged[0].payload.subjectIDs == [1,7], "Nearby events merge without losing identities")
        let pastLead = date("2026-10-30T21:25:00+08:00")
        expect(AiringReminderPlanner.plan(input([a],individual), now: pastLead, calendar: shanghai).isEmpty, "Never enqueue an already elapsed lead-time reminder")
        var abundant = individual; abundant.dailySummary = true
        let many = (0..<100).map { ReminderShow(id: $0+100,title:"作品\($0)",weekday:nil,anchor:now.addingTimeInterval(Double($0+1)*600),end:nil) }
        let bounded = AiringReminderPlanner.plan(input(many,abundant), now: now, calendar: shanghai)
        expect(bounded.count <= 48 && bounded.contains { $0.payload.kind == .summary }, "Bound the queue and preserve daily summaries")
        var pacific = shanghai; pacific.timeZone = TimeZone(identifier:"America/Los_Angeles")!
        let converted = AiringReminderPlanner.plan(input([b],individual),now:now,calendar:pacific)
        expect(converted.first?.date == b.anchor!.addingTimeInterval(-600), "Device timezone conversion must not change the broadcast instant")
        print("PASS: per-date summaries, overnight boundaries, freshness, ends/premieres, timezone, lead time, quiet hours, merging and capacity")

        let defaultsName = "BgmoriReminderTests-\(UUID())"
        let defaults = UserDefaults(suiteName:defaultsName)!
        defer { defaults.removePersistentDomain(forName:defaultsName) }
        defaults.set(true,forKey:"dailyReminder")
        let settings = AppSettings(defaults:defaults)
        expect(settings.reminders.enabled && settings.reminders.dailySummary && !settings.reminders.individual, "Migrate existing opt-in to summary without enabling individual alerts")
        settings.reminders.summaryMinute = 19*60
        settings.reminders.excludedSubjectIDs.insert(7)
        let restored = AppSettings(defaults:defaults)
        expect(restored.reminders.summaryMinute == 19*60 && restored.reminders.excludedSubjectIDs == [7], "Persist edits without initializer overwrites")
        print("PASS: migration, opt-in defaults and option persistence")

        var serviceOptions = options
        serviceOptions.individual = true
        serviceOptions.quietAtNight = false
        let backend = ReminderDeliveryStub()
        let manager = NotificationManager(delivery:backend)
        let actualNow = Date()
        let payload = AiringReminderPayload(owner:"sample",kind:.individual,subjectIDs:[1],calendarDate:actualNow,expiresAt:actualNow.addingTimeInterval(86400))
        let item = PlannedAiringReminder(id:AiringReminderPlanner.prefix+"unit",date:actualNow.addingTimeInterval(3600),title:"预计播出",body:"作品",payload:payload)
        backend.requests["unrelated"] = UNNotificationRequest(identifier:"unrelated",content:UNMutableNotificationContent(),trigger:nil)
        backend.requests[AiringReminderPlanner.legacyID] = UNNotificationRequest(identifier:AiringReminderPlanner.legacyID,content:UNMutableNotificationContent(),trigger:nil)
        await manager.reconcile(plan:[item],owner:"sample",eligible:[1],options:serviceOptions)
        expect(backend.requests[AiringReminderPlanner.legacyID] == nil && backend.requests["unrelated"] != nil, "Remove legacy reminder, preserve unrelated requests")
        let request = backend.requests[item.id]!
        expect((request.trigger as? UNCalendarNotificationTrigger)?.repeats == false, "Each notification is a dated one-shot")
        expect(NotificationManager.planned(from:request) == item, "Payload and exact date round trip")
        let additions = backend.additions
        await manager.reconcile(plan:[item],owner:"sample",eligible:[1],options:serviceOptions)
        expect(backend.additions == additions, "Idempotent refresh must not duplicate or churn unchanged notifications")
        var currentOptions = options; currentOptions.individual = true; currentOptions.quietAtNight = false
        await manager.reconcile(plan:[item],owner:"sample",eligible:[1],options:currentOptions)
        await manager.snooze(item,options:currentOptions)
        expect(manager.pending.contains { $0.payload.snoozed }, "Snooze is scheduled through the same serial reconciler")
        await manager.reconcile(plan:[item],owner:"sample",eligible:[1],options:currentOptions)
        expect(manager.pending.contains { $0.payload.snoozed }, "Routine refresh preserves explicit snoozes")
        var versionedPayload = payload
        versionedPayload.sourceVersions = [1:"old-time"]
        let versioned = PlannedAiringReminder(id:AiringReminderPlanner.prefix+"versioned",date:item.date,title:item.title,body:item.body,payload:versionedPayload)
        await manager.reconcile(plan:[versioned],owner:"sample",eligible:[1],options:currentOptions,sourceVersions:[1:"old-time"])
        await manager.snooze(versioned,options:currentOptions)
        expect(manager.pending.contains { $0.payload.snoozed && $0.payload.sourceVersions[1] == "old-time" }, "Preserve snooze for unchanged source")
        await manager.reconcile(plan:[],owner:"sample",eligible:[1],options:currentOptions,sourceVersions:[1:"changed-time"])
        expect(!manager.pending.contains { $0.payload.snoozed && $0.payload.sourceVersions[1] == "old-time" }, "Changed broadcast data invalidates old snooze content")
        backend.deliveredItems = [DeliveredAiringReminder(id:item.id,payload:payload),DeliveredAiringReminder(id:"unrelated",payload:nil)]
        await manager.reconcile(plan:[],owner:"sample",eligible:[],options:currentOptions)
        expect(manager.pending.isEmpty && backend.deliveredItems.map(\.id) == ["unrelated"], "Removing watching eligibility cancels pending, snoozed and delivered reminders")
        backend.authorization = ReminderPermission(status:.denied)
        await manager.reconcile(plan:[item],owner:"sample",eligible:[1],options:serviceOptions)
        expect(manager.pending.isEmpty && !manager.permission.canSchedule, "Denied permission is visible and cancels owned requests")
        backend.authorization = ReminderPermission(status:.provisional)
        await manager.reconcile(plan:[item],owner:"sample",eligible:[1],options:serviceOptions)
        expect(manager.pending.count == 1, "Honor quiet provisional authorization")
        backend.failures = [item.id]
        backend.requests.removeValue(forKey:item.id)
        await manager.reconcile(plan:[item],owner:"sample",eligible:[1],options:serviceOptions)
        expect(manager.lastError != nil && manager.pending.isEmpty, "Schedule failures cannot masquerade as successful pending reminders")
        backend.failures.removeAll()
        await manager.reconcile(plan:[item],owner:"different-account",eligible:[1],options:serviceOptions)
        expect(manager.pending.isEmpty, "Refuse mismatched owner payloads even if a stale caller supplies them")
        var entered = false
        var released = false
        backend.beforeAdd = { entered = true; while !released { await Task.yield() } }
        let adding = Task { await manager.reconcile(plan:[item],owner:"sample",eligible:[1],options:serviceOptions) }
        while !entered { await Task.yield() }
        let release = Task { released = true }
        await manager.reconcile(plan:[],owner:nil,eligible:[],options:disabled)
        await release.value
        await adding.value
        expect(manager.pending.isEmpty, "A delayed old add cannot resurrect reminders after logout")
        expect(backend.requests["unrelated"] != nil, "No operation clears unrelated notifications")
        print("PASS: notification bridge, one-shot triggers, migration cleanup, permissions, idempotence, errors, snooze, logout/account/collection cancellation and async races")

        let router = AppRouter()
        router.openReminder(plan[0].payload)
        expect(router.selectedSection == .calendar && router.calendarReminderOnlyWatching && router.calendarReminderDate == plan[0].payload.calendarDate, "Summary opens corresponding date with watching filter")
        expect(router.calendarReminderSubjectIDs == [1,2], "Summary navigation preserves the cross-midnight subjects instead of dropping tomorrow's show")
        router.openReminder(payload)
        #if os(macOS)
        expect(router.macPath == [.subject(1)], "Single reminder opens the subject on Mac")
        #else
        expect(router.calendarPath == [.subject(1)], "Single reminder opens the subject on iPhone")
        #endif
        router.clearCalendarReminder()
        expect(router.calendarReminderDate == nil && router.calendarReminderSubjectIDs == nil, "Manual calendar navigation releases the notification filter")
        print("PASS: notification destinations on this platform")
    }
}
