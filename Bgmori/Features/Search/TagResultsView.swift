import SwiftUI

/// Browse every subject carrying a tag. Opened from the tag chips on a subject page.
struct TagResultsView: View {
    @Environment(AppModel.self) private var app
    let tag: String

    @State private var subjects: [Subject] = []
    @State private var total = 0
    @State private var isLoading = true
    @State private var errorText: String?

    private var cardWidth: CGFloat {
        #if os(iOS)
        104
        #else
        132
        #endif
    }

    private var pageMargin: CGFloat {
        #if os(iOS)
        18
        #else
        0
        #endif
    }

    private var webURL: URL {
        let encoded = tag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tag
        return URL(string: "https://bgm.tv/tag/\(encoded)")!
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if isLoading {
                    ProgressView("加载标签…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 72)
                } else if let errorText {
                    EmptyStateView(
                        icon: "wifi.exclamationmark",
                        title: "标签加载失败",
                        message: errorText,
                        actionTitle: "重试"
                    ) {
                        Task { await load() }
                    }
                } else if subjects.isEmpty {
                    EmptyStateView(
                        icon: "tag.slash",
                        title: "没有找到作品",
                        message: "这个标签下暂时没有公开作品。"
                    )
                } else {
                    grid
                }

                footer
            }
            .padding(.horizontal, pageMargin)
            .padding(.top, 10)
            .padding(.bottom, 28)
            .bgmDesktopContent(maxWidth: 1000)
        }
        .scrollIndicators(.hidden)
        .background(pageBackground)
        .navigationTitle(navigationTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: tag) { await load() }
    }

    private var navigationTitle: String {
        #if os(iOS)
        "标签"
        #else
        tag
        #endif
    }

    private var pageBackground: Color {
        #if os(iOS)
        .bgmBackground
        #else
        .bgmCanvas
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            #if os(iOS)
            Text(tag)
                .font(.system(size: 26, weight: .bold))
                .lineLimit(2)
                .textSelection(.enabled)
            #endif

            if total > 0 {
                Text("共 \(total.formatted()) 部作品")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var grid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: cardWidth), spacing: 16, alignment: .top)],
            alignment: .leading,
            spacing: 22
        ) {
            ForEach(subjects) { subject in
                NavigationLink(value: Route.subject(subject.id)) {
                    SubjectCard(subject: subject, width: cardWidth)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Link(destination: webURL) {
                Label("在 Bangumi 查看该标签", systemImage: "arrow.up.right.square")
            }
            Spacer()
            if total > subjects.count {
                Text("仅显示前 \(subjects.count) 部")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }

    private func load() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }

        do {
            var filter = SubjectSearchFilter()
            filter.tag = [tag]
            filter.nsfw = app.settings.showNSFW ? nil : false
            let page = try await app.api.searchSubjects(
                keyword: "",
                sort: "heat",
                filter: filter,
                limit: 60
            )
            subjects = page.data
            total = page.total
        } catch {
            subjects = []
            total = 0
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
