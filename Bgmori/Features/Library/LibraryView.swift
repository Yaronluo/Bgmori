import SwiftUI

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all
    case wish
    case doing
    case done
    case onHold
    case dropped

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .wish: "想看"
        case .doing: "在看"
        case .done: "看过"
        case .onHold: "搁置"
        case .dropped: "抛弃"
        }
    }

    var type: CollectionType? {
        switch self {
        case .all: nil
        case .wish: .wish
        case .doing: .doing
        case .done: .done
        case .onHold: .onHold
        case .dropped: .dropped
        }
    }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case updated
    case score
    case title

    var id: String { rawValue }

    var title: String {
        switch self {
        case .updated: "最近更新"
        case .score: "我的评分"
        case .title: "标题"
        }
    }
}

struct LibraryView: View {
    @Environment(AppModel.self) private var app
    @State private var filter: LibraryFilter = .all
    @State private var subjectType: Int?
    @State private var sort: LibrarySort = .updated
    @State private var isGrid = false
    @State private var searchText = ""

    var body: some View {
        Group {
            if isFilterPreview {
                VStack(spacing: 0) {
                    filterControls
                    Spacer()
                }
            } else if app.isGuest {
                LoginPromptView(
                    title: "登录后查看收藏",
                    message: ""
                ) {
                    app.showLogin = true
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
        }
        .background(Color.bgmBackground)
        .bgmLargeNavigationTitle("收藏")
        .task {
            if !isFilterPreview { await app.library.loadIfNeeded() }
        }
    }

    private var isFilterPreview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["BGMORI_PREVIEW_LIBRARY_FILTERS"] == "1"
        #else
        false
        #endif
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                header
                if filtered.isEmpty {
                    if app.library.isLoading {
                        ProgressView("同步收藏…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                    } else {
                        EmptyStateView(
                            icon: "books.vertical",
                            title: app.library.collections.isEmpty ? "还没有收藏" : "没有符合条件的条目",
                            message: ""
                        )
                    }
                } else if isGrid {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16, alignment: .top)], alignment: .leading, spacing: 20) {
                        ForEach(filtered) { item in
                            NavigationLink(value: Route.subject(item.subjectId)) {
                                collectionCard(item)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                contextMenu(for: item)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { item in
                            NavigationLink(value: Route.subject(item.subjectId)) {
                                CollectionReviewRow(item: item)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("library-row-\(item.subjectId)")
                            .contextMenu { contextMenu(for: item) }
                            Divider().padding(.horizontal, 20)
                        }
                    }
                }
                Color.clear.frame(height: 20)
            }
            .padding(.top, 8)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            filterControls
        }
        .scrollIndicators(.hidden)
        .bgmSearchable(text: $searchText, prompt: "在收藏中搜索")
        .refreshable {
            if let username = app.auth.username {
                await app.library.loadAll(username: username, force: true)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("排序", selection: $sort) {
                        ForEach(LibrarySort.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("排序")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation(.snappy) { isGrid.toggle() }
                } label: {
                    Image(systemName: isGrid ? "list.bullet" : "square.grid.2x2")
                }
                .accessibilityLabel(isGrid ? "列表视图" : "网格视图")
            }
        }
    }

    private var filterControls: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text("类型").font(.caption).foregroundStyle(.secondary).frame(width: 28, alignment: .leading)
                LibraryTypePicker(selection: $subjectType)
            }
            HStack(spacing: 10) {
                Text("状态").font(.caption).foregroundStyle(.secondary).frame(width: 28, alignment: .leading)
                filterBar
            }
        }
        .padding(10)
        .frame(maxWidth: 560, alignment: .leading)
        .bgmFloatingGlass(cornerRadius: 18, shadowRadius: 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bgmFloatingControlMargins()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(subjectType.map(SubjectType.title(for:)) ?? "全部收藏") · \(typedCollections.count) 部作品 · \(typedCollections.filter { $0.type == CollectionType.doing.rawValue }.count) 部在看")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("library-summary")
        }
        .padding(.horizontal, 20)
    }

    private var filterBar: some View {
        HStack(spacing: 2) {
            ForEach(LibraryFilter.allCases) { item in
                Button {
                    withAnimation(.snappy(duration: 0.2)) { filter = item }
                } label: {
                    Text(item.title)
                        .font(.caption.weight(filter == item ? .semibold : .regular))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .foregroundStyle(filter == item ? Color.primary : Color.secondary)
                        .background(filter == item ? Color.primary.opacity(0.05) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(filter == item ? .isSelected : [])
                .accessibilityIdentifier("library-status-\(item.rawValue)")
            }
        }
    }

    private func collectionCard(_ item: UserSubjectCollection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CoverCard(
                title: item.title,
                subtitle: item.collectionType.title,
                coverURL: item.coverURL,
                badge: item.collectionType == .doing && !item.progressText.isEmpty ? item.progressText : nil,
                progress: item.progressFraction,
                tint: .subjectTint(item.subjectType),
                width: nil
            )
            CollectionPersonalRating(rate: item.rate)
            if let review = item.reviewText {
                CollectionReviewText(text: review)
                    .lineLimit(4)
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for item: UserSubjectCollection) -> some View {
        ForEach(CollectionType.allCases) { type in
            Button {
                Task { await app.library.setType(subjectID: item.subjectId, type: type) }
            } label: {
                Label(type.title, systemImage: type.icon)
            }
            .disabled(item.type == type.rawValue)
        }
        Divider()
        Link("在 Bangumi 查看", destination: URL(string: "https://bgm.tv/subject/\(item.subjectId)")!)
    }

    private var filtered: [UserSubjectCollection] {
        var items = typedCollections
        if let type = filter.type { items = items.filter { $0.type == type.rawValue } }
        if !searchText.trimmed.isEmpty {
            let query = searchText.trimmed
            items = items.filter { $0.title.localizedCaseInsensitiveContains(query) }
        }
        switch sort {
        case .updated:
            items.sort { ($0.updatedAt ?? "") > ($1.updatedAt ?? "") }
        case .score:
            items.sort {
                if $0.rate != $1.rate { return $0.rate > $1.rate }
                return ($0.updatedAt ?? "") > ($1.updatedAt ?? "")
            }
        case .title:
            items.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
        return items
    }

    private var typedCollections: [UserSubjectCollection] {
        app.library.collections.values.filter { subjectType == nil || $0.subjectType == subjectType }
    }
}
