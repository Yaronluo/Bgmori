import SwiftUI

struct CalendarView: View {
    @Environment(AppModel.self) private var app
    @State private var selectedWeekday: Int = ((Calendar.current.component(.weekday, from: Date()) + 5) % 7) + 1
    @State private var onlyWatching = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                header
                weekdaySelector

                if app.calendar.isEmpty {
                    ProgressView("加载放送表…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                } else if filteredItems.isEmpty {
                    EmptyStateView(
                        icon: "calendar.badge.exclamationmark",
                        title: onlyWatching ? "今天没有在看的番" : "今天没有放送",
                        message: onlyWatching ? "换成“全部”看看，或去收藏里加一部在看。" : "换一天看看，或稍后刷新。"
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
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                        .frame(width: 32, alignment: .trailing)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 84)
                        }
                    }
                }

                Text("放送时间以 Bangumi 为准，按周显示。")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
        }
        .scrollIndicators(.hidden)
        #if os(macOS)
        .navigationTitle("放送")
        #else
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        #endif
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("每日放送")
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text("今天 · \(weekdayName)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var weekdaySelector: some View {
        GlassSurface(shape: AnyShape(Capsule())) {
            HStack(spacing: 2) {
                ForEach(days) { day in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            selectedWeekday = day.weekday.id
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Text(day.weekday.shortName)
                                .font(.system(size: 11, weight: .semibold))
                            Text("\(day.items.count)")
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .opacity(0.65)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(selectedWeekday == day.weekday.id ? Color.white : Color.primary)
                        .background(
                            selectedWeekday == day.weekday.id ? Color.brandPink : Color.clear,
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
        }
        .padding(.horizontal, 20)
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
            return "\(collection.collectionType.title) · \(collection.epStatus)/\(item.airDate ?? "")"
        }
        return item.airDate ?? "每周更新"
    }
}
