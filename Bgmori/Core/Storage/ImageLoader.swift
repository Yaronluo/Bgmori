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
    private var memory: [String: SendableImage] = [:]
    private var memoryOrder: [String] = []
    private let memoryLimit = 180
    private var downloads: [URL: Task<Data?, Never>] = [:]
    private var generation = UUID()

    init(session: URLSession? = nil, directory: URL? = nil) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.urlCache = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 256 * 1024 * 1024)
        configuration.httpShouldSetCookies = false
        self.session = session ?? URLSession(configuration: configuration)

        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.directory = directory ?? base.appendingPathComponent("BgmoriImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    func image(for url: URL, maxPixel: Int) async -> SendableImage? {
        guard maxPixel > 0, !Task.isCancelled else { return nil }
        let requestURL = Self.requestURL(for: url, maxPixel: maxPixel)
        let key = "\(requestURL.absoluteString)#\(maxPixel)"
        if let cached = memory[key] {
            return cached
        }

        let currentGeneration = generation
        // Reuse full-size images cached by earlier versions, including when offline.
        var cgImage: CGImage?
        if requestURL != url, let original = diskData(for: url) {
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

    /// Only resize Bangumi's original cover paths. Avatars and external images keep their URLs.
    static func requestURL(for url: URL, maxPixel: Int) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host == "lain.bgm.tv",
              components.query == nil,
              let width = [200, 400, 600, 800, 1200].first(where: { $0 >= maxPixel }) else { return url }
        let path = components.path.replacingOccurrences(of: #"^/r/\d+/"#, with: "/", options: .regularExpression)
        guard path.hasPrefix("/pic/cover/l/") else { return url }
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
        let download = Task { [session] () -> Data? in
            do {
                var request = URLRequest(url: url)
                request.assumesHTTP3Capable = false
                request.setValue(APIClient.userAgent, forHTTPHeaderField: "User-Agent")
                let (data, response) = try await session.data(for: request)
                guard !Task.isCancelled,
                      let http = response as? HTTPURLResponse,
                      (200...299).contains(http.statusCode), !data.isEmpty,
                      CGImageSourceCreateWithData(data as CFData, nil) != nil else { return nil }
                return data
            } catch {
                return nil
            }
        }
        downloads[url] = download
        let data = await download.value
        guard generation == currentGeneration else { return nil }
        downloads[url] = nil
        if let data { try? data.write(to: fileURL(for: url), options: .atomic) }
        return data
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
