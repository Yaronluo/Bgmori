import Foundation

private final class ProxyState: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var enabled: Bool {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

private final class ProxyMetrics: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var hosts: Set<String> = []
    var proxyHosts: Set<String> { lock.withLock { hosts } }
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        lock.withLock {
            for transaction in metrics.transactionMetrics where transaction.isProxyConnection {
                if let host = transaction.request.url?.host { hosts.insert(host) }
            }
        }
    }
}

@main struct ECHTests {
    static func main() async throws {
        precondition(MirrorRouting.echAvailable)
        let routing = MirrorRouting()
        try routing.configure(ConnectionSettings(mode: .encrypted), persistChanges: false)
        let apiURL = URL(string: "https://api.bgm.tv/v0/subjects/8")!
        let candidates = routing.candidates(for: apiURL, credentials: true)
        precondition(candidates.count == 1 && candidates.allSatisfy { MirrorRouting.isECHHost($0.host) })
        precondition(routing.canonicalURL(for: candidates[0]) == apiURL)
        precondition(!MirrorRouting.isECHHost(routing.preferredURL(for: apiURL).host), "An external browser must never receive the internal ECH marker")
        precondition(MirrorRouting.echOrigin(for: URL(string: "https://api.bgm-tv.ech.invalid:444/a")!) == nil)
        precondition(MirrorRouting.echOrigin(for: URL(string: "https://evil.bgm-tv.ech.invalid/a")!) == nil)
        print("PASS: strict ECH mode has no ordinary or mirror fallback; credentials stay on authenticated official hosts")

        let proxy = ProxyState()
        let automatic = MirrorRouting(systemProxy: { _ in proxy.enabled })
        let encryptedAPI = MirrorRouting.encryptedURL(for: apiURL)!
        precondition(automatic.candidates(for: apiURL).first == encryptedAPI)
        automatic.record(encryptedAPI, milliseconds: 1, result: "success", succeeded: true)
        automatic.markUnavailable(apiURL)
        proxy.enabled = true
        for host in ["api.bgm.tv", "lain.bgm.tv", "bgm.tv", "next.bgm.tv"] {
            let url = URL(string: "https://\(host)/")!
            precondition(automatic.candidates(for: url, forRequest: true).first == url)
            precondition(automatic.candidates(for: url, credentials: true).first == url)
        }
        precondition(automatic.candidates(for: apiURL, forRequest: true).first == apiURL,
                     "Enabling a proxy must override both ECH stickiness and old official cooldowns")
        let loginAPI = APIClient(routing: automatic, discoverMirrors: false)
        let loginRoutes = await loginAPI.webLoginRoutes()
        precondition(loginRoutes.first?.encrypted == false)
        automatic.markUnavailable(apiURL)
        precondition(automatic.candidates(for: apiURL, forRequest: true).first == encryptedAPI,
                     "A failed system connection must retain ECH fallback")
        automatic.record(apiURL, milliseconds: 1, result: "success", succeeded: true)
        proxy.enabled = false
        precondition(automatic.candidates(for: apiURL, forRequest: true).first == encryptedAPI,
                     "Disabling the proxy must stop reusing a formerly proxied official route")
        proxy.enabled = true
        try automatic.configure(ConnectionSettings(mode: .official), persistChanges: false)
        precondition(automatic.candidates(for: apiURL, credentials: true) == [apiURL, encryptedAPI])
        try automatic.configure(ConnectionSettings(mode: .encrypted), persistChanges: false)
        precondition(automatic.candidates(for: apiURL, credentials: true) == [encryptedAPI])
        try automatic.configure(ConnectionSettings(mode: .custom, customRoot: "own.example.com"), persistChanges: false)
        precondition(automatic.candidates(for: apiURL).first?.host == "api.own.example.com")
        print("PASS: proxy on/off changes API, image, HTML and login priority; ECH fallback and explicit modes remain intact")

        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "https://api.bgm-tv.ech.invalid/a")!)
        request.httpMethod = "UNKNOWN"
        do {
            _ = try await ECHTransport.data(for: request, timeout: 1)
            preconditionFailure("Unsupported methods must fail closed")
        } catch let failure as ECHFailure { precondition(failure.code == "UNSUPPORTED_METHOD") }
        print("PASS: bridge rejects unsupported requests instead of using a plain connection")

        if CommandLine.arguments.contains("--live-proxy") {
            try await checkSystemProxy(apiURL: apiURL)
        }

        if CommandLine.arguments.contains("--live") {
            let cancellation = Task {
                let request = URLRequest(url: URL(string: "https://api.bgm-tv.ech.invalid/v0/subjects/8")!)
                return try await ECHTransport.data(for: request, timeout: 30)
            }
            try await Task.sleep(for: .milliseconds(30))
            let cancelledAt = Date()
            cancellation.cancel()
            do { _ = try await cancellation.value; preconditionFailure("Cancelled ECH request returned a response") }
            catch let error as URLError { precondition(error.code == .cancelled) }
            catch is CancellationError { }
            precondition(Date().timeIntervalSince(cancelledAt) < 2)
            precondition(ECHTransport.info?.activeRequests == 0)
            print("PASS: Swift cancellation reaches the embedded HTTP request and releases its context")

            for host in ["api.bgm-tv.ech.invalid", "bgm-tv.ech.invalid", "lain.bgm-tv.ech.invalid"] {
                var request = URLRequest(url: URL(string: "https://\(host)/cdn-cgi/trace")!)
                request.setValue(APIClient.userAgent, forHTTPHeaderField: "User-Agent")
                let (data, response) = try await ConnectionTransport.data(for: request, session: session, timeout: 18)
                let trace = String(decoding: data, as: UTF8.self).split(separator: "\n")
                precondition((response as? HTTPURLResponse)?.statusCode == 200)
                precondition(trace.contains("sni=encrypted"), "A successful HTTP response alone is insufficient evidence")
                let country = trace.first { $0.hasPrefix("loc=") } ?? "loc=unknown"
                print("PASS live: \(response.url!.host!) \(country) sni=encrypted")
            }
            let api = APIClient(session: session, routing: routing, discoverMirrors: false)
            let subject: Subject = try await api.get("/v0/subjects/8", as: Subject.self, force: true)
            precondition(subject.id == 8)
            let page = try await api.rawHTML(URL(string: "https://bgm.tv/subject/8")!, cacheKey: "ech-test-subject", force: true)
            precondition(page.contains("subject_inner_info") || page.contains("headerSubject"))
            let loader = ImageLoader(routing: routing)
            let cover = await loader.checkConnection(subject.heroURL!)
            precondition(cover)
            precondition(ConnectionService.allCases.allSatisfy { service in routing.diagnostics.first { $0.service == service }?.encrypted == true })
            let info = ECHTransport.info!
            precondition(info.proxyDisabled && info.acceptedConnections >= 3)
            precondition(info.directInterface.hasPrefix("en") || info.directInterface.hasPrefix("pdp_ip"))
            print("PASS live: real subject, HTML and decoded cover; accepted=\(info.acceptedConnections), physicalInterface=\(info.directInterface), proxyDisabled=true")
        }
    }

    static func checkSystemProxy(apiURL: URL) async throws {
        guard SystemProxyRouting.isEnabled(for: apiURL) else {
            print("SKIP live proxy: this environment has no applicable system proxy")
            return
        }
        let routing = MirrorRouting()
        let metrics = ProxyMetrics()
        let session = URLSession(configuration: .ephemeral, delegate: metrics, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let cache = DiskCache(namespace: "ProxyLiveTests-\(UUID())")
        let api = APIClient(session: session, cache: cache, routing: routing, discoverMirrors: false)
        let started = Date()
        let subject: Subject = try await api.get("/v0/subjects/8", as: Subject.self, force: true)
        precondition(subject.id == 8)
        let page = try await api.rawHTML(URL(string: "https://bgm.tv/subject/8")!, cacheKey: "subject", force: true)
        precondition(page.contains("subject_inner_info") || page.contains("headerSubject"))
        let loader = ImageLoader(session: session, routing: routing)
        let cover = await loader.checkConnection(subject.heroURL!)
        precondition(cover)
        precondition(ConnectionService.allCases.allSatisfy { service in
            routing.diagnostics.first { $0.service == service }.map { $0.succeeded && !$0.encrypted } == true
        })
        precondition(metrics.proxyHosts.isSuperset(of: ["api.bgm.tv", "bgm.tv", "lain.bgm.tv"]),
                     "Success alone is insufficient: URLSession must confirm proxy use for all three services")
        let routes = await api.webLoginRoutes()
        precondition(routes.first?.encrypted == false)
        let login = try await api.webLoginRequest(URL(string: "https://bgm.tv/login")!, route: routes[0])
        precondition(login.response.statusCode == 200)
        await cache.clear()
        print("PASS live proxy: real subject, HTML, decoded cover and login page; URLSession confirms proxy use for API/images/web; seconds=\(String(format: "%.2f", Date().timeIntervalSince(started)))")
    }
}
