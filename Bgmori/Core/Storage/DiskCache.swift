import CryptoKit
import Foundation

actor DiskCache {
    private let directory: URL
    private let fileManager = FileManager.default

    init(namespace: String = "BgmoriAPI") {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        directory = base.appendingPathComponent(namespace, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func read(_ key: String, maxAge: TimeInterval) -> Data? {
        guard let url = fileURL(for: key),
              let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) <= maxAge,
              let data = try? Data(contentsOf: url),
              !data.isEmpty else {
            return nil
        }
        return data
    }

    func readStale(_ key: String) -> Data? {
        guard let url = fileURL(for: key),
              let data = try? Data(contentsOf: url),
              !data.isEmpty else { return nil }
        return data
    }

    func write(_ key: String, data: Data) {
        guard let url = fileURL(for: key) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func clear() {
        guard let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for url in contents { try? fileManager.removeItem(at: url) }
    }

    func size() -> Int64 {
        guard let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return contents.reduce(Int64(0)) { partial, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return partial + Int64(size)
        }
    }

    private func fileURL(for key: String) -> URL? {
        guard let data = key.data(using: .utf8) else { return nil }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest + ".cache")
    }
}

enum ByteCountFormatter {
    static func string(_ bytes: Int64) -> String {
        let formatter = Foundation.ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
