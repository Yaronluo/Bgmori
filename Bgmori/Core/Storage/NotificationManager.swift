import Foundation
import UserNotifications

struct ReminderPermission: Equatable, Sendable {
    var status: UNAuthorizationStatus
    var alerts: UNNotificationSetting = .enabled
    var sounds: UNNotificationSetting = .enabled
    var canSchedule: Bool {
        #if os(iOS)
        status == .authorized || status == .provisional || status == .ephemeral
        #else
        status == .authorized || status == .provisional
        #endif
    }
    var description: String {
        if status == .denied { return "系统通知已关闭" }
        if status == .notDetermined { return "尚未授权通知" }
        if alerts == .disabled { return "已授权，横幅提醒已关闭" }
        if status == .provisional { return "已允许安静投递" }
        return "已允许通知"
    }
}

struct DeliveredAiringReminder {
    let id: String
    let payload: AiringReminderPayload?
}

@MainActor
protocol ReminderNotificationDelivering {
    func permission() async -> ReminderPermission
    func requestAuthorization() async throws -> Bool
    func pending() async -> [UNNotificationRequest]
    func delivered() async -> [DeliveredAiringReminder]
    func add(_ request: UNNotificationRequest) async throws
    func removePending(_ identifiers: [String])
    func removeDelivered(_ identifiers: [String])
}

@MainActor
private final class SystemReminderDelivery: ReminderNotificationDelivering {
    let center = UNUserNotificationCenter.current()
    func permission() async -> ReminderPermission {
        let settings = await center.notificationSettings()
        return ReminderPermission(status: settings.authorizationStatus, alerts: settings.alertSetting, sounds: settings.soundSetting)
    }
    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }
    func pending() async -> [UNNotificationRequest] { await center.pendingNotificationRequests() }
    func delivered() async -> [DeliveredAiringReminder] {
        await center.deliveredNotifications().map {
            DeliveredAiringReminder(id: $0.request.identifier, payload: NotificationManager.payload(from: $0.request.content))
        }
    }
    func add(_ request: UNNotificationRequest) async throws { try await center.add(request) }
    func removePending(_ identifiers: [String]) { center.removePendingNotificationRequests(withIdentifiers: identifiers) }
    func removeDelivered(_ identifiers: [String]) { center.removeDeliveredNotifications(withIdentifiers: identifiers) }
}

struct AiringReminderResponse: Sendable {
    let action: String
    let reminder: PlannedAiringReminder
}

@MainActor
@Observable
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    static let snoozeAction = "BGMORI_SNOOZE"
    static let muteAction = "BGMORI_MUTE"
    private(set) var permission = ReminderPermission(status: .notDetermined)
    private(set) var pending: [PlannedAiringReminder] = []
    private(set) var lastError: String?
    private(set) var isScheduling = false
    private(set) var lastTestDeliveredAt: Date?
    @ObservationIgnored var onResponse: ((AiringReminderResponse) async -> Void)?
    @ObservationIgnored private let delivery: any ReminderNotificationDelivering
    @ObservationIgnored private var latest: Reconciliation?
    @ObservationIgnored private var current: Reconciliation?
    @ObservationIgnored private var explicitSnoozes: [String: PlannedAiringReminder] = [:]
    @ObservationIgnored private var waiters: [CheckedContinuation<Void, Never>] = []

    private struct Reconciliation {
        let plan: [PlannedAiringReminder]
        let owner: String?
        let eligible: Set<Int>
        let options: AiringReminderOptions
        let sourceVersions: [Int: String]
    }

    init(delivery: (any ReminderNotificationDelivering)? = nil) {
        let service = delivery ?? SystemReminderDelivery()
        self.delivery = service
        super.init()
        if let system = service as? SystemReminderDelivery {
            system.center.delegate = self
            let snooze = UNNotificationAction(identifier: Self.snoozeAction, title: "30 分钟后提醒", options: [.foreground])
            let mute = UNNotificationAction(identifier: Self.muteAction, title: "关闭本作提醒", options: [.foreground, .destructive])
            system.center.setNotificationCategories([
                UNNotificationCategory(identifier: "BGMORI_AIRING_SINGLE", actions: [snooze, mute], intentIdentifiers: []),
                UNNotificationCategory(identifier: "BGMORI_AIRING_GROUP", actions: [snooze], intentIdentifiers: [])
            ])
        }
    }

    func refreshStatus() async {
        permission = await delivery.permission()
        pending = await delivery.pending().compactMap(Self.planned(from:)).filter { $0.date > .now }.sorted { $0.date < $1.date }
    }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await delivery.requestAuthorization()
            await refreshStatus()
            if !granted { lastError = "请在系统设置中允许 Bgmori 发送通知。" }
            else { lastError = nil }
            return granted
        } catch {
            lastError = "无法申请通知权限，请重试或检查系统设置。"
            return false
        }
    }

    /// Conflate updates, but serialize notification-center mutations. An older
    /// add finishing after logout must be followed by the newest cancellation.
    func reconcile(plan: [PlannedAiringReminder], owner: String?, eligible: Set<Int>, options: AiringReminderOptions,
                   sourceVersions: [Int: String] = [:]) async {
        let input = Reconciliation(plan: plan, owner: owner, eligible: eligible, options: options, sourceVersions: sourceVersions)
        current = input
        latest = input
        if isScheduling {
            await withCheckedContinuation { waiters.append($0) }
            return
        }
        isScheduling = true
        defer {
            isScheduling = false
            let completed = waiters
            waiters.removeAll()
            completed.forEach { $0.resume() }
        }
        while let next = latest {
            latest = nil
            await apply(next)
        }
    }

    private func apply(_ input: Reconciliation) async {
        permission = await delivery.permission()
        let existing = await delivery.pending()
        let delivered = await delivery.delivered()
        let allowed = input.options.enabled && input.owner != nil && permission.canSchedule
        var desired = allowed ? input.plan.filter {
            $0.payload.owner == input.owner && $0.date > .now && $0.payload.expiresAt > .now
                && Set($0.payload.subjectIDs).isSubset(of: input.eligible)
                && ($0.payload.kind == .summary ? input.options.dailySummary : input.options.individual)
        } : []
        // Keep explicit snoozes across routine refreshes, but invalidate them as
        // soon as their account, collection eligibility, mode or expiry changes.
        if allowed {
            let snoozes = existing.compactMap(Self.planned(from:)) + Array(explicitSnoozes.values)
            let valid = snoozes.filter {
                $0.payload.snoozed && $0.payload.owner == input.owner && $0.date > .now && $0.payload.expiresAt > .now
                    && Set($0.payload.subjectIDs).isSubset(of: input.eligible)
                    && ($0.payload.kind == .summary ? input.options.dailySummary : input.options.individual)
                    && $0.payload.sourceVersions.allSatisfy { input.sourceVersions[$0.key] == $0.value }
            }
            let retained = Dictionary(valid.map { ($0.id, $0) }, uniquingKeysWith: { _, newest in newest })
            desired += retained.values
            if latest == nil { explicitSnoozes = retained }
        } else if latest == nil {
            explicitSnoozes.removeAll()
        }
        desired = Array(desired.sorted { $0.date < $1.date }.prefix(AiringReminderPlanner.limit + 8))
        let ids = Set(desired.map(\.id))
        delivery.removePending(existing.filter { Self.owns($0.identifier) && !ids.contains($0.identifier) }.map(\.identifier))
        delivery.removeDelivered(delivered.filter {
            guard Self.owns($0.id) else { return false }
            guard allowed, let payload = $0.payload else { return true }
            return payload.owner != input.owner || payload.expiresAt <= .now
                || !Set(payload.subjectIDs).isSubset(of: input.eligible)
                || (payload.kind == .summary ? !input.options.dailySummary : !input.options.individual)
        }.map(\.id))
        var failed = false
        for item in desired {
            let old = existing.first { $0.identifier == item.id }
            if let old, Self.planned(from: old) == item, (old.content.sound != nil) == input.options.sound { continue }
            do { try await delivery.add(Self.request(for: item, sound: input.options.sound)) }
            catch { failed = true }
        }
        lastError = failed ? "部分提醒未能安排，请点击重新安排重试。" : nil
        await refreshStatus()
    }

    func sendTest(sound: Bool) async {
        permission = await delivery.permission()
        guard permission.canSchedule else {
            lastError = "请先允许通知，再发送测试通知。"
            return
        }
        let date = Date().addingTimeInterval(5)
        let item = PlannedAiringReminder(id: AiringReminderPlanner.prefix + "test", date: date,
            title: "Bgmori 测试通知", body: "通知投递测试成功。正式提醒会列出作品与预计播出时间。",
            payload: AiringReminderPayload(owner: "", kind: .test, subjectIDs: [], calendarDate: date, expiresAt: date.addingTimeInterval(3600)))
        do { try await delivery.add(Self.request(for: item, sound: sound)); lastError = nil; await refreshStatus() }
        catch { lastError = "测试通知未能安排，请重试。" }
    }

    func snooze(_ reminder: PlannedAiringReminder, options: AiringReminderOptions, now: Date = .now) async {
        guard let current, current.options.enabled, current.owner == reminder.payload.owner,
              Set(reminder.payload.subjectIDs).isSubset(of: current.eligible),
              reminder.payload.kind == .summary ? current.options.dailySummary : current.options.individual,
              reminder.payload.sourceVersions.allSatisfy({ current.sourceVersions[$0.key] == $0.value }) else {
            lastError = "当前账号或作品已停止提醒。"
            return
        }
        guard !reminder.payload.snoozed, reminder.payload.expiresAt > now.addingTimeInterval(1800) else {
            lastError = "这条提醒已过期或已延后过一次。"
            return
        }
        let date = now.addingTimeInterval(1800)
        guard pending.filter({ $0.payload.snoozed }).count < 8 else {
            lastError = "已有 8 条延后提醒，请等待投递后再试。"
            return
        }
        guard !options.isQuiet(date, calendar: .current) else {
            lastError = "30 分钟后处于夜间免打扰时段，未安排延后提醒。"
            return
        }
        var payload = reminder.payload
        payload.snoozed = true
        let item = PlannedAiringReminder(id: AiringReminderPlanner.prefix + "snooze." + reminder.id,
                                        date: date, title: reminder.title, body: reminder.body, payload: payload)
        explicitSnoozes[item.id] = item
        await reconcile(plan: current.plan, owner: current.owner, eligible: current.eligible, options: current.options,
                        sourceVersions: current.sourceVersions)
    }

    nonisolated static func owns(_ id: String) -> Bool {
        id.hasPrefix(AiringReminderPlanner.prefix) || id == AiringReminderPlanner.legacyID
    }
    nonisolated static func payload(from content: UNNotificationContent) -> AiringReminderPayload? {
        guard let data = content.userInfo["bgmoriReminder"] as? Data else { return nil }
        return (try? JSONDecoder().decode(PlannedAiringReminder.self, from: data))?.payload
    }
    nonisolated static func planned(from request: UNNotificationRequest) -> PlannedAiringReminder? {
        guard owns(request.identifier), let data = request.content.userInfo["bgmoriReminder"] as? Data,
              let value = try? JSONDecoder().decode(PlannedAiringReminder.self, from: data),
              value.id == request.identifier else { return nil }
        return value
    }
    static func request(for reminder: PlannedAiringReminder, sound: Bool) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = sound ? .default : nil
        content.interruptionLevel = .active
        content.threadIdentifier = "bgmori-airing"
        if reminder.payload.kind != .test {
            content.categoryIdentifier = reminder.payload.subjectIDs.count == 1 && reminder.payload.kind == .individual
                ? "BGMORI_AIRING_SINGLE" : "BGMORI_AIRING_GROUP"
        }
        content.userInfo = ["bgmoriReminder": (try? JSONEncoder().encode(reminder)) ?? Data()]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.date)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        return UNNotificationRequest(identifier: reminder.id, content: content,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let item = Self.planned(from: response.notification.request),
              response.actionIdentifier != UNNotificationDismissActionIdentifier else { return }
        let value = AiringReminderResponse(action: response.actionIdentifier, reminder: item)
        await handleResponse(value)
    }

    private func handleResponse(_ value: AiringReminderResponse) async { await onResponse?(value) }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // Normal notifications respect Focus and scheduled summaries. Foreground
        // delivery is also visible, so the settings test button is useful.
        if Self.payload(from: notification.request.content)?.kind == .test { await recordTestDelivery() }
        return notification.request.content.sound == nil ? [.banner, .list] : [.banner, .list, .sound]
    }

    private func recordTestDelivery() { lastTestDeliveredAt = .now }
}
