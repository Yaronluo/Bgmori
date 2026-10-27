import SwiftUI

struct CommentsView: View {
    @Environment(AppModel.self) private var app
    let subjectID: Int
    let episodeID: Int?
    @State private var comments: [SocialComment] = []
    @State private var page = 1
    @State private var isLoading = false
    @State private var hasMore = true
    @State private var errorText: String?
    @State private var blocked: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "blockedCommentUsers") ?? [])

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if isLoading && comments.isEmpty {
                    ProgressView("加载吐槽…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                } else if comments.isEmpty {
                    EmptyStateView(icon: "text.bubble", title: errorText == nil ? "还没有吐槽" : "吐槽加载失败", message: errorText ?? "", actionTitle: "重试") {
                        Task { await load(page: 1, force: true) }
                    }
                } else {
                    ForEach(visibleComments) { comment in
                        SocialCommentRow(comment: comment)
                            .padding(.horizontal, 20)
                            .contextMenu {
                                Button {
                                    blocked.insert(comment.username)
                                    saveBlocked()
                                } label: {
                                    Label("屏蔽 \(comment.name)", systemImage: "person.crop.circle.badge.xmark")
                                }
                                Link("在 Bangumi 查看", destination: URL(string: "https://bgm.tv/subject/\(subjectID)/comments")!)
                            }
                        Divider().padding(.leading, 62)
                    }

                }
                if !comments.isEmpty && (hasMore || errorText != nil) {
                    PaginationFooter(offset: page, isLoading: isLoading, error: errorText) {
                        await load(page: page + 1)
                    }

                }
            }
            .padding(.bottom, 24)
        }
        .refreshable { await load(page: 1, force: true) }
        .scrollIndicators(.hidden)
        .navigationTitle("吐槽")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .bgmWebFallback(URL(string: episodeID.map { "https://bgm.tv/ep/\($0)" } ?? "https://bgm.tv/subject/\(subjectID)/comments")!)
        .task {
            await load(page: 1)
        }
    }

    private var visibleComments: [SocialComment] {
        comments.filter { !blocked.contains($0.username) }
    }

    private func load(page: Int, force: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            let fetched: [SocialComment]
            if let episodeID {
                fetched = try await app.social.episodeComments(episodeID: episodeID, force: force)
            } else {
                fetched = try await app.social.subjectComments(subjectID: subjectID, page: page, force: force)
            }
            if page == 1 {
                comments = fetched
            } else {
                var ids = Set(comments.map(\.id))
                comments.append(contentsOf: fetched.filter { ids.insert($0.id).inserted })
            }
            self.page = page
            hasMore = episodeID == nil && fetched.count >= 20
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            hasMore = false
        }
    }

    private func saveBlocked() {
        UserDefaults.standard.set(Array(blocked), forKey: "blockedCommentUsers")
    }
}
