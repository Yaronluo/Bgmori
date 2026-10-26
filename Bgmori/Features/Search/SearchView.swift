import SwiftUI

enum SearchScope: String, CaseIterable, Identifiable {
    case subject
    case character
    case person

    var id: String { rawValue }

    var title: String {
        switch self {
        case .subject: "条目"
        case .character: "角色"
        case .person: "人物"
        }
    }
}

enum SearchItem: Identifiable {
    case subject(Subject)
    case character(Character)
    case person(Person)

    var id: String {
        switch self {
        case .subject(let value): "s-\(value.id)"
        case .character(let value): "c-\(value.id)"
        case .person(let value): "p-\(value.id)"
        }
    }
}

struct SearchView: View {
    @Environment(AppModel.self) private var app
    @State private var query = ""
    @State private var scope: SearchScope = .subject
    @State private var store = SearchStore()
    @State private var showFilters = false
    @State private var typeFilter: SubjectType?
    @State private var yearFilter: Int?
    @State private var sort = "match"
    @State private var recent: [String] = UserDefaults.standard.stringArray(forKey: "recentSearches") ?? []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                if query.trimmed.isEmpty {
                    landing
                } else {
                    resultsContent
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 28)
            .bgmDesktopContent(maxWidth: 820)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            searchControls
                .bgmFloatingControlMargins(maxWidth: 820)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            if query.isEmpty, !app.router.searchQuery.isEmpty {
                query = app.router.searchQuery
            }
        }
        .onChange(of: app.router.searchQuery) { _, newValue in
            if !newValue.isEmpty, newValue != query { query = newValue }
        }
        .task(id: request) { await store.load(request, api: app.api) }
        .task(id: "\(query.trimmed.isEmpty)-\(app.settings.showNSFW)") {
            guard query.trimmed.isEmpty else { return }
            await store.loadTrending(api: app.api, includeNSFW: app.settings.showNSFW)
        }
        .background(Color.bgmCanvas)
        .bgmNavigationTitle("搜索")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if scope == .subject {
                    Button("筛选", systemImage: "slider.horizontal.3") { showFilters = true }
                }
            }
        }
        .sheet(isPresented: $showFilters) {
            SearchFilterView(type: $typeFilter, year: $yearFilter, sort: $sort)
                #if os(iOS)
                .presentationDetents([.medium])
                #endif
        }
    }

    private var landing: some View {
        SearchLandingView(
            recentSearches: recent,
            recentSubjects: app.recentSubjects.subjects,
            includeNSFW: app.settings.showNSFW,
            trending: store.trending,
            isLoadingTrending: store.isLoadingTrending,
            trendingError: store.trendingErrorText,
            onSearch: { term in
                scope = .subject
                query = term
                remember()
            },
            onClearRecentSearches: {
                recent.removeAll()
                UserDefaults.standard.set(recent, forKey: "recentSearches")
            },
            onClearRecentSubjects: {
                app.recentSubjects.clear()
            },
            onBrowseCategory: { type in
                browse(type)
            },
            onReloadTrending: {
                Task {
                    await store.loadTrending(api: app.api, includeNSFW: app.settings.showNSFW, force: true)
                }
            }
        )
    }

    @ViewBuilder
    private var resultsContent: some View {
        if store.isSearching {
            ProgressView("正在搜索…")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
        } else if let errorText = store.errorText {
            EmptyStateView(icon: "wifi.exclamationmark", title: "搜索失败", message: errorText, actionTitle: "重试") {
                Task { await store.load(request, api: app.api) }
            }
        } else if store.results.isEmpty {
            EmptyStateView(
                icon: "magnifyingglass",
                title: "没有找到相关结果",
                message: "没有找到“\(query.trimmed)”。试试更短的关键词，或换个类型与年份。",
                actionTitle: scope == .subject ? "浏览分类" : nil
            ) {
                browse(typeFilter ?? .anime)
            }
        } else {
            resultsHeader
            resultGrid
            if store.hasMore {
                PaginationFooter(offset: store.nextOffset, isLoading: store.isLoadingMore, error: store.pageError) {
                    await store.loadMore(request, api: app.api)
                }
                .id(request)
            }
        }
    }

    private var resultsHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("搜索结果")
                .font(.title3.weight(.semibold))
            if store.total > 0 {
                Text("约 \(store.total.formatted()) 条")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
    }

    private var request: SearchRequest {
        SearchRequest(keyword: query.trimmed, scope: scope, type: typeFilter, year: yearFilter, sort: sort, includeNSFW: app.settings.showNSFW)
    }

    private var searchControls: some View {
        #if os(macOS)
        HStack(spacing: 16) {
            searchField.frame(maxWidth: 460)
            scopePicker.fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        #else
        VStack(alignment: .leading, spacing: 6) {
            searchField
            scopePicker
        }
        #endif
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(scope == .subject ? "搜索作品" : scope == .character ? "搜索角色" : "搜索人物", text: $query)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .onSubmit { remember() }
                .accessibilityIdentifier("search-field")
            if !query.isEmpty {
                Button("清除", systemImage: "xmark.circle.fill") { query = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.body)
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .bgmFloatingGlass(cornerRadius: 22, shadowRadius: 6)
    }

    private var scopePicker: some View {
        TextTabs(values: SearchScope.allCases, selection: $scope, title: { $0.title })
    }

    private var resultGrid: some View {
        Group {
            switch scope {
            case .subject:
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16, alignment: .top)], alignment: .leading, spacing: 20) {
                    ForEach(store.results) { item in
                        if case .subject(let subject) = item {
                            NavigationLink(value: Route.subject(subject.id)) {
                                SubjectCard(subject: subject, width: nil)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)
            case .character, .person:
                LazyVStack(spacing: 0) {
                    ForEach(store.results) { item in
                        switch item {
                        case .character(let character):
                            NavigationLink(value: Route.character(character.id)) {
                                personRow(title: character.name, subtitle: character.actors.first?.name, image: character.coverURL, tint: .brandPink)
                            }
                            .buttonStyle(.plain)
                        case .person(let person):
                            NavigationLink(value: Route.person(person.id)) {
                                personRow(title: person.name, subtitle: person.career.first, image: person.coverURL, tint: .purple)
                            }
                            .buttonStyle(.plain)
                        case .subject:
                            EmptyView()
                        }
                    }
                }
            }
        }
    }

    private func personRow(title: String, subtitle: String?, image: URL?, tint: Color) -> some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: image, maxPixel: 220, contentMode: .fit, placeholderTint: tint)
                .frame(width: 52, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func browse(_ type: SubjectType) {
        app.categories.selectType(type)
        app.categories.year = nil
        app.categories.tag = nil
        app.categories.selections = [:]
        app.categories.sort = .heat
        #if os(macOS)
        app.router.selectedSection = .categories
        app.router.macPath.removeAll()
        #else
        // Search can be pushed on top of the category stack; return to its root.
        app.router.categoriesPath.removeAll()
        app.router.selectedSection = .categories
        #endif
    }

    private func remember() {
        let term = query.trimmed
        guard !term.isEmpty else { return }
        recent.removeAll { $0 == term }
        recent.insert(term, at: 0)
        if recent.count > 10 { recent = Array(recent.prefix(10)) }
        UserDefaults.standard.set(recent, forKey: "recentSearches")
    }
}

struct SearchRequest: Hashable {
    let keyword: String
    let scope: SearchScope
    let type: SubjectType?
    let year: Int?
    let sort: String
    let includeNSFW: Bool
}

@MainActor
@Observable
final class SearchStore {
    private(set) var results: [SearchItem] = []
    private(set) var isSearching = false
    private(set) var isLoadingMore = false
    private(set) var hasMore = false
    private(set) var errorText: String?
    private(set) var pageError: String?
    private(set) var total = 0
    private(set) var trending: [Subject] = []
    private(set) var isLoadingTrending = false
    private(set) var trendingErrorText: String?
    private var loadedTrendingNSFW: Bool?
    private var currentRequest: SearchRequest?
    private var generation = UUID()
    private(set) var nextOffset = 0

    func load(_ request: SearchRequest, api: APIClient) async {
        let id = UUID()
        generation = id
        currentRequest = request
        results = []
        nextOffset = 0
        total = 0
        hasMore = false
        pageError = nil
        errorText = nil
        isLoadingMore = false
        isSearching = !request.keyword.isEmpty
        guard !request.keyword.isEmpty else { return }
        defer { if generation == id { isSearching = false } }
        do {
            try await Task.sleep(for: .milliseconds(300))
            let page = try await fetch(request, offset: 0, api: api)
            guard generation == id, !Task.isCancelled else { return }
            append(page)
        } catch {
            guard generation == id, !Task.isCancelled else { return }
            errorText = error.localizedDescription
        }
    }

    func loadTrending(api: APIClient, includeNSFW: Bool, force: Bool = false) async {
        if !force, loadedTrendingNSFW == includeNSFW, !trending.isEmpty { return }
        guard !isLoadingTrending else { return }
        isLoadingTrending = true
        trendingErrorText = nil
        defer { isLoadingTrending = false }
        do {
            let page = try await api.categorySubjects(
                query: CategoryQuery(type: .anime, sort: .heat, includeNSFW: includeNSFW),
                limit: 12
            )
            guard !Task.isCancelled else { return }
            trending = page.data.filter { includeNSFW || !$0.nsfw }
            loadedTrendingNSFW = includeNSFW
        } catch {
            guard !Task.isCancelled else { return }
            trendingErrorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func loadMore(_ request: SearchRequest, api: APIClient) async {
        guard currentRequest == request, hasMore, !isSearching, !isLoadingMore else { return }
        let id = generation
        isLoadingMore = true
        pageError = nil
        defer { if generation == id { isLoadingMore = false } }
        do {
            let page = try await fetch(request, offset: nextOffset, api: api)
            guard generation == id, !Task.isCancelled else { return }
            append(page)
        } catch {
            guard generation == id, !Task.isCancelled else { return }
            pageError = error.localizedDescription
        }
    }

    private func append(_ page: (items: [SearchItem], nextOffset: Int, total: Int)) {
        var ids = Set(results.map(\.id))
        results.append(contentsOf: page.items.filter { ids.insert($0.id).inserted })
        total = page.total
        hasMore = page.nextOffset > nextOffset && page.nextOffset < page.total
        nextOffset = page.nextOffset
    }

    private func fetch(_ request: SearchRequest, offset: Int, api: APIClient) async throws -> (items: [SearchItem], nextOffset: Int, total: Int) {
        switch request.scope {
        case .subject:
            var filter = SubjectSearchFilter()
            filter.type = request.type.map { [$0.rawValue] }
            filter.nsfw = request.includeNSFW ? nil : false
            if let year = request.year {
                filter.airDate = [">=\(year)-01-01", "<\(year + 1)-01-01"]
            }
            let page = try await api.searchSubjects(keyword: request.keyword, sort: request.sort, filter: filter, offset: offset)
            let subjects = page.data.filter { request.includeNSFW || !$0.nsfw }
            return (subjects.map(SearchItem.subject), page.offset + page.data.count, page.total)
        case .character:
            let page = try await api.searchCharacters(keyword: request.keyword, offset: offset)
            return (page.data.map(SearchItem.character), page.offset + page.data.count, page.total)
        case .person:
            let page = try await api.searchPersons(keyword: request.keyword, offset: offset)
            return (page.data.map(SearchItem.person), page.offset + page.data.count, page.total)
        }
    }
}

struct SearchFilterView: View {
    @Binding var type: SubjectType?
    @Binding var year: Int?
    @Binding var sort: String
    var body: some View {
        FilterSheet("搜索筛选", canReset: type != nil || year != nil || sort != "match", reset: {
            type = nil
            year = nil
            sort = "match"
        }) {
            VStack(spacing: 0) {
                field("类型") {
                    Picker("类型", selection: $type) {
                        Text("全部类型").tag(SubjectType?.none)
                        ForEach(SubjectType.browsingTypes) { value in
                            Text(value.title).tag(Optional(value))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("search-filter-type")
                }
                Divider()
                field("年份") {
                    YearPickerButton(selection: $year, earliestYear: 1990) {
                        HStack(spacing: 8) {
                            Text(year.map(String.init) ?? "全部年份")
                            Image(systemName: "chevron.down").font(.caption)
                        }
                        .padding(.horizontal, 10)
                        .frame(minHeight: 32)
                    }
                }
                Divider()
                field("排序") {
                    Picker("排序", selection: $sort) {
                        Text("匹配度").tag("match")
                        Text("热度").tag("heat")
                        Text("排名").tag("rank")
                        Text("评分").tag("score")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("search-filter-sort")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        #if os(macOS)
        .frame(width: 420, height: 300)
        #else
        .presentationDetents([.height(360), .large])
        #endif
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            Spacer(minLength: 12)
            content().font(.subheadline).tint(.primary)
        }
        .frame(minHeight: 48)
    }
}
