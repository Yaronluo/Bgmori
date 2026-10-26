import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        #if os(macOS)
                        Text("发现").font(.title2.bold())
                        Spacer(minLength: 20)
                        #endif
                        quickLinks
                    }
                    .padding(.horizontal, 20)

                    if let featured = featuredSubject {
                        featuredSection(featured)
                    }
                }

                if !app.continueWatching.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: "继续观看")
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 16) {
                                ForEach(app.continueWatching) { item in
                                    NavigationLink(value: Route.subject(item.subjectId)) {
                                        CoverCard(
                                            title: item.title,
                                            subtitle: "看到 \(item.epStatus) 话",
                                            coverURL: item.coverURL,
                                            badge: item.collectionType.title,
                                            progress: item.progressFraction,
                                            tint: .subjectTint(item.subjectType),
                                            width: 148
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }

                if !app.todayAiring.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: "今日放送", subtitle: weekdayText, actionTitle: "全部") {
                            app.router.openCalendar()
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 16) {
                                ForEach(app.todayAiring.prefix(12)) { item in
                                    NavigationLink(value: Route.subject(item.id)) {
                                        AiringCard(subject: item, isWatching: app.library.isWatching(item.id), width: 140)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }

                if !app.seasonal.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: "本季新番", subtitle: app.seasonLabel)
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 16) {
                                ForEach(app.seasonal) { subject in
                                    NavigationLink(value: Route.subject(subject.id)) {
                                        SubjectCard(subject: subject, width: 140)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }

                if !app.ranking.isEmpty {
                    rankingSection
                }

                communitySection

                if app.isGuest {
                    guestCard
                }

                if app.isLoadingHome && app.ranking.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else if app.ranking.isEmpty && app.seasonal.isEmpty && app.todayAiring.isEmpty {
                    EmptyStateView(icon: "wifi.exclamationmark", title: "暂时无法加载", message: "", actionTitle: "重试") {
                        Task { await app.refreshAll() }
                    }
                }
            }
            .padding(.top, 8)
            .bgmDesktopContent()
        }
        .background(Color.bgmCanvas)
        .scrollIndicators(.hidden)
        .refreshable { await app.refreshAll() }
        .bgmLargeNavigationTitle("发现")
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

    private var quickLinks: some View {
        HStack(spacing: 24) {
            Button { app.router.openCalendar() } label: {
                Label("每日放送", systemImage: "calendar")
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("home-calendar")
            Button { app.router.selectedSection = .categories } label: {
                Label("浏览分类", systemImage: "square.grid.2x2")
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("home-categories")
        }
        .font(.subheadline)
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    private var featuredSubject: Subject? {
        app.seasonal.max { ($0.collection?.doing ?? 0) < ($1.collection?.doing ?? 0) }
    }

    private func featuredSection(_ subject: Subject) -> some View {
        NavigationLink(value: Route.subject(subject.id)) {
            #if os(macOS)
            HStack(spacing: 28) {
                CachedAsyncImage(url: subject.coverURL, maxPixel: 600)
                    .frame(width: 160, height: 226)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 12) {
                    Text("本季精选 · \(app.seasonLabel)")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(subject.displayTitle)
                        .font(.system(size: 28, weight: .bold))
                        .lineLimit(2, reservesSpace: true)
                        .truncationMode(.tail)
                    Text(subject.summary.trimmed.isEmpty ? subject.typeName : subject.summary)
                        .font(.body).foregroundStyle(.secondary)
                        .lineLimit(3).lineSpacing(3)
                    Spacer(minLength: 0)
                    HStack(spacing: 14) {
                        if let rating = subject.rating, rating.total > 0 {
                            Label(rating.scoreText, systemImage: "star.fill")
                                .foregroundStyle(.secondary)
                        }
                        Text(subject.episodeCountText).foregroundStyle(.secondary)
                        Spacer()
                        Label("查看条目", systemImage: "arrow.right")
                            .foregroundStyle(Color.brandPink)
                    }
                    .font(.subheadline.weight(.medium))
                }
                .padding(.vertical, 8)
            }
            .padding(24)
            .frame(height: 274)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bgmSurface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.06)))
            .contentShape(RoundedRectangle(cornerRadius: 16))
            #else
            FeaturedSubjectCard(subject: subject, season: app.seasonLabel)
            #endif
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }

    private var rankingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "口碑佳作", subtitle: "Bangumi 动画排行榜")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(0..<((app.ranking.count + 2) / 3), id: \.self) { page in
                        VStack(spacing: 0) {
                            ForEach(Array(app.ranking.enumerated()).filter { $0.offset / 3 == page }, id: \.element.id) { index, subject in
                                if index % 3 != 0 {
                                    Divider().padding(.leading, 100)
                                }
                                NavigationLink(value: Route.subject(subject.id)) {
                                    HStack(spacing: 12) {
                                        Text("\(index + 1)")
                                            .font(.title3.weight(.bold).monospacedDigit())
                                            .foregroundStyle(index < 3 ? Color.brandPink : Color.secondary)
                                            .frame(width: 22)
                                        SubjectRow(title: subject.displayTitle, subtitle: subject.typeName, coverURL: subject.coverURL, trailing: subject.ratingText)
                                    }
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .containerRelativeFrame(.horizontal) { length, _ in
                            min(length, 440)
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
        }
    }

    private var guestCard: some View {
        Button { app.showLogin = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "books.vertical.fill")
                    .font(.title2)
                    .foregroundStyle(Color.brandPink)
                    .frame(width: 44, height: 44)
                    .background(Color.brandPink.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text("登录 Bangumi")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("同步收藏与观看进度")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color.bgmBackground, in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }

    private var communitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "社区")
            VStack(spacing: 0) {
                NavigationLink { GroupListView() } label: {
                    CommunityCard(icon: "person.2.fill", title: "小组")
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 72)
                NavigationLink(value: Route.blogs) {
                    CommunityCard(icon: "text.book.closed.fill", title: "日志")
                }
                .buttonStyle(.plain)
                if let username = app.auth.username {
                    Divider().padding(.leading, 72)
                    NavigationLink { TimelineView(username: username) } label: {
                        CommunityCard(icon: "clock.arrow.circlepath", title: "时光机")
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color.bgmBackground, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 20)
        }
    }

    private var weekdayText: String {
        Date.now.formatted(.dateTime.month().day()) + " · " + (app.calendar.first(where: { $0.weekday.id == app.todayWeekday })?.weekday.cn ?? "今天")
    }
}

struct FeaturedSubjectCard: View {
    let subject: Subject
    let season: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { geometry in
                CachedAsyncImage(url: subject.heroURL, maxPixel: 1200, placeholderTint: .subjectTint(subject.type))
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
            LinearGradient(
                stops: [.init(color: .bgmArtworkScrim.opacity(0.08), location: 0), .init(color: .bgmArtworkScrim.opacity(0.25), location: 0.35), .init(color: .bgmArtworkScrim.opacity(0.92), location: 1)],
                startPoint: .top, endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 10) {
                Text("本季精选")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.bgmArtworkScrim.opacity(0.45), in: Capsule())
                Spacer(minLength: 36)
                Text(season)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.bgmOnArtwork.opacity(0.8))
                Text(subject.displayTitle)
                    .font(.system(.title, weight: .bold))
                    .lineLimit(2, reservesSpace: true)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                HStack {
                    Text(subject.episodeCountText)
                    if let rating = subject.rating, rating.total > 0 {
                        Text("·")
                        Label(rating.scoreText, systemImage: "star.fill")
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                }
                .font(.subheadline)
                .foregroundStyle(Color.bgmOnArtwork.opacity(0.85))
            }
            .padding(22)
        }
        .foregroundStyle(Color.bgmOnArtwork)
        .frame(height: dynamicTypeSize.isAccessibilitySize ? 420 : 260)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct CommunityCard: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.brandPink)
                .frame(width: 42, height: 42)
                .background(Color.brandPink.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .contentShape(Rectangle())
    }
}
