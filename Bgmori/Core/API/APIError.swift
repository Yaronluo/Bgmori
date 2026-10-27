import Foundation

enum APIError: LocalizedError, Sendable {
    case invalidURL
    case unauthorized
    case forbidden
    case notFound
    case rateLimited
    case server(Int, String?)
    case decoding(String)
    case network(String)
    case verificationRequired
    case cancelled
    case message(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "请求地址无效"
        case .unauthorized: "登录已过期，请重新登录"
        case .forbidden: "没有权限访问该内容"
        case .notFound: "内容不存在或已被删除"
        case .rateLimited: "请求太频繁，请稍后再试"
        case .server(let code, let message): message ?? "服务器错误（\(code)）"
        case .decoding: "数据解析失败"
        case .network(let message): message.isEmpty ? "网络连接失败" : message
        case .verificationRequired: "服务需要网页验证，请在浏览器中打开。"
        case .cancelled: "请求已取消"
        case .message(let message): message
        }
    }

    var isRetryable: Bool {
        switch self {
        case .network, .server, .rateLimited, .verificationRequired: true
        default: false
        }
    }

    var isUncertainWrite: Bool {
        switch self {
        case .network, .server: true
        default: false
        }
    }

    static func from(urlError: URLError) -> APIError {
        if urlError.code == .cancelled { return .cancelled }
        return .network(urlError.localizedDescription)
    }
}
