import Foundation

/// The website session is only used for one operation the public API cannot do:
/// removing a subject collection. It lives in the Keychain, device-only, and is
/// deleted on sign-out. Never log its contents.
enum WebsiteSessionStore {
    private static let key = "websiteSession.v1"
    private static let maxBytes = 16 * 1_024

    static func load() -> WebsiteSessionSnapshot? {
        guard let text = Keychain.read(key), let data = text.data(using: .utf8) else { return nil }
        guard let snapshot = try? JSONDecoder().decode(WebsiteSessionSnapshot.self, from: data),
              !snapshot.cookies.isEmpty, snapshot.cookies.count <= 64,
              data.count <= maxBytes else {
            Keychain.delete(key)
            return nil
        }
        return snapshot
    }

    static func save(_ snapshot: WebsiteSessionSnapshot) {
        let snapshot = snapshot.mainSiteOnly
        guard !snapshot.cookies.isEmpty,
              let data = try? JSONEncoder().encode(snapshot), data.count <= maxBytes,
              let text = String(data: data, encoding: .utf8) else { return }
        Keychain.save(text, for: key)
    }

    static func clear() {
        Keychain.delete(key)
    }
}
