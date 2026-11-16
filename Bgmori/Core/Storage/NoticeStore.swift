import Foundation

/// The account's 提醒 feed. Read-only: marking notices read is the only write,
/// and it stays inside the official app's token.
@MainActor
@Observable
final class NoticeStore {
    private let api: APIClient
    private let auth: AuthManager

    private(set) var notices: [Notice] = []
    private(set) var unreadCount = 0
    private(set) var hasLoaded = false
    private(set) var isLoading = false
    private(set) var isMarkingAll = false
    var errorText: String?

    private var lastUnreadRead: Date?
    private var isReadingUnread = false
    private var generation = UUID()

    #if DEBUG
    /// Layout fixtures for screenshots; never a stand-in for account data.
    private let isPreview = ProcessInfo.processInfo.environment["BGMORI_PREVIEW_NOTICES"] == "1"
    var isPreviewing: Bool { isPreview }
    #else
    var isPreviewing: Bool { false }
    #endif

    init(api: APIClient, auth: AuthManager) {
        self.api = api
        self.auth = auth
        #if DEBUG
        if isPreview, let page = Self.previewPage {
            notices = page.data
            unreadCount = page.total
            hasLoaded = true
        }
        #endif
    }

    func reset() {
        generation = UUID()
        notices = []
        unreadCount = 0
        hasLoaded = false
        isLoading = false
        isMarkingAll = false
        errorText = nil
        lastUnreadRead = nil
    }

    func load() async {
        #if DEBUG
        if isPreview { return }
        #endif
        guard auth.isLoggedIn else {
            reset()
            hasLoaded = true
            return
        }
        guard !isLoading else { return }
        let generation = self.generation
        isLoading = true
        errorText = nil
        defer {
            if generation == self.generation {
                isLoading = false
                hasLoaded = true
            }
        }
        do {
            let page = try await api.notices()
            guard generation == self.generation, !Task.isCancelled else { return }
            notices = page.data
            // `total` is the account's unread count; fall back to the visible
            // rows only if the server ever stops filling it.
            let visibleUnread = page.data.filter(\.unread).count
            unreadCount = page.total > 0 ? page.total : visibleUnread
            lastUnreadRead = Date()
        } catch {
            guard generation == self.generation, !Task.isCancelled else { return }
            errorText = Self.message(for: error)
        }
    }

    /// Cheap badge refresh. Runs on launch, when the app returns to the
    /// foreground, and after a pull-to-refresh.
    func refreshUnread(force: Bool = false) async {
        guard auth.isLoggedIn else { return }
        guard !isReadingUnread else { return }
        if !force, let lastUnreadRead, Date().timeIntervalSince(lastUnreadRead) < 45 { return }
        isReadingUnread = true
        defer { isReadingUnread = false }
        let generation = self.generation
        do {
            let page = try await api.notices(unreadOnly: true, limit: 1)
            guard generation == self.generation, !Task.isCancelled else { return }
            unreadCount = page.total
            lastUnreadRead = Date()
        } catch APIError.unauthorized {
            guard generation == self.generation else { return }
            unreadCount = 0
        } catch {
            // A badge read is best-effort; the page keeps its last known state.
        }
    }

    func markRead(_ notice: Notice) async {
        guard let index = notices.firstIndex(where: { $0.id == notice.id }), notices[index].unread else { return }
        notices[index].unread = false
        unreadCount = max(0, unreadCount - 1)
        do {
            try await api.markNoticesRead(ids: [notice.id])
        } catch {
            if let index = notices.firstIndex(where: { $0.id == notice.id }) {
                notices[index].unread = true
            }
            unreadCount += 1
        }
    }

    func markAllRead() async {
        guard auth.isLoggedIn, !isMarkingAll else { return }
        let snapshot = notices
        let previousUnread = unreadCount
        guard unreadCount > 0 || notices.contains(where: \.unread) else { return }
        isMarkingAll = true
        errorText = nil
        for index in notices.indices { notices[index].unread = false }
        unreadCount = 0
        defer { isMarkingAll = false }
        do {
            try await api.markNoticesRead()
        } catch {
            notices = snapshot
            unreadCount = previousUnread
            errorText = "标记已读失败，请重试"
        }
    }

    private static func message(for error: Error) -> String {
        if let api = error as? APIError, case .unauthorized = api {
            return "登录已过期，请重新登录"
        }
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return "提醒加载失败，请检查网络后重试"
    }

    #if DEBUG
    /// Goes through the real decoder so the fixture also proves the payload shape.
    private static let previewPage: NoticePage? = {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let json = """
        {"data":[
          {"id":91001,"type":2,"sender":{"id":1,"username":"sai","nickname":"Sai","avatar":{"small":"https://lain.bgm.tv/pic/user/s/000/00/00/1.jpg","medium":"https://lain.bgm.tv/pic/user/m/000/00/00/1.jpg","large":"https://lain.bgm.tv/pic/user/l/000/00/00/1.jpg"}},"title":"十月新番讨论帖 · 第 4 话","mainID":5155,"relatedID":100234,"createdAt":\(now - 180_000),"unread":true},
          {"id":91002,"type":29,"sender":{"id":2,"username":"chii","nickname":"","avatar":{"small":"","medium":"","large":""}},"title":"今年最值得补的三部剧场版","mainID":382206,"relatedID":5001,"createdAt":\(now - 3_600_000),"unread":true},
          {"id":91003,"type":14,"sender":{"id":3,"username":"yaron","nickname":"Yaron","avatar":{"small":"","medium":"","large":""}},"title":"","mainID":0,"relatedID":0,"createdAt":\(now - 86_400_000),"unread":false}
        ],"total":2}
        """
        return try? JSONDecoder().decode(NoticePage.self, from: Data(json.utf8))
    }()
    #endif
}
