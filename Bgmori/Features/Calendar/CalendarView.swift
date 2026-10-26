import SwiftUI

struct CalendarView: View {
    @Environment(AppModel.self) private var app
    @State private var selectedWeekday: Int = ((Calendar.current.component(.weekday, from: Date()) + 5) % 7) + 1
    @State private var onlyWatching = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                weekdaySelector
                scheduleHeader

                if app.calendar.isEmpty {
                    ProgressView("加载放送表…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                } else if filteredItems.isEmpty {
                    EmptyStateView(
                        icon: "calendar.badge.exclamationmark",
                        title: onlyWatching ? "这天没有在看的番" : "这天没有放送",
                        message: ""
                    )
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredItems) { item in
                            NavigationLink(value: Route.subject(item.id)) {
                                HStack(spacing: 12) {
                                    SubjectRow(
                                        title: item.displayTitle,
                                        subtitle: subtitle(for: item),
                                        coverURL: item.coverURL,
                                        tint: .subjectTint(item.type)
                                    )
                                    if app.library.isWatching(item.id) {
                                        Image(systemName: "play.circle.fill")
                                            .foregroundStyle(Color.brandPink)
                                    }
                                    Text(item.rating?.scoreText ?? "—")
                                        .font(.system(.headline, design: .rounded))
                                        .monospacedDigit()
                                        .lineLimit(1)
                                        .foregroundStyle(.secondary)
                                        .frame(minWidth: 32, alignment: .trailing)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                            if item.id != filteredItems.last?.id {
                                Divider().padding(.leading, 84)
                            }
                        }
                    }
                    .bgmCardBackground(cornerRadius: 22)
                    .padding(.horizontal, 20)
                }
            }
        }
        .background(Color.bgmBackground)
        .scrollIndicators(.hidden)
        .bgmLargeNavigationTitle("每日放送")
        .refreshable { await app.loadCalendar(force: true) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    onlyWatching.toggle()
                } label: {
                    Image(systemName: onlyWatching ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel(onlyWatching ? "显示全部" : "只看在看")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await app.loadCalendar(force: true); await app.updateDailyReminder() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("刷新")
            }
        }
        .task {
            if app.calendar.isEmpty {
                await app.loadCalendar()
            }
        }
    }

    private var scheduleHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(weekdayName)\(selectedWeekday == app.todayWeekday ? " · 今天" : "")")
                .font(.headline)
            Spacer()
            Text("\(filteredItems.count) 部作品")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    private var weekdaySelector: some View {
        HStack(spacing: 4) {
            ForEach(days) { day in
                let isSelected = selectedWeekday == day.weekday.id
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        selectedWeekday = day.weekday.id
                    }
                } label: {
                    VStack(spacing: 8) {
                        Text(day.weekday.shortName)
                            .font(.subheadline.weight(isSelected ? .bold : .medium))
                        Text("\(day.items.count)")
                            .font(.caption.monospacedDigit())
                            .opacity(isSelected ? 0.9 : 0.5)
                    }
                    .foregroundStyle(isSelected ? Color.bgmCanvas : Color.primary)
                    .frame(maxWidth: .infinity, minHeight: 62)
                    .background(isSelected ? Color.brandPink : Color.clear, in: RoundedRectangle(cornerRadius: 16))
                    .contentShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(day.weekday.cn)，\(day.items.count) 部作品")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(6)
        .bgmCardBackground(cornerRadius: 22)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var days: [CalendarDay] {
        app.calendar.sorted { $0.weekday.id < $1.weekday.id }
    }

    private var filteredItems: [LegacySubject] {
        guard let day = days.first(where: { $0.weekday.id == selectedWeekday }) else { return [] }
        return onlyWatching ? day.items.filter { app.library.isWatching($0.id) } : day.items
    }

    private var weekdayName: String {
        days.first(where: { $0.weekday.id == selectedWeekday })?.weekday.cn ?? "今天"
    }

    private func subtitle(for item: LegacySubject) -> String {
        if let collection = app.library.collection(for: item.id) {
            return "\(collection.collectionType.title) · 看到 \(collection.epStatus) 话"
        }
        return item.airDate ?? "每周更新"
    }
}
