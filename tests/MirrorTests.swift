import Foundation

private final class MirrorRequests: @unchecked Sendable {
    struct Reply: Sendable {
        let status: Int
        let data: Data
        var headers: [String: String] = ["Content-Type": "application/json"]
    }
    static let shared = MirrorRequests()
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private var replies: [String: Reply] = [:]

    func reset(_ replies: [String: Reply]) {
        lock.withLock { self.replies = replies; recorded = [] }
    }
    func reply(for request: URLRequest) -> Reply {
        lock.withLock {
            recorded.append(request)
            return replies[request.url!.absoluteString] ?? Reply(status: 503, data: Data("{}".utf8))
        }
    }
    var requests: [URLRequest] { lock.withLock { recorded } }
}

private final class MirrorProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let reply = MirrorRequests.shared.reply(for: request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: reply.status,
                                                            httpVersion: "HTTP/1.1", headerFields: reply.headers)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
struct MirrorTests {
    static func catalog(_ domain: String) -> Data {
        Data("""
        {"mirrors":[{"id":"primary","weight":1000,"recommended":true,"services":[
          {"id":"main","hosts":["\(domain)"]},
          {"id":"api","hosts":["api.\(domain)"]},
          {"id":"lain","hosts":["lain.\(domain)"]}]}]}
        """.utf8)
    }

    static func main() async throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("bgmori-mirrors-\(UUID())")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = temporary.appendingPathComponent("Mirrors.json")
        let routing = MirrorRouting(persistenceURL: store)
        let first = try JSONDecoder().decode(MirrorCatalog.self, from: catalog("first.test"))
        routing.update(first, etag: "v1")
        let original = URL(string: "http://bgm.tv/subject/8?name=%E6%B5%8B%E8%AF%95#comments")!
        let mapped = routing.preferredURL(for: original)
        precondition(mapped.host == "bgm.tv" && mapped.scheme == "https")
        precondition(mapped.query == original.query && mapped.fragment == original.fragment)
        precondition(routing.preferredURL(for: URL(string: "https://chii.in/ep/1")!).host == "bgm.tv")
        for raw in ["https://example.com/subject/8", "bgmori://oauth/callback", "https://bgm.tv.evil.test/8",
                    "https://user@bgm.tv/8", "https://bgm.tv:444/8"] {
            let url = URL(string: raw)!
            precondition(routing.preferredURL(for: url) == url)
        }
        let restored = MirrorRouting(persistenceURL: store)
        precondition(!restored.needsRefresh && restored.etag == "v1")
        let second = try JSONDecoder().decode(MirrorCatalog.self, from: catalog("second.test"))
        restored.update(second, etag: "v2")
        let oldCover = URL(string: "https://lain.first.test/pic/cover/l/8.jpg")!
        precondition(restored.preferredURL(for: oldCover).host == "lain.bgm.tv")
        let resized = ImageLoader.requestURL(for: restored.canonicalURL(for: oldCover), maxPixel: 597)
        precondition(restored.preferredURL(for: resized).path == "/r/600/pic/cover/l/8.jpg")
        restored.markUnavailable(URL(string: "https://api.second.test")!)
        precondition(restored.candidates(for: URL(string: "https://api.bgm.tv/v0/subjects/8")!, forRequest: true).first?.host == "api.bgm.tv")
        print("PASS: service routing, URL boundaries, persistence, domain rotation, CDN sizing and host fallback")

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MirrorProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let namespace = "BgmoriMirrorTests-\(UUID())"
        let cache = DiskCache(namespace: namespace)
        let isolated = MirrorRouting()
        let api = APIClient(session: session, cache: cache, routing: isolated)
        let directory = MirrorRouting.directoryURL.absoluteString
        let subject = Data(#"{"id":8,"name":"test","type":2}"#.utf8)
        MirrorRequests.shared.reset([
            directory: .init(status: 200, data: catalog("first.test"), headers: ["ETag": "v1"]),
            "https://api.first.test/v0/subjects/8": .init(status: 200, data: subject)
        ])
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    let result = try await api.get("/v0/subjects/8", as: Subject.self)
                    precondition(result.id == 8)
                }
            }
            try await group.waitForAll()
        }
        precondition(MirrorRequests.shared.requests.filter { $0.url!.absoluteString == directory }.count == 1)
        precondition(MirrorRequests.shared.requests.allSatisfy { $0.value(forHTTPHeaderField: "User-Agent") == APIClient.userAgent })
        precondition(MirrorRequests.shared.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
        MirrorRequests.shared.reset([directory: .init(status: 304, data: Data())])
        await api.prepareMirrors(force: true)
        precondition(MirrorRequests.shared.requests.first?.value(forHTTPHeaderField: "If-None-Match") == "v1")
        precondition(isolated.candidates(for: URL(string: "https://api.bgm.tv")!).contains { $0.host == "api.first.test" })
        MirrorRequests.shared.reset([directory: .init(status: 503, data: Data("{}".utf8))])
        await api.prepareMirrors(force: true)
        precondition(isolated.candidates(for: URL(string: "https://api.bgm.tv")!).contains { $0.host == "api.first.test" })
        print("PASS: concurrent discovery coalesces; ETag and failed refresh preserve the cached directory")

        let challenge = Data(#"<html><script id="anubis_challenge"></script></html>"#.utf8)
        isolated.resetHealth()
        MirrorRequests.shared.reset([
            "https://api.bgm.tv/v0/subjects/8": .init(status: 200, data: challenge),
            "https://api.first.test/v0/subjects/8": .init(status: 200, data: subject)
        ])
        let fallback = try await api.get("/v0/subjects/8", as: Subject.self)
        precondition(fallback.id == 8 && MirrorRequests.shared.requests.count == 2)
        print("PASS: a verification page is rejected as API data and public reads fall back")

        isolated.update(first, etag: "v1")
        isolated.resetHealth()
        MirrorRequests.shared.reset(["https://api.bgm.tv/v0/users/me/collections/8": .init(status: 503, data: Data("{}".utf8))])
        struct Change: Encodable, Sendable { let type: Int }
        do {
            try await api.patch("/v0/users/me/collections/8", body: Change(type: 3), auth: false)
            preconditionFailure("A failed mutation must surface its error")
        } catch APIError.server { }
        precondition(MirrorRequests.shared.requests.count == 1)
        print("PASS: uncertain write failures are never replayed on another host")

        isolated.update(first, etag: "v1")
        isolated.resetHealth()
        MirrorRequests.shared.reset(["https://api.bgm.tv/v0/me": .init(status: 401, data: Data("{}".utf8))])
        do {
            let _: User = try await api.get("/v0/me", as: User.self)
            preconditionFailure("401 must retain its authentication meaning")
        } catch APIError.unauthorized { }
        precondition(MirrorRequests.shared.requests.count == 1)
        isolated.resetHealth()

        MirrorRequests.shared.reset([
            "https://first.test/blog": .init(status: 200, data: challenge),
            "https://bgm.tv/blog": .init(status: 200, data: Data("<html>real blog content</html>".utf8))
        ])
        let html = try await api.rawHTML(URL(string: "https://bgm.tv/blog")!, cacheKey: "blog")
        precondition(html.contains("real blog content"))
        precondition(MirrorRequests.shared.requests.map { $0.url!.host! } == ["bgm.tv"], "Public HTML must try the working official site before challenged mirrors")
        let saved = await cache.readStale("blog")
        precondition(saved.map { !MirrorRouting.isVerificationPage($0) } == true)
        isolated.update(first, etag: "v1")
        isolated.resetHealth()
        MirrorRequests.shared.reset([
            "https://first.test/group": .init(status: 200, data: challenge),
            "https://bgm.tv/group": .init(status: 200, data: challenge)
        ])
        do {
            _ = try await api.rawHTML(URL(string: "https://bgm.tv/group")!, cacheKey: "group")
            preconditionFailure("Verification must not become an empty social page")
        } catch APIError.verificationRequired { }
        let badCache = await cache.readStale("group")
        precondition(badCache == nil)
        isolated.update(first, etag: "v1")
        isolated.resetHealth()
        let poisoned = Data("<html>login wall</html>".utf8)
        let valid = Data("<div id='content'>正文</div>".utf8)
        await cache.write("validated", data: poisoned)
        MirrorRequests.shared.reset([
            "https://bgm.tv/validated": .init(status: 200, data: poisoned),
            "https://first.test/validated": .init(status: 200, data: valid)
        ])
        let recovered = try await api.rawHTML(URL(string: "https://bgm.tv/validated")!, cacheKey: "validated") {
            guard $0.contains("id='content'") else { throw APIError.message("Unreadable content") }
        }
        precondition(recovered.contains("正文") && MirrorRequests.shared.requests.count == 2)
        let cachedValid = await cache.readStale("validated")
        precondition(cachedValid == valid, "Only validated content can replace the poisoned cache")
        await cache.write("invalid-stale", data: poisoned)
        MirrorRequests.shared.reset([:])
        do {
            _ = try await api.rawHTML(URL(string: "https://bgm.tv/unavailable")!, cacheKey: "invalid-stale", ttl: 0) {
                guard $0.contains("id='content'") else { throw APIError.message("Unreadable content") }
            }
            preconditionFailure("Invalid stale HTML must not masquerade as an empty page")
        } catch { }
        await cache.clear()
        print("PASS: official HTML first, verified mirror fallback, poisoned-cache recovery and invalid stale rejection")

        if CommandLine.arguments.contains("--live") {
            let liveRouting = MirrorRouting()
            let liveCache = DiskCache(namespace: "BgmoriMirrorLive-\(UUID())")
            let live = APIClient(cache: liveCache, routing: liveRouting)
            await live.prepareMirrors()
            let host = liveRouting.preferredURL(for: URL(string: "https://api.bgm.tv")!).host!
            precondition(liveRouting.candidates(for: URL(string: "https://api.bgm.tv")!).count > 1, "Live directory must contain mirror candidates")
            let item = try await live.get("/v0/subjects/8", as: Subject.self)
            precondition(item.id == 8)
            let cover = liveRouting.preferredURL(for: Images.normalized(item.images?.common)!)
            let loader = ImageLoader(routing: liveRouting)
            let image = await loader.image(for: cover, maxPixel: 597)
            precondition(image != nil)
            await liveCache.clear()
            print("PASS: live directory, subject JSON and decoded cover on \(host)")
        }
    }
}
