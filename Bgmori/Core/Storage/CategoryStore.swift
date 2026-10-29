import Foundation
import Observation

@MainActor
@Observable
final class CategoryStore {
    var type: SubjectType = .anime
    var sort: CategorySort = .heat
    var year: Int?
    var tag: String?
    var selections: [String: CategoryFilterOption] = [:]

    var filterGroups: [CategoryFilterGroup] { catalogs[type] ?? [] }
    var isLoadingFilters: Bool { filterLoads[type] != nil }
    var filtersErrorText: String? { catalogErrors[type] }
    var selectedFilterCount: Int { selections.count + (tag == nil ? 0 : 1) }

    private(set) var subjects: [Subject] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var isRefreshing = false
    private(set) var hasMore = false
    private(set) var errorText: String?
    private(set) var refreshErrorText: String?
    private(set) var pageErrorText: String?
    private(set) var nextOffset = 0
    private(set) var fallbackSort: CategorySort?

    var sortNotice: String? {
        guard let fallbackSort else { return nil }
        return "官网\(sort.title)排序暂不可用，已按\(fallbackSort.title)排序显示，筛选条件保持不变。"
    }

    private let api: APIClient
    private let pageSize = 24
    private var currentQuery: CategoryQuery?
    private var requestID = UUID()
    private var contentKey: String?
    private var memoryPages: [String: CachedPage] = [:]
    private var catalogs: [SubjectType: [CategoryFilterGroup]] = [:]
    private var catalogErrors: [SubjectType: String] = [:]
    private var filterLoads: [SubjectType: UUID] = [:]
    private var filterTasks: [SubjectType: Task<[CategoryFilterGroup], Error>] = [:]

    private struct CachedPage: Codable, Sendable {
        let subjects: [Subject]
        let nextOffset: Int
        let hasMore: Bool
        let savedAt: Date
        let fallbackSort: CategorySort?
    }

    init(api: APIClient) {
        self.api = api
    }

    func subjectsForDisplay(columns: Int) -> ArraySlice<Subject> {
        let columns = max(1, columns)
        // Retain the unfinished row in subjects so the next page can complete
        // it in source order. Only a terminal page may expose a partial row.
        let count = hasMore ? subjects.count / columns * columns : subjects.count
        return subjects.prefix(count)
    }

    func query(includeNSFW: Bool) -> CategoryQuery {
        CategoryQuery(type: type, sort: sort, year: year, tag: tag, includeNSFW: includeNSFW,
                      metaTags: Array(Set(selections.values.flatMap(\.metaTags))).sorted(),
                      platform: selections["分类"]?.platform)
    }

    func selectType(_ value: SubjectType) {
        guard type != value else { return }
        tag = nil
        selections = [:]
        type = value
    }

    func loadFilters(for type: SubjectType, force: Bool = false) async {
        guard force || catalogs[type] == nil else { return }
        if !force, catalogs[type] == nil,
           let hit = await api.cachedCategoryFilters(type: type) {
            catalogs[type] = hit.value
            catalogErrors[type] = nil
            if hit.isFresh { return }
            guard await api.beginBackgroundRefresh(hit.cacheKey, minimumInterval: 300) else { return }
        }
        if !force, let task = filterTasks[type] {
            _ = try? await task.value
            return
        }
        let id = UUID()
        filterLoads[type] = id
        catalogErrors[type] = nil
        // Catalogs belong to their content type and remain useful after the panel closes.
        let task = Task { [api] in try await api.categoryFilters(type: type, force: force) }
        filterTasks[type] = task
        defer {
            if filterLoads[type] == id {
                filterLoads[type] = nil
                filterTasks[type] = nil
            }
        }
        do {
            let groups = try await task.value
            guard filterLoads[type] == id else { return }
            catalogs[type] = groups
        } catch {
            guard filterLoads[type] == id else { return }
            catalogErrors[type] = error.localizedDescription
        }
    }

    func load(_ query: CategoryQuery, force: Bool = false) async {
        if !force, query == currentQuery, !subjects.isEmpty { return }
        if query == currentQuery, isLoading || isRefreshing { return }

        let queryChanged = query != currentQuery
        let id = UUID()
        requestID = id
        isLoadingMore = false
        currentQuery = query
        defer {
            if requestID == id {
                isLoading = false
                isRefreshing = false
            }
        }
        if queryChanged {
            // Never render the previous query's list under the new controls.
            subjects = []
            nextOffset = 0
            hasMore = false
            fallbackSort = nil
            isLoading = true
        }
        pageErrorText = nil
        errorText = nil
        refreshErrorText = nil

        let source = await api.cacheScope()
        guard requestID == id else { return }
        let key = cacheKey(for: query, source: source)
        contentKey = key

        if !force {
            if let page = await cachedPage(for: key) {
                guard requestID == id, currentQuery == query else { return }
                subjects = page.subjects
                nextOffset = page.nextOffset
                hasMore = page.hasMore
                fallbackSort = page.fallbackSort
            } else {
                guard requestID == id, currentQuery == query else { return }
                subjects = []
                nextOffset = 0
                hasMore = false
            }
        }

        isLoading = subjects.isEmpty
        isRefreshing = !subjects.isEmpty

        do {
            let (page, resolvedSort) = try await initialPage(query, force: force)
            guard requestID == id, currentQuery == query, !Task.isCancelled else { return }
            replace(page, query: query)
            fallbackSort = resolvedSort
            errorText = nil
            refreshErrorText = nil
            await saveSnapshot(for: key, query: query)
        } catch {
            guard requestID == id, currentQuery == query, !Task.isCancelled else { return }
            if subjects.isEmpty {
                errorText = error.localizedDescription
            } else {
                refreshErrorText = error.localizedDescription
            }
        }
    }

    func loadMore(_ query: CategoryQuery, force: Bool = false) async {
        guard currentQuery == query, hasMore, !isLoading, !isLoadingMore, !isRefreshing else { return }
        let id = requestID
        isLoadingMore = true
        pageErrorText = nil
        defer { if requestID == id { isLoadingMore = false } }
        do {
            var sourceQuery = query
            sourceQuery.sort = fallbackSort ?? query.sort
            let page = try await api.categorySubjects(query: sourceQuery, limit: pageSize, offset: nextOffset, force: force)
            guard requestID == id, !Task.isCancelled else { return }
            append(page, query: query)
            if let key = contentKey {
                await saveSnapshot(for: key, query: query)
            }
        } catch {
            guard requestID == id, !Task.isCancelled else { return }
            pageErrorText = error.localizedDescription
        }
    }

    // MARK: - Cached result pages

    private func initialPage(_ query: CategoryQuery, force: Bool) async throws -> (Paged<Subject>, CategorySort?) {
        do {
            return (try await api.categorySubjects(query: query, limit: pageSize, force: force), nil)
        } catch let error as APIError {
            // Only restart at offset zero: website and search cursors refer to
            // different orders and must never be joined into the same list.
            guard query.sort == .heat || query.sort == .title else { throw error }
            switch error {
            case .verificationRequired, .forbidden, .unauthorized: break
            default: throw error
            }
            try Task.checkCancellation()
            var fallback = query
            fallback.sort = .collects
            return (try await api.categorySubjects(query: fallback, limit: pageSize, force: force), .collects)
        }
    }

    private func cacheKey(for query: CategoryQuery, source: String) -> String {
        "category-page-v2-\(source)-\(pageSize)-\(query.cacheKey)"
    }

    private func cachedPage(for key: String) async -> CachedPage? {
        if let page = memoryPages[key] { return page }
        guard let data = await api.cache.read(key, maxAge: CacheLifetime.publicCatalog),
              let page = try? JSONDecoder().decode(CachedPage.self, from: data) else { return nil }
        remember(page, for: key)
        return page
    }

    private func saveSnapshot(for key: String, query: CategoryQuery) async {
        let page = CachedPage(subjects: subjects, nextOffset: nextOffset, hasMore: hasMore, savedAt: Date(), fallbackSort: fallbackSort)
        remember(page, for: key)
        guard let data = try? JSONEncoder().encode(page) else { return }
        await api.cache.write(key, data: data)
    }

    private func remember(_ page: CachedPage, for key: String) {
        if memoryPages.count >= 24, memoryPages[key] == nil { memoryPages.removeAll() }
        memoryPages[key] = page
    }

    private func replace(_ page: Paged<Subject>, query: CategoryQuery) {
        var ids: Set<Int> = []
        subjects = page.data.filter { query.matches($0) && ids.insert($0.id).inserted }
        nextOffset = page.nextOffset
        hasMore = nextOffset > page.offset && nextOffset < page.total
    }

    private func append(_ page: Paged<Subject>, query: CategoryQuery) {
        var ids = Set(subjects.map(\.id))
        subjects.append(contentsOf: page.data.filter {
            query.matches($0) && ids.insert($0.id).inserted
        })
        // Advance by the server page, including entries removed by local content filtering.
        nextOffset = page.nextOffset
        hasMore = nextOffset > page.offset && nextOffset < page.total
    }
}
