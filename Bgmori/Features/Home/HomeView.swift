import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @State private var hotSelection: Int?
    @State private var isVisible = false

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
                    if app.homeShowsCachedContent {
                        Label(app.isLoadingHome ? "正在显示缓存，更新中…" : "正在显示缓存，下拉可重试更新", systemImage: "clock.arrow.circlepath")
                            .font(.caption)
                            .foregroundStyle(Color.bgmMuted)
                            .padding(.horizontal, 20)
                    }
                    if !app.trending.isEmpty {
                        heroSection
                    }
                }

                if !app.continueWatching.isEmpty {
                    continueSection
                }

                if !app.todayAiring.isEmpty {
                    todaySection
                }

                if !app.seasonal.isEmpty {
                    seasonalSection
                }

                if !app.ranking.isEmpty {
                    rankingSection
                }

                if !app.movies.isEmpty {
                    moviesSection
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
        .refreshable { await app.refreshAll() }
        .bgmLargeNavigationTitle("发现")
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
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

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "最近热播", subtitle: "近 90 天 · 人气动画")
            DiscoverHero(subjects: app.trending, seasonLabel: app.seasonLabel, selection: $hotSelection, isActive: isHeroActive)
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

            shelf {
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

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "今日放送",
                subtitle: "\(app.todayAiring.count) 部作品今日更新",
                actionTitle: "全部"
            ) {
                app.router.openCalendar()
            }

            shelf {
                ForEach(Array(app.todayAiring.prefix(12))) { item in
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

    private var seasonalSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "本季新番",
                subtitle: "\(app.seasonLabel) · 本季精选",
                actionTitle: "全部"
            ) {
                app.openCategory(sort: .rank, tag: app.seasonTag)
            }

            shelf {
                ForEach(app.seasonal) { subject in
                    NavigationLink(value: Route.subject(subject.id)) {
                        subjectPosterCard(subject, subtitle: seriesSubtitle(subject))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var rankingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "口碑佳作",
                subtitle: "Bangumi 动画排行榜",
                actionTitle: "完整榜单"
            ) {
                app.openCategory(sort: .rank)
            }

            shelf {
                ForEach(Array(app.ranking.enumerated()), id: \.element.id) { index, subject in
                    NavigationLink(value: Route.subject(subject.id)) {
                        subjectPosterCard(subject, subtitle: seriesSubtitle(subject, usesYear: true), rank: index + 1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var moviesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "剧场版精选",
                subtitle: "人气动画电影",
                actionTitle: "全部"
            ) {
                app.openCategory(sort: .collects, tag: "剧场版")
            }

            shelf {
                ForEach(app.movies) { subject in
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

    private func shelf<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 16) {
                content()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
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
        app.isGuest && app.hasLoadedHome && !app.isLoadingHome && !showsEmptyState
    }
}
