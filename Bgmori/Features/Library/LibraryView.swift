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
    @State private var removalTarget: UserSubjectCollection?
    @State private var showRemoval = false

    var body: some View {
        Group {
            if isFilterPreview {
                VStack(spacing: 0) {
                    filterControls
                    Spacer()
                }
            } else if isGridPreview {
                content
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
        #if os(macOS)
        .toolbar {
            if !app.isGuest || isFilterPreview || isGridPreview {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 16) {
                        LibraryTypePicker(selection: $subjectType)
                        statusMenu
                    }
                    .fixedSize()
                }
                .sharedBackgroundVisibility(.visible)
            }
        }
        #endif
        .onAppear { if isGridPreview { isGrid = true } }
        .background(Color.bgmBackground)
        .bgmLargeNavigationTitle("收藏")
        .modifier(CollectionRemovalFlow(
            subjectID: removalTarget?.subjectId ?? 0,
            title: removalTarget?.title ?? "",
            isPresented: $showRemoval
        ))
        .task {
            if !isFilterPreview && !isGridPreview { await app.library.loadIfNeeded() }
        }
    }

    private var isGridPreview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["BGMORI_PREVIEW_LIBRARY_GRID"] == "1"
        #else
        false
        #endif
    }

    private var isFilterPreview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["BGMORI_PREVIEW_LIBRARY_FILTERS"] == "1"
        #else
        false
        #endif
    }

    private var content: some View {
        let items = filtered
        return VStack(spacing: 0) {
            filterControls
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if let error = app.library.lastError {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(error, systemImage: "exclamationmark.circle")
                                .font(.footnote)
                            Button("重试同步") {
                                Task {
                                    if let username = app.auth.username {
                                        await app.library.loadAll(username: username, force: true)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    if items.isEmpty {
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
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 20, alignment: .top)], alignment: .leading, spacing: 20) {
                            ForEach(items) { item in
                                NavigationLink(value: Route.subject(item.subjectId)) {
                                    collectionCard(item)
                                }
                                .buttonStyle(.plain)
                                .contextMenu { contextMenu(for: item) }
                                .overlay(alignment: .topTrailing) {
                                    actionsMenu(for: item, compact: true)
                                        .background(Color.bgmSurface.opacity(0.94), in: Circle())
                                        .padding(5)
                                }
                                .accessibilityIdentifier("library-grid-\(item.subjectId)")
                            }
                        }
                        .padding(.horizontal, 20)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(items) { item in
                                HStack(alignment: .top, spacing: 8) {
                                    NavigationLink(value: Route.subject(item.subjectId)) {
                                        CollectionReviewRow(item: item)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("library-row-\(item.subjectId)")
                                    .contextMenu { contextMenu(for: item) }
                                    actionsMenu(for: item)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                                Divider().padding(.horizontal, 20)
                            }
                        }
                    }
                    Color.clear.frame(height: 20)
                }
                .padding(.top, 8)
            }
            .clipped()
            .accessibilityIdentifier("library-content")
            .refreshable {
                if let username = app.auth.username {
                    await app.library.loadAll(username: username, force: true)
                }
            }
        }
        .scrollIndicators(.hidden)
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
        VStack(alignment: .leading, spacing: 12) {
            InlineSearchField(text: $searchText, prompt: "在收藏中搜索")
                #if os(macOS)
                .frame(maxWidth: 420)
                #endif
                .accessibilityIdentifier("library-search-field")
            #if os(macOS)
            header
            #else
            LibraryTypePicker(selection: $subjectType)
            HStack(spacing: 12) {
                header
                Spacer(minLength: 0)
                statusMenu
            }
            #endif
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        Text("\(typedCollections.count) 部作品 · \(typedCollections.filter { $0.type == CollectionType.doing.rawValue }.count) 部在看")
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("library-summary")
    }

    private var statusMenu: some View {
        Menu {
            Picker("收藏状态", selection: $filter) {
                ForEach(LibraryFilter.allCases) { item in
                    Text(item.title)
                        .tag(item)
                        .accessibilityIdentifier("library-status-\(item.rawValue)")
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 5) {
                Text(filter == .all ? "全部状态" : filter.title)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(.caption)
            .foregroundStyle(filter == .all ? Color.secondary : Color.primary)
            #if os(macOS)
            .frame(minHeight: 28)
            #else
            .frame(minHeight: 44)
            #endif
            .contentShape(Rectangle())
        }
        #if os(macOS)
        .menuStyle(.button)
        .buttonStyle(.plain)
        #else
        .menuStyle(.borderlessButton)
        #endif
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("收藏状态")
        .accessibilityValue(filter == .all ? "全部状态" : filter.title)
        .accessibilityIdentifier("library-status-menu")
    }

    private func collectionCard(_ item: UserSubjectCollection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverCard(title: item.title, coverURL: item.coverURL, tint: .subjectTint(item.subjectType), width: nil, showsMetadata: false)
            HStack(spacing: 4) {
                Text(item.collectionType.title).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if item.rate > 0 {
                    Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(Color.brandPink)
                    Text("\(item.rate)").foregroundStyle(Color.brandPink).monospacedDigit()
                }
                if item.collectionType == .doing, !item.progressText.isEmpty {
                    Text(item.progressText).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .font(.caption)
            Text(item.reviewText ?? " ")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1, reservesSpace: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(item.reviewText == nil)
                #if os(macOS)
                .help(item.reviewText ?? "")
                #endif
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
        Button(
            item.subjectType == SubjectType.anime.rawValue && item.collectionType == .doing
                ? "取消追番…"
                : "移除收藏…",
            systemImage: "trash",
            role: .destructive
        ) {
            removalTarget = item
            showRemoval = true
        }
    }

    private func actionsMenu(for item: UserSubjectCollection, compact: Bool = false) -> some View {
        Menu {
            contextMenu(for: item)
        } label: {
            Image(systemName: "ellipsis")
                .font(compact ? .caption.weight(.semibold) : .body.weight(.medium))
                .frame(width: compact ? 30 : 44, height: compact ? 30 : 44)
                .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("\(item.title)的收藏操作")
        .accessibilityIdentifier("library-actions-\(item.subjectId)")
        .disabled(isGridPreview)
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
        #if DEBUG
        if isGridPreview {
            return DebugCollectionFixtures.collections.filter { subjectType == nil || $0.subjectType == subjectType }
        }
        #endif
        return app.library.collections.values.filter { subjectType == nil || $0.subjectType == subjectType }
    }
}
