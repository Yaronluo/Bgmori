import Foundation
import Observation

struct TagResultsQuery: Equatable, Sendable {
    let tag: String
    let includeNSFW: Bool
}

@MainActor
@Observable
final class TagResultsStore {
    private(set) var subjects: [Subject] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var hasMore = false
    private(set) var nextOffset = 0
    private(set) var errorText: String?
    private(set) var pageErrorText: String?
    private var query: TagResultsQuery?
    private var requestID = UUID()

    func subjectsForDisplay(columns: Int) -> ArraySlice<Subject> {
        let count = hasMore ? subjects.count / max(1, columns) * max(1, columns) : subjects.count
        return subjects.prefix(count)
    }

    func load(_ query: TagResultsQuery, api: APIClient, force: Bool = false) async {
        let id = UUID()
        requestID = id
        if self.query != query {
            subjects = []
            nextOffset = 0
            hasMore = false
        }
        self.query = query
        isLoading = true
        isLoadingMore = false
        errorText = nil
        pageErrorText = nil
        defer { if requestID == id { isLoading = false } }
        do {
            let page = try await api.tagSubjects(tag: query.tag, includeNSFW: query.includeNSFW, force: force)
            guard requestID == id, !Task.isCancelled else { return }
            subjects = []
            append(page, query: query)
        } catch {
            guard requestID == id, !Task.isCancelled else { return }
            errorText = error.localizedDescription
        }
    }

    func loadMore(_ query: TagResultsQuery, api: APIClient, force: Bool = false) async {
        guard self.query == query, hasMore, !isLoading, !isLoadingMore else { return }
        let id = requestID
        isLoadingMore = true
        pageErrorText = nil
        defer { if requestID == id { isLoadingMore = false } }
        do {
            let page = try await api.tagSubjects(tag: query.tag, includeNSFW: query.includeNSFW, offset: nextOffset, force: force)
            guard requestID == id, !Task.isCancelled else { return }
            append(page, query: query)
        } catch {
            guard requestID == id, !Task.isCancelled else { return }
            pageErrorText = error.localizedDescription
        }
    }

    private func append(_ page: Paged<Subject>, query: TagResultsQuery) {
        var ids = Set(subjects.map(\.id))
        subjects.append(contentsOf: page.data.filter {
            (query.includeNSFW || !$0.nsfw) && ids.insert($0.id).inserted
        })
        nextOffset = page.nextOffset
        hasMore = nextOffset > page.offset && nextOffset < page.total
    }
}
