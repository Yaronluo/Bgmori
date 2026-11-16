import Foundation

/// A decoded cache hit. `isFresh` is false when the TTL has expired but the
/// entry is still inside the endpoint's display window; callers can show it
/// immediately and refresh in the background.
struct CacheHit<Value: Sendable>: Sendable {
    let value: Value
    let cacheKey: String
    let age: TimeInterval
    let isFresh: Bool
}

/// Refresh windows are deliberately finite: an expired entry can be shown
/// while it is being revalidated, but it is never shown forever.
enum CacheLifetime {
    static let staticReference: TimeInterval = 30 * 86_400
    static let publicCatalog: TimeInterval = 7 * 86_400
    static let personal: TimeInterval = 7 * 86_400
    static let socialHTML: TimeInterval = 7 * 86_400
}

private actor BackgroundRefreshGate {
    private var lastAttempt: [String: Date] = [:]

    func allow(_ key: String, minimumInterval: TimeInterval) -> Bool {
        let now = Date()
        if let last = lastAttempt[key], now.timeIntervalSince(last) < minimumInterval {
            return false
        }
        lastAttempt[key] = now
        if lastAttempt.count > 500 {
            lastAttempt = lastAttempt.filter { now.timeIntervalSince($0.value) < 86_400 }
        }
        return true
    }
}

/// Coalesces identical read-only network requests. The shared Task is owned by
/// this actor, not by a view, so cancelling one waiter does not cancel a request
/// that another caller is still using.
private actor RequestCoalescer {
    private struct Entry {
        let id: UUID
        let task: Task<Data, Error>
    }

    private var tasks: [String: Entry] = [:]

    func data(for key: String, operation: @escaping @Sendable () async throws -> Data) async throws -> Data {
        let entry: Entry
        if let existing = tasks[key] {
            entry = existing
        } else {
            entry = Entry(id: UUID(), task: Task { try await operation() })
            tasks[key] = entry
        }
        do {
            let data = try await entry.task.value
            if tasks[key]?.id == entry.id { tasks[key] = nil }
            return data
        } catch {
            if tasks[key]?.id == entry.id { tasks[key] = nil }
            throw error
        }
    }
}

actor APIClient {
    static let shared = APIClient()

    private let apiBase = URL(string: "https://api.bgm.tv")!
    private let session: URLSession
    private let loginSession: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    let cache: DiskCache
    private let limiter = RateLimiter(interval: 0.22)
    private let htmlLimiter = RateLimiter(interval: 2.0)
    private var token: String?
    private var sessionID = UUID()
    private let refreshGate = BackgroundRefreshGate()
    private let coalescer = RequestCoalescer()
    private let routing: MirrorRouting
    private let discoverMirrors: Bool
    private var mirrorRefresh: Task<Void, Never>?
    private var nextMirrorAttempt = Date.distantPast
    private var lastRoutingRevision = -1

    init(session: URLSession? = nil, cache: DiskCache = DiskCache(),
         routing: MirrorRouting = .shared, discoverMirrors: Bool = true) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = false
        configuration.httpShouldSetCookies = false
        // Reads always bypass URLSession's cache (`.reloadIgnoringLocalCacheData`)
        // and DiskCache owns freshness, so a second copy here would only waste disk.
        configuration.urlCache = nil
        self.session = session ?? URLSession(configuration: configuration, delegate: ConnectionSessionDelegate(), delegateQueue: nil)
        let loginConfiguration = URLSessionConfiguration.ephemeral
        loginConfiguration.httpShouldSetCookies = false
        loginConfiguration.httpCookieStorage = nil
        loginConfiguration.urlCache = nil
        loginConfiguration.waitsForConnectivity = false
        loginConfiguration.timeoutIntervalForRequest = 20
        loginConfiguration.timeoutIntervalForResource = 30
        loginSession = session ?? URLSession(configuration: loginConfiguration, delegate: WebLoginRedirectDelegate(), delegateQueue: nil)
        self.cache = cache
        self.routing = routing
        self.discoverMirrors = discoverMirrors
    }

    func setToken(_ token: String?) {
        if token != self.token { sessionID = UUID() }
        self.token = token
    }

    func hasToken() -> Bool { token != nil }

    /// Non-secret data-source marker used to keep account snapshots from
    /// crossing between the official service and a configured custom root.
    func cacheScope() -> String {
        let settings = routing.settings
        switch settings.mode {
        case .custom:
            return "custom:\(settings.customRoot)"
        case .encrypted:
            return "encrypted"
        case .official:
            return "official"
        case .automatic:
            return "automatic"
        }
    }

    // MARK: - Cache-first reads

    /// Reads fresh or still-displayable stale data without touching the network.
    /// Callers render the hit immediately, then refresh only when `isFresh` is false.
    func cachedValue<T: Decodable & Sendable>(
        cacheKey: String,
        ttl: TimeInterval,
        maxStale: TimeInterval,
        as type: T.Type
    ) async -> CacheHit<T>? {
        guard !Task.isCancelled,
              let entry = await cache.readEntry(cacheKey, maxAge: ttl, maxStaleAge: maxStale),
              let value = try? decoder.decode(T.self, from: entry.data) else { return nil }
        return CacheHit(value: value, cacheKey: cacheKey, age: entry.age, isFresh: entry.isFresh)
    }

    /// Throttles automatic background refresh for a cache key. Explicit user
    /// refreshes must call `get(..., force: true)` and bypass this gate.
    func beginBackgroundRefresh(_ cacheKey: String, minimumInterval: TimeInterval = 60) async -> Bool {
        await refreshGate.allow(cacheKey, minimumInterval: minimumInterval)
    }

    // MARK: - Mirror discovery

    func prepareMirrors(force: Bool = false) async {
        guard discoverMirrors, routing.settings.mode == .automatic else { return }
        if lastRoutingRevision != routing.revision {
            nextMirrorAttempt = .distantPast
            lastRoutingRevision = routing.revision
        }
        if let mirrorRefresh {
            await mirrorRefresh.value
            return
        }
        guard force || (routing.needsRefresh && Date() >= nextMirrorAttempt) else { return }
        nextMirrorAttempt = Date().addingTimeInterval(300)
        let task = Task { await self.fetchMirrorCatalog() }
        mirrorRefresh = task
        await task.value
        mirrorRefresh = nil
    }

    private func waitForMirrorDiscovery(until deadline: Date) async throws {
        guard discoverMirrors, routing.settings.mode == .automatic, !routing.offline else { return }
        Task { await prepareMirrors() }
        // Waiting on a shared Task.value ignores cancellation of just this waiter.
        // Poll its state instead, so discovery cannot extend a page's total budget.
        while routing.needsRefresh, Date() < deadline {
            try Task.checkCancellation()
            if mirrorRefresh == nil, Date() < nextMirrorAttempt { return }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func fetchMirrorCatalog() async {
        do { try await limiter.wait(maxDelay: 2) } catch { return }
        var request = URLRequest(url: MirrorRouting.directoryURL)
        request.assumesHTTP3Capable = false
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let etag = routing.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        do {
            let (data, response) = try await ConnectionTransport.data(for: request, session: session, timeout: 8)
            guard let http = response as? HTTPURLResponse else { return }
            if http.statusCode == 304 {
                routing.revalidated()
            } else if http.statusCode == 200 {
                let catalog = try decoder.decode(MirrorCatalog.self, from: data)
                routing.update(catalog, etag: http.value(forHTTPHeaderField: "ETag"))
            }
        } catch {
            // Preserve the last usable directory when the publishing service is unavailable.
        }
    }

    func browserURL(_ url: URL) async -> URL {
        // Authorization is opened externally; never send it to a community mirror.
        routing.preferredURL(for: url, credentials: true)
    }

    func resetConnections() async {
        await session.reset()
        await loginSession.reset()
    }

    // Website authentication has an isolated, memory-only cookie jar owned by BangumiWebLogin.
    // It never enters the anonymous HTML cache, normal API transport or community mirrors.
    func webLoginRoutes() -> [WebLoginRoute] {
        routing.candidates(for: URL(string: "https://bgm.tv/login")!, credentials: true).compactMap { candidate in
            guard candidate.host == "bgm.tv" || MirrorRouting.isECHHost(candidate.host) else { return nil }
            return WebLoginRoute(encrypted: MirrorRouting.isECHHost(candidate.host), revision: routing.revision)
        }
    }

    func webLoginRequest(_ url: URL, method: String = "GET", route: WebLoginRoute,
                         cookie: String? = nil, bearer: String? = nil, body: Data? = nil,
                         contentType: String? = nil) async throws -> WebLoginHTTPResult {
        guard url.scheme == "https", url.port == nil, url.user == nil,
              ["bgm.tv", "next.bgm.tv", "api.bgm.tv"].contains(url.host),
              Self.webLoginEndpoint(url, method: method) else { throw APIError.invalidURL }
        return try await webRequest(
            url, method: method, route: route, cookie: cookie, bearer: bearer, body: body,
            contentType: contentType, accept: "*/*",
            origin: "https://" + (url.host ?? "bgm.tv"),
            referer: url.host == "next.bgm.tv" ? "https://next.bgm.tv/demo/access-token" : "https://bgm.tv/login",
            acceptLanguage: nil,
            routeChangedMessage: "连接设置已改变，请重新获取验证码"
        )
    }

    /// Credentialed HTML reads for the logged-in website session. Only the
    /// subject page and its collection-removal action are allowed, so the
    /// stored session cookie cannot be used for any other website operation.
    func webSessionRequest(_ url: URL, method: String = "GET", route: WebLoginRoute,
                           cookie: String?, referer: URL? = nil) async throws -> WebLoginHTTPResult {
        guard url.scheme == "https", url.port == nil, url.user == nil, url.host == "bgm.tv",
              Self.webSessionEndpoint(url, method: method) else { throw APIError.invalidURL }
        return try await webRequest(
            url, method: method, route: route, cookie: cookie, bearer: nil, body: nil,
            contentType: nil, accept: "text/html,application/xhtml+xml",
            origin: nil,
            referer: referer?.absoluteString ?? "https://bgm.tv/",
            acceptLanguage: "zh-CN,zh;q=0.9,ja;q=0.8,en;q=0.7",
            routeChangedMessage: "连接设置已改变，请重试"
        )
    }

    private func webRequest(_ url: URL, method: String, route: WebLoginRoute,
                            cookie: String?, bearer: String?, body: Data?,
                            contentType: String?, accept: String,
                            origin: String?, referer: String?,
                            acceptLanguage: String?,
                            routeChangedMessage: String) async throws -> WebLoginHTTPResult {
        try Task.checkCancellation()
        guard route.revision == routing.revision else { throw APIError.message(routeChangedMessage) }
        try await limiter.wait(maxDelay: 5)
        try Task.checkCancellation()
        let target: URL
        if route.encrypted {
            guard let encrypted = MirrorRouting.encryptedURL(for: url) else { throw APIError.invalidURL }
            target = encrypted
        } else { target = url }
        var request = URLRequest(url: target, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        request.httpMethod = method
        request.httpBody = body
        request.assumesHTTP3Capable = false
        request.httpShouldHandleCookies = false
        request.setValue(Self.safariUserAgent + " Bgmori/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let acceptLanguage { request.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language") }
        if let origin { request.setValue(origin, forHTTPHeaderField: "Origin") }
        if let referer { request.setValue(referer, forHTTPHeaderField: "Referer") }
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if let cookie { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        let result: WebLoginHTTPResult
        #if BGMORI_ECH
        if route.encrypted {
            result = try await ECHTransport.loginData(for: request, timeout: 25)
        } else {
            let (data, response) = try await ConnectionTransport.data(for: request, session: loginSession, timeout: 25)
            guard let http = response as? HTTPURLResponse else { throw APIError.network("登录服务响应无效") }
            result = WebLoginHTTPResult(data: data, response: http, setCookies: http.value(forHTTPHeaderField: "Set-Cookie").map { [$0] } ?? [])
        }
        #else
        guard !route.encrypted else { throw APIError.network("当前构建不支持加密直连") }
        let (data, response) = try await ConnectionTransport.data(for: request, session: loginSession, timeout: 25)
        guard let http = response as? HTTPURLResponse else { throw APIError.network("登录服务响应无效") }
        result = WebLoginHTTPResult(data: data, response: http, setCookies: http.value(forHTTPHeaderField: "Set-Cookie").map { [$0] } ?? [])
        #endif
        try Task.checkCancellation()
        guard route.revision == routing.revision else { throw APIError.message(routeChangedMessage) }
        if result.response.statusCode == 429 { throw APIError.rateLimited }
        if MirrorRouting.isVerificationPage(result.data) { throw APIError.verificationRequired }
        return result
    }

    private static func webSessionEndpoint(_ url: URL, method: String) -> Bool {
        guard method == "GET",
              url.path.range(of: #"^/subject/\d+(?:/(?:erase_collect|remove))?$"#,
                             options: .regularExpression) != nil else { return false }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return query.allSatisfy { item in
            if item.name == "ajax" { return item.value == "1" }
            guard item.name == "gh", let value = item.value else { return false }
            return value.range(of: #"^[A-Za-z0-9]+$"#, options: .regularExpression) != nil
        }
    }

    private static func webLoginEndpoint(_ url: URL, method: String) -> Bool {
        switch url.host {
        case "bgm.tv":
            return method == "GET" && ["/login", "/signup/captcha"].contains(url.path)
                || method == "POST" && url.path == "/FollowTheRabbit"
        case "next.bgm.tv":
            return method == "GET" && url.path == "/demo/access-token"
                || ["POST", "DELETE"].contains(method) && url.path == "/demo/access-tokens"
        case "api.bgm.tv": return method == "GET" && url.path == "/v0/me"
        default: return false
        }
    }

    func checkAPIConnection() async throws -> Subject {
        try await get("/v0/subjects/8", as: Subject.self, force: true)
    }

    func checkWebConnection() async throws {
        _ = try await rawHTML(URL(string: "https://bgm.tv/subject/8")!, cacheKey: "connection-check-web", validate: {
            guard $0.contains("id=\"headerSubject\"") || $0.contains("id=\"subject_inner_info\"") else {
                throw APIError.message("网页内容无法识别")
            }
        }, force: true)
    }

    // MARK: - Public GET

    func get<T: Decodable & Sendable>(
        _ path: String,
        query: [URLQueryItem] = [],
        as type: T.Type,
        cacheKey: String? = nil,
        ttl: TimeInterval = 0,
        maxStale: TimeInterval = CacheLifetime.publicCatalog,
        auth: Bool = false,
        force: Bool = false
    ) async throws -> T {
        if Task.isCancelled { throw APIError.cancelled }
        if !force, let cacheKey, ttl > 0, let data = await cache.read(cacheKey, maxAge: ttl) {
            if let value = try? decoder.decode(T.self, from: data) { return value }
        }

        do {
            let data = try await requestData(path: path, method: "GET", query: query, body: nil, auth: auth, coalesce: !force, resetBackoff: force)
            if Task.isCancelled { throw APIError.cancelled }
            if let cacheKey { await cache.write(cacheKey, data: data) }
            return try decode(T.self, from: data)
        } catch {
            if Task.isCancelled || Self.isCancellation(error) { throw APIError.cancelled }
            if !force, let cacheKey,
               let data = await cache.readStale(cacheKey, maxAge: max(maxStale, ttl)),
               let value = try? decoder.decode(T.self, from: data) {
                return value
            }
            throw error
        }
    }

    // MARK: - Public airing clock (no Bangumi credentials or mirror substitution)

    func cachedBgmlistSchedule() async -> CacheHit<BgmlistSchedule>? {
        await cachedValue(cacheKey: BgmlistSchedule.cacheKey, ttl: BgmlistSchedule.ttl,
                          maxStale: BgmlistSchedule.maxStale, as: BgmlistSchedule.self)
    }

    func bgmlistSchedule(force: Bool = false) async throws -> BgmlistSchedule {
        if Task.isCancelled { throw APIError.cancelled }
        if !force, let hit = await cachedBgmlistSchedule(), hit.isFresh { return hit.value }
        do {
            let data = try await requestData(
                path: "/api/v1/bangumi/onair", method: "GET", query: [], body: nil,
                auth: false, coalesce: !force, resetBackoff: force,
                base: URL(string: "https://bgmlist.com")!
            )
            if Task.isCancelled { throw APIError.cancelled }
            let value = try decode(BgmlistSchedule.self, from: data)
            await cache.write(BgmlistSchedule.cacheKey, data: data)
            return value
        } catch {
            if Task.isCancelled || Self.isCancellation(error) { throw APIError.cancelled }
            if !force, let hit = await cachedBgmlistSchedule() { return hit.value }
            throw error
        }
    }

    // MARK: - Mutations

    func post<B: Encodable & Sendable, T: Decodable & Sendable>(
        _ path: String,
        body: B,
        query: [URLQueryItem] = [],
        as type: T.Type,
        auth: Bool = true,
        cacheKey: String? = nil,
        ttl: TimeInterval = 0,
        maxStale: TimeInterval = CacheLifetime.publicCatalog,
        force: Bool = false
    ) async throws -> T {
        if Task.isCancelled { throw APIError.cancelled }
        // Only read-only search POSTs opt into caching.
        if !force, let cacheKey, ttl > 0, let data = await cache.read(cacheKey, maxAge: ttl),
           let value = try? decoder.decode(T.self, from: data) {
            return value
        }
        let data = try encoder.encode(body)
        do {
            let response = try await requestData(path: path, method: "POST", query: query, body: data, auth: auth, coalesce: !force, resetBackoff: force)
            if Task.isCancelled { throw APIError.cancelled }
            let value = try decode(T.self, from: response)
            if let cacheKey { await cache.write(cacheKey, data: response) }
            return value
        } catch {
            if Task.isCancelled || Self.isCancellation(error) { throw APIError.cancelled }
            if !force, let cacheKey, let cached = await cache.readStale(cacheKey, maxAge: max(maxStale, ttl)),
               let value = try? decoder.decode(T.self, from: cached) {
                return value
            }
            throw error
        }
    }

    func postNoContent<B: Encodable & Sendable>(_ path: String, body: B, auth: Bool = true) async throws {
        let data = try encoder.encode(body)
        _ = try await requestData(path: path, method: "POST", query: [], body: data, auth: auth)
    }

    func patch<B: Encodable & Sendable>(_ path: String, body: B, auth: Bool = true) async throws {
        let data = try encoder.encode(body)
        _ = try await requestData(path: path, method: "PATCH", query: [], body: data, auth: auth)
    }

    func put<B: Encodable & Sendable>(_ path: String, body: B, auth: Bool = true) async throws {
        let data = try encoder.encode(body)
        _ = try await requestData(path: path, method: "PUT", query: [], body: data, auth: auth)
    }

    func delete(_ path: String, auth: Bool = true) async throws {
        _ = try await requestData(path: path, method: "DELETE", query: [], body: nil, auth: auth)
    }

    // MARK: - HTML

    func rawHTML(_ url: URL, cacheKey: String, ttl: TimeInterval = 3600,
                 maxStale: TimeInterval = CacheLifetime.socialHTML,
                 validate: (@Sendable (String) throws -> Void)? = nil, force: Bool = false) async throws -> String {
        if Task.isCancelled { throw APIError.cancelled }
        if !force, let data = await cache.read(cacheKey, maxAge: ttl),
           !MirrorRouting.isVerificationPage(data),
           let html = String(data: data, encoding: .utf8),
           (try? validate?(html)) != nil || validate == nil {
            return html
        }

        do {
            if force { routing.resetBackoff(for: url) }
            Task { await prepareMirrors() }
            var lastError: Error = APIError.network("页面加载失败")
            let started = Date()
            let revision = routing.revision
            var attempted: Set<URL> = []
            for pass in 0..<2 {
                if pass == 1 { try await waitForMirrorDiscovery(until: started.addingTimeInterval(18)) }
                for candidate in routing.candidates(for: url, forRequest: true) where attempted.insert(candidate).inserted {
                    let remaining = 18 - Date().timeIntervalSince(started)
                    guard remaining > 0 else { throw lastError }
                    let attempt = Date()
                    do {
                        try Task.checkCancellation()
                        if routing.offline, !MirrorRouting.isECHHost(candidate.host) { throw URLError(.notConnectedToInternet) }
                        try await htmlLimiter.wait(maxDelay: remaining)
                        try Task.checkCancellation()
                        guard revision == routing.revision else { throw APIError.cancelled }
                        var request = URLRequest(url: candidate)
                        request.httpMethod = "GET"
                        request.assumesHTTP3Capable = false
                        request.timeoutInterval = min(remaining, routing.timeout(for: candidate))
                        request.setValue(Self.safariUserAgent + " Bgmori/1.0", forHTTPHeaderField: "User-Agent")
                        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
                        request.setValue("zh-CN,zh;q=0.9,ja;q=0.8,en;q=0.7", forHTTPHeaderField: "Accept-Language")
                        request.cachePolicy = .reloadIgnoringLocalCacheData
                        let (data, response) = try await ConnectionTransport.data(for: request, session: session,
                            timeout: min(routing.timeout(for: candidate), max(0.1, 18 - Date().timeIntervalSince(started))))
                        guard let http = response as? HTTPURLResponse else { throw APIError.network("无效的服务器响应") }
                        guard !MirrorRouting.isVerificationPage(data) else {
                            throw APIError.verificationRequired
                        }
                        if http.statusCode == 429 { throw APIError.rateLimited }
                        if http.statusCode == 404 { throw APIError.notFound }
                        guard (200...299).contains(http.statusCode) else {
                            throw APIError.server(http.statusCode, "页面加载失败（\(http.statusCode)）")
                        }
                        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS) else {
                            throw APIError.decoding("网页编码无法识别")
                        }
                        if html.contains("id=\"colunmNotice\""), html.contains("/img/bangumi/404.png") {
                            throw APIError.notFound
                        }
                        try validate?(html)
                        routing.record(candidate, milliseconds: Int(Date().timeIntervalSince(attempt) * 1000),
                                       result: "连接成功", succeeded: true, revision: revision)
                        if Task.isCancelled { throw APIError.cancelled }
                        await cache.write(cacheKey, data: data)
                        return html
                    } catch {
                        if Self.isCancellation(error) { throw APIError.cancelled }
                        if case APIError.notFound = error { throw error }
                        if case APIError.rateLimited = error { throw error }
                        let penalize: Bool = {
                            if let failure = error as? APIError {
                                if case .server = failure { return false }
                                if case .verificationRequired = failure { return false }
                            }
                            return true
                        }()
                        routing.record(candidate, milliseconds: Int(Date().timeIntervalSince(attempt) * 1000),
                                       result: (error as? APIError).map { failure in
                                           if case .verificationRequired = failure { return "需要网页验证" }
                                           return ConnectionTransport.failureDescription(error)
                                       } ?? ConnectionTransport.failureDescription(error), succeeded: false,
                                       revision: revision, penalize: penalize)
                        lastError = error
                        if routing.offline { throw error }
                    }
                }
            }
            throw lastError
        } catch {
            if Task.isCancelled || Self.isCancellation(error) { throw APIError.cancelled }
            if !force, let data = await cache.readStale(cacheKey, maxAge: max(maxStale, ttl)),
               !MirrorRouting.isVerificationPage(data),
               let html = String(data: data, encoding: .utf8),
               (try? validate?(html)) != nil || validate == nil {
                return html
            }
            throw error
        }
    }

    /// Returns a structurally valid cached HTML page without waiting for the
    /// network. The caller should render it and then refresh in the background.
    func cachedHTML(_ url: URL, cacheKey: String, ttl: TimeInterval = 3600,
                    maxStale: TimeInterval = CacheLifetime.socialHTML,
                    validate: (@Sendable (String) throws -> Void)? = nil) async -> CacheHit<String>? {
        guard !Task.isCancelled,
              let entry = await cache.readEntry(cacheKey, maxAge: ttl, maxStaleAge: maxStale),
              !MirrorRouting.isVerificationPage(entry.data),
              let html = String(data: entry.data, encoding: .utf8),
              (try? validate?(html)) != nil || validate == nil else { return nil }
        return CacheHit(value: html, cacheKey: cacheKey, age: entry.age, isFresh: entry.isFresh)
    }

    // MARK: - Core request

    private func requestData(
        path: String,
        method: String,
        query: [URLQueryItem],
        body: Data?,
        auth: Bool,
        coalesce: Bool = true,
        resetBackoff: Bool = false,
        base: URL? = nil,
        contentType: String = "application/json",
        accept: String = "application/json"
    ) async throws -> Data {
        let readOnly = method == "GET" || (method == "POST" && path.hasPrefix("/v0/search/"))
        guard coalesce, readOnly else {
            return try await performRequestData(path: path, method: method, query: query, body: body,
                                                auth: auth, resetBackoff: resetBackoff,
                                                base: base, contentType: contentType, accept: accept)
        }
        var key = "\(method)|\(path)|\(auth ? sessionID.uuidString : "public")"
        for item in query.sorted(by: { $0.name < $1.name }) {
            key += "|\(item.name)=\(item.value ?? "")"
        }
        if let body, let text = String(data: body, encoding: .utf8) { key += "|body=\(text)" }
        return try await coalescer.data(for: key) { [self] in
            try await performRequestData(path: path, method: method, query: query, body: body,
                                         auth: auth, resetBackoff: resetBackoff,
                                         base: base, contentType: contentType, accept: accept)
        }
    }

    private func performRequestData(
        path: String,
        method: String,
        query: [URLQueryItem],
        body: Data?,
        auth: Bool,
        resetBackoff: Bool,
        base: URL? = nil,
        contentType: String = "application/json",
        accept: String = "application/json"
    ) async throws -> Data {
        guard var components = URLComponents(url: (base ?? apiBase).appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.invalidURL }
        if resetBackoff { routing.resetBackoff(for: url) }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.assumesHTTP3Capable = false
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,ja;q=0.8,en;q=0.7", forHTTPHeaderField: "Accept-Language")

        if let body {
            request.httpBody = body
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }

        if auth {
            guard let token, !token.isEmpty else { throw APIError.unauthorized }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let sensitive = auth || path.hasPrefix("/oauth/")
        let canReplay = method == "GET" || (method == "POST" && path.hasPrefix("/v0/search/"))
        if !sensitive { Task { await prepareMirrors() } }
        let started = Date()
        let budget: TimeInterval = sensitive || !canReplay ? 30 : 18
        let revision = routing.revision
        var attempted: Set<URL> = []
        var lastError: Error = APIError.network("网络连接失败")
        for pass in 0..<(canReplay && !sensitive ? 2 : 1) {
            if pass == 1 { try await waitForMirrorDiscovery(until: started.addingTimeInterval(budget)) }
            let candidates = routing.candidates(for: url, forRequest: true, credentials: sensitive)
            for candidate in candidates where attempted.insert(candidate).inserted {
                guard Date().timeIntervalSince(started) < budget else { throw lastError }
                let attempt = Date()
                do {
                    try Task.checkCancellation()
                    if routing.offline, !MirrorRouting.isECHHost(candidate.host) { throw URLError(.notConnectedToInternet) }
                    try await limiter.wait(maxDelay: max(0, budget - Date().timeIntervalSince(started)))
                    try Task.checkCancellation()
                    guard revision == routing.revision else { throw APIError.cancelled }
                    request.url = candidate
                    let timeout = min(budget - Date().timeIntervalSince(started),
                                      canReplay ? routing.timeout(for: candidate, credentials: sensitive) : 30)
                    guard timeout > 0 else { throw URLError(.timedOut) }
                    request.timeoutInterval = timeout
                    let (data, response) = try await ConnectionTransport.data(for: request, session: session, timeout: timeout)
                    guard let http = response as? HTTPURLResponse else { throw APIError.network("无效的服务器响应") }
                    guard !MirrorRouting.isVerificationPage(data) else {
                        throw APIError.verificationRequired
                    }
                    // Preserve account and rate-limit semantics even when an error body is not JSON.
                    switch http.statusCode {
                    case 401: throw APIError.unauthorized
                    case 403: throw APIError.forbidden
                    case 404: throw APIError.notFound
                    case 429: throw APIError.rateLimited
                    default: break
                    }
                    guard data.isEmpty && (!canReplay || http.statusCode == 204)
                        || (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) != nil else {
                        throw APIError.network("服务器返回了无效的数据，请稍后重试。")
                    }
                    guard (200...299).contains(http.statusCode) else {
                        let detail = try? decoder.decode(ErrorDetail.self, from: data)
                        throw APIError.server(http.statusCode, detail?.description ?? detail?.title)
                    }
                    routing.record(candidate, milliseconds: Int(Date().timeIntervalSince(attempt) * 1000),
                                   result: "连接成功", succeeded: true, revision: revision)
                    return data
                } catch {
                    if Self.isCancellation(error) { throw APIError.cancelled }
                    let failure: APIError
                    if let error = error as? APIError { failure = error }
                    else if let error = error as? URLError { failure = APIError.from(urlError: error) }
                    else { failure = .network("网络连接失败") }
                    let retryable = failure.isRetryable && {
                        if case .rateLimited = failure { return false }
                        return true
                    }()
                    // An HTTP error means the route itself worked. Cooling the host
                    // down would make an unrelated immediate retry look like a
                    // network outage, so only transport failures penalize routes.
                    let penalize = retryable && {
                        if case .server = failure { return false }
                        if case .verificationRequired = failure { return false }
                        return true
                    }()
                    let result: String
                    switch failure {
                    case .unauthorized: result = "需要登录（401）"
                    case .forbidden: result = "没有权限（403）"
                    case .notFound: result = "内容不存在（404）"
                    case .rateLimited: result = "请求限流（429）"
                    case .verificationRequired: result = "需要网页验证"
                    case .server(let status, _): result = "服务错误（\(status)）"
                    default: result = ConnectionTransport.failureDescription(error)
                    }
                    routing.record(candidate, milliseconds: Int(Date().timeIntervalSince(attempt) * 1000),
                                   result: result, succeeded: false, revision: revision, penalize: penalize)
                    guard retryable, canReplay, !routing.offline else { throw failure }
                    lastError = failure
                }
            }
        }
        throw lastError
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
            || (error as? APIError).map { if case .cancelled = $0 { true } else { false } } == true
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    static var userAgent: String {
        #if os(macOS)
        "Bgmori/1.0 (macOS) (https://github.com/yaron/bgmori)"
        #else
        "Bgmori/1.0 (iOS) (https://github.com/yaron/bgmori)"
        #endif
    }

    static let safariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
}
