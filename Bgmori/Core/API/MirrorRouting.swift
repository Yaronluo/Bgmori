import Foundation

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
    }

    private static var defaultPersistenceURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Bgmori/Mirrors.json")
    }

    private let lock = NSLock()
    private let persistenceURL: URL?
    private var snapshot: Snapshot
    private var unavailableUntil: [String: Date] = [:]

    init(persistenceURL: URL? = nil) {
        self.persistenceURL = persistenceURL
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
            unavailableUntil.removeAll()
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

    func preferredURL(for url: URL) -> URL {
        candidates(for: url).first ?? url
    }

    func candidates(for url: URL, forRequest: Bool = false) -> [URL] {
        lock.withLock {
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
            var hosts = mirrors.flatMap { $0.services.filter { $0.id == service }.flatMap(\.hosts) }
                .filter(Self.validHost).map { $0.lowercased() }
            if forRequest {
                hosts.removeAll { unavailableUntil[$0].map { $0 > Date() } ?? false }
            }
            hosts.append(host)
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
        guard let host = url.host else { return }
        lock.withLock { unavailableUntil[host] = Date().addingTimeInterval(300) }
    }

    private func canonicalURL(for url: URL, snapshot: Snapshot) -> URL {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil, url.port == nil,
              let host = url.host?.lowercased(),
              let service = Self.service(for: host) ?? snapshot.knownHosts[host],
              let official = Self.officialHost(for: service),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.host = official
        components.scheme = "https"
        return components.url ?? url
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
