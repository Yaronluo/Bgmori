import Foundation

struct AiringReminderOptions: Codable, Equatable, Sendable {
    var enabled = false
    var dailySummary = true
    var summaryMinute = 20 * 60
    var individual = false
    var leadMinutes = 10
    var sound = true
    var quietAtNight = true
    var quietStart = 23 * 60
    var quietEnd = 8 * 60
    var excludedSubjectIDs: Set<Int> = []

    func isQuiet(_ date: Date, calendar: Calendar) -> Bool {
        guard quietAtNight, quietStart != quietEnd else { return false }
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        return quietStart < quietEnd
            ? minute >= quietStart && minute < quietEnd
            : minute >= quietStart || minute < quietEnd
    }
}

struct ReminderShow: Equatable, Sendable {
    let id: Int
    let title: String
    let weekday: Int?
    let anchor: Date?
    let end: Date?
    var sourceVersion: String {
        [String(id), title, String(weekday ?? 0), anchor.map { String($0.timeIntervalSince1970) } ?? "",
         end.map { String($0.timeIntervalSince1970) } ?? ""].joined(separator: "|")
    }
}

struct AiringReminderPayload: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case summary, individual, test }
    let owner: String
    let kind: Kind
    let subjectIDs: [Int]
    let calendarDate: Date
    let expiresAt: Date
    var snoozed = false
    var sourceVersions: [Int: String] = [:]
}

struct PlannedAiringReminder: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let date: Date
    let title: String
    let body: String
    let payload: AiringReminderPayload
}

struct AiringReminderInput: Equatable, Sendable {
    let owner: String?
    let options: AiringReminderOptions
    let shows: [ReminderShow]
    let calendarUpdatedAt: Date?
    let timesUpdatedAt: Date?
}

enum AiringReminderPlanner {
    static let prefix = "com.yaron.bgmori.airing.v2."
    static let legacyID = "com.yaron.bgmori.daily-airing"
    // Leave room for explicit test/snooze requests and other future app features.
    static let limit = 48

    private struct Occurrence {
        let show: ReminderShow
        let date: Date
    }

    static func plan(_ input: AiringReminderInput, now: Date = .now, calendar: Calendar = .current) -> [PlannedAiringReminder] {
        let options = input.options
        guard options.enabled, let owner = input.owner, !owner.isEmpty else { return [] }
        let shows = input.shows.filter { !options.excludedSubjectIDs.contains($0.id) && ($0.end.map { $0 > now } ?? true) }
        let day = calendar.startOfDay(for: now)
        guard let horizon = calendar.date(byAdding: .day, value: 7, to: now) else { return [] }
        let preciseIsFresh = input.timesUpdatedAt.map { now.timeIntervalSince($0) >= 0 && now.timeIntervalSince($0) <= 48 * 3600 } ?? false
        let calendarIsFresh = input.calendarUpdatedAt.map { now.timeIntervalSince($0) >= 0 && now.timeIntervalSince($0) <= 7 * 86400 } ?? false
        let preciseLimit = min(horizon, input.timesUpdatedAt?.addingTimeInterval(7 * 86400) ?? now)
        let calendarLimit = min(horizon, input.calendarUpdatedAt?.addingTimeInterval(7 * 86400) ?? now)
        var occurrences: [Occurrence] = []
        if preciseIsFresh {
            for show in shows {
                guard let anchor = show.anchor else { continue }
                // BGMLIST's P7D recurrence is elapsed time in the source timezone,
                // not a local wall clock (which can change during travel or DST).
                let first = max(0, Int(floor(day.addingTimeInterval(-86400).timeIntervalSince(anchor) / (7 * 86400))))
                for index in first...(first + 3) {
                    let date = anchor.addingTimeInterval(Double(index) * 7 * 86400)
                    if date < preciseLimit, show.end.map({ date < $0 }) ?? true {
                        occurrences.append(Occurrence(show: show, date: date))
                    }
                }
            }
        }
        var result: [PlannedAiringReminder] = []
        if options.dailySummary {
            for offset in 0...7 {
                guard let base = calendar.date(byAdding: .day, value: offset, to: day),
                      let fire = calendar.date(bySettingHour: min(23, max(0, options.summaryMinute / 60)),
                                               minute: min(59, max(0, options.summaryMinute % 60)), second: 0, of: base),
                      fire > now, fire < horizon else { continue }
                // A chase-anime day runs from 04:00 to 04:00; after-midnight shows
                // appear once, in the preceding evening's summary, with an explicit date.
                let summaryDay = calendar.date(byAdding: .day, value: options.summaryMinute < 240 ? -1 : 0, to: base)!
                let start = calendar.date(bySettingHour: 4, minute: 0, second: 0, of: summaryDay)!
                let end = calendar.date(byAdding: .day, value: 1, to: start)!
                let timed = occurrences.filter { $0.date >= start && $0.date < end }.sorted { $0.date < $1.date }
                var rows = timed.map { "《\($0.show.title)》\(timeLabel($0.date, relativeTo: fire, calendar: calendar)) 预计播出" }
                var ids = timed.map { $0.show.id }
                if calendarIsFresh, fire < calendarLimit {
                    let weekday = ((calendar.component(.weekday, from: summaryDay) + 5) % 7) + 1
                    for show in shows.sorted(by: { $0.id < $1.id }) where (show.anchor == nil || !preciseIsFresh) && show.weekday == weekday {
                        rows.append("《\(show.title)》时间待定")
                        ids.append(show.id)
                    }
                }
                let uniqueIDs = Array(Set(ids)).sorted()
                guard !uniqueIDs.isEmpty else { continue }
                result.append(PlannedAiringReminder(
                    id: prefix + "summary.\(Int(start.timeIntervalSince1970))", date: fire,
                    title: "追番安排 · \(uniqueIDs.count) 部", body: compact(rows),
                    payload: AiringReminderPayload(owner: owner, kind: .summary, subjectIDs: uniqueIDs,
                                                  calendarDate: summaryDay, expiresAt: end.addingTimeInterval(12 * 3600),
                                                  sourceVersions: Dictionary(shows.filter { uniqueIDs.contains($0.id) }.map { ($0.id, $0.sourceVersion) }, uniquingKeysWith: { first, _ in first }))))
            }
        }
        if options.individual {
            let candidates = occurrences.filter {
                let fire = $0.date.addingTimeInterval(-Double(max(0, min(options.leadMinutes, 120))) * 60)
                return fire > now && fire < horizon && !options.isQuiet(fire, calendar: calendar)
            }.sorted { $0.date < $1.date }
            var groups: [[Occurrence]] = []
            for event in candidates {
                if let previous = groups.last?.first, event.date.timeIntervalSince(previous.date) <= 5 * 60 {
                    groups[groups.count - 1].append(event)
                } else { groups.append([event]) }
            }
            for group in groups {
                let first = group[0]
                let fire = first.date.addingTimeInterval(-Double(max(0, min(options.leadMinutes, 120))) * 60)
                let ids = Array(Set(group.map { $0.show.id })).sorted()
                result.append(PlannedAiringReminder(
                    id: prefix + "individual.\(Int(first.date.timeIntervalSince1970)).\(ids.map(String.init).joined(separator: "-"))",
                    date: fire, title: ids.count == 1 ? "即将播出 · \(first.show.title)" : "即将播出 · \(ids.count) 部",
                    body: compact(group.map { "《\($0.show.title)》\(timeLabel($0.date, relativeTo: fire, calendar: calendar)) 预计播出" }),
                    payload: AiringReminderPayload(owner: owner, kind: .individual, subjectIDs: ids,
                                                  calendarDate: first.date, expiresAt: first.date.addingTimeInterval(12 * 3600),
                                                  sourceVersions: Dictionary(group.map { ($0.show.id, $0.show.sourceVersion) }, uniquingKeysWith: { first, _ in first }))))
            }
        }
        // Reserve all summaries before filling remaining capacity with the nearest
        // individual reminders; never silently lose the later daily summaries.
        let summaries = result.filter { $0.payload.kind == .summary }
        let individuals = result.filter { $0.payload.kind != .summary }.prefix(max(0, limit - summaries.count))
        return (summaries + individuals).sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }

    static func timeLabel(_ date: Date, relativeTo reference: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        if calendar.isDate(date, inSameDayAs: reference) { return formatter.string(from: date) }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: reference), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "明日 " + formatter.string(from: date)
        }
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }

    private static func compact(_ rows: [String]) -> String {
        rows.prefix(4).joined(separator: "\n") + (rows.count > 4 ? "\n另有 \(rows.count - 4) 部，点击查看放送表" : "")
    }
}
