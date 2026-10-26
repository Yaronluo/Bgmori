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
    private var offsets: [Int] = []

    var count: Int { lock.withLock { requests } }
    var requestedOffsets: [Int] { lock.withLock { offsets } }

    func setFailure(_ value: Bool) { lock.withLock { fail = value } }
    func failOnePage() { lock.withLock { failNextPage = true } }

    func response(for request: URLRequest) -> StubResponse {
        lock.withLock {
            requests += 1
            if request.url?.host == "bgm.tv" {
                precondition(request.value(forHTTPHeaderField: "User-Agent") == APIClient.safariUserAgent)
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
            precondition(payload["keyword"] as? String == "")
            precondition(filter["nsfw"] as? Bool == false)
            let type = (filter["type"] as! [Int])[0]
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
            let data = try! JSONSerialization.data(withJSONObject: ["data": rows, "total": 6, "limit": 24, "offset": offset])
            return StubResponse(data: data, status: failed ? 503 : 200, delay: tag.contains("race") && type == 2 ? 0.6 : 0.01)
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
        if CommandLine.arguments.contains("--live") {
            try await checkLiveData()
            return
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CategoryProtocol.self]
        let cache = DiskCache(namespace: "BgmoriCategoryTests")
        let api = APIClient(session: URLSession(configuration: configuration), cache: cache)
        let store = CategoryStore(api: api)
        let run = UUID().uuidString
        let query = CategoryQuery(type: .anime, sort: .rank, year: 2020, tag: "\(run)-filters")
        await store.load(query)
        precondition(store.subjects.map(\.id) == [201] && store.hasMore && store.errorText == nil)
        CategoryProtocol.server.failOnePage()
        await store.loadMore(query)
        precondition(store.subjects.map(\.id) == [201] && store.pageErrorText != nil && store.hasMore)
        await store.loadMore(query)
        precondition(store.subjects.map(\.id) == [201, 204] && !store.hasMore && store.pageErrorText == nil)
        print("PASS: pagination offsets, deduplication, content filtering, failed-page retry")

        let count = CategoryProtocol.server.count
        _ = try await api.categorySubjects(query: query)
        precondition(CategoryProtocol.server.count == count)
        CategoryProtocol.server.setFailure(true)
        _ = try await api.categorySubjects(query: query, force: true)
        CategoryProtocol.server.setFailure(false)
        print("PASS: cached search and offline fallback")

        let anime = CategoryQuery(type: .anime, tag: "\(run)-race")
        let book = CategoryQuery(type: .book, tag: "\(run)-race")
        let oldLoad = Task { await store.load(anime) }
        try await Task.sleep(for: .milliseconds(60))
        await store.load(book)
        await oldLoad.value
        precondition(store.subjects.map(\.id) == [101] && !store.isLoading)
        print("PASS: late animation response cannot replace selected books")

        let retry = CategoryQuery(type: .book, tag: "\(run)-retry")
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

        var metadataQuery = CategoryQuery(type: .anime, tag: "\(run)-metadata", metaTags: ["科幻", "TV"])
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
        let panelStore = CategoryStore(api: APIClient(session: URLSession(configuration: configuration), cache: panelCache))
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
            let page = try await api.categorySubjects(query: CategoryQuery(type: type), limit: 3, force: true)
            precondition(!page.data.isEmpty && page.data.allSatisfy { $0.type == type.rawValue && !$0.nsfw })
            print("PASS live \(type.title): \(page.data.map(\.displayTitle).joined(separator: ", "))")
        }
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
            let page = try await api.categorySubjects(query: CategoryQuery(type: type, metaTags: tags), limit: 3, force: true)
            precondition(!page.data.isEmpty && page.data.allSatisfy { $0.type == type.rawValue && !$0.nsfw })
            precondition(page.data.allSatisfy { Set(tags.map { $0.lowercased() }).isSubset(of: Set($0.metaTags.map { $0.lowercased() })) })
            print("PASS live \(type.title) public-tag combination: \(tags.joined(separator: " + "))")
        }
        await cache.clear()
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
