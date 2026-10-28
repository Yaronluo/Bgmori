import SwiftUI

struct TagResultsView: View {
    @Environment(AppModel.self) private var app
    let tag: String
    @State private var store = TagResultsStore()
    @State private var columnCount = 3
    @State private var isNearBottom = false

    private let cardWidth: CGFloat = 104
    private var query: TagResultsQuery { TagResultsQuery(tag: tag, includeNSFW: app.settings.showNSFW) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                header
                if store.isLoading && store.subjects.isEmpty {
                    ProgressView("加载标签…")
                        .frame(maxWidth: .infinity).padding(.vertical, 72)
                } else if let error = store.errorText, store.subjects.isEmpty {
                    EmptyStateView(icon: "wifi.exclamationmark", title: "标签加载失败", message: error, actionTitle: "重试") {
                        Task { await store.load(query, api: app.api, force: true) }
                    }
                } else if store.subjects.isEmpty && !store.hasMore {
                    EmptyStateView(icon: "tag.slash", title: "没有找到作品", message: "这个标签下暂时没有公开作品。")
                } else {
                    if store.errorText != nil {
                        RefreshFailureNotice(message: "刷新失败，请重试") {
                            Task { await store.load(query, api: app.api, force: true) }
                        }
                    }
                    grid
                    if store.hasMore {
                        PaginationFooter(offset: store.nextOffset, isLoading: store.isLoadingMore, error: store.pageErrorText,
                                         retry: { await store.loadMore(query, api: app.api, force: true) }) {
                            await store.loadMore(query, api: app.api)
                        }
                        .id(query.tag + String(query.includeNSFW))
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 28)
            .bgmDesktopContent(maxWidth: 1000)
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentSize.height - geometry.visibleRect.maxY < geometry.containerSize.height
        } action: { _, nearBottom in isNearBottom = nearBottom }
        .scrollIndicators(.hidden)
        .background(Color.bgmCanvas)
        .navigationTitle("标签")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: query) { await store.load(query, api: app.api) }
        .onChange(of: prefetchRequest, initial: true) { _, request in
            guard request.isReady else { return }
            Task { await store.loadMore(request.query, api: app.api) }
        }
        .refreshable { await store.load(query, api: app.api, force: true) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(tag).font(.system(size: 26, weight: .bold)).lineLimit(2).textSelection(.enabled)
        }
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: cardWidth), spacing: 16, alignment: .top)], alignment: .leading, spacing: 22) {
            ForEach(store.subjectsForDisplay(columns: columnCount)) { subject in
                NavigationLink(value: Route.subject(subject.id)) {
                    SubjectCard(subject: subject, width: nil)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tag-subject-\(subject.id)")
            }
        }
        .onGeometryChange(for: Int.self) { geometry in
            max(1, Int((geometry.size.width + 16) / (cardWidth + 16)))
        } action: { columnCount = $0 }
        .accessibilityIdentifier("tag-results")
    }

    private struct PrefetchRequest: Equatable {
        let query: TagResultsQuery
        let offset: Int
        let isReady: Bool
    }

    private var prefetchRequest: PrefetchRequest {
        PrefetchRequest(query: query, offset: store.nextOffset,
                        isReady: isNearBottom && store.hasMore && !store.isLoadingMore && !store.isLoading && store.pageErrorText == nil)
    }
}
