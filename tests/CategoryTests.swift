import Foundation

private struct StubResponse: Sendable {
    let data: Data
    let status: Int
    let delay: TimeInterval
}

private final class TestServer: @unchecked Sendable {
    private let lock = NSLock()
    private var requests = 0
    private var fail = false
    private var failNextPage = false
    private var emptyResults = false
    private var offsets: [Int] = []
    private var blockBrowser = false
    private var browserRequests = 0

    var count: Int { lock.withLock { requests } }
    var requestedOffsets: [Int] { lock.withLock { offsets } }
    var browserCount: Int { lock.withLock { browserRequests } }

    func setFailure(_ value: Bool) { lock.withLock { fail = value } }
    func failOnePage() { lock.withLock { failNextPage = true } }
    func setEmptyResults(_ value: Bool) { lock.withLock { emptyResults = value } }
    func setBrowserBlocked(_ value: Bool) { lock.withLock { blockBrowser = value } }

    func response(for request: URLRequest) -> StubResponse {
        lock.withLock {
            requests += 1
            if request.url?.host == "bgm.tv", request.url?.query?.contains("page=") == true {
                browserRequests += 1
                if blockBrowser {
                    return StubResponse(data: Data("<html><title>Just a moment</title>cf-chl-test</html>".utf8), status: 403, delay: 0.01)
                }
                let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
                let page = Int(items.first { $0.name == "page" }!.value!)!
                if request.url?.path == "/book/browser" {
                    let html = "<div id='browserTools'></div><ul id='browserItemList'>"
                        + [901, 902].map { "<li id='item_\($0)'><a href='/subject/\($0)'>作品</a></li>" }.joined()
                        + "</ul>"
                    return StubResponse(data: Data(html.utf8), status: fail ? 503 : 200, delay: 0.01)
                }
                let ids = page == 1 ? Array(701...724) : [725, 726]
                let html = "<div id='browserTools'></div><ul id='browserItemList'>"
                    + ids.map { "<li id='item_\($0)'><a href='/subject/\($0)'>作品</a></li>" }.joined()
                    + "</ul>" + (page == 1 ? "<a href='?sort=title&amp;page=2'>2</a>" : "")
                return StubResponse(data: Data(html.utf8), status: fail ? 503 : 200, delay: 0.01)
            }
            if request.httpMethod == "GET", request.url?.path == "/v0/subjects" {
                let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
                precondition(items.first { $0.name == "sort" }!.value == "date")
                let offset = Int(items.first { $0.name == "offset" }!.value!)!
                let ids = offset == 0 ? [801, 802] : [803, 804]
                let rows: [[String: Any]] = ids.map { id in
                    ["id": id, "type": 2, "name": id == 803 ? "tag-match" : "tag-miss", "nsfw": false,
                     "date": id < 803 ? "2021-01-01" : "2020-01-01", "meta_tags": ["TV", "科幻"]]
                }
                let data = try! JSONSerialization.data(withJSONObject: ["data": rows, "total": 4, "offset": offset, "limit": 24])
                return StubResponse(data: data, status: 200, delay: 0.01)
            }
            if request.httpMethod == "GET", request.url?.path.hasPrefix("/v0/subjects/") == true {
                let id = Int(request.url!.lastPathComponent)!
                if id == 902 {
                    return StubResponse(data: Data("{}".utf8), status: 404, delay: 0.01)
                }
                let type = id == 901 ? 1 : 2
                let data = try! JSONSerialization.data(withJSONObject: ["id": id, "type": type, "nsfw": id == 702,
                    "date": "2020-01-01", "meta_tags": ["TV", "科幻"]] as [String: Any])
                return StubResponse(data: data, status: fail ? 503 : 200, delay: id == 701 ? 0.15 : 0.01)
            }
            if request.url?.host == "bgm.tv" {
                precondition(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix(APIClient.safariUserAgent) == true)
                return StubResponse(data: Data(CategoryTests.catalogFixture.utf8), status: fail ? 503 : 200, delay: 0.01)
            }
            precondition(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("Bgmori/") == true)
            let body: Data
            if let data = request.httpBody {
                body = data
            } else if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var data = Data()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let length = stream.read(&buffer, maxLength: buffer.count)
                    if length <= 0 { break }
                    data.append(buffer, count: length)
                }
                body = data
            } else { fatalError("Missing request body") }
            let payload = try! JSONSerialization.jsonObject(with: body) as! [String: Any]
            let filter = payload["filter"] as! [String: Any]
            if payload["keyword"] as? String != "" {
                precondition(filter["tag"] as? [String] == ["完整标签"])
                let rows: [[String: Any]] = payload["keyword"] as? String == "tag-match" ? [["id": 803, "type": 2]] : []
                let data = try! JSONSerialization.data(withJSONObject: ["data": rows, "total": rows.count, "offset": 0, "limit": 50])
                return StubResponse(data: data, status: 200, delay: 0.01)
            }
            precondition(filter["nsfw"] as? Bool == false)
            if filter["type"] == nil {
                let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
                let offset = Int(items.first { $0.name == "offset" }!.value!)!
                offsets.append(offset)
                let failed = fail || (offset > 0 && failNextPage)
                if offset > 0 { failNextPage = false }
                // The live service caps a requested 24 to 20, and can include duplicates/NSFW rows.
                let ids = offset == 0 ? Array(1...18) + [1, 19] : [18, 20, 21]
                let rows: [[String: Any]] = ids.map { ["id": $0, "type": 2, "nsfw": $0 == 19] }
                let data = try! JSONSerialization.data(withJSONObject: ["data": rows, "total": 23, "limit": 20, "offset": offset])
                return StubResponse(data: data, status: failed ? 503 : 200, delay: 0.01)
            }
            let type = (filter["type"] as! [Int])[0]
            precondition(["rank", "heat"].contains(payload["sort"] as! String), "Website sorts must not be sent to search")
            let tag = (filter["tag"] as! [String])[0]
            if tag.contains("metadata") {
                precondition(filter["meta_tags"] as? [String] == ["TV", "科幻"] || filter["meta_tags"] as? [String] == ["TV", "恋爱"])
            }
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            let offset = Int(query.first { $0.name == "offset" }!.value!)!
            offsets.append(offset)
            if tag.contains("filters") {
                precondition(filter["air_date"] as? [String] == [">=2020-01-01", "<2021-01-01"])
                precondition(filter["rank"] as? [String] == [">0"])
            }
            let failed = fail || (offset > 0 && failNextPage)
            if offset > 0 { failNextPage = false }
            if emptyResults {
                let data = try! JSONSerialization.data(withJSONObject: ["data": [], "total": 0, "limit": 24, "offset": offset])
                return StubResponse(data: data, status: 200, delay: 0.01)
            }
            let rows: [[String: Any]]
            if offset == 0 {
                rows = [
                    ["id": type * 100 + 1, "type": type, "nsfw": false],
                    ["id": type * 100 + 2, "type": type, "nsfw": true],
                    ["id": 999, "type": 6, "nsfw": false],
                    ["id": type * 100 + 1, "type": type, "nsfw": false]
                ]
            } else {
                precondition(offset == 4, "Pagination must advance by the unfiltered server page")
                rows = [
                    ["id": type * 100 + 1, "type": type, "nsfw": false],
                    ["id": type * 100 + 4, "type": type, "nsfw": false]
                ]
            }
            let datedRows = rows.map { $0.merging(["date": "2020-01-01", "meta_tags": ["TV", "科幻"]]) { _, new in new } }
            let data = try! JSONSerialization.data(withJSONObject: ["data": datedRows, "total": 6, "limit": 24, "offset": offset])
            return StubResponse(data: data, status: failed ? 503 : 200, delay: (tag.contains("race") || tag.contains("slow")) && type == 2 ? 0.6 : 0.01)
        }
    }
}

private final class CategoryProtocol: URLProtocol, @unchecked Sendable {
    static let server = TestServer()
    private let lock = NSLock()
    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool { ["api.bgm.tv", "bgm.tv"].contains(request.url?.host ?? "") }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = Self.server.response(for: request)
        DispatchQueue.global().asyncAfter(deadline: .now() + response.delay) { [self] in
            lock.withLock {
                guard !stopped else { return }
                let http = HTTPURLResponse(url: request.url!, statusCode: response.status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
                client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: response.data)
                client?.urlProtocolDidFinishLoading(self)
            }
        }
    }

    override func stopLoading() { lock.withLock { stopped = true } }
}

@main
struct CategoryTests {
    @MainActor
    static func main() async throws {
        try checkCatalogParsing()
        try checkWebsiteSorting()
        if CommandLine.arguments.contains("--live") {
            try await checkLiveData()
            return
        }
        if CommandLine.arguments.contains("--live-filtered") {
            try await checkLiveFilteredData()
            return
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CategoryProtocol.self]
        let cache = DiskCache(namespace: "BgmoriCategoryTests")
        let api = APIClient(session: URLSession(configuration: configuration), cache: cache, routing: MirrorRouting(), discoverMirrors: false)
        let tags = TagResultsStore()
        let tagQuery = TagResultsQuery(tag: UUID().uuidString, includeNSFW: false)
        await tags.load(tagQuery, api: api)
        precondition(tags.subjects.count == 18 && tags.nextOffset == 20 && tags.hasMore)
        precondition(tags.subjectsForDisplay(columns: 4).count == 16)
        CategoryProtocol.server.failOnePage()
        await tags.loadMore(tagQuery, api: api)
        precondition(tags.subjects.count == 18 && tags.nextOffset == 20 && tags.pageErrorText != nil)
        await tags.loadMore(tagQuery, api: api, force: true)
        precondition(tags.subjects.map(\.id) == Array(1...18) + [20, 21] && !tags.hasMore)
        precondition(tags.subjectsForDisplay(columns: 3).count == 20)
        CategoryProtocol.server.setFailure(true)
        await tags.load(tagQuery, api: api, force: true)
        precondition(tags.subjects.count == 20 && tags.errorText != nil)
        let otherTag = TagResultsQuery(tag: UUID().uuidString, includeNSFW: false)
        await tags.load(otherTag, api: api, force: true)
        precondition(tags.subjects.isEmpty && tags.errorText != nil)
        CategoryProtocol.server.setFailure(false)
        print("PASS: tag clamped page size, offsets, complete rows, filtering, deduplication, retry and refresh preservation")
        let store = CategoryStore(api: api)
        let run = UUID().uuidString
        let query = CategoryQuery(type: .anime, sort: .rank, year: 2020, tag: "\(run)-filters")
        await store.load(query)
        precondition(store.subjects.map(\.id) == [201] && store.hasMore && store.errorText == nil)
        precondition(store.subjectsForDisplay(columns: 2).isEmpty)
        CategoryProtocol.server.failOnePage()
        await store.loadMore(query)
        precondition(store.subjects.map(\.id) == [201] && store.pageErrorText != nil && store.hasMore)
        precondition(store.subjectsForDisplay(columns: 2).isEmpty, "A failed page must retain the buffered partial row")
        await store.loadMore(query, force: true)
        precondition(store.subjects.map(\.id) == [201, 204] && !store.hasMore && store.pageErrorText == nil)
        precondition(store.subjectsForDisplay(columns: 5).map(\.id) == [201, 204], "The terminal partial row must remain visible")
        print("PASS: pagination offsets, deduplication, content filtering, failed-page retry")

        let count = CategoryProtocol.server.count
        _ = try await api.categorySubjects(query: query)
        precondition(CategoryProtocol.server.count == count)
        CategoryProtocol.server.setFailure(true)
        do {
            _ = try await api.categorySubjects(query: query, force: true)
            preconditionFailure("An explicit refresh must surface network failures")
        } catch APIError.server(let status, _) {
            precondition(status == 503)
        }
        CategoryProtocol.server.setFailure(false)
        let preserved = try await api.categorySubjects(query: query)
        precondition(!preserved.data.isEmpty && CategoryProtocol.server.count == count + 1)
        print("PASS: cached search, forced refresh errors, and preserved fallback")

        let emptyQuery = CategoryQuery(type: .anime, sort: .rank, year: 2020, tag: "\(run)-empty")
        CategoryProtocol.server.setEmptyResults(true)
        await store.load(emptyQuery, force: true)
        precondition(store.subjects.isEmpty && store.errorText == nil && !store.hasMore)
        CategoryProtocol.server.setEmptyResults(false)
        print("PASS: a successful empty page replaces cached results with the empty state")

        let anime = CategoryQuery(type: .anime, sort: .collects, tag: "\(run)-race")
        let book = CategoryQuery(type: .book, sort: .collects, tag: "\(run)-race")
        let oldLoad = Task { await store.load(anime) }
        try await Task.sleep(for: .milliseconds(60))
        await store.load(book)
        await oldLoad.value
        precondition(store.subjects.map(\.id) == [101] && !store.isLoading)
        print("PASS: late animation response cannot replace selected books")

        let slowAnime = CategoryQuery(type: .anime, sort: .collects, tag: "\(run)-slow")
        let slowBook = CategoryQuery(type: .book, sort: .collects, tag: "\(run)-slow")
        let coldGame = CategoryQuery(type: .game, sort: .collects, tag: "\(run)-cold")
        await store.load(slowAnime)
        precondition(store.subjects.map(\.id) == [201])
        await store.load(slowBook)
        precondition(store.subjects.map(\.id) == [101])
        let cachedSwitch = Task { await store.load(slowAnime) }
        try await Task.sleep(for: .milliseconds(120))
        precondition(store.subjects.map(\.id) == [201] && !store.isLoading)
        await cachedSwitch.value
        let sameQueryRefresh = Task { await store.load(slowAnime, force: true) }
        try await Task.sleep(for: .milliseconds(120))
        precondition(store.subjects.map(\.id) == [201] && !store.isLoading)
        await sameQueryRefresh.value
        let coldSwitch = Task { await store.load(coldGame) }
        await Task.yield()
        precondition(!store.subjects.contains(where: { $0.id == 201 }),
                     "A new query must not show the previous query's list")
        await coldSwitch.value
        print("PASS: same-query refresh keeps results, other queries restore their own cache")

        let retry = CategoryQuery(type: .book, sort: .collects, tag: "\(run)-retry")
        CategoryProtocol.server.setFailure(true)
        await store.load(retry)
        precondition(store.subjects.isEmpty && store.errorText != nil && !store.isLoading)
        CategoryProtocol.server.setFailure(false)
        await store.load(retry, force: true)
        precondition(store.subjects.map(\.id) == [101] && store.errorText == nil)
        store.tag = "恋爱"
        store.year = 2020
        store.selectType(.book)
        precondition(store.tag == nil && store.year == 2020)
        print("PASS: initial error retry and resetting topic when switching content type")

        var metadataQuery = CategoryQuery(type: .anime, sort: .collects, tag: "\(run)-metadata", metaTags: ["科幻", "TV"])
        _ = try await api.categorySubjects(query: metadataQuery)
        let metadataCount = CategoryProtocol.server.count
        metadataQuery.metaTags.reverse()
        _ = try await api.categorySubjects(query: metadataQuery)
        precondition(CategoryProtocol.server.count == metadataCount, "Equivalent combinations must share the cache")
        metadataQuery.metaTags = ["TV", "恋爱"]
        _ = try await api.categorySubjects(query: metadataQuery)
        precondition(CategoryProtocol.server.count == metadataCount + 1, "Different public tags must not share cached results")
        print("PASS: combined public tags use meta_tags with distinct, order-independent cache keys")

        await store.loadFilters(for: .anime)
        store.selectType(.anime)
        precondition(store.filterGroups.count == 3 && store.filtersErrorText == nil)
        let filtersCount = CategoryProtocol.server.count
        await store.loadFilters(for: .anime)
        precondition(CategoryProtocol.server.count == filtersCount)
        store.selections["类型"] = store.filterGroups.first { $0.title == "类型" }!.options[0]
        precondition(store.query(includeNSFW: false).metaTags == ["科幻"] && store.selectedFilterCount == 1)
        store.selectType(.game)
        precondition(store.selections.isEmpty && store.filterGroups.isEmpty)
        await store.loadFilters(for: .anime)
        store.selectType(.anime)
        precondition(store.filterGroups.count == 3)
        print("PASS: website catalog loading, caching, selection and switching content types")

        let panelCache = DiskCache(namespace: "BgmoriCatalogCancellation-\(run)")
        let panelStore = CategoryStore(api: APIClient(session: URLSession(configuration: configuration), cache: panelCache, routing: MirrorRouting(), discoverMirrors: false))
        let panelLoad = Task { await panelStore.loadFilters(for: .anime) }
        await Task.yield()
        panelLoad.cancel()
        await panelLoad.value
        precondition(panelStore.filterGroups.count == 3 && !panelStore.isLoadingFilters)
        await panelCache.clear()
        print("PASS: closing a panel does not discard or strand its catalog request")
        let router = AppRouter()
        router.setPath([.subject(8)], for: .categories)
        router.setPath([.subject(9)], for: .search)
        precondition(AppSection.allCases.count == 6)
        precondition(router.path(for: .categories) == [.subject(8)] && router.path(for: .search) == [.subject(9)])
        print("PASS: six sections with independent navigation paths")
        let dateQuery = CategoryQuery(type: .anime, sort: .date, year: 2020, tag: "完整标签", metaTags: ["TV", "科幻"])
        await store.load(dateQuery)
        precondition(store.subjects.isEmpty && store.nextOffset == 2 && store.hasMore)
        await store.loadMore(dateQuery)
        precondition(store.subjects.map(\.id) == [803] && store.nextOffset == 4 && !store.hasMore)
        print("PASS: date browsing, full custom-tag lookup, and pagination past a locally empty page")
        let browserQuery = CategoryQuery(type: .anime, sort: .title)
        await store.load(browserQuery)
        precondition(store.subjects.map(\.id) == Array(701...724).filter { $0 != 702 })
        precondition(store.nextOffset == 24 && store.hasMore)
        let bufferedIDs = store.subjects.map(\.id)
        precondition(store.subjectsForDisplay(columns: 5).map(\.id) == Array(bufferedIDs.prefix(20)))
        precondition(store.subjectsForDisplay(columns: 6).map(\.id) == Array(bufferedIDs.prefix(18)))
        precondition(store.subjectsForDisplay(columns: 2).map(\.id) == Array(bufferedIDs.prefix(22)))
        precondition(store.subjects.map(\.id) == bufferedIDs, "Resizing must preserve buffered subjects")
        await store.loadMore(browserQuery)
        precondition(store.subjects.suffix(2).map(\.id) == [725, 726] && !store.hasMore)
        precondition(store.subjectsForDisplay(columns: 5).map(\.id) == bufferedIDs + [725, 726])
        precondition(store.subjectsForDisplay(columns: 6).count == 25)
        print("PASS: complete rows, resize-safe buffering, ordered page joins and terminal partial rows")
        let slice = try await api.categorySubjects(query: browserQuery, limit: 3, offset: 23)
        precondition(slice.data.map(\.id) == [724, 725, 726] && slice.total == 26)
        print("PASS: website order survives concurrent hydration, NSFW filtering, pagination and page boundaries")
        let staleBrowserQuery = CategoryQuery(type: .book, sort: .title)
        await store.load(staleBrowserQuery)
        precondition(store.subjects.map(\.id) == [901] && store.errorText == nil && !store.hasMore)
        print("PASS: a stale website ID is skipped instead of failing the whole category page")
        CategoryProtocol.server.setBrowserBlocked(true)
        let blocked = CategoryQuery(type: .anime, sort: .heat, year: 2020, tag: "\(run)-metadata-fallback", metaTags: ["TV", "科幻"])
        await store.load(blocked, force: true)
        precondition(store.subjects.map(\.id) == [201] && store.errorText == nil && store.fallbackSort == .collects)
        precondition(store.sortNotice != nil && store.nextOffset == 4 && store.hasMore)
        let browserCount = CategoryProtocol.server.browserCount
        CategoryProtocol.server.failOnePage()
        await store.loadMore(blocked, force: true)
        precondition(store.subjects.map(\.id) == [201] && store.pageErrorText != nil && store.nextOffset == 4)
        await store.loadMore(blocked, force: true)
        precondition(store.subjects.map(\.id) == [201, 204] && !store.hasMore && store.pageErrorText == nil)
        precondition(CategoryProtocol.server.browserCount == browserCount, "Fallback pagination must stay on search, including retries")
        let restored = CategoryStore(api: api)
        await restored.load(blocked)
        precondition(restored.subjects.map(\.id) == [201] && restored.fallbackSort == .collects)
        CategoryProtocol.server.setFailure(true)
        await restored.load(blocked, force: true)
        precondition(restored.subjects.map(\.id) == [201] && restored.fallbackSort == .collects && restored.refreshErrorText != nil)
        CategoryProtocol.server.setFailure(false)
        CategoryProtocol.server.setBrowserBlocked(false)
        await store.load(blocked, force: true)
        precondition(store.fallbackSort == nil && store.sortNotice == nil && store.subjects.contains { $0.id == 701 })
        print("PASS: verification fallback preserves combined filters, search cursors, retries, cached sort and original-order recovery")
        await cache.clear()
    }

    @MainActor
    private static func checkLiveFilteredData() async throws {
        let cache = DiskCache(namespace: "BgmoriCategoryFilteredLiveTests-\(UUID().uuidString)")
        let api = APIClient(cache: cache)
        let store = CategoryStore(api: api)
        for query in [
            CategoryQuery(type: .anime, year: 2020),
            CategoryQuery(type: .anime, metaTags: ["TV"]),
            CategoryQuery(type: .anime, year: 2020, metaTags: ["TV", "科幻"]),
            CategoryQuery(type: .anime, sort: .title, year: 2020, metaTags: ["TV"])
        ] {
            await store.load(query, force: true)
            precondition(store.errorText == nil && !store.subjects.isEmpty, "Filtered categories failed: \(store.errorText ?? "empty")")
            precondition(store.subjects.allSatisfy(query.matches))
            let firstIDs = Set(store.subjects.map(\.id))
            let firstOffset = store.nextOffset
            if store.hasMore {
                await store.loadMore(query, force: true)
                precondition(store.pageErrorText == nil && store.nextOffset > firstOffset, "Pagination failed: \(store.pageErrorText ?? "no cursor advance")")
                precondition(store.subjects.count > firstIDs.count && Set(store.subjects.map(\.id)).count == store.subjects.count)
            } else {
                await store.loadMore(query, force: true)
                precondition(store.nextOffset == firstOffset && Set(store.subjects.map(\.id)) == firstIDs)
            }
            precondition(store.subjects.allSatisfy(query.matches))
            print("PASS live filtered \(query.sort.title), year \(query.year.map(String.init) ?? "all"), tags \(query.metaTags): \(store.subjects.count) subjects, fallback \(store.fallbackSort?.title ?? "none")")
        }
        await cache.clear()
    }

    @MainActor
    private static func checkLiveData() async throws {
        let cache = DiskCache(namespace: "BgmoriCategoryLiveTests")
        let api = APIClient(cache: cache)
        for type in SubjectType.browsingTypes {
            let groups = try await api.categoryFilters(type: type, force: true)
            precondition(groups.allSatisfy { !$0.options.isEmpty })
            print("PASS live \(type.title) catalog: \(groups.map { "\($0.title) \($0.options.count)" }.joined(separator: ", "))")
            let page = try await api.categorySubjects(query: CategoryQuery(type: type, sort: .collects), limit: 3, force: true)
            precondition(!page.data.isEmpty && page.data.allSatisfy { $0.type == type.rawValue && !$0.nsfw })
            print("PASS live \(type.title): \(page.data.map(\.displayTitle).joined(separator: ", "))")
        }
        let gameTrends = try await api.categorySubjects(
            query: CategoryQuery(type: .game, sort: .heat),
            limit: 6,
            force: true
        )
        precondition(!gameTrends.data.isEmpty && gameTrends.data.allSatisfy { $0.type == SubjectType.game.rawValue })
        print("PASS live game trends: \(gameTrends.data.map(\.displayTitle).joined(separator: ", "))")

        let query = CategoryQuery(type: .anime, sort: .rank, year: 2011, tag: "科幻")
        let first = try await api.categorySubjects(query: query, limit: 3, force: true)
        let next = try await api.categorySubjects(query: query, limit: 3, offset: 3, force: true)
        precondition(!first.data.isEmpty && !next.data.isEmpty)
        precondition((first.data + next.data).allSatisfy { $0.type == 2 && !$0.nsfw && $0.date?.hasPrefix("2011-") == true && ($0.rating?.rank ?? 0) > 0 })
        precondition(Set(first.data.map(\.id)).isDisjoint(with: next.data.map(\.id)))
        print("PASS live topic + year + ranking + second page")
        let combinations: [(SubjectType, [String])] = [(.anime, ["TV", "科幻", "日本"]), (.book, ["漫画", "推理"]),
                                                        (.music, ["OST", "动画"]), (.game, ["PC", "RPG"]),
                                                        (.real, ["电视剧", "日本", "悬疑"])]
        for (type, tags) in combinations {
            let page = try await api.categorySubjects(query: CategoryQuery(type: type, sort: .collects, metaTags: tags), limit: 3, force: true)
            precondition(!page.data.isEmpty && page.data.allSatisfy { $0.type == type.rawValue && !$0.nsfw })
            precondition(page.data.allSatisfy { Set(tags.map { $0.lowercased() }).isSubset(of: Set($0.metaTags.map { $0.lowercased() })) })
            print("PASS live \(type.title) public-tag combination: \(tags.joined(separator: " + "))")
        }
        for sort in [CategorySort.heat, .title] {
            let query = CategoryQuery(type: .anime, sort: sort)
            let page = try await api.categorySubjects(query: query, limit: 3, force: true)
            precondition(!page.data.isEmpty)
            let html = try await api.rawHTML(query.browserURL, cacheKey: "live-order-\(sort.rawValue)", ttl: 0)
            let expected = try CategoryBrowserPage.parse(html, page: 1).ids
            precondition(page.data.map(\.id) == Array(expected.prefix(3)))
            print("PASS live website \(sort.title): \(page.data.map(\.displayTitle).joined(separator: ", "))")
        }
        let dates = try await api.categorySubjects(query: CategoryQuery(type: .anime, sort: .date), limit: 3, force: true)
        precondition(dates.data.count == 3)
        let dateValues = dates.data.compactMap(\.date)
        precondition(dateValues == dateValues.sorted(by: >))
        print("PASS live date order: \(dates.data.map(\.displayTitle).joined(separator: ", "))")
        await cache.clear()
    }

    private static func checkWebsiteSorting() throws {
        precondition(CategorySort.allCases.map(\.title) == ["排名", "热度", "收藏", "日期", "名称"])
        precondition(CategorySort.collects.searchSort == "heat" && CategorySort.heat.searchSort == nil)
        let query = CategoryQuery(type: .anime, sort: .date, year: 2020, tag: "科幻", metaTags: ["TV", "日本"])
        precondition(query.browserURL.path == "/anime/browser/科幻/airtime/2020")
        precondition(query.browserURL.query == "sort=date")
        let html = "<div id='browserTools'></div><ul id='browserItemList'><li id='item_9'></li><li id='item_8'></li></ul><a href='?sort=title&amp;page=12'>尾页</a>"
        let page = try CategoryBrowserPage.parse(html, page: 1)
        precondition(page.ids == [9, 8] && page.total == 288)
        let subject = try JSONDecoder().decode(Subject.self, from: Data(#"{"id":8,"type":2,"date":"2020-01-01","meta_tags":["TV","日本"]}"#.utf8))
        precondition(query.matches(subject))
        var excluded = query
        excluded.metaTags = ["-TV"]
        precondition(!excluded.matches(subject))
        excluded = query
        excluded.year = 2021
        precondition(!excluded.matches(subject))
        let empty = try CategoryBrowserPage.parse("<div id='browserTools'></div><ul id='browserItemList'><p>没有找到相关条目</p></ul>", page: 1)
        precondition(empty.ids.isEmpty)
        for malformed in ["<html>challenge</html>", "<div id='browserTools'></div><ul id='browserItemList'></ul>", "<ul id='browserItemList'><li id='item_9'></li><li id='item_9'></li></ul>"] {
            do {
                _ = try CategoryBrowserPage.parse(malformed, page: 1)
                preconditionFailure("Broken website pages must fail visibly")
            } catch {}
        }
        print("PASS: five official sort options, website URLs, ordering, page counts, combined filters and parser errors")
    }

    static let catalogFixture = #"""
    <div id="columnSubjectBrowserB"><div class="sideInner">
    <h2 class="subtitle">分类</h2><ul><li><a href="/anime/browser">全部</a></li>
    <li><a href="/anime/browser/tv?sort=title">TV</a></li></ul>
    <h2 class="subtitle">类型</h2><ul>
    <li><a href="/anime/browser/">全部</a></li>
    <li><a href="/anime/browser/%E7%A7%91%E5%B9%BB">科幻</a></li>
    <li><a href="/anime/browser/%E7%A7%91%E5%B9%BB">重复</a></li>
    <li><a href="/anime/browser/%E6%81%8B%E7%88%B1"><span>恋爱</span></a></li>
    <li><a href="https://example.com/anime/browser/test">外部链接</a></li>
    <li><a href="/game/browser/RPG">其他类型</a></li></ul>
    <h2>地区</h2><ul><li><a href="/anime/browser/%E9%A6%99%E6%B8%AF">中国香港</a></li></ul>
    <h2>时间</h2><ul><li><a href="/anime/browser/airtime/2026">2026年</a></li></ul>
    </div></div><h2>类型</h2><ul><a href="/anime/browser/ignored">页面外部</a></ul>
    """#

    private static func checkCatalogParsing() throws {
        let groups = try CategoryCatalog.parse(catalogFixture, type: .anime)
        precondition(groups.map(\.title) == ["分类", "类型", "地区"])
        precondition(groups[0].options[0].metaTags == ["TV"])
        precondition(groups[1].options.map(\.title) == ["科幻", "恋爱"])
        precondition(groups[2].options[0].title == "中国香港" && groups[2].options[0].metaTags == ["香港"])
        let real = catalogFixture.replacingOccurrences(of: "/anime/", with: "/real/")
            .replacingOccurrences(of: "browser/tv?sort=title\">TV", with: "browser/jp?sort=title\">日剧")
        let realGroups = try CategoryCatalog.parse(real, type: .real)
        precondition(realGroups[0].options[0].metaTags == ["电视剧", "日本"])
        for invalid in ["<html>blocked</html>", "<div id='columnSubjectBrowserB'><h2>类型</h2><ul></ul></div>"] {
            do {
                _ = try CategoryCatalog.parse(invalid, type: .anime)
                preconditionFailure("Malformed catalogs must fail visibly")
            } catch {}
        }
        print("PASS: official catalog groups, URL tag values, aliases, deduplication and malformed-page errors")
    }
}
