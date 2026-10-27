import Foundation

actor APIClient {
    static let shared = APIClient()

    private let apiBase = URL(string: "https://api.bgm.tv")!
    private let oauthBase = URL(string: "https://bgm.tv")!
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    let cache: DiskCache
    private let limiter = RateLimiter(interval: 0.22)
    private let htmlLimiter = RateLimiter(interval: 2.0)
    private var token: String?
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
        configuration.urlCache = URLCache(memoryCapacity: 32 * 1024 * 1024, diskCapacity: 128 * 1024 * 1024)
        self.session = session ?? URLSession(configuration: configuration, delegate: ConnectionSessionDelegate(), delegateQueue: nil)
        self.cache = cache
        self.routing = routing
        self.discoverMirrors = discoverMirrors
    }

    func setToken(_ token: String?) {
        self.token = token
    }

    func hasToken() -> Bool { token != nil }

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

    func resetConnections() async { await session.reset() }

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
        auth: Bool = false,
        force: Bool = false
    ) async throws -> T {
        if !force, let cacheKey, ttl > 0, let data = await cache.read(cacheKey, maxAge: ttl) {
            if let value = try? decoder.decode(T.self, from: data) { return value }
        }

        do {
            let data = try await requestData(path: path, method: "GET", query: query, body: nil, auth: auth)
            if let cacheKey { await cache.write(cacheKey, data: data) }
            return try decode(T.self, from: data)
        } catch {
            if Self.isCancellation(error) { throw APIError.cancelled }
            if !force, let cacheKey, let data = await cache.readStale(cacheKey), let value = try? decoder.decode(T.self, from: data) {
                return value
            }
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
        force: Bool = false
    ) async throws -> T {
        // Only read-only search POSTs opt into caching.
        if !force, let cacheKey, ttl > 0, let data = await cache.read(cacheKey, maxAge: ttl),
           let value = try? decoder.decode(T.self, from: data) {
            return value
        }
        let data = try encoder.encode(body)
        do {
            let response = try await requestData(path: path, method: "POST", query: query, body: data, auth: auth)
            let value = try decode(T.self, from: response)
            if let cacheKey { await cache.write(cacheKey, data: response) }
            return value
        } catch {
            if Self.isCancellation(error) { throw APIError.cancelled }
            if !force, let cacheKey, let cached = await cache.readStale(cacheKey),
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

    // MARK: - OAuth

    func oauthToken(form: [String: String]) async throws -> TokenResponse {
        let body = form
            .map { key, value in
                "\(urlEncode(key))=\(urlEncode(value))"
            }
            .joined(separator: "&")
            .data(using: .utf8)

        let data = try await requestData(
            path: "/oauth/access_token",
            method: "POST",
            query: [],
            body: body,
            auth: false,
            base: oauthBase,
            contentType: "application/x-www-form-urlencoded",
            accept: "application/json"
        )
        return try decode(TokenResponse.self, from: data)
    }

    // MARK: - HTML

    func rawHTML(_ url: URL, cacheKey: String, ttl: TimeInterval = 3600,
                 validate: (@Sendable (String) throws -> Void)? = nil, force: Bool = false) async throws -> String {
        if !force, let data = await cache.read(cacheKey, maxAge: ttl),
           !MirrorRouting.isVerificationPage(data),
           let html = String(data: data, encoding: .utf8),
           (try? validate?(html)) != nil || validate == nil {
            return html
        }

        do {
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
                        await cache.write(cacheKey, data: data)
                        return html
                    } catch {
                        if Self.isCancellation(error) { throw APIError.cancelled }
                        if case APIError.notFound = error { throw error }
                        if case APIError.rateLimited = error { throw error }
                        routing.record(candidate, milliseconds: Int(Date().timeIntervalSince(attempt) * 1000),
                                       result: (error as? APIError).map { failure in
                                           if case .verificationRequired = failure { return "需要网页验证" }
                                           return ConnectionTransport.failureDescription(error)
                                       } ?? ConnectionTransport.failureDescription(error), succeeded: false, revision: revision)
                        lastError = error
                        if routing.offline { throw error }
                    }
                }
            }
            throw lastError
        } catch {
            if Self.isCancellation(error) { throw APIError.cancelled }
            if !force, let data = await cache.readStale(cacheKey), !MirrorRouting.isVerificationPage(data),
               let html = String(data: data, encoding: .utf8),
               (try? validate?(html)) != nil || validate == nil {
                return html
            }
            throw error
        }
    }

    // MARK: - Core request

    private func requestData(
        path: String,
        method: String,
        query: [URLQueryItem],
        body: Data?,
        auth: Bool,
        base: URL? = nil,
        contentType: String = "application/json",
        accept: String = "application/json"
    ) async throws -> Data {
        guard var components = URLComponents(url: (base ?? apiBase).appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.invalidURL }

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
                                   result: result, succeeded: false, revision: revision, penalize: retryable)
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

    private func urlEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
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
