import SwiftUI

struct EpisodeDetailView: View {
    @Environment(AppModel.self) private var app
    let episodeID: Int

    @State private var episode: Episode?
    @State private var subject: Subject?
    @State private var comments: [SocialComment] = []
    @State private var commentsLoading = true
    @State private var commentsError: String?
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var refreshError: String?
    @State private var commentsEpisodeID: Int?
    @State private var loadedEpisodeID: Int?

    var body: some View {
        Group {
            if let episode {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if refreshError != nil {
                            RefreshFailureNotice(message: "章节更新失败，显示的是缓存内容") {
                                Task { await refreshAll() }
                            }
                            .padding(.horizontal, 20)
                        }
                        header(episode)
                        if let desc = episode.desc, !desc.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("简介").font(.bgmSection)
                                Text(desc)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .lineSpacing(3)
                            }
                            .padding(.horizontal, 20)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("吐槽").font(.bgmSection)
                                Spacer()
                                Text("\(episode.comment) 条")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            if commentsLoading && comments.isEmpty {
                                ProgressView("加载吐槽…")
                            } else if let commentsError, comments.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(commentsError).foregroundStyle(.secondary)
                                    Button("重试") { Task { await loadComments(force: true) } }
                                    Link("在网页查看", destination: URL(string: "https://bgm.tv/ep/\(episodeID)")!)
                                }
                                .font(.system(size: 12))
                            } else if comments.isEmpty {
                                Text("暂无吐槽")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            } else {
                                if commentsError != nil {
                                    RefreshFailureNotice(message: "吐槽更新失败，显示的是缓存内容") {
                                        Task { await loadComments(force: true) }
                                    }
                                }
                                VStack(spacing: 0) {
                                    ForEach(comments) { comment in
                                        SocialCommentRow(comment: comment)
                                        Divider().padding(.leading, 52)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)

                    }
                    .padding(.top, 8)
                }
                .scrollIndicators(.hidden)
                .refreshable { await refreshAll() }
            } else if isLoading {
                ProgressView("加载章节…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyStateView(icon: "exclamationmark.triangle", title: "章节加载失败", message: errorText ?? "请稍后再试", actionTitle: "重试") {
                    Task { await load() }
                }
            }
        }
        .navigationTitle(episode?.numberText ?? "章节")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .bgmWebFallback(URL(string: "https://bgm.tv/ep/\(episodeID)")!, isPresented: errorText != nil || commentsError != nil)
        .task(id: episodeID) {
            prepareIfNeeded()
            await load()
        }
        .task(id: episodeID) { await loadComments() }
    }

    private func header(_ episode: Episode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let subject {
                NavigationLink(value: Route.subject(subject.id)) {
                    HStack(spacing: 5) {
                        Text(subject.displayTitle)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text(episode.displayTitle)
                .font(.system(size: 24, weight: .bold))
            if !episode.originalTitle.isEmpty {
                Text(episode.originalTitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                if let airdate = episode.airdate, !airdate.isEmpty {
                    Label(airdate, systemImage: "calendar")
                }
                if let duration = episode.duration, !duration.isEmpty {
                    Label(duration, systemImage: "clock")
                }
                Label(episode.typeName, systemImage: "square.stack")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            Button {
                guard app.auth.isLoggedIn else { app.showLogin = true; return }
                guard let subject else { return }
                Task {
                    let isDone = app.library.episodeType(episode.id, subjectID: subject.id) == EpisodeCollectionType.done.rawValue
                    await app.library.setEpisode(
                        subject: subject,
                        episode: episode,
                        type: isDone ? EpisodeCollectionType.none.rawValue : EpisodeCollectionType.done.rawValue
                    )
                }
            } label: {
                Label(
                    isWatched(episode) ? "已看过" : "标记为看过",
                    systemImage: isWatched(episode) ? "checkmark.circle.fill" : "checkmark.circle"
                )
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .tint(isWatched(episode) ? .green : .brandPink)
        }
        .padding(.horizontal, 20)
    }

    private func isWatched(_ episode: Episode) -> Bool {
        guard let subject else { return false }
        if app.library.episodeType(episode.id, subjectID: subject.id) == EpisodeCollectionType.done.rawValue { return true }
        return (app.library.collection(for: subject.id)?.epStatus ?? 0) >= Int(episode.ep ?? 0)
    }

    private func prepareIfNeeded() {
        guard loadedEpisodeID != episodeID else { return }
        loadedEpisodeID = episodeID
        episode = nil
        subject = nil
        comments = []
        commentsEpisodeID = nil
        commentsError = nil
        commentsLoading = true
        errorText = nil
        refreshError = nil
        isLoading = true
    }

    private func load() async {
        await loadBase(force: false)
    }

    private func refreshAll() async {
        async let base: Void = loadBase(force: true)
        async let comments: Void = loadComments(force: true)
        _ = await (base, comments)
    }

    private func loadBase(force: Bool) async {
        let id = episodeID
        if !force, let hit = await app.api.cachedEpisode(id) {
            guard !Task.isCancelled, id == episodeID else { return }
            episode = hit.value
            isLoading = false
            if hit.isFresh {
                await loadLinkedSubject(force: false)
                return
            }
            guard await app.api.beginBackgroundRefresh(hit.cacheKey, minimumInterval: 120) else {
                await loadLinkedSubject(force: false)
                return
            }
        }
        if episode == nil { isLoading = true }
        if force { refreshError = nil }
        do {
            let value = try await app.api.episode(id)
            guard !Task.isCancelled, id == episodeID else { return }
            episode = value
            errorText = nil
            refreshError = nil
            isLoading = false
            await loadLinkedSubject(force: force)
        } catch {
            guard !Task.isCancelled, !Self.isCancellation(error) else { return }
            if episode == nil {
                errorText = Self.message(for: error)
            } else {
                refreshError = Self.message(for: error)
            }
            isLoading = false
        }
    }

    private func loadLinkedSubject(force: Bool) async {
        guard let subjectID = episode?.subjectId else { return }
        var needsRefresh = force || subject?.id != subjectID
        if !force, let hit = await app.api.cachedSubject(subjectID) {
            guard !Task.isCancelled, episode?.subjectId == subjectID else { return }
            subject = hit.value
            needsRefresh = !hit.isFresh
            if !needsRefresh {
                if app.auth.isLoggedIn { await app.library.loadEpisodes(subjectID: subjectID) }
                return
            }
            guard await app.api.beginBackgroundRefresh(hit.cacheKey, minimumInterval: 120) else {
                if app.auth.isLoggedIn { await app.library.loadEpisodes(subjectID: subjectID) }
                return
            }
        }
        if app.auth.isLoggedIn {
            await app.library.loadEpisodes(subjectID: subjectID)
        }
        guard needsRefresh else { return }
        if let value = try? await app.api.subject(subjectID) {
            guard !Task.isCancelled, episode?.subjectId == subjectID else { return }
            subject = value
        }
    }

    private func loadComments(force: Bool = false) async {
        let id = episodeID
        if commentsEpisodeID != id {
            commentsEpisodeID = id
            comments = []
            commentsError = nil
            commentsLoading = true
        }
        if !force, let hit = await app.social.cachedEpisodeComments(episodeID: id) {
            guard !Task.isCancelled, id == episodeID else { return }
            comments = hit.value
            commentsError = nil
            commentsLoading = false
            if hit.isFresh { return }
            guard await app.api.beginBackgroundRefresh(hit.cacheKey, minimumInterval: 120) else { return }
        }
        if force { commentsError = nil }
        if comments.isEmpty { commentsLoading = true }
        defer { commentsLoading = false }
        do {
            let value = try await app.social.episodeComments(episodeID: id, force: force)
            guard !Task.isCancelled, id == episodeID else { return }
            comments = value
            commentsError = nil
        } catch {
            guard !Task.isCancelled else { return }
            commentsError = error.localizedDescription
        }
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let api = error as? APIError, case .cancelled = api { return true }
        return (error as? URLError)?.code == .cancelled
    }
}
