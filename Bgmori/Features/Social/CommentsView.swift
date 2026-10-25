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
                    EmptyStateView(icon: "text.bubble", title: "还没有吐槽", message: errorText ?? "这里还很安静。")
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

                    if hasMore {
                        Button {
                            Task { await load(page: page + 1) }
                        } label: {
                            if isLoading { ProgressView() } else { Text("加载更多").font(.system(size: 13, weight: .semibold)) }
                        }
                        .buttonStyle(.glass)
                        .padding(.vertical, 18)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("吐槽")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await load(page: 1)
        }
    }

    private var visibleComments: [SocialComment] {
        comments.filter { !blocked.contains($0.username) }
    }

    private func load(page: Int) async {
        guard !isLoading else { return }
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            let fetched: [SocialComment]
            if let episodeID {
                fetched = try await app.social.episodeComments(episodeID: episodeID)
            } else {
                fetched = try await app.social.subjectComments(subjectID: subjectID, page: page)
            }
            if page == 1 { comments = fetched } else { comments.append(contentsOf: fetched) }
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
