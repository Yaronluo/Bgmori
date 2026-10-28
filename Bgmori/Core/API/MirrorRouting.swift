import Foundation
import Network
import CFNetwork

enum SystemProxyRouting {
    static func isEnabled(for url: URL) -> Bool {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() else { return false }
        return isEnabled(for: url, settings: settings)
    }

    static func isEnabled(for url: URL, settings: CFDictionary) -> Bool {
        let proxies = CFNetworkCopyProxiesForURL(url as CFURL, settings).takeRetainedValue() as? [[String: Any]] ?? []
        guard let type = proxies.first?[kCFProxyTypeKey as String] as? String else { return false }
        // Let URLSession resolve PAC and apply system exceptions; never copy
        // proxy credentials or execute a PAC script on the routing lock.
        return [kCFProxyTypeHTTP, kCFProxyTypeHTTPS, kCFProxyTypeSOCKS,
                kCFProxyTypeAutoConfigurationURL, kCFProxyTypeAutoConfigurationJavaScript]
            .contains { type == $0 as String }
    }
}

enum ConnectionMode: String, Codable, CaseIterable, Sendable {
    case automatic, official, encrypted, custom
    var title: String {
        switch self {
        case .automatic: "自动"
        case .official: "仅官方"
        case .encrypted: "加密直连（ECH）"
        case .custom: "自定义服务"
        }
    }
}

struct ConnectionSettings: Codable, Equatable, Sendable {
    var mode: ConnectionMode = .automatic
    var customRoot = ""
    var encryptedDNS = false
}

enum ConnectionService: String, CaseIterable, Sendable {
    case api, images, web
    var title: String {
        switch self {
        case .api: "API"
        case .images: "图片"
        case .web: "网页"
        }
    }
}

struct ConnectionEvent: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let service: ConnectionService
    let host: String
    let milliseconds: Int
    let result: String
    let succeeded: Bool
    let encrypted: Bool
}

struct MirrorCatalog: Codable, Sendable {
    struct Mirror: Codable, Sendable {
        struct Service: Codable, Sendable {
            let id: String
            let hosts: [String]
        }

        let id: String
        let weight: Int
        let recommended: Bool
        let services: [Service]
    }

    let mirrors: [Mirror]
}

/// A small synchronized snapshot also used by synchronous browser links and image cache keys.
/// Only domain discovery is persisted here; account data never enters this file.
final class MirrorRouting: @unchecked Sendable {
    static let shared = MirrorRouting(persistenceURL: defaultPersistenceURL)
    static let directoryURL = URL(string: "https://bangumi.wiki/api/v1/mirrors")!

    private struct Snapshot: Codable {
        var catalog: MirrorCatalog?
        var etag: String?
        var checkedAt: Date?
        var knownHosts: [String: String] = [:]
        var connection: ConnectionSettings?
    }

    private static var defaultPersistenceURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Bgmori/Mirrors.json")
    }

    private let lock = NSLock()
    private let persistenceURL: URL?
    private let systemProxy: @Sendable (URL) -> Bool
    private var snapshot: Snapshot
    private struct Health {
        var failures = 0
        var until = Date.distantPast
        var succeededAt: Date?
    }
    private var health: [String: Health] = [:]
    private var selected: [ConnectionService: (String, Date)] = [:]
    private var proxyUsage: [String: Bool] = [:]
    private var events: [ConnectionEvent] = []
    private var generation = 0
    private let now: @Sendable () -> Date
    private var monitor: NWPathMonitor?
    private var lastPath: String?
    private var isOffline = false

    init(persistenceURL: URL? = nil, now: @escaping @Sendable () -> Date = { Date() },
         systemProxy: @escaping @Sendable (URL) -> Bool = { SystemProxyRouting.isEnabled(for: $0) }) {
        self.persistenceURL = persistenceURL
        self.systemProxy = systemProxy
        self.now = now
        if let persistenceURL, let data = try? Data(contentsOf: persistenceURL),
           let saved = try? JSONDecoder().decode(Snapshot.self, from: data) {
            snapshot = saved
        } else {
            snapshot = Snapshot()
        }
    }

    var etag: String? { lock.withLock { snapshot.etag } }
    var needsRefresh: Bool {
        lock.withLock { snapshot.checkedAt.map { Date().timeIntervalSince($0) >= 21_600 } ?? true }
    }

    func update(_ catalog: MirrorCatalog, etag: String?) {
        lock.withLock {
            // Keep previous domains recognizable when API/HTML caches still contain old links.
            for mirror in catalog.mirrors {
                for service in mirror.services where Self.officialHost(for: service.id) != nil {
                    for host in service.hosts where Self.validHost(host) {
                        snapshot.knownHosts[host.lowercased()] = service.id
                    }
                }
            }
            snapshot.catalog = catalog
            snapshot.etag = etag
            snapshot.checkedAt = .now
            persist()
        }
    }

    func revalidated() {
        lock.withLock {
            guard snapshot.catalog != nil else { return }
            snapshot.checkedAt = .now
            persist()
        }
    }

    func canonicalURL(for url: URL) -> URL {
        lock.withLock { canonicalURL(for: url, snapshot: snapshot) }
    }

    func preferredURL(for url: URL, credentials: Bool = false) -> URL {
        candidates(for: url, forRequest: true, credentials: credentials).first { !Self.isECHHost($0.host) }
            ?? canonicalURL(for: url)
    }

    func candidates(for url: URL, forRequest: Bool = false, credentials: Bool = false) -> [URL] {
        let hasSystemProxy = systemProxy(canonicalURL(for: url))
        return lock.withLock {
            let canonical = canonicalURL(for: url, snapshot: snapshot)
            guard ["http", "https"].contains(canonical.scheme?.lowercased() ?? ""),
                  canonical.user == nil, canonical.password == nil, canonical.port == nil,
                  let host = canonical.host, let service = Self.service(for: host),
                  var components = URLComponents(url: canonical, resolvingAgainstBaseURL: false) else { return [url] }
            let mirrors = (snapshot.catalog?.mirrors ?? []).sorted {
                if $0.recommended != $1.recommended { return $0.recommended }
                if $0.weight != $1.weight { return $0.weight > $1.weight }
                return $0.id < $1.id
            }
            let settings = snapshot.connection ?? ConnectionSettings()
            var hosts = [host]
            if Self.echAvailable, let encrypted = Self.echHost(for: host) {
                hosts.insert(encrypted, at: 0)
            }
            if settings.mode == .encrypted { hosts = hosts.filter { Self.isECHHost($0) } }
            if settings.mode == .custom, let root = Self.normalizedRoot(settings.customRoot) {
                hosts.insert(service == "main" ? root : "\(service == "lain" ? "lain" : service).\(root)", at: 0)
            } else if settings.mode == .automatic, !credentials {
                hosts += mirrors.flatMap { $0.services.filter { $0.id == service }.flatMap(\.hosts) }
                    .filter(Self.validHost).map { $0.lowercased() }
            }
            let channel = Self.channel(for: service)
            if let previous = proxyUsage[host], previous != hasSystemProxy {
                // An official connection that failed before the proxy was
                // enabled must be tried again immediately through URLSession.
                health = health.filter { !$0.key.hasPrefix("\(channel.rawValue)|") }
                selected[channel] = nil
            }
            proxyUsage[host] = hasSystemProxy
            if let (working, date) = selected[channel], now().timeIntervalSince(date) < 1800,
               hosts.contains(working), (!credentials || Self.isECHHost(working) || working == host) {
                hosts.removeAll { $0 == working }
                hosts.insert(working, at: 0)
            }
            if hasSystemProxy, settings.mode == .automatic || settings.mode == .official {
                hosts.removeAll { $0 == host }
                hosts.insert(host, at: 0)
            }
            if forRequest, !credentials {
                let available = hosts.filter { (health["\(channel.rawValue)|\($0)"]?.until ?? .distantPast) <= now() }
                hosts = available
            }
            var seen: Set<String> = []
            return hosts.compactMap { candidate in
                guard seen.insert(candidate).inserted else { return nil }
                components.host = candidate
                components.scheme = "https"
                return components.url
            }
        }
    }

    func markUnavailable(_ url: URL) {
        record(url, milliseconds: 0, result: "连接失败", succeeded: false)
    }

    var settings: ConnectionSettings { lock.withLock { snapshot.connection ?? ConnectionSettings() } }
    var revision: Int { lock.withLock { generation } }
    var offline: Bool { lock.withLock { isOffline } }
    var diagnostics: [ConnectionEvent] { lock.withLock { events } }

    func configure(_ value: ConnectionSettings, persistChanges: Bool = true) throws {
        var value = value
        if value.mode == .custom {
            guard let root = Self.normalizedRoot(value.customRoot) else {
                throw URLError(.badURL)
            }
            value.customRoot = root
        }
        lock.withLock {
            snapshot.connection = value
            if let root = Self.normalizedRoot(value.customRoot) {
                for service in ["main", "api", "lain", "next", "doujin"] {
                    snapshot.knownHosts[service == "main" ? root : "\(service).\(root)"] = service
                }
            }
            health.removeAll()
            selected.removeAll()
            generation += 1
            if persistChanges { persist() }
        }
        Self.applyEncryptedDNS(value.encryptedDNS)
    }

    /// Explicit user refreshes and retries should not be silently swallowed by
    /// a recent automatic-failure cooldown.
    func resetBackoff(for url: URL) {
        lock.withLock {
            guard url.host != nil,
                  let canonicalHost = canonicalURL(for: url, snapshot: snapshot).host,
                  let service = Self.service(for: canonicalHost) else { return }
            let prefix = "\(Self.channel(for: service).rawValue)|"
            health = health.filter { !$0.key.hasPrefix(prefix) }
        }
    }

    func resetHealth() {
        lock.withLock {
            health.removeAll()
            selected.removeAll()
            events.removeAll()
            generation += 1
        }
    }

    func record(_ url: URL, milliseconds: Int, result: String, succeeded: Bool, revision: Int? = nil,
                penalize: Bool = true) {
        lock.withLock {
            guard revision == nil || revision == generation,
                  let host = url.host,
                  let canonicalHost = canonicalURL(for: url, snapshot: snapshot).host,
                  let service = Self.service(for: canonicalHost) else { return }
            let channel = Self.channel(for: service)
            let key = "\(channel.rawValue)|\(host)"
            if succeeded {
                health[key] = Health(succeededAt: now())
                if selected[channel]?.0 != host || now().timeIntervalSince(selected[channel]?.1 ?? .distantPast) >= 1800 {
                    selected[channel] = (host, now())
                }
            } else if penalize {
                var state = health[key] ?? Health()
                state.failures = min(state.failures + 1, 6)
                state.until = now().addingTimeInterval(min(300, 15 * pow(2, Double(state.failures - 1))))
                health[key] = state
                if selected[channel]?.0 == host { selected[channel] = nil }
            }
            let encrypted = Self.isECHHost(host)
            events.insert(ConnectionEvent(date: now(), service: channel, host: encrypted ? canonicalHost : host,
                                          milliseconds: milliseconds,
                                          result: succeeded && encrypted ? "ECH 已验证" : result,
                                          succeeded: succeeded, encrypted: encrypted), at: 0)
            events = Array(events.prefix(40))
        }
    }

    func timeout(for url: URL, credentials: Bool = false) -> TimeInterval {
        return lock.withLock {
            guard let host = url.host,
                  let canonical = canonicalURL(for: url, snapshot: snapshot).host,
                  let service = Self.service(for: canonical) else { return 12 }
            let key = "\(Self.channel(for: service).rawValue)|\(host)"
            return health[key]?.succeededAt == nil ? (Self.isECHHost(host) ? 8 : 5) : 12
        }
    }

    func startNetworkMonitoring() {
        Self.applyEncryptedDNS(settings.encryptedDNS)
        lock.withLock {
            guard monitor == nil else { return }
            let observer = NWPathMonitor()
            observer.pathUpdateHandler = { [weak self] path in
                self?.networkChanged(offline: path.status == .unsatisfied,
                                     signature: "\(path.status)-\(path.availableInterfaces.map(\.name))-\(path.isExpensive)-\(path.isConstrained)")
            }
            monitor = observer
            observer.start(queue: DispatchQueue(label: "com.yaron.bgmori.network"))
        }
    }

    func networkChanged(offline: Bool, signature: String) {
        lock.withLock {
            isOffline = offline
            if let previous = lastPath, previous != signature {
                health.removeAll()
                selected.removeAll()
                generation += 1
            }
            lastPath = signature
        }
    }

    static func applyEncryptedDNS(_ enabled: Bool) {
        let context = NWParameters.PrivacyContext.default
        context.requireEncryptedNameResolution(enabled, fallbackResolver: enabled
            ? .https(URL(string: "https://dns.alidns.com/dns-query")!, serverAddresses: []) : nil)
        context.flushCache()
    }

    static func normalizedRoot(_ input: String) -> String? {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URLComponents(string: raw.contains("://") ? raw : "https://\(raw)"),
              url.scheme == "https", let host = url.host?.lowercased(), validHost(host),
              url.port == nil, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/",
              service(for: host) == nil, !host.hasSuffix(".invalid") else { return nil }
        return host
    }

    private static func channel(for service: String) -> ConnectionService {
        service == "lain" ? .images : (service == "main" ? .web : .api)
    }

    private func canonicalURL(for url: URL, snapshot: Snapshot) -> URL {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil, url.port == nil,
              let host = url.host?.lowercased(),
              let service = Self.service(for: host) ?? Self.echService(for: host) ?? snapshot.knownHosts[host],
              let official = Self.officialHost(for: service),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.host = official
        components.scheme = "https"
        return components.url ?? url
    }

    static var echAvailable: Bool {
        #if BGMORI_ECH
        true
        #else
        false
        #endif
    }

    static func isECHHost(_ host: String?) -> Bool { host.map { echService(for: $0) != nil } ?? false }

    private static func echService(for host: String) -> String? {
        switch host {
        case "bgm-tv.ech.invalid": "main"
        case "api.bgm-tv.ech.invalid": "api"
        case "lain.bgm-tv.ech.invalid": "lain"
        case "next.bgm-tv.ech.invalid": "next"
        case "doujin.bgm-tv.ech.invalid": "doujin"
        default: nil
        }
    }

    private static func echHost(for host: String) -> String? {
        guard let service = service(for: host) else { return nil }
        return service == "main" ? "bgm-tv.ech.invalid" : "\(service).bgm-tv.ech.invalid"
    }

    static func echOrigin(for url: URL) -> URL? {
        guard let host = url.host, let service = echService(for: host), let official = officialHost(for: service),
              url.scheme == "https", url.port == nil, url.user == nil, url.password == nil,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.host = official
        return components.url
    }

    static func encryptedURL(for url: URL) -> URL? {
        guard let host = url.host, let encrypted = echHost(for: host),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.host = encrypted
        return components.url
    }

    private static func service(for host: String) -> String? {
        switch host {
        case "bgm.tv", "www.bgm.tv", "bangumi.tv", "www.bangumi.tv", "chii.in", "www.chii.in": "main"
        case "api.bgm.tv": "api"
        case "lain.bgm.tv": "lain"
        case "next.bgm.tv": "next"
        case "doujin.bgm.tv": "doujin"
        default: nil
        }
    }

    private static func officialHost(for service: String) -> String? {
        switch service {
        case "main": "bgm.tv"
        case "api": "api.bgm.tv"
        case "lain": "lain.bgm.tv"
        case "next": "next.bgm.tv"
        case "doujin": "doujin.bgm.tv"
        default: nil
        }
    }

    private static func validHost(_ host: String) -> Bool {
        guard host.utf8.count <= 253, host.contains("."),
              host.range(of: #"^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+$"#,
                         options: .regularExpression) != nil,
              let last = host.split(separator: ".").last, last.contains(where: \.isLetter) else { return false }
        return host.split(separator: ".").allSatisfy { $0.utf8.count <= 63 }
    }

    /// Called while holding the lock so an older snapshot cannot overwrite a newer one.
    private func persist() {
        guard let persistenceURL, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: persistenceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: persistenceURL, options: .atomic)
    }

    static func isVerificationPage(_ data: Data) -> Bool {
        let prefix = String(decoding: data.prefix(131_072), as: UTF8.self).lowercased()
        return prefix.contains("anubis_challenge") || prefix.contains("anubis-main")
            || prefix.contains("正在确认你是不是机器人") || prefix.contains("cf-chl-")
            || prefix.contains("<title>just a moment")
    }
}

struct WebLoginHTTPResult: Sendable {
    let data: Data
    let response: HTTPURLResponse
    let setCookies: [String]
}

struct WebLoginRoute: Sendable {
    let encrypted: Bool
    let revision: Int
}

final class WebLoginRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Enforces an elapsed-time budget, rather than URLSession's idle timeout alone.
enum ConnectionTransport {
    static func data(for request: URLRequest, session: URLSession, timeout: TimeInterval) async throws -> (Data, URLResponse) {
        try await withThrowingTaskGroup(of: (Data, URLResponse).self) { group in
            group.addTask {
                #if BGMORI_ECH
                if MirrorRouting.isECHHost(request.url?.host) {
                    return try await ECHTransport.data(for: request, timeout: timeout)
                }
                #endif
                return try await session.data(for: request)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    static func failureDescription(_ error: Error) -> String {
        #if BGMORI_ECH
        if let error = error as? ECHFailure { return error.errorDescription ?? "ECH 加密直连失败" }
        #endif
        if let error = error as? URLError {
            switch error.code {
            case .timedOut: return "连接超时"
            case .notConnectedToInternet, .networkConnectionLost: return "网络不可用"
            case .cannotFindHost, .dnsLookupFailed: return "域名解析失败"
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
                    .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid: return "安全连接失败"
            default: return "连接失败（\(error.code.rawValue)）"
            }
        }
        // Never put error descriptions, request URLs or server-provided text into diagnostics.
        return "响应无法使用"
    }
}

final class ConnectionSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        let original = task.originalRequest
        let sensitive = original?.value(forHTTPHeaderField: "Authorization") != nil
            || original?.url?.path.hasPrefix("/oauth/") == true
            || !["GET", "HEAD"].contains(original?.httpMethod ?? "GET")
                && original?.url?.path.hasPrefix("/v0/search/") != true
        guard request.url?.scheme == "https",
              !sensitive || request.url?.host == original?.url?.host else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
