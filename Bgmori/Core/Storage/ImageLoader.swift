import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

struct SendableImage: @unchecked Sendable {
    let cgImage: CGImage
}

actor ImageLoader {
    static let shared = ImageLoader()

    private let session: URLSession
    private let directory: URL
    private let routing: MirrorRouting
    private var memory: [String: SendableImage] = [:]
    private var memoryOrder: [String] = []
    private let memoryLimit = 180
    private var downloads: [URL: Task<Data?, Never>] = [:]
    private var generation = UUID()
    private let gate = ImageDownloadGate(limit: 4)

    init(session: URLSession? = nil, directory: URL? = nil, routing: MirrorRouting = .shared) {
        self.routing = routing
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 18
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.urlCache = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 256 * 1024 * 1024)
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
            return cached
        }

        let currentGeneration = generation
        // Reuse full-size images cached by earlier versions, including when offline.
        var cgImage: CGImage?
        if requestURL != url, let original = diskData(for: url) ?? diskData(for: canonical) {
            cgImage = downsample(data: original, maxPixel: maxPixel)
        }
        if cgImage == nil, let data = await data(for: requestURL) {
            cgImage = downsample(data: data, maxPixel: maxPixel)
        }
        guard generation == currentGeneration, !Task.isCancelled else { return nil }
        if cgImage == nil, requestURL != url, let data = await data(for: url) {
            cgImage = downsample(data: data, maxPixel: maxPixel)
        }

        guard generation == currentGeneration, !Task.isCancelled, let cgImage else { return nil }
        // Another caller may have decoded the shared download while we were suspended.
        if let cached = memory[key] { return cached }
        let wrapped = SendableImage(cgImage: cgImage)
        memory[key] = wrapped
        memoryOrder.append(key)
        trimMemory()
        return wrapped
    }

    func clear() {
        generation = UUID()
        for download in downloads.values { download.cancel() }
        downloads.removeAll()
        memory.removeAll()
        memoryOrder.removeAll()
        session.configuration.urlCache?.removeAllCachedResponses()
        if let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for url in contents { try? FileManager.default.removeItem(at: url) }
        }
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

    private func diskData(for url: URL) -> Data? {
        guard let data = try? Data(contentsOf: fileURL(for: url)), !data.isEmpty else { return nil }
        return data
    }

    private func data(for url: URL) async -> Data? {
        if let disk = diskData(for: url) { return disk }
        if let download = downloads[url] { return await download.value }

        let currentGeneration = generation
        let download = Task { [self] () -> Data? in
            await fetchData(for: url)
        }
        downloads[url] = download
        let data = await download.value
        guard generation == currentGeneration else { return nil }
        downloads[url] = nil
        if let data { try? data.write(to: fileURL(for: url), options: .atomic) }
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

    private func trimMemory() {
        while memoryOrder.count > memoryLimit {
            let key = memoryOrder.removeFirst()
            memory.removeValue(forKey: key)
        }
    }

    private func fileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest + ".img")
    }

    private func downsample(data: Data, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
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
