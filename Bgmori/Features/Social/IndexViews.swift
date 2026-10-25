import SwiftUI

struct IndexDetailView: View {
    @Environment(AppModel.self) private var app
    let indexID: Int
    @State private var index: IndexDetail?
    @State private var subjects: [IndexSubject] = []
    @State private var isLoading = true
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if let index {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(index.title)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        if let desc = index.desc, !desc.isEmpty {
                            Text(desc)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                    if subjects.isEmpty {
                        Text("这个目录还没有条目。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12, alignment: .top)], alignment: .leading, spacing: 16) {
                            ForEach(subjects) { item in
                                NavigationLink(value: Route.subject(item.id)) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        CachedAsyncImage(url: item.coverURL, maxPixel: 260, placeholderTint: .subjectTint(item.type))
                                            .frame(height: 140)
                                            .frame(maxWidth: .infinity)
                                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                        Text(item.displayTitle)
                                            .font(.system(size: 11, weight: .medium))
                                            .lineLimit(2)
                                        if let comment = item.comment, !comment.isEmpty {
                                            Text(comment)
                                                .font(.system(size: 9))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    Link("在 Bangumi 打开目录", destination: URL(string: "https://bgm.tv/index/\(indexID)")!)
                        .font(.system(size: 11))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                } else if isLoading {
                    ProgressView("加载目录…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                } else {
                    EmptyStateView(icon: "list.bullet.rectangle", title: "加载失败", message: errorText ?? "请稍后再试", actionTitle: "重试") {
                        Task { await load() }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .navigationTitle(index?.title ?? "目录")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            index = try await app.api.index(indexID)
            subjects = try await app.api.indexSubjects(indexID).data
            if subjects.isEmpty, let embedded = index?.subjects {
                subjects = embedded
            }
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct RevisionsView: View {
    @Environment(AppModel.self) private var app
    let subjectID: Int
    @State private var revisions: [Revision] = []
    @State private var isLoading = true
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if isLoading && revisions.isEmpty {
                    ProgressView("加载编辑历史…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                } else if revisions.isEmpty {
                    EmptyStateView(icon: "clock.arrow.circlepath", title: "暂无编辑历史", message: errorText ?? "这个条目还没有公开的修订记录。")
                } else {
                    ForEach(revisions) { revision in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                                .padding(.top, 3)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(revision.summary?.trimmed.isEmpty == false ? revision.summary! : "修订 #\(revision.id)")
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(3)
                                HStack(spacing: 5) {
                                    if let creator = revision.creator {
                                        Text(creator.displayName)
                                    }
                                    if let date = revision.createdAt {
                                        Text("· \(date)")
                                    }
                                }
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        Divider().padding(.leading, 50)
                    }
                }
                Link("在 Bangumi 查看条目", destination: URL(string: "https://bgm.tv/subject/\(subjectID)")!)
                    .font(.system(size: 11))
                    .padding(20)
            }
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("编辑历史")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            revisions = try await app.api.subjectRevisions(subjectID).data
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
