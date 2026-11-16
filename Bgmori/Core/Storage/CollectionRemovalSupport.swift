import Foundation

enum BangumiWebSessionError: LocalizedError, Sendable, Equatable {
    case signInRequired
    case sessionExpired
    case notRemoved
    case websiteChanged
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .signInRequired: "应用内取消收藏需要先登录一次官网会话。"
        case .sessionExpired: "官网登录已过期，请重新登录后再试。"
        case .notRemoved: "官网没有确认取消收藏，请稍后重试。"
        case .websiteChanged: "收藏页面暂时无法识别，请稍后重试或在网页中移除。"
        case .http(let code): "官网返回错误（\(code)），请稍后重试。"
        }
    }
}

protocol SubjectCollectionRemoving: Sendable {
    func removeCollection(subjectID: Int) async throws
}
