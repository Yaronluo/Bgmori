import Foundation

private final class CollectionResponses: @unchecked Sendable {
    static let shared = CollectionResponses()
    private let lock = NSLock()
    private var status = 200
    private var payload = Data()
    private var count = 0

    func set(_ body: String, status: Int = 200) {
        lock.withLock { self.status = status; payload = Data(body.utf8) }
    }

    func response() -> (Int, Data) {
        lock.withLock { count += 1; return (status, payload) }
    }

    var requests: Int { lock.withLock { count } }
}

private final class CollectionProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data) = CollectionResponses.shared.response()
        precondition(request.httpMethod == "GET")
        precondition(request.value(forHTTPHeaderField: "User-Agent") == APIClient.userAgent)
        precondition(request.value(forHTTPHeaderField: "Authorization") == nil)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
            httpVersion: "HTTP/1.1", headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct CollectionRefreshTests {
    static func main() async throws {
        let cache = DiskCache(namespace: "BgmoriCollectionTests-\(UUID())")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CollectionProtocol.self]
        let session = URLSession(configuration: configuration)
        let api = APIClient(session: session, cache: cache)
        let responses = CollectionResponses.shared
        // Anonymous public data only; no credentials are read or fabricated.
        responses.set(#"{"total":1,"limit":50,"offset":0,"data":[{"subject_id":8,"subject_type":2,"type":3}]}"#)
        let initial = try await api.userCollections("fixture", auth: false)
        precondition(initial.data.count == 1 && responses.requests == 1)

        responses.set(#"{"total":0,"limit":50,"offset":0,"data":[]}"#)
        let cached = try await api.userCollections("fixture", auth: false)
        precondition(cached.data.count == 1 && responses.requests == 1)
        let refreshed = try await api.userCollections("fixture", auth: false, force: true)
        precondition(refreshed.data.isEmpty && responses.requests == 2)
        let afterRefresh = try await api.userCollections("fixture", auth: false)
        precondition(afterRefresh.data.isEmpty && responses.requests == 2,
                     "A later cached load must not restore the removed collection")
        print("PASS: forced collection refresh bypasses fresh cache and replaces it after removal")

        responses.set(#"{"title":"Unavailable"}"#, status: 503)
        do {
            _ = try await api.userCollections("fixture", auth: false, force: true)
            preconditionFailure("A forced refresh must surface server errors")
        } catch APIError.server(let status, _) {
            precondition(status == 503)
        }
        let preserved = try await api.userCollections("fixture", auth: false)
        precondition(preserved.data.isEmpty, "A failed refresh must preserve the last successful snapshot")
        print("PASS: failed force refresh surfaces errors and preserves the last successful cache")
        await cache.clear()
        session.invalidateAndCancel()

        if CommandLine.arguments.contains("--live") {
            let live = try await APIClient().userCollections("sai", auth: false, force: true)
            precondition(live.total >= live.data.count)
            precondition(Set(live.data.map(\.subjectId)).count == live.data.count)
            print("PASS: live anonymous collection refresh (\(live.data.count) / \(live.total) items)")
        }
    }
}
