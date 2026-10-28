import Foundation
import CFNetwork

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date()
    func now() -> Date { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value = value.addingTimeInterval(seconds) } }
}

private final class Requests: @unchecked Sendable {
    struct Reply: Sendable {
        var status: Int = 200
        var data = Data(#"{"id":8,"name":"test","type":2}"#.utf8)
        var hang = false
    }
    static let shared = Requests()
    private let lock = NSLock()
    private var replies: [String: Reply] = [:]
    private var recorded: [URLRequest] = []
    func reset(_ replies: [String: Reply]) { lock.withLock { self.replies = replies; recorded = [] } }
    func reply(_ request: URLRequest) -> Reply {
        lock.withLock { recorded.append(request); return replies[request.url!.absoluteString] ?? Reply(status: 503) }
    }
    var requests: [URLRequest] { lock.withLock { recorded } }
}

private final class Stub: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let reply = Requests.shared.reply(request)
        guard !reply.hang else { return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: reply.status,
                                                            httpVersion: "HTTP/1.1", headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private actor Peak {
    var count = 0
    var maximum = 0
    func enter() { count += 1; maximum = max(maximum, count) }
    func leave() { count -= 1 }
}

@main
struct ConnectionTests {
    static func catalog() throws -> MirrorCatalog {
        try JSONDecoder().decode(MirrorCatalog.self, from: Data(#"{"mirrors":[{"id":"test","weight":1,"recommended":true,"services":[{"id":"api","hosts":["api.mirror.test"]},{"id":"lain","hosts":["lain.mirror.test"]},{"id":"main","hosts":["mirror.test"]}]}]}"#.utf8))
    }

    static func main() async throws {
        let apiURL = URL(string: "https://api.bgm.tv/v0/subjects/8")!
        let proxySettings = ["HTTPSEnable": 1, "HTTPSProxy": "127.0.0.1", "HTTPSPort": 6152] as [String: Any]
        precondition(SystemProxyRouting.isEnabled(for: apiURL, settings: proxySettings as CFDictionary))
        var excludedSettings = proxySettings
        excludedSettings["ExceptionsList"] = ["*.bgm.tv"]
        precondition(!SystemProxyRouting.isEnabled(for: apiURL, settings: excludedSettings as CFDictionary))
        precondition(!SystemProxyRouting.isEnabled(for: apiURL, settings: [:] as CFDictionary))
        let pac = ["ProxyAutoConfigEnable": 1, "ProxyAutoConfigURLString": "https://proxy.test/proxy.pac"] as [String: Any]
        precondition(SystemProxyRouting.isEnabled(for: apiURL, settings: pac as CFDictionary))
        print("PASS: system proxy detection respects HTTPS, PAC, absent proxies and per-URL direct exceptions")

        let clock = TestClock()
        let routing = MirrorRouting(now: { clock.now() }, systemProxy: { _ in false })
        routing.update(try catalog(), etag: "test")
        let mirror = URL(string: "https://api.mirror.test/v0/subjects/8")!
        let cover = URL(string: "https://lain.bgm.tv/pic/cover/l/a.jpg")!
        precondition(routing.candidates(for: apiURL).first == apiURL)
        routing.record(apiURL, milliseconds: 5, result: "超时", succeeded: false)
        precondition(routing.candidates(for: apiURL, forRequest: true).first == mirror)
        routing.record(mirror, milliseconds: 10, result: "成功", succeeded: true)
        precondition(routing.candidates(for: apiURL).first == mirror)
        precondition(routing.candidates(for: cover).first == cover, "Image health must be independent of API health")
        precondition(routing.candidates(for: apiURL, credentials: true) == [apiURL])
        clock.advance(1801)
        precondition(routing.candidates(for: apiURL, forRequest: true).first == apiURL, "Fallback stickiness must expire")
        let oldRevision = routing.revision
        routing.resetHealth()
        routing.record(mirror, milliseconds: 0, result: "old", succeeded: true, revision: oldRevision)
        precondition(routing.diagnostics.isEmpty && routing.candidates(for: apiURL).first == apiURL)
        print("PASS: official priority, service isolation, cooldown, expiring stickiness and stale-generation rejection")

        routing.networkChanged(offline: false, signature: "wifi")
        routing.record(apiURL, milliseconds: 1, result: "failure", succeeded: false)
        routing.networkChanged(offline: true, signature: "offline")
        precondition(routing.offline)
        routing.networkChanged(offline: false, signature: "cellular")
        precondition(!routing.offline && routing.candidates(for: apiURL, forRequest: true).first == apiURL)
        print("PASS: network changes clear route failures and restore official probing")

        let persistedURL = FileManager.default.temporaryDirectory.appendingPathComponent("connection-settings-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: persistedURL) }
        let persistent = MirrorRouting(persistenceURL: persistedURL)
        try persistent.configure(ConnectionSettings(mode: .custom, customRoot: "own.example.com"))
        let restoredSettings = MirrorRouting(persistenceURL: persistedURL)
        precondition(restoredSettings.settings.mode == .custom && restoredSettings.settings.customRoot == "own.example.com")
        precondition(restoredSettings.canonicalURL(for: URL(string: "https://api.own.example.com/v0/me")!).host == "api.bgm.tv")
        print("PASS: connection preferences persist and cached custom URLs remain canonicalizable")

        try routing.configure(ConnectionSettings(mode: .custom, customRoot: "https://own.example.com/"))
        precondition(routing.candidates(for: apiURL, credentials: true).map(\.host) == ["api.own.example.com", "api.bgm.tv"])
        try routing.configure(ConnectionSettings(mode: .official))
        precondition(routing.candidates(for: apiURL) == [apiURL])
        for invalid in ["http://own.test", "https://own.test/path", "https://user@own.test", "https://own.test?secret=x", "https://own.test:444", "api.bgm.tv"] {
            precondition(MirrorRouting.normalizedRoot(invalid) == nil)
        }
        try routing.configure(ConnectionSettings())
        print("PASS: official/custom modes and root-domain validation; community mirrors never receive credentials")

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Stub.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let cache = DiskCache(namespace: "ConnectionTests-\(UUID())")
        defer { Task { await cache.clear() } }
        let api = APIClient(session: session, cache: cache, routing: routing, discoverMirrors: false)
        let credential = UUID().uuidString
        await api.setToken(credential)
        Requests.shared.reset([apiURL.absoluteString: .init(status: 503), mirror.absoluteString: .init()])
        do { let _: Subject = try await api.get("/v0/subjects/8", as: Subject.self, auth: true); preconditionFailure() }
        catch APIError.server { }
        precondition(Requests.shared.requests.count == 1 && Requests.shared.requests[0].url?.host == "api.bgm.tv")
        precondition(Requests.shared.requests[0].value(forHTTPHeaderField: "Authorization") != nil)
        routing.resetHealth()
        Requests.shared.reset(["https://bgm.tv/FollowTheRabbit": .init(status: 503)])
        let loginRoutes = await api.webLoginRoutes()
        let loginResponse = try await api.webLoginRequest(URL(string: "https://bgm.tv/FollowTheRabbit")!, method: "POST", route: loginRoutes[0])
        precondition(loginResponse.response.statusCode == 503)
        precondition(Requests.shared.requests.count == 1 && Requests.shared.requests[0].url?.host == "bgm.tv")
        precondition(!routing.diagnostics.contains { $0.result.contains(credential) || $0.host.contains(credential) })
        print("PASS: bearer and login forms stay on official hosts and never replay failed writes")

        let delegate = ConnectionSessionDelegate()
        var protected = URLRequest(url: apiURL)
        protected.setValue(credential, forHTTPHeaderField: "Authorization")
        let redirectResponse = HTTPURLResponse(url: apiURL, statusCode: 307, httpVersion: nil, headerFields: nil)!
        let redirected: URLRequest? = await withCheckedContinuation { continuation in
            delegate.urlSession(session, task: session.dataTask(with: protected), willPerformHTTPRedirection: redirectResponse,
                                newRequest: URLRequest(url: mirror)) { continuation.resume(returning: $0) }
        }
        precondition(redirected == nil)
        let downgraded: URLRequest? = await withCheckedContinuation { continuation in
            delegate.urlSession(session, task: session.dataTask(with: apiURL), willPerformHTTPRedirection: redirectResponse,
                                newRequest: URLRequest(url: URL(string: "http://api.bgm.tv/a")!)) { continuation.resume(returning: $0) }
        }
        precondition(downgraded == nil)
        print("PASS: credential redirects cannot cross hosts and HTTPS cannot downgrade")

        routing.resetHealth()
        Requests.shared.reset([apiURL.absoluteString: .init(status: 429, data: Data("not json".utf8))])
        do { let _: Subject = try await api.get("/v0/subjects/8", as: Subject.self); preconditionFailure() }
        catch APIError.rateLimited { }
        precondition(Requests.shared.requests.count == 1 && routing.candidates(for: apiURL, forRequest: true).first == apiURL)
        precondition(routing.diagnostics.first?.result == "请求限流（429）")
        print("PASS: rate limiting preserves semantics and does not punish a reachable route")

        Requests.shared.reset([apiURL.absoluteString: .init(hang: true)])
        let started = Date()
        do {
            _ = try await ConnectionTransport.data(for: URLRequest(url: apiURL), session: session, timeout: 0.1)
            preconditionFailure()
        } catch let error as URLError { precondition(error.code == .timedOut) }
        precondition(Date().timeIntervalSince(started) < 1, "A silent connection must respect its elapsed-time budget")
        await cache.write("cancel", data: Data(#"{"id":8,"type":2}"#.utf8))
        let cancelled = Task { try await api.get("/v0/subjects/8", as: Subject.self, cacheKey: "cancel") }
        try await Task.sleep(for: .milliseconds(80))
        cancelled.cancel()
        do { _ = try await cancelled.value; preconditionFailure("Cancellation must not return a stale success") }
        catch APIError.cancelled { }
        print("PASS: hard request deadline and cancellation propagate without stale-cache masking")

        let freshRouting = MirrorRouting()
        Requests.shared.reset([MirrorRouting.directoryURL.absoluteString: .init(hang: true), apiURL.absoluteString: .init()])
        let nonblocking = APIClient(session: session, cache: cache, routing: freshRouting)
        let start = Date()
        let item: Subject = try await nonblocking.get("/v0/subjects/8", as: Subject.self)
        precondition(item.id == 8 && Date().timeIntervalSince(start) < 1.5)
        print("PASS: a stalled mirror directory does not block a working official request")

        let limiter = RateLimiter(interval: 0.15)
        try await limiter.wait()
        do { try await limiter.wait(maxDelay: 0.02); preconditionFailure() }
        catch let error as URLError { precondition(error.code == .timedOut) }
        let waiting = Task { try await limiter.wait() }
        try await Task.sleep(for: .milliseconds(20))
        waiting.cancel()
        do { try await waiting.value; preconditionFailure() } catch is CancellationError { }
        try await Task.sleep(for: .milliseconds(160))
        try await limiter.wait(maxDelay: 0.02)
        print("PASS: rate-limiter waits respect request budgets and cancelled callers reserve no future slots")

        let gate = ImageDownloadGate(limit: 4)
        let peak = Peak()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    guard await gate.acquire() else { return }
                    await peak.enter()
                    try? await Task.sleep(for: .milliseconds(20))
                    await peak.leave()
                    await gate.release()
                }
            }
        }
        let maximum = await peak.maximum
        precondition(maximum == 4)
        let single = ImageDownloadGate(limit: 1)
        let initialSlot = await single.acquire()
        precondition(initialSlot)
        let queued = Task { await single.acquire() }
        try await Task.sleep(for: .milliseconds(20))
        queued.cancel()
        let obtained = await queued.value
        precondition(!obtained)
        await single.release()
        let recoveredSlot = await single.acquire()
        precondition(recoveredSlot)
        await single.release()
        print("PASS: image concurrency is bounded and cancelled waiters cannot leak slots")

        let subject = try JSONDecoder().decode(Subject.self, from: Data(#"{"id":8,"type":2,"name":"cache","infobox":[{"key":"别名","value":[{"v":"a"},{"v":"b"}]}],"rating":{"score":8.5},"images":{"large":"https://lain.bgm.tv/a.jpg"}}"#.utf8))
        let restored = try JSONDecoder().decode(Subject.self, from: JSONEncoder().encode(subject))
        precondition(restored.infobox.first?.value.display == "a / b" && restored.rating?.score == 8.5 && restored.heroURL == subject.heroURL)
        print("PASS: startup snapshot encoding preserves API-shaped subject details")
        if CommandLine.arguments.contains("--live") {
            MirrorRouting.applyEncryptedDNS(true)
            defer { MirrorRouting.applyEncryptedDNS(false) }
            let native = URLSessionConfiguration.ephemeral
            native.waitsForConnectivity = false
            let live = URLSession(configuration: native, delegate: ConnectionSessionDelegate(), delegateQueue: nil)
            defer { live.invalidateAndCancel() }
            var request = URLRequest(url: apiURL)
            request.assumesHTTP3Capable = false
            request.setValue(APIClient.userAgent, forHTTPHeaderField: "User-Agent")
            let (data, response) = try await ConnectionTransport.data(for: request, session: live, timeout: 12)
            let item = try JSONDecoder().decode(Subject.self, from: data)
            precondition((response as? HTTPURLResponse)?.statusCode == 200 && item.id == 8)
            print("PASS live: app-only native encrypted-DNS configuration and a fresh certificate-validated official API connection")
        }
        await cache.clear()
    }
}
