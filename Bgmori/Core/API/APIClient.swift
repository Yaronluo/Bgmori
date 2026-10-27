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

    init(session: URLSession? = nil, cache: DiskCache = DiskCache(),
         routing: MirrorRouting = .shared, discoverMirrors: Bool = true) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = true
        configuration.httpShouldSetCookies = false
        configuration.urlCache = URLCache(memoryCapacity: 32 * 1024 * 1024, diskCapacity: 128 * 1024 * 1024)
        self.session = session ?? URLSession(configuration: configuration)
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
        guard discoverMirrors else { return }
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

    private func fetchMirrorCatalog() async {
        await limiter.wait()
        var request = URLRequest(url: MirrorRouting.directoryURL)
        request.assumesHTTP3Capable = false
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let etag = routing.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        do {
            let (data, response) = try await session.data(for: request)
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
        await prepareMirrors()
        return routing.preferredURL(for: url)
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
        ttl: TimeInterval = 0
    ) async throws -> T {
        // Only read-only search POSTs opt into caching.
        if let cacheKey, ttl > 0, let data = await cache.read(cacheKey, maxAge: ttl),
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
            if let cacheKey, let cached = await cache.readStale(cacheKey),
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
                 validate: (@Sendable (String) throws -> Void)? = nil) async throws -> String {
        if let data = await cache.read(cacheKey, maxAge: ttl),
           !MirrorRouting.isVerificationPage(data),
           let html = String(data: data, encoding: .utf8),
           (try? validate?(html)) != nil || validate == nil {
            return html
        }

        do {
            await prepareMirrors()
            var lastError: Error = APIError.network("页面加载失败")
            // Public HTML often works directly while mirrors require JavaScript challenges.
            let official = routing.canonicalURL(for: url)
            var seen: Set<URL> = []
            let candidates = ([official] + routing.candidates(for: url, forRequest: true)).filter { seen.insert($0).inserted }
            for candidate in candidates {
                do {
                    try Task.checkCancellation()
                    await htmlLimiter.wait()
                    var request = URLRequest(url: candidate)
                    request.httpMethod = "GET"
                    request.assumesHTTP3Capable = false
                    request.timeoutInterval = 15
                    request.setValue(Self.safariUserAgent, forHTTPHeaderField: "User-Agent")
                    request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
                    request.setValue("zh-CN,zh;q=0.9,ja;q=0.8,en;q=0.7", forHTTPHeaderField: "Accept-Language")
                    request.cachePolicy = .reloadIgnoringLocalCacheData

                    let (data, response) = try await session.data(for: request)
                    guard let http = response as? HTTPURLResponse else { throw APIError.network("无效的服务器响应") }
                    guard !MirrorRouting.isVerificationPage(data) else {
                        throw APIError.network("页面需要验证，请在浏览器中打开。")
                    }
                    guard (200...299).contains(http.statusCode) else {
                        if http.statusCode == 404 { throw APIError.notFound }
                        throw APIError.server(http.statusCode, "页面加载失败（\(http.statusCode)）")
                    }
                    guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS) else {
                        throw APIError.decoding("网页编码无法识别")
                    }
                    if html.contains("id=\"colunmNotice\""), html.contains("/img/bangumi/404.png") {
                        throw APIError.notFound
                    }
                    try validate?(html)
                    await cache.write(cacheKey, data: data)
                    return html
                } catch {
                    if Self.isCancellation(error) { throw APIError.cancelled }
                    if case APIError.notFound = error { throw error }
                    routing.markUnavailable(candidate)
                    lastError = error
                }
            }
            throw lastError
        } catch {
            if Self.isCancellation(error) { throw APIError.cancelled }
            if let data = await cache.readStale(cacheKey), !MirrorRouting.isVerificationPage(data),
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
        accept: String = "application/json",
        allowMirrorRefresh: Bool = true
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

        await prepareMirrors()
        // A failed write may already have reached the server. Never replay it on another host.
        let canReplay = method == "GET" || (method == "POST" && path.hasPrefix("/v0/search/"))
        let candidates = routing.candidates(for: url, forRequest: true)
        var lastError: Error = APIError.network("网络连接失败")
        for candidate in canReplay ? candidates : Array(candidates.prefix(1)) {
            do {
                try Task.checkCancellation()
                await limiter.wait()
                request.url = candidate
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw APIError.network("无效的服务器响应") }
                guard !MirrorRouting.isVerificationPage(data) else {
                    throw APIError.network("服务暂时无法连接，请稍后重试。")
                }
                if !data.isEmpty, http.statusCode != 204,
                   (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) == nil {
                    throw APIError.network("服务器返回了无效的数据，请稍后重试。")
                }
                switch http.statusCode {
                case 200...299: return data
                case 401: throw APIError.unauthorized
                case 403: throw APIError.forbidden
                case 404: throw APIError.notFound
                case 429: throw APIError.rateLimited
                default:
                    let detail = try? decoder.decode(ErrorDetail.self, from: data)
                    throw APIError.server(http.statusCode, detail?.description ?? detail?.title)
                }
            } catch {
                if Self.isCancellation(error) { throw APIError.cancelled }
                let failure: APIError
                if let error = error as? APIError { failure = error }
                else if let error = error as? URLError { failure = APIError.from(urlError: error) }
                else { failure = .network(error.localizedDescription) }
                guard failure.isRetryable else { throw failure }
                if case .rateLimited = failure { throw failure }
                routing.markUnavailable(candidate)
                lastError = failure
            }
        }
        if canReplay, allowMirrorRefresh, discoverMirrors, Date() >= nextMirrorAttempt {
            await prepareMirrors(force: true)
            return try await requestData(path: path, method: method, query: query, body: body, auth: auth,
                                         base: base, contentType: contentType, accept: accept, allowMirrorRefresh: false)
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
