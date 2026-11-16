import CryptoKit
import Foundation

actor DiskCache {
    struct Entry: Sendable {
        let data: Data
        let age: TimeInterval
        let isFresh: Bool
    }

    private let directory: URL
    private let fileManager = FileManager.default
    private let maxBytes: Int64
    private var knownBytes: Int64?
    private var writesSinceTrim = 0
    private var lastTrim = Date.distantPast
    private let trimWriteThreshold = 32
    private let trimInterval: TimeInterval = 3_600

    init(namespace: String = "BgmoriAPI", maxBytes: Int64 = 64 * 1024 * 1024) {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        directory = base.appendingPathComponent(namespace, isDirectory: true)
        self.maxBytes = maxBytes
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func read(_ key: String, maxAge: TimeInterval) -> Data? {
        guard let entry = readEntry(key, maxAge: maxAge, maxStaleAge: maxAge) else { return nil }
        return entry.data
    }

    /// Reads a cache entry that may already be past its refresh TTL, as long as it
    /// is still inside the caller's explicit display window.
    func readEntry(_ key: String, maxAge: TimeInterval, maxStaleAge: TimeInterval) -> Entry? {
        guard let url = fileURL(for: key),
              let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date else {
            return nil
        }
        let age = Date().timeIntervalSince(modified)
        guard age >= 0, age <= max(maxAge, maxStaleAge),
              let data = try? Data(contentsOf: url),
              !data.isEmpty else {
            return nil
        }
        return Entry(data: data, age: age, isFresh: age <= maxAge)
    }

    func readStale(_ key: String, maxAge: TimeInterval? = nil) -> Data? {
        guard let url = fileURL(for: key),
              let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date else {
            return nil
        }
        if let maxAge, Date().timeIntervalSince(modified) > maxAge { return nil }
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return data
    }

    func remove(_ key: String) {
        guard let url = fileURL(for: key) else { return }
        try? fileManager.removeItem(at: url)
        knownBytes = nil
    }

    func write(_ key: String, data: Data) {
        guard let url = fileURL(for: key) else { return }
        try? data.write(to: url, options: .atomic)
        let total = (knownBytes ?? directorySize()) + Int64(data.count)
        knownBytes = total
        writesSinceTrim += 1
        if total > maxBytes || writesSinceTrim >= trimWriteThreshold || Date().timeIntervalSince(lastTrim) >= trimInterval {
            trimIfNeeded()
        }
    }

    /// Deletes the oldest entries until this namespace is back under its cap.
    /// The 10% margin keeps the next few writes from triggering another scan.
    /// Caches are disposable, so this never needs the caller's permission.
    @discardableResult
    func trimIfNeeded() -> Int64 {
        writesSinceTrim = 0
        lastTrim = Date()
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            knownBytes = 0
            return 0
        }

        var entries: [(url: URL, size: Int64, modified: Date)] = []
        var total: Int64 = 0
        for url in contents {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = Int64(values?.fileSize ?? 0)
            total += size
            entries.append((url, size, values?.contentModificationDate ?? .distantPast))
        }
        guard total > maxBytes else {
            knownBytes = total
            return total
        }

        let target = maxBytes - maxBytes / 10
        entries.sort { $0.modified < $1.modified }
        for entry in entries where total > target {
            try? fileManager.removeItem(at: entry.url)
            total -= entry.size
        }
        knownBytes = total
        return total
    }

    private func directorySize() -> Int64 {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        return contents.reduce(Int64(0)) { partial, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return partial + Int64(size)
        }
    }

    func clear() {
        knownBytes = 0
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
