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
        case .score: "评分"
        case .title: "标题"
        }
    }
}

struct LibraryView: View {
    @Environment(AppModel.self) private var app
    @State private var filter: LibraryFilter = .all
    @State private var subjectType: Int?
    @State private var sort: LibrarySort = .updated
    @State private var isGrid = true
    @State private var searchText = ""

    var body: some View {
        Group {
            if app.isGuest {
                LoginPromptView(
                    title: "登录后查看收藏",
                    message: "Bgmori 会从 Bangumi 同步你的想看、在看、看过、搁置与抛弃列表。"
                ) {
                    app.showLogin = true
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
        }
        #if os(macOS)
        .navigationTitle("收藏")
        #else
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await app.library.loadIfNeeded()
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                header
                filterBar
                if filtered.isEmpty {
                    if app.library.isLoading {
                        ProgressView("同步收藏…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                    } else {
                        EmptyStateView(
                            icon: "books.vertical",
                            title: app.library.collections.isEmpty ? "还没有收藏" : "没有符合条件的条目",
                            message: app.library.collections.isEmpty ? "去首页或搜索里找一部喜欢的作品吧。" : "换个筛选条件试试。"
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
                                SubjectRow(
                                    title: item.title,
                                    subtitle: "\(item.collectionType.title) · \(item.progressText) · \(item.subject?.ratingText ?? "—")",
                                    coverURL: item.coverURL,
                                    trailing: item.progressText,
                                    tint: .subjectTint(item.subjectType)
                                )
                                .padding(.horizontal, 20)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                            .contextMenu { contextMenu(for: item) }
                            Divider().padding(.leading, 84)
                        }
                    }
                }
                Color.clear.frame(height: 20)
            }
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
        .searchable(text: $searchText, prompt: "在收藏中搜索")
        .refreshable {
            if let username = app.auth.username {
                await app.library.loadAll(username: username, force: true)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("类型", selection: $subjectType) {
                        Text("全部类型").tag(Int?.none)
                        ForEach(SubjectType.allCases) { type in
                            Text(type.title).tag(Optional(type.rawValue))
                        }
                    }
                    Picker("排序", selection: $sort) {
                        ForEach(LibrarySort.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("筛选")
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("我的收藏")
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text("\(app.library.collections.count) 部作品 · \(app.library.watching.count) 部在看")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LibraryFilter.allCases) { item in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { filter = item }
                    } label: {
                        Text(item.title)
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                            .foregroundStyle(filter == item ? Color.white : Color.primary)
                            .background(filter == item ? Color.brandPink : Color.bgmSecondary.opacity(0.65), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func collectionCard(_ item: UserSubjectCollection) -> some View {
        CoverCard(
            title: item.title,
            subtitle: "\(item.collectionType.title) · \(item.progressText) · \(item.subject?.ratingText ?? "—")",
            coverURL: item.coverURL,
            badge: item.progressText.isEmpty ? item.collectionType.title : item.progressText,
            progress: item.progressFraction,
            tint: .subjectTint(item.subjectType),
            width: 150
        )
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
        var items = Array(app.library.collections.values)
        if let type = filter.type { items = items.filter { $0.type == type.rawValue } }
        if let subjectType { items = items.filter { $0.subjectType == subjectType } }
        if !searchText.trimmed.isEmpty {
            let query = searchText.trimmed
            items = items.filter { $0.title.localizedCaseInsensitiveContains(query) }
        }
        switch sort {
        case .updated:
            items.sort { ($0.updatedAt ?? "") > ($1.updatedAt ?? "") }
        case .score:
            items.sort { ($0.subject?.score ?? 0) > ($1.subject?.score ?? 0) }
        case .title:
            items.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
        return items
    }
}
