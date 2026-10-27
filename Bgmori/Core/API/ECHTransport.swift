#if BGMORI_ECH
import Foundation

struct ECHInfo: Decodable, Sendable {
    let runtime: String
    let configReady: Bool
    let configAgeSeconds: Int
    let acceptedConnections: UInt64
    let proxyDisabled: Bool
    let directInterface: String
    let activeRequests: Int
}

struct ECHFailure: LocalizedError, Sendable {
    let code: String
    var errorDescription: String? {
        switch code {
        case "ECH_CONFIG_UNAVAILABLE": "无法获取 ECH 配置，请稍后重试"
        case "ECH_REJECTED", "ECH_NOT_ACCEPTED": "服务器未接受 ECH 加密握手"
        case "RESPONSE_TOO_LARGE": "响应内容超过读取上限"
        case "UNSUPPORTED_HOST", "UNSUPPORTED_METHOD": "此请求不能使用 ECH 直连"
        default: "ECH 加密直连失败"
        }
    }
}

enum ECHTransport {
    private struct Input: Encodable, Sendable {
        let url: String
        let method: String
        let headers: [String: String]
        let body: Data?
        let timeoutMilliseconds: Int
    }
    private struct Output: Decodable {
        let status: Int
        let headers: [String: String]?
        let body: Data?
        let echAccepted: Bool
        let error: String?
    }

    static var info: ECHInfo? {
        guard let pointer = BgmoriECHInfo() else { return nil }
        defer { BgmoriECHFree(pointer) }
        return try? JSONDecoder().decode(ECHInfo.self, from: Data(String(cString: pointer).utf8))
    }

    static func data(for request: URLRequest, timeout: TimeInterval) async throws -> (Data, URLResponse) {
        try Task.checkCancellation()
        guard let marker = request.url, let official = MirrorRouting.echOrigin(for: marker) else {
            throw ECHFailure(code: "UNSUPPORTED_HOST")
        }
        let input = Input(url: official.absoluteString, method: request.httpMethod ?? "GET",
                          headers: request.allHTTPHeaderFields ?? [:], body: request.httpBody,
                          timeoutMilliseconds: max(1, Int(timeout * 1000)))
        let json = String(decoding: try JSONEncoder().encode(input), as: UTF8.self)
        let identifier = UUID().uuidString
        identifier.withCString { BgmoriECHBegin($0) }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // The C call uses Go's cancellable request context; never block a Swift actor.
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        guard let pointer = identifier.withCString({ id in
                            json.withCString { BgmoriECHPerform(id, $0) }
                        }) else { throw ECHFailure(code: "INVALID_RESPONSE") }
                        defer { BgmoriECHFree(pointer) }
                        let decoded = try JSONDecoder().decode(Output.self, from: Data(String(cString: pointer).utf8))
                        if let code = decoded.error {
                            if code == "CANCELLED" { throw URLError(.cancelled) }
                            if code == "TIMEOUT" { throw URLError(.timedOut) }
                            throw ECHFailure(code: code)
                        }
                        guard decoded.echAccepted,
                              let response = HTTPURLResponse(url: official, statusCode: decoded.status,
                                                             httpVersion: "HTTP/1.1", headerFields: decoded.headers) else {
                            throw ECHFailure(code: "ECH_NOT_ACCEPTED")
                        }
                        continuation.resume(returning: (decoded.body ?? Data(), response))
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: {
            identifier.withCString { BgmoriECHCancel($0) }
        }
    }
}
#endif
