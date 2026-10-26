import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

private final class ImageRequests: @unchecked Sendable {
    static let shared = ImageRequests()
    private let lock = NSLock()
    private var requests: [URLRequest] = []
    private var rejectedPaths: Set<String> = []
    private var invalidPaths: Set<String> = []
    private var payload = Data()

    func reset(payload: Data, rejected: Set<String> = [], invalid: Set<String> = []) {
        lock.withLock {
            requests = []
            rejectedPaths = rejected
            invalidPaths = invalid
            self.payload = payload
        }
    }

    func response(for request: URLRequest) -> (Int, Data) {
        lock.withLock {
            requests.append(request)
            let path = request.url!.path
            return (rejectedPaths.contains(path) ? 404 : 200,
                    invalidPaths.contains(path) ? Data("not an image".utf8) : payload)
        }
    }

    var recorded: [URLRequest] { lock.withLock { requests } }
}

private final class ImageStubProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (status, data) = ImageRequests.shared.response(for: request)
        // Keep requests outstanding long enough to exercise actor reentrancy and cancellation.
        Thread.sleep(forTimeInterval: 0.05)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
                                                            httpVersion: "HTTP/1.1", headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@main
struct ImageLoaderTests {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("bgmori-image-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageStubProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let loader = ImageLoader(session: session, directory: directory, routing: MirrorRouting())
        let original = URL(string: "https://lain.bgm.tv/pic/cover/l/test/cover.jpg")!
        let resized = ImageLoader.requestURL(for: original, maxPixel: 597)
        precondition(resized.path == "/r/600/pic/cover/l/test/cover.jpg")
        precondition(ImageLoader.requestURL(for: resized, maxPixel: 280).path == "/r/400/pic/cover/l/test/cover.jpg")
        for path in ["https://example.com/pic/cover/l/test.jpg", "https://lain.bgm.tv/pic/user/l/test.jpg",
                     "https://lain.bgm.tv/pic/cover/c/test.jpg", "https://lain.bgm.tv/pic/cover/l/test.jpg?x=1"] {
            let url = URL(string: path)!
            precondition(ImageLoader.requestURL(for: url, maxPixel: 400) == url)
        }
        precondition(ImageLoader.requestURL(for: original, maxPixel: 1600) == original)
        print("PASS: cover sizing uses bounded CDN widths and preserves other image URLs")

        let payload = fixture()
        ImageRequests.shared.reset(payload: payload)
        let dimensions = await withTaskGroup(of: Int?.self, returning: [Int].self) { group in
            for index in 0..<12 {
                group.addTask {
                    let image = await loader.image(for: original, maxPixel: index.isMultiple(of: 2) ? 597 : 599)
                    return image?.cgImage.height
                }
            }
            var heights: [Int] = []
            for await height in group { if let height { heights.append(height) } }
            return heights
        }
        precondition(dimensions.count == 12 && dimensions.allSatisfy { $0 >= 597 && $0 <= 599 })
        precondition(ImageRequests.shared.recorded.count == 1, "All sizes sharing a source must share one download")
        precondition(ImageRequests.shared.recorded.first?.value(forHTTPHeaderField: "User-Agent") == APIClient.userAgent)
        _ = await loader.image(for: original, maxPixel: 597)
        let diskLoader = ImageLoader(session: session, directory: directory, routing: MirrorRouting())
        let diskImage = await diskLoader.image(for: original, maxPixel: 597)
        precondition(diskImage != nil && ImageRequests.shared.recorded.count == 1)
        print("PASS: concurrent sizes share one request, stay sharp, and reuse memory/disk caches")

        for invalid in [false, true] {
            await loader.clear()
            ImageRequests.shared.reset(payload: payload, rejected: invalid ? [] : [resized.path],
                                       invalid: invalid ? [resized.path] : [])
            let fallback = await loader.image(for: original, maxPixel: 597)
            precondition(fallback != nil)
            precondition(ImageRequests.shared.recorded.map { $0.url!.path } == [resized.path, original.path])
        }
        print("PASS: missing or invalid resized images fall back to the original")

        await loader.clear()
        ImageRequests.shared.reset(payload: payload)
        let digest = SHA256.hash(data: Data(original.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        try payload.write(to: directory.appendingPathComponent(digest + ".img"))
        let oldCache = await loader.image(for: original, maxPixel: 597)
        precondition(oldCache != nil && ImageRequests.shared.recorded.isEmpty)
        print("PASS: original images cached by earlier versions work without a network request")

        await loader.clear()
        ImageRequests.shared.reset(payload: payload, rejected: [resized.path, original.path])
        let failed = await loader.image(for: original, maxPixel: 597)
        precondition(failed == nil)
        ImageRequests.shared.reset(payload: payload)
        let retry = await loader.image(for: original, maxPixel: 597)
        precondition(retry != nil && ImageRequests.shared.recorded.count == 1)
        print("PASS: failed downloads can be retried")

        await loader.clear()
        ImageRequests.shared.reset(payload: payload)
        let pending = Task { await loader.image(for: original, maxPixel: 597) }
        while ImageRequests.shared.recorded.isEmpty { await Task.yield() }
        await loader.clear()
        let cleared = await pending.value
        let size = await loader.cacheSize()
        precondition(cleared == nil && size == 0, "Clearing must not let in-flight requests repopulate caches")
        print("PASS: clearing cancels downloads and prevents late cache writes")

        if CommandLine.arguments.contains("--live") { try await live(directory: directory.appendingPathComponent("live")) }
    }

    private static func fixture() -> Data {
        let context = CGContext(data: nil, width: 900, height: 1300, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 0.3, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 900, height: 1300))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private static func live(directory: URL) async throws {
        let url = URL(string: "https://lain.bgm.tv/pic/cover/l/84/86/505550_OLQmz.jpg")!
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        var sizes: [Int] = []
        for source in [url, ImageLoader.requestURL(for: url, maxPixel: 597)] {
            var request = URLRequest(url: source)
            request.assumesHTTP3Capable = false
            request.setValue(APIClient.userAgent, forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            precondition((response as? HTTPURLResponse)?.statusCode == 200)
            sizes.append(data.count)
        }
        let loader = ImageLoader(session: session, directory: directory, routing: MirrorRouting())
        let image = await loader.image(for: url, maxPixel: 597)
        precondition(image?.cgImage.height == 597 && sizes[1] < sizes[0])
        print("PASS live: original \(sizes[0]) bytes -> resized \(sizes[1]) bytes; decoded \(image!.cgImage.width)x\(image!.cgImage.height)")
    }
}
