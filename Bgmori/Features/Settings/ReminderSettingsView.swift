import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ReminderSettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var isEnabling = false
    @State private var isRefreshing = false

    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Section {
                Toggle(deviceTitle, isOn: Binding(get: { settings.reminders.enabled }, set: { enabled in
                    Task {
                        isEnabling = true
                        await app.setRemindersEnabled(enabled)
                        isEnabling = false
                    }
                }))
                .disabled(isEnabling)
                .accessibilityIdentifier("reminder-enabled")
                if app.isReminderPreview {
                    Label("示例预览 · 不会安排真实通知", systemImage: "eye")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    LabeledContent("系统通知", value: app.notifications.permission.description)
                        .accessibilityIdentifier("reminder-permission")
                    if !app.notifications.permission.canSchedule {
                        Button("前往系统通知设置", action: openSystemSettings)
                            .accessibilityIdentifier("reminder-system-settings")
                    }
                    if app.isGuest {
                        Text("登录 Bangumi 后，自动从在看作品生成提醒。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("仅在这台设备生效。建议主要在 iPhone 接收，避免两端重复提醒。")
            }

            Section {
                Toggle("每日追番汇总", isOn: $settings.reminders.dailySummary)
                    .accessibilityIdentifier("reminder-summary")
                if settings.reminders.dailySummary {
                    DatePicker("汇总时间", selection: minuteBinding(\.summaryMinute), displayedComponents: .hourAndMinute)
                        .accessibilityIdentifier("reminder-summary-time")
                }
                Toggle("单番开播提醒", isOn: $settings.reminders.individual)
                    .accessibilityIdentifier("reminder-individual")
                if settings.reminders.individual {
                    Picker("提醒时机", selection: $settings.reminders.leadMinutes) {
                        Text("开播时").tag(0)
                        Text("提前 10 分钟").tag(10)
                        Text("提前 30 分钟").tag(30)
                        Text("提前 60 分钟").tag(60)
                    }
                    .accessibilityIdentifier("reminder-lead")
                }
                Toggle("通知声音", isOn: $settings.reminders.sound)
                    .accessibilityIdentifier("reminder-sound")
                if !settings.reminders.dailySummary && !settings.reminders.individual {
                    Text("请至少开启一种提醒方式。")
                        .font(.footnote).foregroundStyle(Color.brandPink)
                }
            } header: { Text("提醒方式") } footer: {
                Text("没有放送安排就不发送。汇总包含当天 04:00 至次日 04:00 的排期；凌晨节目会标明日期。时间按设备当前时区显示。")
            }

            if settings.reminders.individual {
                Section {
                    Toggle("夜间不发单番提醒", isOn: $settings.reminders.quietAtNight)
                        .accessibilityIdentifier("reminder-quiet")
                    if settings.reminders.quietAtNight {
                        DatePicker("开始", selection: minuteBinding(\.quietStart), displayedComponents: .hourAndMinute)
                        DatePicker("结束", selection: minuteBinding(\.quietEnd), displayedComponents: .hourAndMinute)
                    }
                } header: { Text("夜间免打扰") } footer: {
                    Text("夜间的单番提醒会跳过，排期仍可出现在每日汇总中。开始与结束相同时不限制时段；系统专注模式仍然生效。")
                }
            }

            Section {
                if let next = app.scheduledReminders.first {
                    ReminderPreviewRow(reminder: next)
                        .accessibilityIdentifier("reminder-next")
                    NavigationLink {
                        ReminderScheduleView().environment(app)
                    } label: {
                        Text("查看全部 \(app.scheduledReminders.count) 条提醒")
                    }
                    .accessibilityIdentifier("reminder-schedule-list")
                } else {
                    Text(emptyMessage).foregroundStyle(.secondary)
                        .accessibilityIdentifier("reminder-empty")
                }
                if let error = app.notifications.lastError, !app.isReminderPreview {
                    Label(error, systemImage: "exclamationmark.circle")
                        .foregroundStyle(Color.brandPink).font(.footnote)
                        .accessibilityIdentifier("reminder-error")
                }
                if !app.isReminderPreview, app.calendarError != nil || app.calendarTimesError != nil {
                    Label("放送数据刷新失败，提醒仅使用仍在有效期内的已有排期。", systemImage: "exclamationmark.circle")
                        .font(.footnote).foregroundStyle(Color.brandPink)
                }
                Button(isRefreshing ? "正在重新安排…" : "刷新排期并重新安排") {
                    Task {
                        isRefreshing = true
                        await app.refreshReminderData(force: true)
                        isRefreshing = false
                    }
                }
                .disabled(isRefreshing || app.notifications.isScheduling)
                .accessibilityIdentifier("reminder-refresh")
                Button("5 秒后发送测试通知") {
                    Task {
                        await app.notifications.sendTest(sound: settings.reminders.sound)
                        if app.notifications.lastError == nil { app.showToast("已安排测试通知，请留意系统横幅或通知中心") }
                    }
                }
                .disabled(app.isReminderPreview)
                .accessibilityIdentifier("reminder-test")
                if let date = app.notifications.lastTestDeliveredAt, !app.isReminderPreview {
                    Label("系统已投递测试通知 · \(date.formatted(date: .omitted, time: .shortened))", systemImage: "checkmark.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("reminder-test-delivered")
                }
            } header: { Text("下一条提醒") } footer: {
                Text("预先安排未来 7 天；打开应用、同步收藏或刷新排期后更新。请定期打开应用以续排提醒。播出时间来自公开排期，不代表播放平台已经更新；后台刷新由系统决定。")
            }

            Section {
                DisclosureGroup("在看作品 · \(app.reminderInput.shows.count) 部") {
                    if app.reminderInput.shows.isEmpty {
                        Text("同步在看的动画后，可在这里单独关闭某部作品的提醒。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(app.reminderInput.shows.sorted { $0.title < $1.title }, id: \.id) { show in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(show.title)
                                Text(settings.reminders.excludedSubjectIDs.contains(show.id) ? "已关闭本作提醒" : (show.anchor == nil ? "无可靠时刻时仅加入汇总" : "按公开排期提醒"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 12)
                            Button(settings.reminders.excludedSubjectIDs.contains(show.id) ? "恢复" : "关闭") {
                                if !settings.reminders.excludedSubjectIDs.insert(show.id).inserted {
                                    settings.reminders.excludedSubjectIDs.remove(show.id)
                                }
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("\(settings.reminders.excludedSubjectIDs.contains(show.id) ? "恢复" : "关闭")\(show.title)提醒")
                            .accessibilityIdentifier("reminder-show-\(show.id)")
                        }
                    }
                }
                .accessibilityIdentifier("reminder-shows")
            } header: { Text("按作品管理") }
        }
        .formStyle(.grouped)
        .tint(.brandPink)
        .navigationTitle("追番提醒")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
        }
        .task { await app.refreshReminderData() }
        .onChange(of: settings.reminders) { _, _ in
            Task { await app.updateDailyReminder(); app.scheduleReminderBackgroundRefresh() }
        }
    }

    private var deviceTitle: String {
        #if os(macOS)
        "在这台 Mac 上提醒"
        #else
        "在这台 iPhone 上提醒"
        #endif
    }

    private var emptyMessage: String {
        if !app.settings.dailyReminder { return "开启后在这里查看下一条提醒。" }
        if !app.settings.reminders.dailySummary && !app.settings.reminders.individual { return "尚未选择提醒方式。" }
        if !app.isReminderPreview && !app.notifications.permission.canSchedule { return "系统尚未允许通知，请先检查通知权限。" }
        if app.isGuest && !app.isReminderPreview { return "登录后，根据在看作品生成提醒。" }
        if app.library.isLoading { return "正在同步在看作品，完成后会自动安排提醒。" }
        if app.library.lastError != nil { return "收藏同步失败，请联网后重试。" }
        if app.calendarUpdatedAt == nil && !app.isReminderPreview { return "还没有可用排期，请联网刷新。" }
        return "未来 7 天暂无可安排的提醒。没有相关放送、排期过旧或夜间免打扰都可能影响安排。"
    }

    private func minuteBinding(_ keyPath: WritableKeyPath<AiringReminderOptions, Int>) -> Binding<Date> {
        Binding(get: {
            let minute = app.settings.reminders[keyPath: keyPath]
            return Calendar.current.date(bySettingHour: min(23, max(0, minute / 60)), minute: min(59, max(0, minute % 60)), second: 0, of: .now)!
        }, set: { date in
            app.settings.reminders[keyPath: keyPath] = Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date)
        })
    }

    private func openSystemSettings() {
        #if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
        #else
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
        #endif
    }
}

private struct ReminderPreviewRow: View {
    let reminder: PlannedAiringReminder
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(reminder.date, format: .dateTime.month().day().hour().minute())
                .font(.caption).foregroundStyle(.secondary)
            Text(reminder.title).font(.headline)
            Text(reminder.body).font(.subheadline).foregroundStyle(.secondary)
            if reminder.payload.snoozed {
                Text("已延后一次").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ReminderScheduleView: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        List {
            ForEach(app.scheduledReminders) { item in
                ReminderPreviewRow(reminder: item)
            }
            if app.scheduledReminders.isEmpty { Text("暂无已安排的提醒").foregroundStyle(.secondary) }
        }
        .navigationTitle(app.isReminderPreview ? "提醒示例" : "已安排的提醒")
        .task { if !app.isReminderPreview { await app.notifications.refreshStatus() } }
    }
}
