import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

struct SendableImage: @unchecked Sendable {
    let cgImage: CGImage
}

actor ImageLoader {
    static let shared = ImageLoader()

    private struct MemoryEntry {
        let image: SendableImage
        let cost: Int
    }

    private let session: URLSession
    private let directory: URL
    private let routing: MirrorRouting
    private var memory: [String: MemoryEntry] = [:]
    private var memoryOrder: [String] = []
    private var memoryBytes = 0
    private let memoryLimitBytes: Int
    private let diskLimitBytes: Int64
    private var writesSinceTrim = 0
    private var lastDiskTrim = Date.distantPast
    private var downloads: [URL: Task<Data?, Never>] = [:]
    private var generation = UUID()
    private let gate = ImageDownloadGate(limit: 4)

    init(session: URLSession? = nil, directory: URL? = nil, routing: MirrorRouting = .shared,
         memoryLimitBytes: Int = 96 * 1024 * 1024, diskLimitBytes: Int64 = 320 * 1024 * 1024) {
        self.routing = routing
        self.memoryLimitBytes = memoryLimitBytes
        self.diskLimitBytes = diskLimitBytes
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 18
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 4
        // The loader keeps its own TTL-free disk cache; a second URLSession copy
        // would only duplicate every download on disk without ever being read.
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        self.session = session ?? URLSession(configuration: configuration, delegate: ConnectionSessionDelegate(), delegateQueue: nil)

        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.directory = directory ?? base.appendingPathComponent("BgmoriImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    func image(for url: URL, maxPixel: Int) async -> SendableImage? {
        guard maxPixel > 0, !Task.isCancelled else { return nil }
        let canonical = routing.canonicalURL(for: url)
        let requestURL = Self.requestURL(for: canonical, maxPixel: maxPixel)
        let key = "\(requestURL.absoluteString)#\(maxPixel)"
        if let cached = memory[key] {
            touch(key)
            return cached.image
        }

        let currentGeneration = generation
        // Reuse full-size images cached by earlier versions, including when offline.
        var image: SendableImage?
        if requestURL != url {
            var original = await diskData(for: url)
            if original == nil { original = await diskData(for: canonical) }
            if let original { image = await decode(original, maxPixel: maxPixel) }
        }
        if image == nil, let data = await data(for: requestURL) {
            image = await decode(data, maxPixel: maxPixel)
        }
        guard generation == currentGeneration, !Task.isCancelled else { return nil }
        if image == nil, requestURL != url, let data = await data(for: url) {
            image = await decode(data, maxPixel: maxPixel)
        }

        guard generation == currentGeneration, !Task.isCancelled, let image else { return nil }
        // Another caller may have decoded the shared download while we were suspended.
        if let cached = memory[key] { return cached.image }
        store(image, for: key)
        return image
    }

    func clear() async {
        generation = UUID()
        for download in downloads.values { download.cancel() }
        downloads.removeAll()
        memory.removeAll()
        memoryOrder.removeAll()
        memoryBytes = 0
        await Self.removeAllFiles(in: directory)
    }

    /// Resize original posters and portraits. User avatars and external images keep their URLs.
    static func requestURL(for url: URL, maxPixel: Int) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host == "lain.bgm.tv",
              components.query == nil,
              let width = [200, 400, 600, 800, 1200].first(where: { $0 >= maxPixel }) else { return url }
        let path = components.path.replacingOccurrences(of: #"^/r/\d+/"#, with: "/", options: .regularExpression)
        guard path.hasPrefix("/pic/cover/l/") || path.hasPrefix("/pic/crt/l/") else { return url }
        // The CDN bounds width, so using the requested longest edge never undersizes a cover.
        components.scheme = "https"
        components.path = "/r/\(width)" + path
        return components.url ?? url
    }

    nonisolated private func diskData(for url: URL) async -> Data? {
        guard let data = try? Data(contentsOf: fileURL(for: url)), !data.isEmpty else { return nil }
        return data
    }

    private func data(for url: URL) async -> Data? {
        if let disk = await diskData(for: url) { return disk }
        if let download = downloads[url] { return await download.value }

        let currentGeneration = generation
        let download = Task { [self] () -> Data? in
            await fetchData(for: url)
        }
        downloads[url] = download
        let data = await download.value
        guard generation == currentGeneration else { return nil }
        if let data {
            await write(data, for: url)
            await trimDiskIfNeeded()
        }
        downloads[url] = nil
        return data
    }

    func resetConnections() async { await session.reset() }

    /// Diagnostics deliberately bypass disk/memory caches and exercise the image transport.
    func checkConnection(_ url: URL) async -> Bool {
        await fetchData(for: routing.canonicalURL(for: url)) != nil
    }

    private func fetchData(for url: URL) async -> Data? {
        guard await gate.acquire() else { return nil }
        let result = await fetchUncachedData(for: url)
        await gate.release()
        return result
    }

    private func fetchUncachedData(for url: URL) async -> Data? {
        let started = Date()
        let revision = routing.revision
        for candidate in routing.candidates(for: url, forRequest: true) {
            let attempt = Date()
            var penalize = true
            do {
                try Task.checkCancellation()
                guard revision == routing.revision else { return nil }
                if routing.offline, !MirrorRouting.isECHHost(candidate.host) { throw URLError(.notConnectedToInternet) }
                let remaining = 14 - Date().timeIntervalSince(started)
                guard remaining > 0 else { return nil }
                var request = URLRequest(url: candidate)
                request.assumesHTTP3Capable = false
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.timeoutInterval = min(remaining, routing.timeout(for: candidate))
                request.setValue(APIClient.userAgent, forHTTPHeaderField: "User-Agent")
                let (data, response) = try await ConnectionTransport.data(for: request, session: session,
                                                                          timeout: request.timeoutInterval)
                guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                if http.statusCode == 429 {
                    routing.record(candidate, milliseconds: Int(Date().timeIntervalSince(attempt) * 1000),
                                   result: "请求限流（429）", succeeded: false, revision: revision, penalize: false)
                    return nil
                }
                if http.statusCode == 404 { penalize = false }
                guard (200...299).contains(http.statusCode), !data.isEmpty,
                      !MirrorRouting.isVerificationPage(data) else { throw URLError(.badServerResponse) }
                guard CGImageSourceCreateWithData(data as CFData, nil) != nil else {
                    penalize = false
                    throw URLError(.cannotDecodeContentData)
                }
                routing.record(candidate, milliseconds: Int(Date().timeIntervalSince(attempt) * 1000),
                               result: "连接成功", succeeded: true, revision: revision)
                return data
            } catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled { return nil }
                routing.record(candidate, milliseconds: Int(Date().timeIntervalSince(attempt) * 1000),
                               result: ConnectionTransport.failureDescription(error), succeeded: false, revision: revision, penalize: penalize)
                if routing.offline { return nil }
            }
        }
        return nil
    }

    func cacheSize() -> Int64 {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return contents.reduce(Int64(0)) { partial, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return partial + Int64(size)
        }
    }

    /// Drops the least recently used decodes once the byte budget is exceeded.
    /// A byte budget (not a fixed count) keeps large hero images from claiming
    /// hundreds of megabytes on iPhone.
    private func store(_ image: SendableImage, for key: String) {
        if let existing = memory.removeValue(forKey: key) {
            memoryBytes -= existing.cost
            if let index = memoryOrder.firstIndex(of: key) { memoryOrder.remove(at: index) }
        }
        let cost = image.cgImage.bytesPerRow * image.cgImage.height
        memory[key] = MemoryEntry(image: image, cost: cost)
        memoryBytes += cost
        memoryOrder.append(key)
        trimMemory()
    }

    private func touch(_ key: String) {
        guard let index = memoryOrder.firstIndex(of: key), index != memoryOrder.count - 1 else { return }
        memoryOrder.remove(at: index)
        memoryOrder.append(key)
    }

    private func trimMemory() {
        // Keep one entry even when a single decode exceeds the budget.
        while memoryBytes > memoryLimitBytes, memoryOrder.count > 1 {
            let key = memoryOrder.removeFirst()
            if let entry = memory.removeValue(forKey: key) { memoryBytes -= entry.cost }
        }
    }

    nonisolated private func fileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest + ".img")
    }

    nonisolated private func write(_ data: Data, for url: URL) async {
        try? data.write(to: fileURL(for: url), options: .atomic)
    }

    private func trimDiskIfNeeded() async {
        writesSinceTrim += 1
        guard writesSinceTrim >= 32 || Date().timeIntervalSince(lastDiskTrim) >= 3_600 else { return }
        writesSinceTrim = 0
        lastDiskTrim = Date()
        await trimDisk()
    }

    /// Old covers are disposable; the cap only keeps months of browsing from
    /// leaving gigabytes behind.
    func trimDisk() async {
        let directory = self.directory
        let limit = diskLimitBytes
        await Self.trimDirectory(directory, maxBytes: limit)
    }

    nonisolated private static func trimDirectory(_ directory: URL, maxBytes: Int64) async {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var entries: [(url: URL, size: Int64, modified: Date)] = []
        var total: Int64 = 0
        for url in contents {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = Int64(values?.fileSize ?? 0)
            total += size
            entries.append((url, size, values?.contentModificationDate ?? .distantPast))
        }
        guard total > maxBytes else { return }

        let target = maxBytes - maxBytes / 10
        entries.sort { $0.modified < $1.modified }
        for entry in entries where total > target {
            try? fileManager.removeItem(at: entry.url)
            total -= entry.size
        }
    }

    nonisolated private static func removeAllFiles(in directory: URL) async {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for url in contents { try? fileManager.removeItem(at: url) }
    }

    /// Decoding runs off the actor so parallel downloads can decode in
    /// parallel instead of queueing behind one executor.
    nonisolated private func decode(_ data: Data, maxPixel: Int) async -> SendableImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return SendableImage(cgImage: image)
    }
}

/// A cancelled queued download must release its continuation without consuming a slot.
actor ImageDownloadGate {
    private let limit: Int
    private var active = 0
    private var waiting: [(UUID, CheckedContinuation<Bool, Never>)] = []

    init(limit: Int) { self.limit = limit }

    func acquire() async -> Bool {
        guard !Task.isCancelled else { return false }
        if active < limit {
            active += 1
            return true
        }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled { continuation.resume(returning: false) }
                else { waiting.append((id, continuation)) }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    private func cancel(_ id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.0 == id }) else { return }
        waiting.remove(at: index).1.resume(returning: false)
    }

    func release() {
        if waiting.isEmpty { active -= 1 }
        else { waiting.removeFirst().1.resume(returning: true) }
    }
}
