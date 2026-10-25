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

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.urlCache = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 256 * 1024 * 1024)
        session = URLSession(configuration: configuration)

        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        directory = base.appendingPathComponent("BgmoriImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func image(for url: URL, maxPixel: Int) async -> SendableImage? {
        let key = "\(url.absoluteString)#\(maxPixel)"
        if let cached = memory[key] {
            return cached
        }

        let data: Data
        if let disk = try? Data(contentsOf: fileURL(for: url)), !disk.isEmpty {
            data = disk
        } else {
            do {
                var request = URLRequest(url: url)
                request.assumesHTTP3Capable = false
                let (downloaded, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), !downloaded.isEmpty else {
                    return nil
                }
                data = downloaded
                try? downloaded.write(to: fileURL(for: url), options: .atomic)
            } catch {
                return nil
            }
        }

        guard let cgImage = downsample(data: data, maxPixel: maxPixel) else { return nil }
        let wrapped = SendableImage(cgImage: cgImage)
        memory[key] = wrapped
        memoryOrder.append(key)
        trimMemory()
        return wrapped
    }

    func clear() {
        memory.removeAll()
        memoryOrder.removeAll()
        if let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for url in contents { try? FileManager.default.removeItem(at: url) }
        }
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
