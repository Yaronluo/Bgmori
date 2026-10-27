import Foundation

struct LibraryEpisodeProgress: Codable, Sendable {
    let subjectID: Int
    let episodeID: Int
    let type: Int
}

struct LibrarySnapshot: Codable, Sendable {
    static let version = 1

    let version: Int
    let username: String
    let source: String
    let savedAt: Date
    let collections: [UserSubjectCollection]
    let progress: [LibraryEpisodeProgress]
}

/// Persists the last complete collection reconciliation and known episode
/// progress per account. The key contains only the public username; no token,
/// password, cookie, or authorization header is ever written here.
actor LibrarySnapshotStore {
    private let cache: DiskCache

    init(namespace: String = "BgmoriLibrarySnapshots") {
        cache = DiskCache(namespace: namespace)
    }

    func read(username: String, source: String, maxAge: TimeInterval) async -> LibrarySnapshot? {
        guard let data = await cache.read(key(for: username), maxAge: maxAge),
              let snapshot = try? JSONDecoder().decode(LibrarySnapshot.self, from: data),
              snapshot.version == LibrarySnapshot.version,
              snapshot.username == username,
              snapshot.source == source,
              Date().timeIntervalSince(snapshot.savedAt) <= maxAge else { return nil }
        return snapshot
    }

    func write(_ snapshot: LibrarySnapshot) async {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        await cache.write(key(for: snapshot.username), data: data)
    }

    func clear(username: String) async {
        await cache.remove(key(for: username))
    }

    private func key(for username: String) -> String {
        "library-snapshot-v1-\(username)"
    }
}
