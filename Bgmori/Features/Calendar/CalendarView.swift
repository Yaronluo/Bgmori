import SwiftUI
import Foundation

struct CalendarView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedWeekday: Int = ((Calendar.current.component(.weekday, from: Date()) + 5) % 7) + 1
    @State private var onlyWatching = false
    @Namespace private var daySelection

    private let contentMaxWidth: CGFloat = 760

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = pageWidth(for: geometry.size.width)
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if app.calendarError != nil, !app.calendar.isEmpty {
                            RefreshFailureNotice(message: "放送表更新失败，显示的是缓存内容") {
                                Task { await app.loadCalendar(force: true) }
                            }
                        }
                        scheduleHeader
                            .id("calendar-top")
                        if let error = app.calendarTimesError {
                            VStack(alignment: .leading, spacing: 6) {
                                RefreshFailureNotice(message: error) {
                                    Task { await app.loadCalendarTimes(force: true) }
                                }
                                Link("在网页查看播放时刻", destination: URL(string: "https://bgmlist.com")!)
                                    .font(.caption)
                            }
                        }
                        scheduleContent
                    }
                    .frame(width: contentWidth, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
                .refreshable {
                    await app.refreshCalendar()
                }
                .onChange(of: selectedWeekday) { _, _ in
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        scrollProxy.scrollTo("calendar-top", anchor: .top)
                    }
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    weekdaySelector
                        .frame(maxWidth: 420)
                        .frame(width: contentWidth, alignment: .leading)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(Color.bgmGroupedBackground)
                        .overlay(alignment: .bottom) { Divider() }
                }
            }
        }
        .background(Color.bgmGroupedBackground)
        .bgmNavigationTitle("每日放送")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                        onlyWatching.toggle()
                    }
                } label: {
                    Image(systemName: onlyWatching ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .help(onlyWatching ? "显示全部" : "只看在看")
                .accessibilityLabel(onlyWatching ? "显示全部" : "只看在看")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        await app.refreshCalendar()
                        await app.updateDailyReminder()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("刷新放送表")
                .accessibilityLabel("刷新")
            }
        }
        .task {
            async let times: Void = app.loadCalendarTimes()
            if app.calendar.isEmpty {
                await app.loadCalendar()
            }
            await times
        }
    }

    private func pageWidth(for totalWidth: CGFloat) -> CGFloat {
        #if os(macOS)
        let horizontalInsets: CGFloat = 56
        #else
        let horizontalInsets: CGFloat = 40
        #endif
        return min(max(totalWidth - horizontalInsets, 300), contentMaxWidth)
    }

    // MARK: - Header

    private var scheduleHeader: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(weekdayName)
                        .font(.system(.title2, weight: .bold))
                    if selectedWeekday == app.todayWeekday {
                        Text("今天")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.brandPink)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.brandPink.opacity(0.12), in: Capsule())
                    }
                }
                Text(daySummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if filteredItems.contains(where: { app.calendarAirings[$0.id] != nil }) {
                    Text("北京时间")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if selectedWeekday != app.todayWeekday {
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
                        selectedWeekday = app.todayWeekday
                    }
                } label: {
                    Text("回到今天")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.brandPink)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(Color.brandPink.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityLabel("回到今天，\(weekdayName(for: app.todayWeekday))")
            }
        }
        .padding(.top, 6)
    }

    private var daySummary: String {
        let countText = onlyWatching ? "\(filteredItems.count) 部在看" : "\(filteredItems.count) 部作品"
        guard !selectedDateText.isEmpty else { return countText }
        return "\(selectedDateText) · \(countText)"
    }

    private var selectedDateText: String {
        guard let date = weekDates[selectedWeekday] else { return "" }
        let components = Calendar.current.dateComponents([.month, .day], from: date)
        guard let month = components.month, let day = components.day else { return "" }
        return "\(month)月\(day)日"
    }

    private var weekdayName: String {
        weekdayName(for: selectedWeekday)
    }

    private func weekdayName(for weekday: Int) -> String {
        days.first(where: { $0.weekday.id == weekday })?.weekday.cn ?? "今天"
    }

    // MARK: - Week selector

    private var weekdaySelector: some View {
        let dates = weekDates
        return HStack(spacing: 2) {
            ForEach(days) { day in
                WeekdayChip(
                    day: day,
                    date: dates[day.weekday.id],
                    isSelected: selectedWeekday == day.weekday.id,
                    isToday: day.weekday.id == app.todayWeekday,
                    namespace: daySelection
                ) {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
                        selectedWeekday = day.weekday.id
                    }
                }
            }
        }
    }

    private var weekDates: [Int: Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let daysSinceMonday = (weekday + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today) else {
            return [:]
        }
        var dates: [Int: Date] = [:]
        for id in 1...7 {
            if let date = calendar.date(byAdding: .day, value: id - 1, to: monday) {
                dates[id] = date
            }
        }
        return dates
    }

    // MARK: - Content

    @ViewBuilder
    private var scheduleContent: some View {
        if app.calendar.isEmpty {
            if let error = app.calendarError {
                EmptyStateView(
                    icon: "wifi.exclamationmark",
                    title: "放送表加载失败",
                    message: error,
                    actionTitle: "重试"
                ) {
                    Task { await app.loadCalendar(force: true) }
                }
                .calendarCard()
            } else if app.isLoadingCalendar || !app.hasLoadedCalendar {
                CalendarSkeleton()
            } else {
                EmptyStateView(
                    icon: "calendar",
                    title: "暂无放送数据",
                    message: "",
                    actionTitle: "重试"
                ) {
                    Task { await app.loadCalendar(force: true) }
                }
                .calendarCard()
            }
        } else if filteredItems.isEmpty {
            EmptyStateView(
                icon: onlyWatching ? "line.3.horizontal.decrease.circle" : "calendar.badge.exclamationmark",
                title: onlyWatching ? "这天没有在看的番" : "这天没有放送",
                message: "",
                actionTitle: onlyWatching ? "显示全部" : nil
            ) {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                    onlyWatching = false
                }
            }
            .calendarCard()
        } else {
            scheduleList
        }
    }

    private var scheduleList: some View {
        VStack(spacing: 0) {
            ForEach(filteredItems) { item in
                NavigationLink(value: Route.subject(item.id)) {
                    CalendarAiringRow(
                        item: item,
                        collection: app.library.collection(for: item.id),
                        airing: app.calendarAirings[item.id],
                        calendarWeekday: selectedWeekday
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("calendar-row-\(item.id)")
                if item.id != filteredItems.last?.id {
                    Divider()
                        .padding(.leading, 94)
                        .padding(.trailing, 16)
                }
            }
        }
        .calendarCard()
    }

    // MARK: - Data

    private var days: [CalendarDay] {
        app.calendar.sorted { $0.weekday.id < $1.weekday.id }
    }

    private var filteredItems: [LegacySubject] {
        guard let day = days.first(where: { $0.weekday.id == selectedWeekday }) else { return [] }
        return onlyWatching ? day.items.filter { app.library.isWatching($0.id) } : day.items
    }
}

// MARK: - Weekday chip

private struct WeekdayChip: View {
    let day: CalendarDay
    let date: Date?
    let isSelected: Bool
    let isToday: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(day.weekday.shortName)
                    .font(.caption2.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

                Text(dayNumber)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(isToday ? Color.brandPink : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

            }
            #if os(macOS)
            .frame(maxWidth: .infinity, minHeight: 44)
            #else
            .frame(maxWidth: .infinity, minHeight: 48)
            #endif
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.brandPink.opacity(0.08))
                        .matchedGeometryEffect(id: "selected-day", in: namespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var dayNumber: String {
        guard let date else { return "—" }
        let components = Calendar.current.dateComponents([.month, .day], from: date)
        guard let month = components.month, let day = components.day else { return "—" }
        return day == 1 ? "\(month)/1" : "\(day)"
    }

    private var accessibilityText: String {
        var parts = [day.weekday.cn]
        if let date {
            let components = Calendar.current.dateComponents([.month, .day], from: date)
            if let month = components.month, let day = components.day {
                parts.append("\(month)月\(day)日")
            }
        }
        if isToday { parts.append("今天") }
        parts.append("\(day.items.count) 部作品")
        return parts.joined(separator: "，")
    }
}

// MARK: - Airing row

private struct CalendarAiringRow: View {
    let item: LegacySubject
    let collection: UserSubjectCollection?
    let airing: BgmlistAiring?
    let calendarWeekday: Int

    private var isWatching: Bool {
        collection?.collectionType == .doing
    }

    private var totalEpisodes: Int {
        collection?.subject?.eps ?? 0
    }

    private var progress: Double {
        collection?.progressFraction ?? 0
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            CachedAsyncImage(url: item.coverURL, maxPixel: 256, placeholderTint: .subjectTint(item.type))
                .frame(width: 64, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.displayTitle)
                    .font(titleFont)
                    .foregroundStyle(.primary)
                    .lineLimit(2, reservesSpace: true)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let airing {
                    Text(airing.label(for: calendarWeekday))
                        .font(metaFont.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.brandPink)
                        .accessibilityIdentifier("calendar-airtime-\(item.id)")
                }

                HStack(spacing: 6) {
                    if isWatching {
                        watchingBadge
                    }
                    Text(metadata)
                        .font(metaFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if progress > 0, totalEpisodes > 0 {
                    HStack(spacing: 7) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 96, height: 3)
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(Color.brandPink)
                                    .frame(width: max(3, 96 * CGFloat(progress)), height: 3)
                            }
                        Text("\(collection?.epStatus ?? 0)/\(totalEpisodes)")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            scoreBadge
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var titleFont: Font {
        #if os(macOS)
        .title3.weight(.semibold)
        #else
        .headline
        #endif
    }

    private var metaFont: Font {
        #if os(macOS)
        .system(size: 12)
        #else
        .caption
        #endif
    }

    private var watchingBadge: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(Color.brandPink)
                .frame(width: 5, height: 5)
            Text("在看")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(Color.brandPink)
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(Color.brandPink.opacity(0.11), in: Capsule())
        .fixedSize()
    }

    private var metadata: String {
        if let collection {
            switch collection.collectionType {
            case .doing:
                if collection.epStatus > 0 {
                    if totalEpisodes > 0 {
                        return "已看 \(collection.epStatus)/\(totalEpisodes) 话"
                    }
                    return "已看 \(collection.epStatus) 话"
                }
            case .wish, .done, .onHold, .dropped:
                return "\(collection.collectionType.title) · \(premiereText)"
            }
        }
        return premiereText
    }

    private var premiereText: String {
        guard let raw = item.airDate, !raw.isEmpty else { return "每周更新" }
        let parts = raw.split(separator: "-", omittingEmptySubsequences: true)
        guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]) else {
            return raw
        }
        return "\(month)月\(day)日开播"
    }

    @ViewBuilder
    private var scoreBadge: some View {
        if let score = item.rating?.score, score > 0 {
            HStack(spacing: 3) {
                Image(systemName: "star.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color(red: 0.96, green: 0.70, blue: 0.16))
                Text(String(format: "%.1f", score))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(Color.primary.opacity(0.055), in: Capsule())
            .accessibilityLabel("评分 \(String(format: "%.1f", score))")
        } else {
            Text("暂无")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
                .frame(minWidth: 34, minHeight: 26)
                .accessibilityLabel("暂无评分")
        }
    }
}

// MARK: - Loading

private struct CalendarSkeleton: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { index in
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.bgmSecondary)
                        .frame(width: 64, height: 88)
                    VStack(alignment: .leading, spacing: 9) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.bgmSecondary)
                            .frame(height: 14)
                            .frame(maxWidth: index.isMultiple(of: 2) ? 220 : 160)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.bgmSecondary.opacity(0.7))
                            .frame(width: 108, height: 11)
                    }
                    Spacer(minLength: 8)
                    Capsule()
                        .fill(Color.bgmSecondary.opacity(0.8))
                        .frame(width: 42, height: 26)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                if index < 5 {
                    Divider()
                        .padding(.leading, 94)
                        .padding(.trailing, 16)
                }
            }
        }
        .calendarCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在加载放送表")
    }
}

// MARK: - Card

private extension View {
    func calendarCard() -> some View {
        background(Color.bgmSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.055), lineWidth: 0.5)
            }
    }
}
