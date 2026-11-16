import CryptoKit
import Foundation

private struct StubReply: Sendable {
    let status: Int
    let data: Data
    let delay: TimeInterval
}

private final class CacheStub: @unchecked Sendable {
    static let shared = CacheStub()

    private let lock = NSLock()
    private var subjectDelays: [Int: TimeInterval] = [:]
    private var libraryDelays: [String: TimeInterval] = [:]
    private var failSubject = false
    private var failHTML = false
    private var failLibraryOffsets: Set<Int> = []
    private var episodeDelay: TimeInterval = 0
    private var subjectRequestCount = 0
    private var libraryOffsets: [String: [Int]] = [:]
    private var subjectValues: [Int: [String: Any]] = [:]
    private var libraryValues: [String: [Int]] = [:]
    private var savedCollection: [String: Any]?
    private var mutationMethods: [String] = []

    func reset() {
        lock.withLock {
            subjectDelays = [:]
            libraryDelays = [:]
            failSubject = false
            failHTML = false
            failLibraryOffsets = []
            episodeDelay = 0
            subjectRequestCount = 0
            libraryOffsets = [:]
            subjectValues = [:]
            libraryValues = [:]
            savedCollection = nil
            mutationMethods = []
        }
    }

    func configureSubject(id: Int, delay: TimeInterval = 0) {
        lock.withLock { subjectDelays[id] = delay }
    }

    func configureLibrary(user: String, ids: [Int], delay: TimeInterval = 0) {
        lock.withLock {
            libraryValues[user] = ids
            libraryDelays[user] = delay
        }
    }

    func failLibrary(offset: Int) {
        _ = lock.withLock { failLibraryOffsets.insert(offset) }
    }

    func clearLibraryFailure() {
        lock.withLock { failLibraryOffsets.removeAll() }
    }

    func setSubjectFailure(_ value: Bool) {
        lock.withLock { failSubject = value }
    }

    func setHTMLFailure(_ value: Bool) {
        lock.withLock { failHTML = value }
    }

    func setEpisodeDelay(_ value: TimeInterval) {
        lock.withLock { episodeDelay = value }
    }

    var subjectsRequested: Int { lock.withLock { subjectRequestCount } }
    var recordedLibraryOffsets: [String: [Int]] { lock.withLock { libraryOffsets } }
    var mutations: [String] { lock.withLock { mutationMethods } }

    func reply(for request: URLRequest) -> StubReply {
        lock.withLock {
            let path = request.url?.path ?? ""
            if request.url?.host == "bgm.tv" {
                if failHTML { return StubReply(status: 503, data: Data("{}".utf8), delay: 0) }
                return StubReply(status: 200,
                                 data: Data(#"<html><div id="comment_box"><div class="item"><a href="/user/a" class="l">a</a><div class="comment">hello</div></div></div></html>"#.utf8),
                                 delay: 0)
            }
            if request.httpMethod == "PATCH" || request.httpMethod == "POST" {
                mutationMethods.append(request.httpMethod ?? "")
                let body = request.httpBodyData
                if let body, let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                    savedCollection = object
                }
                return StubReply(status: 204, data: Data(), delay: 0)
            }
            if path.hasSuffix("/episodes") {
                let subjectID = Int(path.split(separator: "/").dropLast().last.map(String.init) ?? "") ?? 8
                let data: [String: Any] = [
                    "data": [[
                        "episode": ["id": subjectID * 10 + 1, "type": 0, "sort": 1, "subject_id": subjectID],
                        "type": 2, "updated_at": 0
                    ]],
                    "total": 1, "limit": 1000, "offset": 0
                ]
                return StubReply(status: 200, data: try! JSONSerialization.data(withJSONObject: data), delay: episodeDelay)
            }
            if path.hasPrefix("/v0/subjects/") {
                subjectRequestCount += 1
                let id = Int(path.split(separator: "/").last.map(String.init) ?? "") ?? 0
                if failSubject { return StubReply(status: 503, data: Data("{}".utf8), delay: 0) }
                let value = subjectValues[id] ?? ["id": id, "type": 2, "name": "fixture-\(id)"]
                return StubReply(status: 200, data: try! JSONSerialization.data(withJSONObject: value),
                                 delay: subjectDelays[id] ?? 0)
            }
            if path.hasPrefix("/v0/users/"), path.hasSuffix("/collections") {
                let parts = path.split(separator: "/").map(String.init)
                let user = parts.count > 2 ? parts[2] : "fixture"
                let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
                let query = components.queryItems ?? []
                let offset = Int(query.first { $0.name == "offset" }?.value ?? "0") ?? 0
                libraryOffsets[user, default: []].append(offset)
                if failLibraryOffsets.contains(offset) {
                    return StubReply(status: 503, data: Data("{}".utf8), delay: 0)
                }
                let ids = libraryValues[user] ?? []
                let slice = Array(ids.dropFirst(offset).prefix(50))
                let rows: [[String: Any]] = slice.map { id in
                    ["subject_id": id, "subject_type": 2, "type": id == 8 ? 3 : 2,
                     "rate": 0, "ep_status": 0, "vol_status": 0,
                     "subject": ["id": id, "type": 2, "name": "fixture-\(id)"]]
                }
                let value: [String: Any] = ["data": rows, "total": ids.count, "limit": 50, "offset": offset]
                return StubReply(status: 200, data: try! JSONSerialization.data(withJSONObject: value),
                                 delay: libraryDelays[user] ?? 0)
            }
            if path.hasPrefix("/v0/users/-/collections/"), request.httpMethod == "GET" {
                let id = Int(path.split(separator: "/").last.map(String.init) ?? "") ?? 0
                let value: [String: Any] = savedCollection ?? [
                    "subject_id": id, "subject_type": 2, "type": 3, "rate": 8
                ]
                return StubReply(status: 200, data: try! JSONSerialization.data(withJSONObject: value), delay: 0)
            }
            return StubReply(status: 404, data: Data("{}".utf8), delay: 0)
        }
    }
}

private extension URLRequest {
    var httpBodyData: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final class CacheStubProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let reply = CacheStub.shared.reply(for: request)
        DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay) { [self] in
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status,
                                           httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: reply.data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

@MainActor
private final class TestAccount: LibraryAccountProviding {
    var isLoggedIn = true
    var username: String? = "fixture"
}

private func cacheFile(_ key: String, namespace: String) -> URL {
    let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
    let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    return base.appendingPathComponent(namespace).appendingPathComponent(digest + ".cache")
}

/// The cache is disposable, so it must stay bounded without asking the user:
/// oldest files go first once the namespace exceeds its byte cap.
private func checkDiskCacheEviction() async throws {
    let namespace = "BgmoriEvictionTests-\(UUID())"
    let cache = DiskCache(namespace: namespace, maxBytes: 12 * 1024)
    let payload = Data(repeating: 0x41, count: 4 * 1024)
    for index in 0..<6 {
        await cache.write("entry-\(index)", data: payload)
        try await Task.sleep(for: .milliseconds(10))
    }
    let size = await cache.size()
    precondition(size <= 12 * 1024, "cache grew past its cap: \(size) bytes")
    let newest = await cache.readEntry("entry-5", maxAge: 60, maxStaleAge: 60)
    let oldest = await cache.readEntry("entry-0", maxAge: 60, maxStaleAge: 60)
    precondition(newest != nil, "the newest entry must survive eviction")
    precondition(oldest == nil, "the oldest entries must be evicted first")
    _ = await cache.trimIfNeeded()
    let afterTrim = await cache.size()
    precondition(afterTrim <= 12 * 1024)
    await cache.clear()
    let cleared = await cache.size()
    precondition(cleared == 0)
    print("PASS: disk cache evicts the oldest entries when it exceeds its byte cap")
}

private func ageCache(_ key: String, namespace: String, seconds: TimeInterval) throws {
    let url = cacheFile(key, namespace: namespace)
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-seconds)],
                                          ofItemAtPath: url.path)
}

@MainActor
private func elapsed(_ block: () async throws -> Void) async rethrows -> TimeInterval {
    let start = Date()
    try await block()
    return Date().timeIntervalSince(start)
}

@main
@MainActor
struct CacheBehaviorTests {
    static func main() async throws {
        let stub = CacheStub.shared
        stub.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CacheStubProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let namespace = "BgmoriCacheTests-\(UUID())"
        let cache = DiskCache(namespace: namespace)
        let api = APIClient(session: session, cache: cache, routing: MirrorRouting(), discoverMirrors: false)
        await api.setToken("fixture-\(UUID().uuidString)")

        stub.configureSubject(id: 8, delay: 1.2)
        let initial = try await elapsed { _ = try await api.subject(8) }
        precondition(initial > 1.0)
        let fresh = try await elapsed { _ = try await api.subject(8) }
        precondition(fresh < 0.1 && stub.subjectsRequested == 1)
        print(String(format: "PASS: fresh cache skips the network (%.3fs)", fresh))

        try ageCache("subject-8", namespace: namespace, seconds: 2 * 86_400)
        let stale = await elapsed {
            let hit = await api.cachedSubject(8)
            precondition(hit?.isFresh == false && hit?.value.id == 8)
        }
        precondition(stale < 0.2)
        let refreshed = try await elapsed { _ = try await api.subject(8) }
        precondition(refreshed > 1.0)
        let afterRefresh = await api.cachedSubject(8)
        precondition(afterRefresh?.isFresh == true && stub.subjectsRequested == 2)
        print(String(format: "PASS: stale cache renders in %.3fs, network refresh takes %.3fs", stale, refreshed))

        try ageCache("subject-8", namespace: namespace, seconds: 2 * 86_400)
        stub.setSubjectFailure(true)
        let preserved = try await api.subject(8)
        precondition(preserved.id == 8)
        do {
            _ = try await api.subject(8, force: true)
            preconditionFailure("force must bypass the cache and surface the failure")
        } catch APIError.server(let status, _) {
            precondition(status == 503)
        }
        print("PASS: failed refresh keeps the cache; force still accesses the network")

        try ageCache("subject-8", namespace: namespace, seconds: 31 * 86_400)
        stub.setSubjectFailure(false)
        let expired = await api.cachedSubject(8)
        precondition(expired == nil, "stale content must not be displayable forever")
        stub.configureSubject(id: 9, delay: 0.6)
        let beforeConcurrent = stub.subjectsRequested
        let concurrent = try await elapsed {
            async let first = api.subject(9)
            async let second = api.subject(9)
            _ = try await (first, second)
        }
        precondition(concurrent < 1.0 && stub.subjectsRequested == beforeConcurrent + 1)
        print("PASS: expired entries are bounded and identical reads share one request")

        stub.configureSubject(id: 10, delay: 0.8)
        let beforeCancel = stub.subjectsRequested
        let firstWaiter = Task { try await api.subject(10) }
        let secondWaiter = Task { try await api.subject(10) }
        try await Task.sleep(for: .milliseconds(120))
        firstWaiter.cancel()
        do {
            _ = try await firstWaiter.value
            preconditionFailure("A cancelled waiter must not report success")
        } catch APIError.cancelled { }
        let secondValue = try await secondWaiter.value
        precondition(secondValue.id == 10 && stub.subjectsRequested == beforeCancel + 1)
        print("PASS: cancelling one waiter leaves the shared request alive for the other")

        try await checkDiskCacheEviction()

        let html = try await api.rawHTML(URL(string: "https://bgm.tv/subject/8")!, cacheKey: "html-8")
        precondition(html.contains("comment_box"))
        try ageCache("html-8", namespace: namespace, seconds: 2 * 3_600)
        let htmlHit = await api.cachedHTML(URL(string: "https://bgm.tv/subject/8")!,
                                           cacheKey: "html-8",
                                           validate: { precondition($0.contains("comment_box")) })
        precondition(htmlHit?.isFresh == false && htmlHit?.value.contains("comment_box") == true)
        await cache.write("html-broken", data: Data("<html>challenge</html>".utf8))
        let rejected = await api.cachedHTML(URL(string: "https://bgm.tv/subject/8")!,
                                            cacheKey: "html-broken",
                                            validate: { _ = try SocialFixtureParser.parse($0) })
        precondition(rejected == nil, "structurally invalid cached HTML must fall back to the network")
        print("PASS: HTML cache is validated before display")

        try await checkLibrary(session: session)
        await cache.clear()
    }

    private static func checkLibrary(session: URLSession) async throws {
        let stub = CacheStub.shared
        stub.reset()
        stub.configureLibrary(user: "fixture", ids: Array(1...120), delay: 0.12)
        stub.setEpisodeDelay(1.5)
        let cache = DiskCache(namespace: "BgmoriLibraryTests-\(UUID())")
        let api = APIClient(session: session, cache: cache, routing: MirrorRouting(), discoverMirrors: false)
        await api.setToken("fixture-\(UUID().uuidString)")
        let account = TestAccount()
        let snapshots = LibrarySnapshotStore(namespace: "BgmoriSnapshots-\(UUID())")
        let store = LibraryStore(api: api, auth: account, snapshots: snapshots)

        let loadTime = await elapsed { _ = await store.loadAll(username: "fixture", force: true) }
        precondition(store.collections.count == 120 && store.lastError == nil)
        precondition(loadTime < 1.2, "episode progress must not block the collection body")
        print(String(format: "PASS: complete library loads in %.3fs without waiting for progress", loadTime))

        let restored = LibraryStore(api: api, auth: account, snapshots: snapshots)
        let restoreTime = await elapsed { await restored.loadIfNeeded() }
        precondition(restored.collections.count == 120)
        precondition(restoreTime < 0.3)
        print(String(format: "PASS: account snapshot restores in %.3fs", restoreTime))

        stub.failLibrary(offset: 50)
        let failed = await store.loadAll(username: "fixture", force: true)
        precondition(!failed)
        precondition(store.collections.count == 120, "a failed pagination must not replace the complete snapshot")
        let stillRestored = LibraryStore(api: api, auth: account, snapshots: snapshots)
        await stillRestored.loadIfNeeded()
        precondition(stillRestored.collections.count == 120)
        stub.configureLibrary(user: "empty", ids: [], delay: 0.02)
        account.username = "empty"
        let emptySnapshots = LibrarySnapshotStore(namespace: "BgmoriSnapshots-\(UUID())")
        let emptyStore = LibraryStore(api: api, auth: account, snapshots: emptySnapshots)
        let emptyOK = await emptyStore.loadAll(username: "empty", force: true)
        precondition(emptyOK && emptyStore.collections.isEmpty && emptyStore.lastError == nil)
        let restoredEmpty = LibraryStore(api: api, auth: account, snapshots: emptySnapshots)
        await restoredEmpty.loadIfNeeded()
        precondition(restoredEmpty.collections.isEmpty && !restoredEmpty.isLoading)
        account.username = "fixture"
        print("PASS: a successful empty collection response is published as an empty snapshot")

        stub.clearLibraryFailure()
        let fresh = LibraryStore(api: api, auth: account,
                                 snapshots: LibrarySnapshotStore(namespace: "BgmoriSnapshots-\(UUID())"))
        stub.failLibrary(offset: 50)
        let firstFailure = await fresh.loadAll(username: "fixture", force: true)
        precondition(!firstFailure && fresh.collections.isEmpty && fresh.lastError != nil)
        print("PASS: a partial first reconciliation is never published")

        stub.clearLibraryFailure()
        stub.configureSubject(id: 8, delay: 0)
        _ = await store.loadAll(username: "fixture", force: true)
        let subject = try JSONDecoder().decode(Subject.self, from: Data(#"{"id":8,"type":2,"name":"fixture-8"}"#.utf8))
        try await store.save(subject: subject, patch: CollectionPatch(rate: 9, comment: "saved"))
        guard let saved = store.collection(for: 8), saved.rate == 9 else {
            preconditionFailure("saving a collection must update local state")
        }
        let afterSave = LibraryStore(api: api, auth: account, snapshots: snapshots)
        await afterSave.loadIfNeeded()
        precondition(afterSave.collection(for: 8)?.rate == 9)
        print("PASS: successful collection mutations update the snapshot")

        stub.configureLibrary(user: "a", ids: Array(201...210), delay: 0.4)
        stub.configureLibrary(user: "b", ids: Array(301...305), delay: 0.05)
        let switched = LibraryStore(api: api, auth: account,
                                    snapshots: LibrarySnapshotStore(namespace: "BgmoriSnapshots-\(UUID())"))
        account.username = "a"
        let old = Task { await switched.loadAll(username: "a", force: true) }
        try await Task.sleep(for: .milliseconds(60))
        account.username = "b"
        await switched.loadIfNeeded()
        _ = await old.value
        try await Task.sleep(for: .milliseconds(600))
        precondition(switched.loadedUsername == "b")
        precondition(Set(switched.collections.keys).isSubset(of: Set(301...305)))
        print("PASS: account switch invalidates late responses from the previous account")

        await cache.clear()
    }
}

private enum SocialFixtureParser {
    static func parse(_ html: String) throws {
        guard html.contains("comment_box") else { throw APIError.decoding("fixture") }
    }
}
