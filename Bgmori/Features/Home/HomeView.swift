import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @State private var hotSelection: Int?
    @State private var isVisible = false
    @State private var scrollingSections: Set<String> = []
    @State private var shelfPositions: [String: Int] = [:]

    private var isInteracting: Bool { !scrollingSections.isEmpty }

    private var isHeroActive: Bool {
        #if os(macOS)
        let isAtRoot = app.router.macPath.isEmpty
        #else
        let isAtRoot = app.router.homePath.isEmpty
        #endif
        return isVisible && app.router.selectedSection == .home && isAtRoot
            && !app.showLogin && !app.showSettings
    }

    private var cardWidth: CGFloat {
        #if os(macOS)
        140
        #else
        132
        #endif
    }

    private var sectionGap: CGFloat {
        #if os(macOS)
        42
        #else
        36
        #endif
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: sectionGap) {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    if !app.trending.isEmpty {
                        HomeRefreshSection(value: app.trending, sourceVersion: app.homeContentVersion, isInteracting: isInteracting, prepare: { subjects in
                            let selected = subjects.first { $0.id == hotSelection } ?? subjects.first
                            #if os(macOS)
                            await HomeImageWarmup.prepare(urls: [selected?.heroURL].compactMap { $0 }, maxPixel: 900)
                            #else
                            await HomeImageWarmup.prepare(urls: [selected?.heroURL].compactMap { $0 }, maxPixel: 1000)
                            #endif
                        }) { subjects, isPrevious in
                            heroSection(subjects: subjects, isPrevious: isPrevious)
                        }
                    }
                }

                if !app.continueWatching.isEmpty {
                    continueSection
                }

                if !app.todayAiring.isEmpty {
                    HomeRefreshSection(value: app.todayAiring, sourceVersion: app.calendarContentVersion, isInteracting: isInteracting, prepare: { subjects in
                        await HomeImageWarmup.prepare(urls: subjects.prefix(2).compactMap(\.coverURL), maxPixel: 400)
                    }) { subjects, isPrevious in
                        todaySection(subjects: subjects, isPrevious: isPrevious)
                    }
                }

                if !app.seasonal.isEmpty {
                    HomeRefreshSection(value: app.seasonal, sourceVersion: app.homeContentVersion, isInteracting: isInteracting, prepare: { subjects in
                        await HomeImageWarmup.prepare(urls: subjects.prefix(2).compactMap(\.coverURL), maxPixel: 400)
                    }) { subjects, isPrevious in
                        seasonalSection(subjects: subjects, isPrevious: isPrevious)
                    }
                }

                if !app.ranking.isEmpty {
                    HomeRefreshSection(value: app.ranking, sourceVersion: app.homeContentVersion, isInteracting: isInteracting, prepare: { subjects in
                        await HomeImageWarmup.prepare(urls: subjects.prefix(2).compactMap(\.coverURL), maxPixel: 400)
                    }) { subjects, isPrevious in
                        rankingSection(subjects: subjects, isPrevious: isPrevious)
                    }
                }

                if !app.movies.isEmpty {
                    HomeRefreshSection(value: app.movies, sourceVersion: app.homeContentVersion, isInteracting: isInteracting, prepare: { subjects in
                        await HomeImageWarmup.prepare(urls: subjects.prefix(2).compactMap(\.coverURL), maxPixel: 400)
                    }) { subjects, isPrevious in
                        moviesSection(subjects: subjects, isPrevious: isPrevious)
                    }
                }

                if showsGuestCard {
                    guestCard
                }

                if showsSkeleton {
                    loadingSkeleton
                } else if showsEmptyState {
                    emptyState
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 44)
            .bgmDesktopContent()
        }
        .background(Color.bgmCanvas)
        .scrollIndicators(.hidden)
        .onScrollPhaseChange { _, phase in setScrolling("page", phase: phase) }
        .refreshable { await app.refreshAll() }
        .bgmLargeNavigationTitle("发现")
        .onAppear { isVisible = true }
        .onDisappear {
            isVisible = false
            scrollingSections.removeAll()
        }
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if app.isGuest {
                        app.showLogin = true
                    } else {
                        app.router.selectedSection = .profile
                    }
                } label: {
                    AvatarView(url: app.auth.user?.avatarURL, size: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("账户")
            }
        }
        #endif
    }

    // MARK: - Header

    private var header: some View {
        dateLabel
            .padding(.horizontal, 20)
    }

    private var dateLabel: some View {
        Text(dateLine)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("今天是 \(dateLine)")
    }

    // MARK: - Sections

    private func heroSection(subjects: [Subject], isPrevious: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "最近热播", subtitle: "近 90 天 · 人气动画")
            DiscoverHero(
                subjects: subjects,
                seasonLabel: app.seasonLabel,
                selection: isPrevious ? .constant(hotSelection) : $hotSelection,
                isActive: !isPrevious && isHeroActive,
                onScrollPhaseChange: { phase in
                    if !isPrevious { setScrolling("hero", phase: phase) }
                }
            )
        }
    }

    private var continueSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "正在看",
                subtitle: "\(app.continueWatching.count) 部在追",
                actionTitle: "收藏库"
            ) {
                app.openLibrary()
            }

            shelf(id: "continue") {
                ForEach(app.continueWatching) { item in
                    NavigationLink(value: Route.subject(item.subjectId)) {
                        CoverCard(
                            title: item.title,
                            subtitle: continueProgressText(item),
                            coverURL: item.coverURL,
                            progress: item.progressFraction,
                            tint: .subjectTint(item.subjectType),
                            width: cardWidth
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func todaySection(subjects: [LegacySubject], isPrevious: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "今日放送",
                subtitle: "\(subjects.count) 部作品今日更新",
                actionTitle: "全部"
            ) {
                app.router.openCalendar()
            }

            shelf(id: "today", isPrevious: isPrevious) {
                ForEach(Array(subjects.prefix(12))) { item in
                    NavigationLink(value: Route.subject(item.id)) {
                        AiringCard(
                            subject: item,
                            isWatching: app.library.isWatching(item.id),
                            width: cardWidth
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func seasonalSection(subjects: [Subject], isPrevious: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "本季新番",
                subtitle: "\(app.seasonLabel) · 本季精选",
                actionTitle: "全部"
            ) {
                app.openCategory(sort: .rank, tag: app.seasonTag)
            }

            shelf(id: "seasonal", isPrevious: isPrevious) {
                ForEach(subjects) { subject in
                    NavigationLink(value: Route.subject(subject.id)) {
                        subjectPosterCard(subject, subtitle: seriesSubtitle(subject))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func rankingSection(subjects: [Subject], isPrevious: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "口碑佳作",
                subtitle: "Bangumi 动画排行榜",
                actionTitle: "完整榜单"
            ) {
                app.openCategory(sort: .rank)
            }

            shelf(id: "ranking", isPrevious: isPrevious) {
                ForEach(Array(subjects.enumerated()), id: \.element.id) { index, subject in
                    NavigationLink(value: Route.subject(subject.id)) {
                        subjectPosterCard(subject, subtitle: seriesSubtitle(subject, usesYear: true), rank: index + 1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func moviesSection(subjects: [Subject], isPrevious: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "剧场版精选",
                subtitle: "人气动画电影",
                actionTitle: "全部"
            ) {
                app.openCategory(sort: .collects, tag: "剧场版")
            }

            shelf(id: "movies", isPrevious: isPrevious) {
                ForEach(subjects) { subject in
                    NavigationLink(value: Route.subject(subject.id)) {
                        subjectPosterCard(subject, subtitle: movieSubtitle(subject))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var guestCard: some View {
        Button {
            app.showLogin = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "books.vertical.fill")
                    .font(.title3)
                    .foregroundStyle(Color.brandPink)
                    .frame(width: 42, height: 42)
                    .background(Color.brandPink.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("登录 Bangumi")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("同步收藏、观看进度与每日放送提醒")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Text("登录")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.bgmCanvas)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 7)
                    .background(Color.brandPink, in: Capsule())
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .bgmPanel(cornerRadius: 18)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .accessibilityIdentifier("home-guest-card")
    }

    private var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: 18) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.bgmSecondary)
                .frame(width: 120, height: 18)
                .padding(.horizontal, 20)

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.bgmSecondary.opacity(0.75))
                .frame(height: 318)
                .padding(.horizontal, 20)

            HStack(spacing: 16) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.bgmSecondary.opacity(0.7))
                            .frame(width: cardWidth, height: cardWidth * 1.42)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.bgmSecondary)
                            .frame(width: cardWidth * 0.82, height: 12)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.bgmSecondary.opacity(0.7))
                            .frame(width: cardWidth * 0.55, height: 10)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .accessibilityHidden(true)
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "wifi.exclamationmark",
            title: "暂时无法加载",
            message: app.homeError ?? "请检查网络连接后重试。",
            actionTitle: "重试"
        ) {
            Task { await app.refreshAll() }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Helpers

    private func setScrolling(_ section: String, phase: ScrollPhase) {
        if phase == .idle { scrollingSections.remove(section) }
        else { scrollingSections.insert(section) }
    }

    private func shelf<Content: View>(id: String, isPrevious: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 16) {
                content()
            }
            .scrollTargetLayout()
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
        }
        .scrollPosition(id: Binding<Int?>(
            get: { shelfPositions[id] },
            set: { if !isPrevious { shelfPositions[id] = $0 } }
        ))
        .scrollIndicators(.hidden)
        .onScrollPhaseChange { _, phase in
            if !isPrevious { setScrolling(id, phase: phase) }
        }
    }

    private func subjectPosterCard(_ subject: Subject, subtitle: String, rank: Int? = nil) -> some View {
        CoverCard(
            title: subject.displayTitle,
            subtitle: subtitle,
            coverURL: subject.coverURL,
            badge: subject.rating.map { String(format: "%.1f", $0.score) },
            tint: .subjectTint(subject.type),
            width: cardWidth,
            rank: rank
        )
    }

    private func seriesSubtitle(_ subject: Subject, usesYear: Bool = false) -> String {
        if subject.platform == "剧场版" { return "剧场版" }
        let count = subject.totalEpisodes > 0 ? subject.totalEpisodes : subject.eps
        if count > 0 { return "全 \(count) 话" }
        if let date = subject.date, date.count >= 10 {
            if usesYear { return "\(date.prefix(4)) 年" }
            let month = Int(date.dropFirst(5).prefix(2)) ?? 0
            let day = Int(date.dropFirst(8).prefix(2)) ?? 0
            return month > 0 && day > 0 ? "\(month) 月 \(day) 日" : "\(date.prefix(4)) 年"
        }
        let platform = subject.platform?.trimmed ?? ""
        return platform.isEmpty ? subject.typeName : platform
    }

    private func movieSubtitle(_ subject: Subject) -> String {
        guard let year = subject.date?.prefix(4), !year.isEmpty else { return "剧场版" }
        return "\(year) · 剧场版"
    }

    private func continueProgressText(_ item: UserSubjectCollection) -> String {
        let watched = max(app.library.watchedCount(for: item.subjectId), item.epStatus)
        let total = item.subject?.eps ?? 0
        if total > 0 {
            return "看到 \(watched) / \(total) 话"
        }
        return watched > 0 ? "看到 \(watched) 话" : "尚未开始"
    }

    private var dateLine: String {
        let components = Calendar.current.dateComponents([.month, .day, .weekday], from: Date())
        let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let weekday = max(0, min(6, (components.weekday ?? 1) - 1))
        return "\(components.month ?? 1) 月 \(components.day ?? 1) 日 · \(names[weekday])"
    }

    private var hasNoHomeContent: Bool {
        app.trending.isEmpty
            && app.seasonal.isEmpty
            && app.ranking.isEmpty
            && app.movies.isEmpty
            && app.continueWatching.isEmpty
            && app.todayAiring.isEmpty
    }

    private var showsSkeleton: Bool {
        // Keep the skeleton up from launch until the first discover load finishes;
        // otherwise the empty state flashes while the account is being restored.
        (!app.hasLoadedHome || app.isLoadingHome) && hasNoHomeContent
    }

    private var showsEmptyState: Bool {
        app.hasLoadedHome && !app.isLoadingHome && hasNoHomeContent
    }

    private var showsGuestCard: Bool {
        app.isGuest && app.hasLoadedHome && !showsEmptyState
    }
}

/// Keep the live subtree (and its scroll position) while fading away an inert
/// copy of the previous data. Refreshes wait until scrolling has settled.
private struct HomeRefreshSection<Value: Encodable, Content: View>: View {
    let value: Value
    private let revision: Data
    let sourceVersion: Int
    let isInteracting: Bool
    let prepare: @MainActor (Value) async -> Void
    @ViewBuilder let content: (Value, Bool) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayed: Value
    @State private var displayedRevision: Data
    @State private var previous: Value?
    @State private var blend = 1.0

    init(value: Value, sourceVersion: Int, isInteracting: Bool,
         prepare: @escaping @MainActor (Value) async -> Void,
         @ViewBuilder content: @escaping (Value, Bool) -> Content) {
        self.value = value
        self.sourceVersion = sourceVersion
        // Subject/LegacySubject compare identity only. A sorted JSON revision
        // also detects title, rating, image and other changes on the same IDs.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let revision = (try? encoder.encode(value)) ?? Data(UUID().uuidString.utf8)
        self.revision = revision
        _displayedRevision = State(initialValue: revision)
        self.isInteracting = isInteracting
        self.prepare = prepare
        self.content = content
        _displayed = State(initialValue: value)
    }

    private struct Update: Equatable {
        let revision: Data
        let sourceVersion: Int
        let isInteracting: Bool
        let reduceMotion: Bool
    }

    var body: some View {
        content(displayed, false)
            .opacity(blend)
            .overlay(alignment: .topLeading) {
                if let previous {
                    content(previous, true)
                        .opacity(1 - blend)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .task(id: Update(revision: revision, sourceVersion: sourceVersion, isInteracting: isInteracting, reduceMotion: reduceMotion)) {
                // A newer update or a gesture can interrupt an in-flight fade.
                withTransaction(Transaction(animation: nil)) {
                    previous = nil
                    blend = 1
                }
                guard !isInteracting, displayedRevision != revision else { return }
                await prepare(value)
                guard !Task.isCancelled else { return }
                if reduceMotion {
                    displayed = value
                    displayedRevision = revision
                    return
                }
                withTransaction(Transaction(animation: nil)) {
                    previous = displayed
                    displayed = value
                    displayedRevision = revision
                    blend = 0
                }
                // Give the two layers a frame before starting their crossfade.
                do { try await Task.sleep(for: .milliseconds(16)) }
                catch { return }
                withAnimation(.easeInOut(duration: 0.25)) { blend = 1 }
                do { try await Task.sleep(for: .milliseconds(250)) }
                catch { return }
                previous = nil
            }
    }
}

/// Image downloads may continue into the shared cache after the short readiness
/// window, so a slow or missing cover never holds a content update indefinitely.
@MainActor
private final class HomeImageWarmup {
    private var continuation: CheckedContinuation<Void, Never>?

    static func prepare(urls: [URL], maxPixel: Int) async {
        guard !urls.isEmpty, !Task.isCancelled else { return }
        let readiness = HomeImageWarmup()
        await withCheckedContinuation { continuation in
            readiness.continuation = continuation
            Task {
                await withTaskGroup(of: Void.self) { group in
                    for url in urls {
                        group.addTask { _ = await ImageLoader.shared.image(for: url, maxPixel: maxPixel) }
                    }
                }
                readiness.finish()
            }
            Task {
                try? await Task.sleep(for: .milliseconds(800))
                readiness.finish()
            }
        }
    }

    private func finish() {
        continuation?.resume()
        continuation = nil
    }
}
