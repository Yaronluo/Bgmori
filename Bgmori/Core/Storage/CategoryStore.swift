import Foundation
import Observation

@MainActor
@Observable
final class CategoryStore {
    var type: SubjectType = .anime
    var sort: CategorySort = .heat
    var year: Int?
    var tag: String?

    private(set) var subjects: [Subject] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var hasMore = false
    private(set) var errorText: String?
    private(set) var pageErrorText: String?

    private let api: APIClient
    private let pageSize = 24
    private var nextOffset = 0
    private var currentQuery: CategoryQuery?
    private var requestID = UUID()

    init(api: APIClient) {
        self.api = api
    }

    func query(includeNSFW: Bool) -> CategoryQuery {
        CategoryQuery(type: type, sort: sort, year: year, tag: tag, includeNSFW: includeNSFW)
    }

    func selectType(_ value: SubjectType) {
        guard type != value else { return }
        tag = nil
        type = value
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
            $0.type == query.type.rawValue && (query.includeNSFW || !$0.nsfw) && ids.insert($0.id).inserted
        })
        // Advance by the server page, including entries removed by local content filtering.
        nextOffset = page.offset + page.data.count
        hasMore = !page.data.isEmpty && nextOffset < page.total
    }
}
