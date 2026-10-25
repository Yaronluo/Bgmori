import Foundation

actor APIClient {
    static let shared = APIClient()

    private let apiBase = URL(string: "https://api.bgm.tv")!
    private let htmlBase = URL(string: "https://bgm.tv")!
    private let oauthBase = URL(string: "https://bgm.tv")!
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    let cache: DiskCache
    private let limiter = RateLimiter(interval: 0.22)
    private let htmlLimiter = RateLimiter(interval: 2.0)
    private var token: String?

    init(session: URLSession? = nil, cache: DiskCache = DiskCache()) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = true
        configuration.httpShouldSetCookies = false
        configuration.urlCache = URLCache(memoryCapacity: 32 * 1024 * 1024, diskCapacity: 128 * 1024 * 1024)
        self.session = session ?? URLSession(configuration: configuration)
        self.cache = cache
    }

    func setToken(_ token: String?) {
        self.token = token
    }

    func hasToken() -> Bool { token != nil }

    // MARK: - Public GET

    func get<T: Decodable & Sendable>(
        _ path: String,
        query: [URLQueryItem] = [],
        as type: T.Type,
        cacheKey: String? = nil,
        ttl: TimeInterval = 0,
        auth: Bool = false
    ) async throws -> T {
        if let cacheKey, ttl > 0, let data = await cache.read(cacheKey, maxAge: ttl) {
            if let value = try? decoder.decode(T.self, from: data) { return value }
        }

        do {
            let data = try await requestData(path: path, method: "GET", query: query, body: nil, auth: auth)
            if let cacheKey { await cache.write(cacheKey, data: data) }
            return try decode(T.self, from: data)
        } catch {
            if let cacheKey, let data = await cache.readStale(cacheKey), let value = try? decoder.decode(T.self, from: data) {
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

    func rawHTML(_ url: URL, cacheKey: String, ttl: TimeInterval = 3600) async throws -> String {
        if let data = await cache.read(cacheKey, maxAge: ttl),
           let html = String(data: data, encoding: .utf8) {
            return html
        }

        do {
            await htmlLimiter.wait()
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.assumesHTTP3Capable = false
            request.timeoutInterval = 30
            request.setValue(Self.safariUserAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
            request.setValue("zh-CN,zh;q=0.9,ja;q=0.8,en;q=0.7", forHTTPHeaderField: "Accept-Language")
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.network("无效的服务器响应") }
            guard (200...299).contains(http.statusCode) else {
                if http.statusCode == 404 { throw APIError.notFound }
                throw APIError.server(http.statusCode, "页面加载失败（\(http.statusCode)）")
            }
            await cache.write(cacheKey, data: data)
            if let html = String(data: data, encoding: .utf8) { return html }
            if let html = String(data: data, encoding: .shiftJIS) { return html }
            throw APIError.decoding("网页编码无法识别")
        } catch {
            if let data = await cache.readStale(cacheKey), let html = String(data: data, encoding: .utf8) {
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

        await limiter.wait()

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.network("无效的服务器响应") }
            switch http.statusCode {
            case 200...299:
                return data
            case 401:
                throw APIError.unauthorized
            case 403:
                throw APIError.forbidden
            case 404:
                throw APIError.notFound
            case 429:
                throw APIError.rateLimited
            default:
                let message = (try? decoder.decode(ErrorDetail.self, from: data))?.description
                    ?? (try? decoder.decode(ErrorDetail.self, from: data))?.title
                throw APIError.server(http.statusCode, message)
            }
        } catch let error as APIError {
            throw error
        } catch let error as URLError {
            throw APIError.from(urlError: error)
        } catch {
            throw APIError.network(error.localizedDescription)
        }
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
