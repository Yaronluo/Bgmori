import Foundation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    let settings: AppSettings
    let api: APIClient
    let auth: AuthManager
    let library: LibraryStore
    let router: AppRouter
    let social: SocialService
    let categories: CategoryStore
    let recentSubjects: RecentSubjectsStore

    var calendar: [CalendarDay] = []
    var ranking: [Subject] = []
    var seasonal: [Subject] = []
    var isLoadingHome = false
    var showLogin = false
    var showSettings = false
    var toast: ToastMessage?

    private var didBootstrap = false
    private var didLoadCalendar = false
    private var didLoadHome = false

    init() {
        let settings = AppSettings()
        let api = APIClient()
        let auth = AuthManager(api: api, settings: settings)
        self.settings = settings
        self.api = api
        self.auth = auth
        self.library = LibraryStore(api: api, auth: auth)
        self.router = AppRouter()
        self.social = SocialService(api: api)
        self.categories = CategoryStore(api: api)
        self.recentSubjects = RecentSubjectsStore()
    }

    var isGuest: Bool { !auth.isLoggedIn }
    var displayName: String { auth.displayName }
    var username: String? { auth.username }

    var todayWeekday: Int {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return ((weekday + 5) % 7) + 1
    }

    var todayAiring: [LegacySubject] {
        calendar.first(where: { $0.weekday.id == todayWeekday })?.items ?? []
    }

    var continueWatching: [UserSubjectCollection] {
        library.watching
            .sorted { ($0.updatedAt ?? "") > ($1.updatedAt ?? "") }
            .prefix(12)
            .map { $0 }
    }

    var seasonLabel: String {
        let now = Date()
        let year = Calendar.current.component(.year, from: now)
        let month = Calendar.current.component(.month, from: now)
        return "\(year) 年 \(month) 月"
    }

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true

        #if DEBUG
        applyDebugRouteIfNeeded()
        #endif

        await auth.restore()
        if auth.isLoggedIn, let username = auth.username {
            await library.loadAll(username: username, force: true)
        }
        await loadCalendar()
        await loadHome()
        await updateDailyReminder()
    }

    #if DEBUG
    private func applyDebugRouteIfNeeded() {
        guard let raw = ProcessInfo.processInfo.environment["BGMORI_ROUTE"]?.trimmed, !raw.isEmpty else { return }
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        let name = parts[0]
        let value = parts.count > 1 ? parts[1] : ""

        switch name {
        case "subject": router.selectedSection = .home; router.homePath = [.subject(Int(value) ?? 8)]
        case "episode": router.selectedSection = .home; router.homePath = [.episode(Int(value) ?? 1027)]
        case "comments": router.selectedSection = .home; router.homePath = [.subject(Int(value) ?? 8), .comments(Int(value) ?? 8)]
        case "revisions": router.selectedSection = .home; router.homePath = [.subject(Int(value) ?? 8), .revisions(Int(value) ?? 8)]
        case "blogs": router.selectedSection = .home; router.homePath = [.blogs]
        case "blog": router.selectedSection = .home; router.homePath = [.blog(Int(value) ?? 382206)]
        case "group": router.selectedSection = .profile; router.profilePath = [.group(value.isEmpty ? "pixiv" : value)]
        case "topic": router.selectedSection = .profile; router.profilePath = [.topic(Int(value) ?? 5155)]
        case "timeline": router.selectedSection = .profile; router.profilePath = [.timeline(value.isEmpty ? "sai" : value)]
        case "index": router.selectedSection = .home; router.homePath = [.index(Int(value) ?? 1)]
        case "calendar": router.openCalendar()
        case "categories":
            router.selectedSection = .categories
            if let rawType = Int(value), let type = SubjectType(rawValue: rawType) {
                categories.selectType(type)
            }
        case "library": router.selectedSection = .library
        case "search":
            router.openSearch(query: value)
        case "login": showLogin = true
        case "settings": showSettings = true
        case "profile": router.selectedSection = .profile
        default: break
        }
        #if os(macOS)
        switch router.selectedSection {
        case .home: router.macPath = router.homePath
        case .categories: router.macPath = router.categoriesPath
        case .calendar: router.macPath = router.calendarPath
        case .library: router.macPath = router.libraryPath
        case .search: router.macPath = router.searchPath
        case .profile: router.macPath = router.profilePath
        }
        #endif
    }
    #endif

    func loadCalendar(force: Bool = false) async {
        guard force || !didLoadCalendar else { return }
        didLoadCalendar = true
        do {
            calendar = try await api.calendar().sorted { $0.weekday.id < $1.weekday.id }
        } catch {
            showToast((error as? LocalizedError)?.errorDescription ?? "放送表加载失败", isError: true)
        }
    }

    func loadHome(force: Bool = false) async {
        guard force || !didLoadHome else { return }
        guard !isLoadingHome else { return }
        isLoadingHome = true
        didLoadHome = true
        defer { isLoadingHome = false }

        let now = Date()
        let year = Calendar.current.component(.year, from: now)
        let month = Calendar.current.component(.month, from: now)

        do {
            async let rankingPage = api.browseSubjects(type: SubjectType.anime.rawValue, sort: "rank", limit: 12)
            async let seasonalPage = api.browseSubjects(type: SubjectType.anime.rawValue, sort: "date", year: year, month: month, limit: 12)
            let (rankingResult, seasonalResult) = try await (rankingPage, seasonalPage)
            ranking = rankingPageFilter(rankingResult.data)
            seasonal = rankingPageFilter(seasonalResult.data)
        } catch {
            if ranking.isEmpty && seasonal.isEmpty {
                showToast((error as? LocalizedError)?.errorDescription ?? "首页加载失败", isError: true)
            }
        }
    }

    private func rankingPageFilter(_ subjects: [Subject]) -> [Subject] {
        guard !settings.showNSFW else { return subjects }
        return subjects.filter { !$0.nsfw }
    }

    func refreshAll() async {
        if router.selectedSection == .categories {
            await categories.load(categories.query(includeNSFW: settings.showNSFW), force: true)
            showToast("已刷新")
            return
        }
        await auth.refreshIfNeeded()
        if auth.isLoggedIn, let username = auth.username {
            await library.loadAll(username: username, force: true)
        }
        await loadCalendar(force: true)
        await loadHome(force: true)
        await updateDailyReminder()
        showToast("已刷新")
    }

    func signIn() async {
        await auth.signIn()
        if auth.isLoggedIn, let username = auth.username {
            await library.loadAll(username: username, force: true)
            await updateDailyReminder()
            showToast("欢迎回来，\(auth.displayName)")
        } else if let error = auth.errorMessage {
            showToast(error, isError: true)
        }
    }

    func signInWithToken(_ token: String) async {
        await auth.signInWithToken(token)
        if auth.isLoggedIn, let username = auth.username {
            await library.loadAll(username: username, force: true)
            await updateDailyReminder()
            showToast("登录成功")
        } else if let error = auth.errorMessage {
            showToast(error, isError: true)
        }
    }

    func signOut() {
        auth.signOut()
        library.reset()
        showToast("已退出登录")
    }

    func requireLogin() {
        showLogin = true
    }

    func updateDailyReminder() async {
        let watchingIDs = Set(library.watching.map(\.subjectId))
        let count = todayAiring.filter { watchingIDs.contains($0.id) }.count
        await NotificationManager.shared.scheduleDailyReminder(enabled: settings.dailyReminder, count: count)
    }

    func enableDailyReminder() async -> Bool {
        let granted = await NotificationManager.shared.requestAuthorization()
        if granted {
            settings.dailyReminder = true
            await updateDailyReminder()
        } else {
            settings.dailyReminder = false
            showToast("通知权限未开启，可在系统设置中允许", isError: true)
        }
        return granted
    }

    func clearCaches() async {
        await api.clearCache()
        await ImageLoader.shared.clear()
        URLCache.shared.removeAllCachedResponses()
        showToast("缓存已清理")
    }

    func cacheSizeText() async -> String {
        let apiSize = await api.cacheSize()
        let imageSize = await ImageLoader.shared.cacheSize()
        return ByteCountFormatter.string(apiSize + imageSize)
    }

    func showToast(_ text: String, isError: Bool = false) {
        let message = ToastMessage(text: text, isError: isError)
        toast = message
        Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if toast?.id == message.id { toast = nil }
        }
    }

    func handleOpenURL(_ url: URL) {
        router.handle(url: url)
    }
}
