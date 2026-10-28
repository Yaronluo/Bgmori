import Foundation
import SwiftUI

struct ProfileView: View {
    @Environment(AppModel.self) private var app

    @State private var showIndexLookup = false
    @State private var friends: [FriendSummary] = []
    @State private var isLoadingFriends = false
    @State private var friendError: String?
    @State private var characterTotal = 0
    @State private var personTotal = 0
    @State private var isLoadingPeople = false
    @State private var peopleError: String?
    @State private var loadedProfileUsername: String?

    private var isSignedIn: Bool { app.auth.isLoggedIn }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                hero

                if isSignedIn {
                    personalContent
                } else if !recentItems.isEmpty {
                    recentSection
                }

                communitySection
                toolsSection
                footer
            }
            .padding(.top, 6)
            .padding(.bottom, 34)
            #if os(iOS)
            .padding(.horizontal, 20)
            #endif
            .bgmDesktopContent(maxWidth: 980)
        }
        .background(Color.bgmBackground)
        .scrollIndicators(.hidden)
        .bgmLargeNavigationTitle("我的")
        .task(id: app.auth.username) { await load() }
        .refreshable { await refresh() }
        .sheet(isPresented: $showIndexLookup) {
            IndexLookupView().environment(app)
                #if os(macOS)
                .frame(width: 440, height: 300)
                #endif
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            #if os(macOS)
            HStack(alignment: .center, spacing: 28) {
                VStack(alignment: .leading, spacing: 16) {
                    identity
                    actionsRow
                }
                Spacer(minLength: 20)
                if isSignedIn {
                    statsGrid
                        .frame(width: 380)
                }
            }
            #else
            identity
            actionsRow
            if isSignedIn {
                statsGrid
            }
            #endif
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private var identity: some View {
        HStack(alignment: .top, spacing: 16) {
            AvatarView(url: app.auth.user?.avatarURL, size: 82)
                .overlay {
                    Circle().strokeBorder(Color.bgmSurface.opacity(0.9), lineWidth: 3)
                }
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)

            VStack(alignment: .leading, spacing: 5) {
                Text(displayName)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                if let username = app.auth.username, !app.isGuest {
                    Text("@\(username)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let signature {
                    Text(signature)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                } else if app.isGuest {
                    Text("登录后同步收藏、评分与观看进度。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var actionsRow: some View {
        HStack(spacing: 10) {
            if app.isGuest {
                primaryAction("登录", systemImage: "person.crop.circle.badge.checkmark") {
                    app.showLogin = true
                }
                .accessibilityIdentifier("profile-login")
            } else {
                primaryAction("我的收藏", systemImage: "books.vertical.fill") {
                    openLibrary()
                }

                Button { app.showSettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("偏好设置")
                .help("偏好设置")
            }

            Spacer(minLength: 0)
        }
    }

    private func primaryAction(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage).font(.subheadline)
                Text(title).font(.subheadline.weight(.medium))
                Image(systemName: "chevron.right").font(.caption2)
            }
            .foregroundStyle(Color.brandPink)
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var statsGrid: some View {
        HStack(spacing: 0) {
            ProfileStatTile(
                value: statValue(app.library.collections.count),
                title: "全部收藏",
                tint: .brandPink
            )
            statDivider
            ProfileStatTile(
                value: statValue(app.library.counts[.doing] ?? 0),
                title: "在看",
                tint: .collectionTint(CollectionType.doing.rawValue)
            )
            statDivider
            ProfileStatTile(
                value: statValue(app.library.counts[.done] ?? 0),
                title: "看过",
                tint: .collectionTint(CollectionType.done.rawValue)
            )
            statDivider
            ProfileStatTile(
                value: statValue(app.library.counts[.wish] ?? 0),
                title: "想看",
                tint: .collectionTint(CollectionType.wish.rawValue)
            )
        }
        .padding(.vertical, 4)
    }

    private var statDivider: some View {
        Divider()
            .frame(height: 30)
    }

    private var displayName: String {
        if app.isGuest { return "我的" }
        return app.auth.user?.displayName ?? app.auth.displayName
    }

    private var signature: String? {
        guard !app.isGuest,
              let raw = app.auth.user?.sign,
              !raw.trimmed.isEmpty else { return nil }
        return raw.trimmed
    }

    private func statValue(_ value: Int) -> String? {
        if app.library.isLoading && app.library.collections.isEmpty { return nil }
        return value.formatted()
    }

    // MARK: - Personal stats

    @ViewBuilder
    private var personalContent: some View {
        if app.library.isLoading && app.library.collections.isEmpty {
            syncLoadingCard
        } else if let error = app.library.lastError, app.library.collections.isEmpty {
            syncErrorCard(error)
        } else if app.library.collections.isEmpty {
            emptyLibraryCard
        } else {
            if app.library.lastError != nil {
                RefreshFailureNotice(message: "收藏同步失败，显示的是本地快照") {
                    Task {
                        if let username = app.auth.username {
                            await app.library.loadAll(username: username, force: true)
                        }
                    }
                }
            }
            if !app.continueWatching.isEmpty {
                continueSection
            }
            if !recentItems.isEmpty {
                recentSection
            }
            overviewSection
        }
    }

    private var syncLoadingCard: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("正在同步收藏…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(18)
        .profileCard(cornerRadius: 18)
    }

    private func syncErrorCard(_ error: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text("收藏同步失败")
                    .font(.subheadline.weight(.semibold))
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Button("重试") {
                Task {
                    if let username = app.auth.username {
                        await app.library.loadAll(username: username, force: true)
                    }
                }
            }
            .buttonStyle(.glass)
            .disabled(app.library.isLoading)
        }
        .padding(16)
        .profileCard(cornerRadius: 18)
    }

    private var emptyLibraryCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.brandPink)
                .frame(width: 42, height: 42)
                .background(Color.brandPink.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("还没有收藏")
                    .font(.subheadline.weight(.semibold))
                Text("去发现喜欢的作品，收藏会显示在这里。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("去发现") { openHome() }
                .font(.subheadline.weight(.medium))
                .buttonStyle(.plain)
                .foregroundStyle(Color.brandPink)
        }
        .padding(16)
        .profileCard(cornerRadius: 18)
    }

    private var continueSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ProfileSectionHeader(
                title: "继续观看",
                subtitle: "\(app.library.watching.count) 部在看",
                actionTitle: "全部收藏"
            ) {
                openLibrary()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(app.continueWatching) { item in
                        NavigationLink(value: Route.subject(item.subjectId)) {
                            CoverCard(
                                title: item.title,
                                subtitle: item.epStatus > 0 ? "看到 \(item.epStatus) 话" : "在看",
                                coverURL: item.coverURL,
                                progress: item.progressFraction,
                                tint: .subjectTint(item.subjectType),
                                width: 132
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ProfileSectionHeader(
                title: "最近浏览",
                subtitle: "\(recentItems.count) 部作品"
            )

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(recentItems) { item in
                        NavigationLink(value: Route.subject(item.id)) {
                            CoverCard(
                                title: item.title,
                                subtitle: item.typeName,
                                coverURL: item.coverURL,
                                tint: .subjectTint(item.type),
                                width: 112
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("最近浏览：\(item.title)")
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ProfileSectionHeader(
                title: "收藏概览",
                subtitle: "\(app.library.collections.count) 部作品 · \(rated.count) 部已评分",
                actionTitle: rated.isEmpty ? nil : "全部评分"
            ) {
                app.router.push(.ratings, in: .profile)
            }

            #if os(macOS)
            HStack(alignment: .top, spacing: 16) {
                ratingCard
                typeCard
                    .frame(width: 342)
            }
            #else
            VStack(spacing: 14) {
                ratingCard
                typeCard
            }
            #endif
        }
    }

    private var ratingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(averageText)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("平均评分 · \(rated.count) 部已评分")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(completionText)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("完成率")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            RatingDistributionBars(counts: ratingCounts, height: 38)

            Divider()

            if recentRated.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "star")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Text("给看过的作品打分，这里会出现你的评分与短评。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentRated.enumerated()), id: \.element.subjectId) { index, item in
                        ratingRow(item)
                        if index < recentRated.count - 1 {
                            Divider().padding(.leading, 40)
                        }
                    }
                }
            }
        }
        .padding(18)
        .profileCard()
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func ratingRow(_ item: UserSubjectCollection) -> some View {
        NavigationLink(value: Route.subject(item.subjectId)) {
            HStack(spacing: 10) {
                CachedAsyncImage(
                    url: item.coverURL,
                    maxPixel: 120,
                    placeholderTint: .subjectTint(item.subjectType)
                )
                .frame(width: 30, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(SubjectType.title(for: item.subjectType)) · \(item.rate) 分")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                RatingStars(score: Double(item.rate), size: 9)
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var typeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("收藏构成")
                    .font(.headline)
                Spacer(minLength: 8)
                Text("\(app.library.collections.count) 部")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 11) {
                ForEach(SubjectType.browsingTypes) { type in
                    typeRow(type)
                }
            }

            Divider()

            HStack(spacing: 0) {
                quickStat(value: "\(rated.count)", title: "已评分", icon: "star.fill", tint: .brandPink)
                Divider().frame(height: 26)
                quickStat(value: "\(reviewCount)", title: "短评", icon: "text.bubble", tint: .collectionTint(1))
                Divider().frame(height: 26)
                quickStat(value: favoriteTypeTitle, title: "最多", icon: "chart.bar.fill", tint: .collectionTint(2))
            }

            Divider()

            Button { openCategories() } label: {
                HStack(spacing: 7) {
                    Label("按类型浏览", systemImage: "square.grid.2x2")
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(minHeight: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .profileCard()
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func typeRow(_ type: SubjectType) -> some View {
        let count = typeCount(type)
        let tint = Color.subjectTint(type.rawValue)
        return VStack(spacing: 4) {
            HStack(spacing: 7) {
                Image(systemName: type.icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 14)
                Text(type.title)
                    .font(.caption)
                Spacer(minLength: 0)
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.06))
                    Capsule()
                        .fill(tint.opacity(0.75))
                        .frame(width: count == 0 ? 0 : max(3, proxy.size.width * CGFloat(count) / CGFloat(maxTypeCount)))
                }
            }
            .frame(height: 4)
        }
    }

    private func quickStat(value: String, title: String, icon: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(tint)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)：\(value)")
    }

    // MARK: - Community & tools

    private var communitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ProfileSectionHeader(
                title: "社区",
                subtitle: isSignedIn ? "好友、小组与我的记录" : "发现同好"
            )

            LazyVGrid(columns: featureColumns, spacing: 0) {
                if isSignedIn, let username = app.auth.username {
                    NavigationLink(value: Route.friends(username)) {
                        ProfileDestinationRow(
                            icon: "person.2.fill",
                            title: "好友",
                            subtitle: friendSubtitle,
                            tint: .brandPink,
                            accessory: friendAccessory
                        )
                    }
                    .buttonStyle(.plain)
                }

                NavigationLink {
                    GroupListView()
                } label: {
                    ProfileDestinationRow(
                        icon: "person.3.fill",
                        title: "小组与讨论",
                        subtitle: "热门小组与话题",
                        tint: .collectionTint(4)
                    )
                }
                .buttonStyle(.plain)

                NavigationLink(value: Route.blogs) {
                    ProfileDestinationRow(
                        icon: "text.book.closed.fill",
                        title: "日志",
                        subtitle: "作品之外的文字",
                        tint: .collectionTint(2)
                    )
                }
                .buttonStyle(.plain)

                if isSignedIn, let username = app.auth.username {
                    NavigationLink(value: Route.timeline(username)) {
                        ProfileDestinationRow(
                            icon: "clock.arrow.circlepath",
                            title: "时光机",
                            subtitle: "我的收藏动态",
                            tint: .collectionTint(1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ProfileSectionHeader(
                title: "更多",
                subtitle: isSignedIn ? "人物收藏与工具" : "工具与设置"
            )

            LazyVGrid(columns: featureColumns, spacing: 0) {
                if isSignedIn, let username = app.auth.username {
                    NavigationLink(value: Route.people(username)) {
                        ProfileDestinationRow(
                            icon: "person.crop.rectangle.stack.fill",
                            title: "人物收藏",
                            subtitle: peopleSubtitle,
                            tint: .collectionTint(1),
                            accessory: peopleAccessory
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    Button { app.router.openSearch() } label: {
                        ProfileDestinationRow(
                            icon: "magnifyingglass",
                            title: "搜索",
                            subtitle: "找作品、角色与人物",
                            tint: .collectionTint(1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Button { showIndexLookup = true } label: {
                    ProfileDestinationRow(
                        icon: "list.bullet.rectangle.portrait",
                        title: "查看目录",
                        subtitle: "打开一份作品清单",
                        tint: .collectionTint(4)
                    )
                }
                .buttonStyle(.plain)

                Button { app.router.openCalendar() } label: {
                    ProfileDestinationRow(
                        icon: "calendar",
                        title: "每日放送",
                        subtitle: "今天的放送表",
                        tint: .collectionTint(3)
                    )
                }
                .buttonStyle(.plain)

                Button { app.showSettings = true } label: {
                    ProfileDestinationRow(
                        icon: "slider.horizontal.3",
                        title: "偏好设置",
                        subtitle: "界面、内容与通知",
                        tint: .collectionTint(2)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var footer: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Bgmori \(app.settings.appVersion)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    private var featureColumns: [GridItem] {
        #if os(macOS)
        Array(repeating: GridItem(.flexible(), spacing: 28), count: 2)
        #else
        Array(repeating: GridItem(.flexible(), spacing: 0), count: 1)
        #endif
    }

    private var friendSubtitle: String {
        if isLoadingFriends && friends.isEmpty { return "正在读取…" }
        if friends.isEmpty { return friendError == nil ? "还没有好友" : "打开好友列表" }
        return "\(friends.count) 位好友"
    }

    private var friendAccessory: AnyView? {
        guard !friends.isEmpty else { return nil }
        return AnyView(
            FriendAvatarStack(urls: friends.prefix(3).map(\.avatarURL), size: 22)
        )
    }

    private var peopleSubtitle: String {
        let total = characterTotal + personTotal
        if isLoadingPeople && total == 0 { return "正在读取…" }
        if total == 0 { return peopleError == nil ? "角色与人物" : "暂时无法读取" }
        return "\(total) 位"
    }

    private var peopleAccessory: AnyView? {
        let total = characterTotal + personTotal
        guard total > 0 else { return nil }
        return AnyView(
            Text("\(total)")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.collectionTint(1))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.collectionTint(1).opacity(0.12), in: Capsule())
        )
    }

    // MARK: - Derived data

    private var recentItems: [RecentSubject] {
        Array(
            app.recentSubjects.subjects
                .filter { app.settings.showNSFW || !$0.nsfw }
                .prefix(10)
        )
    }

    private var rated: [UserSubjectCollection] {
        app.library.collections.values.filter { $0.rate > 0 }
    }

    private var recentRated: [UserSubjectCollection] {
        Array(
            rated
                .sorted { ($0.updatedAt ?? "") > ($1.updatedAt ?? "") }
                .prefix(3)
        )
    }

    private var ratingCounts: [Int] {
        var counts = Array(repeating: 0, count: 10)
        for item in app.library.collections.values where item.rate > 0 {
            counts[min(max(item.rate, 1), 10) - 1] += 1
        }
        return counts
    }

    private var reviewCount: Int {
        rated.filter { $0.reviewText != nil }.count
    }

    private var favoriteTypeTitle: String {
        guard let favorite = SubjectType.browsingTypes.max(by: { typeCount($0) < typeCount($1) }),
              typeCount(favorite) > 0 else { return "—" }
        return favorite.title
    }

    private var averageText: String {
        guard !rated.isEmpty else { return "—" }
        let average = Double(rated.reduce(0) { $0 + $1.rate }) / Double(rated.count)
        return String(format: "%.1f", average)
    }

    private var completionText: String {
        let total = app.library.collections.count
        guard total > 0 else { return "—" }
        let done = app.library.counts[.done] ?? 0
        return String(format: "%.1f%%", Double(done) / Double(total) * 100)
    }

    private var maxTypeCount: Int {
        max(SubjectType.browsingTypes.map { typeCount($0) }.max() ?? 0, 1)
    }

    private func typeCount(_ type: SubjectType) -> Int {
        app.library.collections.values.filter { $0.subjectType == type.rawValue }.count
    }

    // MARK: - Actions & loading

    private func openLibrary() {
        app.router.selectedSection = .library
        #if os(macOS)
        app.router.macPath.removeAll()
        #endif
    }

    private func openCategories() {
        app.router.selectedSection = .categories
        #if os(macOS)
        app.router.macPath.removeAll()
        #endif
    }

    private func openHome() {
        app.router.selectedSection = .home
        #if os(macOS)
        app.router.macPath.removeAll()
        #endif
    }

    private func load() async {
        guard let username = app.auth.username, !app.isGuest else {
            friends = []
            characterTotal = 0
            personTotal = 0
            friendError = nil
            peopleError = nil
            loadedProfileUsername = nil
            await app.library.loadIfNeeded()
            return
        }
        if loadedProfileUsername != username {
            loadedProfileUsername = username
            friends = []
            characterTotal = 0
            personTotal = 0
            friendError = nil
            peopleError = nil
            isLoadingFriends = false
            isLoadingPeople = false
        }
        async let library: Void = app.library.loadIfNeeded()
        async let friends: Void = loadFriends(username: username)
        async let people: Void = loadPeople(username: username)
        _ = await (library, friends, people)
    }

    private func refresh() async {
        guard let username = app.auth.username, !app.isGuest else { return }
        async let library: Bool = app.library.loadAll(username: username, force: true)
        async let friends: Void = loadFriends(username: username, force: true)
        async let people: Void = loadPeople(username: username, force: true)
        _ = await (library, friends, people)
    }

    private func loadFriends(username: String, force: Bool = false) async {
        if !force, let hit = await app.social.cachedFriends(username: username) {
            guard !Task.isCancelled else { return }
            friends = hit.value
            friendError = nil
            isLoadingFriends = false
            if hit.isFresh { return }
            guard await app.api.beginBackgroundRefresh(hit.cacheKey, minimumInterval: 120) else { return }
        }
        guard !isLoadingFriends else { return }
        isLoadingFriends = true
        friendError = nil
        defer { isLoadingFriends = false }
        do {
            let value = try await app.social.friends(username: username, force: force)
            guard !Task.isCancelled else { return }
            friends = value
        } catch {
            guard !Task.isCancelled else { return }
            friendError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadPeople(username: String, force: Bool = false) async {
        guard !isLoadingPeople else { return }
        isLoadingPeople = true
        peopleError = nil
        defer { isLoadingPeople = false }
        let auth = app.auth.isLoggedIn
        async let characters: String? = loadCharacterTotal(username: username, auth: auth, force: force)
        async let persons: String? = loadPersonTotal(username: username, auth: auth, force: force)
        let failures = await [characters, persons].compactMap { $0 }
        guard !Task.isCancelled else { return }
        peopleError = failures.first
    }

    private func loadCharacterTotal(username: String, auth: Bool, force: Bool) async -> String? {
        if !force, let hit = await app.api.cachedUserCharacterCollections(username, limit: 1) {
            guard !Task.isCancelled else { return nil }
            characterTotal = hit.value.total
            if hit.isFresh { return nil }
            guard await app.api.beginBackgroundRefresh(hit.cacheKey, minimumInterval: 120) else { return nil }
        }
        do {
            let total = try await app.api
                .userCharacterCollections(username, limit: 1, auth: auth, force: force)
                .total
            guard !Task.isCancelled else { return nil }
            characterTotal = total
            return nil
        } catch {
            guard !Task.isCancelled else { return nil }
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadPersonTotal(username: String, auth: Bool, force: Bool) async -> String? {
        if !force, let hit = await app.api.cachedUserPersonCollections(username, limit: 1) {
            guard !Task.isCancelled else { return nil }
            personTotal = hit.value.total
            if hit.isFresh { return nil }
            guard await app.api.beginBackgroundRefresh(hit.cacheKey, minimumInterval: 120) else { return nil }
        }
        do {
            let total = try await app.api
                .userPersonCollections(username, limit: 1, auth: auth, force: force)
                .total
            guard !Task.isCancelled else { return nil }
            personTotal = total
            return nil
        } catch {
            guard !Task.isCancelled else { return nil }
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct StatTile: View {
    let value: Int
    let title: String

    var body: some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.brandPink)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(Color.bgmSecondary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct IndexLookupView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("目录 ID") {
                    TextField("例如 1", text: $text)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    Button("打开目录") {
                        guard let id = Int(text.trimmed), id > 0 else { return }
                        dismiss()
                        app.router.push(.index(id), in: .profile)
                    }
                    .disabled(Int(text.trimmed) == nil)
                }
            }
            .navigationTitle("查看目录")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

struct UserProfileView: View {
    @Environment(AppModel.self) private var app
    let username: String
    @State private var user: User?
    @State private var collections: [UserSubjectCollection] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var refreshError: String?
    @State private var loadedUsernameKey: String?
    @State private var loadedAt: Date?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if refreshError != nil, user != nil || !collections.isEmpty {
                    RefreshFailureNotice(message: "用户页面更新失败，显示的是缓存内容") {
                        Task { await load(force: true) }
                    }
                    .padding(.horizontal, 20)
                }
                if let user {
                    HStack(spacing: 14) {
                        AvatarView(url: user.avatarURL, size: 70)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.displayName)
                                .font(.title2.weight(.bold))
                            Text("@\(user.username)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if !user.sign.isEmpty {
                                Text(user.sign)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)

                    HStack(spacing: 8) {
                        StatTile(value: collections.count, title: "公开收藏")
                        StatTile(value: collections.filter { $0.type == 3 }.count, title: "在看")
                        StatTile(value: collections.filter { $0.type == 2 }.count, title: "看过")
                    }
                    .padding(.horizontal, 20)
                } else if isLoading {
                    ProgressView("加载用户…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                } else if let errorText {
                    EmptyStateView(icon: "person.crop.circle.badge.exclamationmark", title: "加载失败", message: errorText)
                }

                if !collections.isEmpty {
                    Text("公开收藏")
                        .font(.bgmSection)
                        .padding(.horizontal, 20)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16, alignment: .top)], alignment: .leading, spacing: 18) {
                        ForEach(collections) { item in
                            NavigationLink(value: Route.subject(item.subjectId)) {
                                CoverCard(
                                    title: item.title,
                                    subtitle: item.subject?.ratingText ?? "",
                                    coverURL: item.coverURL,
                                    badge: item.collectionType.title,
                                    progress: item.progressFraction,
                                    tint: .subjectTint(item.subjectType),
                                    width: nil
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .navigationTitle(user?.displayName ?? "用户")
        .task(id: username) {
            await load()
        }
    }

    private func load(force: Bool = false) async {
        let requested = username
        if loadedUsernameKey != requested {
            loadedUsernameKey = requested
            user = nil
            collections = []
            errorText = nil
            refreshError = nil
            isLoading = true
            loadedAt = nil
        }
        if !force, let loadedAt, Date().timeIntervalSince(loadedAt) < 120 { return }
        guard !isLoading || force || user == nil else { return }
        loadedAt = Date()
        if !force {
            if let hit = await app.api.cachedUser(requested) {
                guard !Task.isCancelled, requested == username, loadedUsernameKey == requested else { return }
                user = hit.value
                isLoading = false
            }
            if let hit = await app.api.cachedUserCollections(requested) {
                guard !Task.isCancelled, requested == username, loadedUsernameKey == requested else { return }
                collections = hit.value.data
                isLoading = false
            }
        }
        isLoading = user == nil
        if force { refreshError = nil }
        defer { isLoading = false }
        do {
            async let userValue = app.api.user(requested)
            async let pageValue = app.api.userCollections(requested, limit: 50, auth: app.auth.isLoggedIn)
            let (value, page) = try await (userValue, pageValue)
            guard !Task.isCancelled, requested == username, loadedUsernameKey == requested else { return }
            user = value
            collections = page.data
            errorText = nil
            refreshError = nil
        } catch {
            guard !Task.isCancelled, requested == username, loadedUsernameKey == requested else { return }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if user == nil && collections.isEmpty {
                errorText = message
            } else {
                refreshError = message
            }
        }
    }
}
