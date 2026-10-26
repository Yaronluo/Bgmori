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
    private(set) var hasMore = false
    private(set) var errorText: String?
    private(set) var pageErrorText: String?

    private let api: APIClient
    private let pageSize = 24
    private(set) var nextOffset = 0
    private var currentQuery: CategoryQuery?
    private var requestID = UUID()
    private var catalogs: [SubjectType: [CategoryFilterGroup]] = [:]
    private var catalogErrors: [SubjectType: String] = [:]
    private var filterLoads: [SubjectType: UUID] = [:]
    private var filterTasks: [SubjectType: Task<[CategoryFilterGroup], Error>] = [:]

    init(api: APIClient) {
        self.api = api
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
        guard force || query != currentQuery || subjects.isEmpty else { return }
        let id = UUID()
        requestID = id
        currentQuery = query
        subjects = []
        nextOffset = 0
        hasMore = false
        errorText = nil
        pageErrorText = nil
        isLoading = true
        isLoadingMore = false
        defer { if requestID == id { isLoading = false } }

        do {
            let page = try await api.categorySubjects(query: query, limit: pageSize, force: force)
            guard requestID == id, !Task.isCancelled else { return }
            append(page, query: query)
        } catch {
            guard requestID == id, !Task.isCancelled else { return }
            errorText = error.localizedDescription
        }
    }

    func loadMore(_ query: CategoryQuery) async {
        guard currentQuery == query, hasMore, !isLoading, !isLoadingMore else { return }
        let id = requestID
        isLoadingMore = true
        pageErrorText = nil
        defer { if requestID == id { isLoadingMore = false } }
        do {
            let page = try await api.categorySubjects(query: query, limit: pageSize, offset: nextOffset)
            guard requestID == id, !Task.isCancelled else { return }
            append(page, query: query)
        } catch {
            guard requestID == id, !Task.isCancelled else { return }
            pageErrorText = error.localizedDescription
        }
    }

    private func append(_ page: Paged<Subject>, query: CategoryQuery) {
        var ids = Set(subjects.map(\.id))
        subjects.append(contentsOf: page.data.filter {
            $0.type == query.type.rawValue && (query.includeNSFW || !$0.nsfw)
            && (query.platform == nil || $0.platform == query.platform) && ids.insert($0.id).inserted
        })
        // Advance by the server page, including entries removed by local content filtering.
        nextOffset = page.offset + page.data.count
        hasMore = !page.data.isEmpty && nextOffset < page.total
    }
}
