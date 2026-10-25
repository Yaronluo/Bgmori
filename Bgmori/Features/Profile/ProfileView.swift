import SwiftUI

struct ProfileView: View {
    @Environment(AppModel.self) private var app
    @State private var showIndexLookup = false

    var body: some View {
        Group {
            #if os(macOS)
            desktopProfile
            #else
            phoneProfile
            #endif
        }
        .bgmLargeNavigationTitle("我的")
        .task { await app.library.loadIfNeeded() }
        .sheet(isPresented: $showIndexLookup) {
            IndexLookupView().environment(app)
                #if os(macOS)
                .frame(width: 440, height: 280)
                #endif
        }
    }

    private var phoneProfile: some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                    .listRowBackground(Color.clear)
            }

            if app.auth.isLoggedIn {
                Section {
                    HStack(spacing: 8) {
                        StatTile(value: app.library.collections.count, title: "收藏")
                        StatTile(value: app.library.counts[.doing] ?? 0, title: "在看")
                        StatTile(value: app.library.counts[.done] ?? 0, title: "看过")
                        StatTile(value: app.library.counts[.wish] ?? 0, title: "想看")
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }

            Section("资料库") {
                Button {
                    app.router.selectedSection = .library
                } label: {
                    Label("我的收藏", systemImage: "books.vertical")
                }

                if let username = app.auth.username {
                    NavigationLink(value: Route.timeline(username)) {
                        Label("时光机", systemImage: "clock.arrow.circlepath")
                    }
                }

                Button {
                    showIndexLookup = true
                } label: {
                    Label("查看目录", systemImage: "list.bullet.rectangle")
                }

                Button {
                    app.showSettings = true
                } label: {
                    Label("设置", systemImage: "gearshape")
                }
            }

            Section("社区（只读）") {
                NavigationLink {
                    GroupListView()
                } label: {
                    Label("小组与讨论", systemImage: "person.3")
                }
                NavigationLink {
                    BlogListView()
                } label: {
                    Label("日志", systemImage: "text.book.closed")
                }
                if let username = app.auth.username {
                    NavigationLink {
                        TimelineView(username: username)
                    } label: {
                        Label("我的时光机", systemImage: "clock")
                    }
                }
            }

            Section("关于") {
                HStack {
                    Text("Bgmori")
                    Spacer()
                    Text(app.settings.appVersion)
                        .foregroundStyle(.secondary)
                }
                Link("Bangumi 官网", destination: URL(string: "https://bgm.tv")!)
                Text("非官方客户端，与 Bangumi 官方无关联。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
    }

    #if os(macOS)
    private var desktopProfile: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("我的").font(.largeTitle.bold())
                HStack(spacing: 20) {
                    AvatarView(url: app.auth.user?.avatarURL, size: 64)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(app.auth.user?.displayName ?? "你的 Bangumi")
                            .font(.title2.bold())
                        Text(app.auth.username.map { "@" + $0 } ?? "收藏喜爱的作品，记录每一段故事。")
                            .foregroundStyle(.secondary)
                        if let sign = app.auth.user?.sign, !sign.isEmpty {
                            Text(sign).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    Spacer()
                    if app.isGuest {
                        Button("登录 Bangumi") { app.showLogin = true }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    }
                }
                .padding(24)
                .background(Color.bgmSurface, in: RoundedRectangle(cornerRadius: 12))

                if app.auth.isLoggedIn {
                    HStack(spacing: 12) {
                        StatTile(value: app.library.collections.count, title: "收藏")
                        StatTile(value: app.library.counts[.doing] ?? 0, title: "在看")
                        StatTile(value: app.library.counts[.done] ?? 0, title: "看过")
                        StatTile(value: app.library.counts[.wish] ?? 0, title: "想看")
                    }
                }
                HStack(alignment: .top, spacing: 20) {
                    DesktopPanel(title: "资料库") {
                        VStack(spacing: 0) {
                            Button { app.router.selectedSection = .library } label: {
                                desktopRow("我的收藏", subtitle: "管理作品与观看进度", icon: "books.vertical")
                            }
                            Divider()
                            Button { showIndexLookup = true } label: {
                                desktopRow("查看目录", subtitle: "通过 ID 打开 Bangumi 目录", icon: "list.bullet.rectangle")
                            }
                            Divider()
                            Button { app.showSettings = true } label: {
                                desktopRow("设置", subtitle: "账户、外观与通知", icon: "gearshape")
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    DesktopPanel(title: "社区") {
                        VStack(spacing: 0) {
                            NavigationLink { GroupListView() } label: {
                                desktopRow("小组与讨论", subtitle: "发现同好的话题", icon: "person.2")
                            }
                            Divider()
                            NavigationLink { BlogListView() } label: {
                                desktopRow("日志", subtitle: "阅读关于作品的想法", icon: "text.book.closed")
                            }
                            if let username = app.auth.username {
                                Divider()
                                NavigationLink(value: Route.timeline(username)) {
                                    desktopRow("时光机", subtitle: "回顾你的收藏轨迹", icon: "clock.arrow.circlepath")
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        Text("社区内容以只读方式浏览")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
                HStack {
                    Text("Bgmori \(app.settings.appVersion)")
                    Text("·")
                    Text("非官方客户端")
                    Spacer()
                    Link("Bangumi 官网 ↗", destination: URL(string: "https://bgm.tv")!)
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .bgmDesktopContent(maxWidth: 940)
        }
        .background(Color.bgmCanvas)
    }

    private func desktopRow(_ title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18)).foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
    #endif

    @ViewBuilder
    private var header: some View {
        if let user = app.auth.user {
            HStack(spacing: 14) {
                AvatarView(url: user.avatarURL, size: 64)
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
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    AvatarView(url: nil, size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("你的 Bangumi")
                            .font(.title2.weight(.bold))
                        Text("登录后同步收藏、评分与进度")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Button {
                    app.showLogin = true
                } label: {
                    Label("登录 Bangumi", systemImage: "person.badge.key")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(Color.bgmCanvas)
                .tint(.brandPink)
            }
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
                Section {
                    Text("Bangumi 的目录（Index）没有公开的列表接口，只能通过 ID 或链接进入。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
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
                                    width: 150
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

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            user = try await app.api.user(username)
            let page = try await app.api.userCollections(username, limit: 50, auth: app.auth.isLoggedIn)
            collections = page.data
            errorText = nil
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
