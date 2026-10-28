import Foundation

private final class AiringStub: @unchecked Sendable {
    static let shared = AiringStub()
    private let lock = NSLock()
    private var payload = Data()
    private var status = 200
    private var recorded: [URLRequest] = []

    func configure(_ data: Data, status: Int = 200) {
        lock.withLock { payload = data; self.status = status }
    }
    func reply(_ request: URLRequest) -> (Data, Int) {
        lock.withLock { recorded.append(request); return (payload, status) }
    }
    var requests: [URLRequest] { lock.withLock { recorded } }
}

private final class AiringProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (data, status) = AiringStub.shared.reply(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
struct BgmlistTests {
    static func fixture(_ timestamp: String = "2026-10-07T13:30:00.000Z") -> Data {
        Data("""
        {"items":[{"begin":"1999-01-01T00:00:00Z","broadcast":"R/\(timestamp)/P7D","end":"",
          "sites":[{"site":"aniList","id":"999"},{"site":"bangumi","id":"393010"}]}]}
        """.utf8)
    }

    static func main() async throws {
        let decoder = JSONDecoder()
        let schedule = try decoder.decode(BgmlistSchedule.self, from: fixture())
        let airings = schedule.airings()
        precondition(airings.count == 1 && airings[999] == nil, "Match only a Bangumi site's ID")
        precondition(airings[393010]?.weekday == 3 && airings[393010]?.clockTime == "21:30")
        precondition(airings[393010]?.label(for: 3) == "21:30 播出")
        let midnight = try decoder.decode(BgmlistSchedule.self, from: fixture("2026-10-11T16:15:00Z"))
        precondition(midnight.airings()[393010]?.weekday == 1)
        precondition(midnight.airings()[393010]?.label(for: 7) == "周一 00:15 播出",
                     "UTC Sunday evening must become Beijing Monday, not Sunday")
        let offset = try decoder.decode(BgmlistSchedule.self, from: fixture("2026-10-07T22:30:00+09:00"))
        precondition(offset.airings()[393010]?.clockTime == "21:30")

        for replacement in ["", "R/invalid/P7D", "R/2026-10-07T13:30:00/P7D", "R/2026-10-07T13:30:00Z/P0D"] {
            let invalid = String(data: fixture(), encoding: .utf8)!
                .replacingOccurrences(of: "R/2026-10-07T13:30:00.000Z/P7D", with: replacement)
            let invalidSchedule = try decoder.decode(BgmlistSchedule.self, from: Data(invalid.utf8))
            precondition(invalidSchedule.airings().isEmpty,
                         "Do not invent times from a premiere date or unsupported cadence")
        }
        let ended = String(data: fixture(), encoding: .utf8)!
            .replacingOccurrences(of: "\"end\":\"\"", with: "\"end\":\"2020-01-01T00:00:00Z\"")
        let endedSchedule = try decoder.decode(BgmlistSchedule.self, from: Data(ended.utf8))
        precondition(endedSchedule.airings().isEmpty)
        print("PASS: Bangumi ID matching, Beijing clock, UTC/offset midnight rollover, unknown/ended schedules")

        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.protocolClasses = [AiringProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let namespace = "BgmoriBgmlistTests-\(UUID())"
        let cache = DiskCache(namespace: namespace)
        let routing = MirrorRouting(systemProxy: { _ in false })
        try routing.configure(ConnectionSettings(mode: .custom, customRoot: "https://custom.example"), persistChanges: false)
        let api = APIClient(session: session, cache: cache, routing: routing, discoverMirrors: false)
        await api.setToken("synthetic-test-token")
        AiringStub.shared.configure(fixture())
        let first = try await api.bgmlistSchedule()
        precondition(first.airings()[393010]?.clockTime == "21:30")
        let sent = AiringStub.shared.requests[0]
        precondition(sent.url?.absoluteString == "https://bgmlist.com/api/v1/bangumi/onair")
        precondition(sent.value(forHTTPHeaderField: "Authorization") == nil)
        precondition(sent.value(forHTTPHeaderField: "Cookie") == nil)
        precondition(sent.value(forHTTPHeaderField: "User-Agent") == APIClient.userAgent)
        _ = try await api.bgmlistSchedule()
        precondition(AiringStub.shared.requests.count == 1, "Fresh cache should avoid another request")
        AiringStub.shared.configure(fixture("2026-10-07T14:00:00Z"))
        let refreshed = try await api.bgmlistSchedule(force: true)
        precondition(refreshed.airings()[393010]?.clockTime == "22:00" && AiringStub.shared.requests.count == 2)
        AiringStub.shared.configure(Data("{\"unexpected\":true}".utf8))
        do {
            _ = try await api.bgmlistSchedule(force: true)
            preconditionFailure("Malformed feed must report a decoding failure")
        } catch {}
        let retained = try await api.bgmlistSchedule()
        precondition(retained.airings()[393010]?.clockTime == "22:00", "Invalid data must not replace the last valid cache")

        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent(namespace)
        let file = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)[0]
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-BgmlistSchedule.ttl - 60)],
                                              ofItemAtPath: file.path)
        AiringStub.shared.configure(Data("{}".utf8), status: 503)
        let offline = try await api.bgmlistSchedule()
        precondition(offline.airings()[393010]?.clockTime == "22:00", "Automatic failure should retain usable stale data")
        do {
            _ = try await api.bgmlistSchedule(force: true)
            preconditionFailure("Explicit refresh must report failure instead of pretending cached data is fresh")
        } catch {}
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-BgmlistSchedule.maxStale - 60)],
                                              ofItemAtPath: file.path)
        do {
            _ = try await api.bgmlistSchedule()
            preconditionFailure("Expired clocks must not survive indefinitely")
        } catch {}
        await cache.clear()
        try? FileManager.default.removeItem(at: directory)
        print("PASS: anonymous bgmlist request, custom-root isolation, fresh/stale cache, explicit refresh and invalid-response retention")

        if CommandLine.arguments.contains("--live") {
            let live = APIClient(discoverMirrors: false)
            let value = try await live.bgmlistSchedule(force: true)
            let times = value.airings()
            precondition(!times.isEmpty)
            print("PASS: live bgmlist feed decoded \(value.items.count) on-air entries and \(times.count) weekly Bangumi clocks")
            if let time = times[393010] { print("Live sample 393010: \(time.label(for: 3))（北京时间）") }
        }
    }
}
