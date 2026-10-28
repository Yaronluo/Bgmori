import SwiftUI

// MARK: - Groups

struct GroupListView: View {
    @Environment(AppModel.self) private var app
    @State private var home: GroupHome?
    @State private var isLoading = true
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if errorText != nil, home != nil {
                    RefreshFailureNotice(message: "小组更新失败，显示的是缓存内容") {
                        Task { await load(force: true) }
                    }
                    .padding(.horizontal, 20)
                }
                if let home {
                    if !home.groups.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("热门小组")
                                .font(.bgmSection)
                                .padding(.horizontal, 20)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], alignment: .leading, spacing: 12) {
                                ForEach(home.groups) { group in
                                    NavigationLink {
                                        GroupDetailView(groupName: group.id)
                                    } label: {
                                        HStack(spacing: 10) {
                                            CachedAsyncImage(url: group.iconURL, maxPixel: 120, placeholderTint: .brandPink)
                                                .frame(width: 42, height: 42)
                                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(group.title)
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .lineLimit(1)
                                                Text(group.members)
                                                    .font(.system(size: 9))
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                            Spacer(minLength: 0)
                                        }
                                        .padding(10)
                                        .bgmCardBackground(cornerRadius: 12)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    if !home.topics.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("最新讨论")
                                .font(.bgmSection)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 8)
                            ForEach(home.topics.prefix(30)) { topic in
                                NavigationLink {
                                    TopicDetailView(topicID: topic.id)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(topic.title)
                                            .font(.system(size: 13, weight: .medium))
                                            .lineLimit(2)
                                        HStack(spacing: 6) {
                                            if let group = topic.groupName { Text(group) }
                                            if let author = topic.author { Text("· \(author)") }
                                            if let replies = topic.replies { Text("· \(replies) 回复") }
                                            if let last = topic.lastReply { Text("· \(last)") }
                                        }
                                        .font(.system(size: 9))
                                        .foregroundStyle(.tertiary)
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 9)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                Divider().padding(.leading, 20)
                            }
                        }
                    }

                    if home.groups.isEmpty && home.topics.isEmpty {
                        EmptyStateView(icon: "person.3", title: "暂无内容", message: "")
                    }
                } else if isLoading {
                    ProgressView("加载小组…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                } else {
                    EmptyStateView(icon: "wifi.exclamationmark", title: "加载失败", message: errorText ?? "请稍后再试", actionTitle: "重试") {
                        Task { await load(force: true) }
                    }
                }

            }
            .padding(.top, 8)
            .padding(.bottom, 24)
            .bgmDesktopContent(maxWidth: 820)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("小组")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .bgmWebFallback(URL(string: "https://bgm.tv/group")!, isPresented: errorText != nil)
        .task { await load() }
    }

    private func load(force: Bool = false) async {
        if !force, let hit = await app.social.cachedGroupHome() {
            guard !Task.isCancelled else { return }
            home = hit.value
            isLoading = false
            if hit.isFresh { return }
            guard await app.api.beginBackgroundRefresh(hit.cacheKey, minimumInterval: 120) else { return }
        }
        isLoading = home == nil
        errorText = nil
        defer { isLoading = false }
        do {
            home = try await app.social.groupHome()
            errorText = nil
        } catch {
            guard !Task.isCancelled else { return }
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct GroupDetailView: View {
    @Environment(AppModel.self) private var app
    let groupName: String
    @State private var detail: GroupDetail?
    @State private var isLoading = true
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if errorText != nil, detail != nil {
                    RefreshFailureNotice(message: "小组更新失败，显示的是缓存内容") {
                        Task { await load(force: true) }
                    }
                    .padding(.horizontal, 20)
                }
                if let detail {
                    HStack(spacing: 12) {
                        CachedAsyncImage(url: detail.iconURL, maxPixel: 160, placeholderTint: .brandPink)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(detail.title)
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                            Text(detail.intro)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                    if detail.topics.isEmpty {
                        EmptyStateView(icon: "text.bubble", title: "暂无话题", message: "")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(detail.topics) { topic in
                                NavigationLink {
                                    TopicDetailView(topicID: topic.id)
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(topic.title)
                                            .font(.system(size: 13, weight: .medium))
                                            .lineLimit(2)
                                        HStack(spacing: 6) {
                                            if let author = topic.author { Text(author) }
                                            if let replies = topic.replies { Text("· \(replies) 回复") }
                                            if let last = topic.lastReply { Text("· \(last)") }
                                        }
                                        .font(.system(size: 9))
                                        .foregroundStyle(.tertiary)
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 9)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                Divider().padding(.leading, 20)
                            }
                        }
                    }

                } else if isLoading {
                    ProgressView("加载小组…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                } else {
                    EmptyStateView(icon: "wifi.exclamationmark", title: "加载失败", message: errorText ?? "请稍后再试", actionTitle: "重试") {
                        Task { await load(force: true) }
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
            .bgmDesktopContent(maxWidth: 820)
        }
        .scrollIndicators(.hidden)
        .navigationTitle(detail?.title ?? groupName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .bgmWebFallback(URL(string: "https://bgm.tv/group/\(groupName)")!, isPresented: errorText != nil)
        .task { await load() }
    }

    private func load(force: Bool = false) async {
        if !force, let hit = await app.social.cachedGroupDetail(name: groupName) {
            guard !Task.isCancelled else { return }
            detail = hit.value
            isLoading = false
            if hit.isFresh { return }
            guard await app.api.beginBackgroundRefresh(hit.cacheKey, minimumInterval: 120) else { return }
        }
        isLoading = detail == nil
        errorText = nil
        defer { isLoading = false }
        do {
            detail = try await app.social.groupDetail(name: groupName)
            errorText = nil
        } catch {
            guard !Task.isCancelled else { return }
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct TopicDetailView: View {
    @Environment(AppModel.self) private var app
    let topicID: Int
    @State private var detail: TopicDetail?
    @State private var isLoading = true
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if errorText != nil, detail != nil {
                    RefreshFailureNotice(message: "话题更新失败，显示的是缓存内容") {
                        Task { await load(force: true) }
                    }
                    .padding(.horizontal, 20)
                }
                if let detail {
                    if let group = detail.groupName {
                        Text(group)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                    }
                    Text(detail.title)
                        .font(.system(size: 22, weight: .bold))
                        .padding(.horizontal, 20)

                    ForEach(detail.posts) { post in
                        HStack(alignment: .top, spacing: 10) {
                            AvatarView(url: post.avatarURL, size: 32)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(post.name)
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(post.floor)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.tertiary)
                                    Spacer()
                                    Text(post.time)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.tertiary)
                                }
                                Text(post.text)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .lineSpacing(3)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        Divider().padding(.leading, 62)
                    }

                } else if isLoading {
                    ProgressView("加载话题…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                } else {
                    EmptyStateView(icon: "wifi.exclamationmark", title: "加载失败", message: errorText ?? "请稍后再试", actionTitle: "重试") {
                        Task { await load(force: true) }
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
            .bgmDesktopContent(maxWidth: 820)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("话题")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .bgmWebFallback(URL(string: "https://bgm.tv/group/topic/\(topicID)")!, isPresented: errorText != nil)
        .task { await load() }
    }

    private func load(force: Bool = false) async {
        if !force, let hit = await app.social.cachedTopic(id: topicID) {
            guard !Task.isCancelled else { return }
            detail = hit.value
            isLoading = false
            if hit.isFresh { return }
            guard await app.api.beginBackgroundRefresh(hit.cacheKey, minimumInterval: 120) else { return }
        }
        isLoading = detail == nil
        errorText = nil
        defer { isLoading = false }
        do {
            detail = try await app.social.topic(id: topicID)
            errorText = nil
        } catch {
            guard !Task.isCancelled else { return }
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Blogs

struct BlogListView: View {
    @Environment(AppModel.self) private var app
    @State private var blogs: [BlogSummary] = []
    @State private var isLoading = true
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if isLoading && blogs.isEmpty {
                    ProgressView("加载日志…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                } else if blogs.isEmpty {
                    EmptyStateView(icon: "text.book.closed", title: "暂无日志", message: errorText ?? "", actionTitle: "重试") {
                        Task { await load(force: true) }
                    }
                } else {
                    if errorText != nil {
                        RefreshFailureNotice(message: "日志更新失败，显示的是缓存内容") {
                            Task { await load(force: true) }
                        }
                        .padding(.horizontal, 20)
                    }
                    ForEach(blogs) { blog in
                        NavigationLink(value: Route.blog(blog.id)) {
                            HStack(alignment: .top, spacing: 12) {
                                CachedAsyncImage(url: blog.coverURL, maxPixel: 220, placeholderTint: .brandPink)
                                    .frame(width: 62, height: 84)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(blog.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .lineLimit(2)
                                    Text(blog.summary)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    HStack(spacing: 5) {
                                        if let author = blog.author { Text(author) }
                                        if let subject = blog.subjectName { Text("· \(subject)") }
                                        if let date = blog.date { Text("· \(date)") }
                                    }
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("blog-\(blog.id)")
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 94)
                    }
                }

            }
            .padding(.top, 8)
            .padding(.bottom, 24)
            .bgmDesktopContent(maxWidth: 820)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("日志")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .bgmWebFallback(URL(string: "https://bgm.tv/blog")!, isPresented: errorText != nil)
        .task { await load() }
    }

    private func load(force: Bool = false) async {
        if !force, let hit = await app.social.cachedBlogList() {
            guard !Task.isCancelled else { return }
            blogs = hit.value
            isLoading = false
            if hit.isFresh { return }
            guard await app.api.beginBackgroundRefresh(hit.cacheKey, minimumInterval: 120) else { return }
        }
        isLoading = blogs.isEmpty
        errorText = nil
        defer { isLoading = false }
        do {
            blogs = try await app.social.blogList()
            errorText = nil
        } catch {
            guard !Task.isCancelled else { return }
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct BlogDetailView: View {
    @Environment(AppModel.self) private var app
    let blogID: Int
    @State private var detail: BlogDetail?
    @State private var isLoading = true
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if errorText != nil, detail != nil {
                    RefreshFailureNotice(message: "日志更新失败，显示的是缓存内容") {
                        Task { await load(force: true) }
                    }
                    .padding(.horizontal, 20)
                }
                if let detail {
                    if let cover = detail.coverURL {
                        CachedAsyncImage(url: cover, maxPixel: 900, placeholderTint: .brandPink)
                            .frame(height: 220)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.horizontal, 20)
                    }
                    Text(detail.title)
                        .accessibilityIdentifier("blog-detail-title")
                        .font(.system(size: 24, weight: .bold))
                        .padding(.horizontal, 20)
                    HStack(spacing: 6) {
                        if let author = detail.author { Text(author) }
                        if let date = detail.date { Text("· \(date)") }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)

                    Text(detail.content)
                        .accessibilityIdentifier("blog-detail-content")
                        .font(.system(size: 14))
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)

                } else if isLoading {
                    ProgressView("加载日志…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                } else {
                    EmptyStateView(icon: "wifi.exclamationmark", title: "加载失败", message: errorText ?? "请稍后再试", actionTitle: "重试") {
                        Task { await load(force: true) }
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
            .bgmDesktopContent(maxWidth: 820)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("日志")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .bgmWebFallback(URL(string: "https://bgm.tv/blog/\(blogID)")!, isPresented: errorText != nil)
        .task { await load() }
    }

    private func load(force: Bool = false) async {
        if !force, let hit = await app.social.cachedBlogDetail(id: blogID) {
            guard !Task.isCancelled else { return }
            detail = hit.value
            isLoading = false
            if hit.isFresh { return }
            guard await app.api.beginBackgroundRefresh(hit.cacheKey, minimumInterval: 120) else { return }
        }
        isLoading = detail == nil
        errorText = nil
        defer { isLoading = false }
        do {
            detail = try await app.social.blogDetail(id: blogID)
            errorText = nil
        } catch {
            guard !Task.isCancelled else { return }
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Timeline

struct TimelineView: View {
    @Environment(AppModel.self) private var app
    let username: String
    @State private var items: [TimelineItem] = []
    @State private var isLoading = true
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if isLoading && items.isEmpty {
                    ProgressView("加载时光机…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                } else if items.isEmpty {
                    EmptyStateView(icon: "clock.arrow.circlepath", title: "暂无动态", message: errorText ?? "")
                } else {
                    if errorText != nil {
                        RefreshFailureNotice(message: "时光机更新失败，显示的是缓存内容") {
                            Task { await load(force: true) }
                        }
                        .padding(.horizontal, 20)
                    }
                    ForEach(items) { item in
                        Group {
                            if let subjectID = item.subjectID {
                                NavigationLink(value: Route.subject(subjectID)) {
                                    timelineRow(item)
                                }
                                .buttonStyle(.plain)
                            } else {
                                timelineRow(item)
                            }
                        }
                        Divider().padding(.leading, 74)
                    }
                }

            }
            .padding(.top, 8)
            .padding(.bottom, 24)
            .bgmDesktopContent(maxWidth: 820)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("时光机")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .bgmWebFallback(URL(string: "https://bgm.tv/user/\(username)/timeline")!, isPresented: errorText != nil)
        .task { await load() }
    }

    private func timelineRow(_ item: TimelineItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            CachedAsyncImage(url: item.coverURL, maxPixel: 180, placeholderTint: .brandPink)
                .frame(width: 48, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(item.action)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.brandPink)
                    if let rating = item.rating {
                        Text("\(rating) 分").font(.system(size: 10)).foregroundStyle(.orange)
                    }
                    Spacer()
                    if let time = item.time {
                        Text(time).font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                }
                if let title = item.subjectTitle, !title.isEmpty {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                if let comment = item.comment, !comment.isEmpty {
                    Text(comment)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load(force: Bool = false) async {
        if !force, let hit = await app.social.cachedTimeline(username: username) {
            guard !Task.isCancelled else { return }
            items = hit.value
            isLoading = false
            if hit.isFresh { return }
            guard await app.api.beginBackgroundRefresh(hit.cacheKey, minimumInterval: 120) else { return }
        }
        isLoading = items.isEmpty
        errorText = nil
        defer { isLoading = false }
        do {
            items = try await app.social.timeline(username: username)
            errorText = nil
        } catch {
            guard !Task.isCancelled else { return }
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
