import SwiftUI

struct ProfileView: View {
    @Environment(AppModel.self) private var app
    @State private var showIndexLookup = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                #if os(macOS)
                Text("我的").font(.largeTitle.bold())
                #endif

                accountCard

                HStack(alignment: .top, spacing: 14) {
                    Button { openLibrary() } label: {
                        shortcut("我的收藏", icon: "books.vertical")
                    }
                    Button { app.showSettings = true } label: {
                        shortcut("偏好设置", icon: "slider.horizontal.3")
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 12) {
                    Text("探索与记录")
                        .font(.headline)
                        .padding(.leading, 4)

                    VStack(spacing: 0) {
                        NavigationLink { GroupListView() } label: {
                            actionRow("小组与讨论", icon: "person.2")
                        }
                        rowDivider
                        NavigationLink(value: Route.blogs) {
                            actionRow("日志", icon: "text.book.closed")
                        }
                        rowDivider
                        Button { showIndexLookup = true } label: {
                            actionRow("查看目录", icon: "list.bullet.rectangle")
                        }
                        if let username = app.auth.username {
                            rowDivider
                            NavigationLink(value: Route.timeline(username)) {
                                actionRow("我的时光机", icon: "clock.arrow.circlepath")
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .background(Color.bgmSurface, in: RoundedRectangle(cornerRadius: 20))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20).strokeBorder(Color.primary.opacity(0.05))
                    }
                }

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bgmori \(app.settings.appVersion)")
                            .font(.caption2)
                    }
                    Spacer()
                    Link(destination: URL(string: "https://bgm.tv")!) {
                        Label("Bangumi", systemImage: "arrow.up.right")
                    }
                    .foregroundStyle(.secondary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            }
            .padding(.top, 8)
            .padding(.bottom, 28)
            #if os(iOS)
            .padding(.horizontal, 20)
            #endif
            .bgmDesktopContent(maxWidth: 820)
        }
        .background(Color.bgmBackground)
        .scrollIndicators(.hidden)
        .bgmLargeNavigationTitle("我的")
        .task { await app.library.loadIfNeeded() }
        .refreshable {
            if let username = app.auth.username {
                await app.library.loadAll(username: username, force: true)
            }
        }
        .sheet(isPresented: $showIndexLookup) {
            IndexLookupView().environment(app)
                #if os(macOS)
                .frame(width: 440, height: 300)
                #endif
        }
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                AvatarView(url: app.auth.user?.avatarURL, size: 58)
                VStack(alignment: .leading, spacing: 5) {
                    Text(app.auth.user?.displayName ?? "我的 Bangumi")
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                    if let username = app.auth.username {
                        Text("@" + username).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            if let sign = app.auth.user?.sign, !sign.trimmed.isEmpty {
                Text(sign)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Divider()

            if app.isGuest {
                HStack(spacing: 12) {
                    Text("同步收藏、评分与进度")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button { app.showLogin = true } label: {
                        Label("登录", systemImage: "arrow.right")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .foregroundStyle(Color.bgmCanvas)
                    .controlSize(.regular)
                }
            } else {
                collectionOverview
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 22)
                .fill(LinearGradient(colors: [Color.brandPink.opacity(0.08), Color.bgmSurface], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22).strokeBorder(Color.primary.opacity(0.05))
        }
    }

    @ViewBuilder
    private var collectionOverview: some View {
        if app.library.isLoading && app.library.collections.isEmpty {
            ProgressView("正在同步收藏…")
                .font(.caption)
                .frame(maxWidth: .infinity)
        } else if app.library.lastError == nil || !app.library.collections.isEmpty {
            HStack(spacing: 0) {
                collectionStat(app.library.collections.count, title: "全部收藏")
                collectionStat(app.library.counts[.doing] ?? 0, title: "在看")
                collectionStat(app.library.counts[.done] ?? 0, title: "看过")
                collectionStat(app.library.counts[.wish] ?? 0, title: "想看")
            }
        }
        if let error = app.library.lastError {
            HStack {
                Text("收藏同步失败：\(error)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("重试") {
                    Task {
                        if let username = app.auth.username {
                            await app.library.loadAll(username: username, force: true)
                        }
                    }
                }
                .disabled(app.library.isLoading)
            }
        }
    }

    private func collectionStat(_ value: Int, title: String) -> some View {
        VStack(spacing: 5) {
            Text(value, format: .number)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(.primary)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func shortcut(_ title: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(Color.brandPink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline).foregroundStyle(.primary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.bgmSurface, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20).strokeBorder(Color.primary.opacity(0.05))
        }
        .contentShape(RoundedRectangle(cornerRadius: 20))
    }

    private func actionRow(_ title: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.brandPink)
                .frame(width: 38, height: 38)
                .background(Color.brandPink.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var rowDivider: some View { Divider().padding(.leading, 64) }

    private func openLibrary() {
        app.router.selectedSection = .library
        #if os(macOS)
        app.router.macPath.removeAll()
        #endif
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
