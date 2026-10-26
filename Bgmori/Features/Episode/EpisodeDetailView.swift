import SwiftUI

struct EpisodeDetailView: View {
    @Environment(AppModel.self) private var app
    let episodeID: Int

    @State private var episode: Episode?
    @State private var subject: Subject?
    @State private var comments: [SocialComment] = []
    @State private var isLoading = true
    @State private var errorText: String?

    var body: some View {
        Group {
            if let episode {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
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
                            if comments.isEmpty {
                                Text("暂无吐槽")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            } else {
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
        .bgmWebFallback(URL(string: "https://bgm.tv/ep/\(episodeID)")!)
        .task(id: episodeID) { await load() }
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

    private func load() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            let episode = try await app.api.episode(episodeID)
            self.episode = episode
            if let subjectID = episode.subjectId {
                subject = try? await app.api.subject(subjectID)
                if app.auth.isLoggedIn {
                    await app.library.loadEpisodes(subjectID: subjectID)
                }
            }
            comments = (try? await app.social.episodeComments(episodeID: episodeID)) ?? []
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
