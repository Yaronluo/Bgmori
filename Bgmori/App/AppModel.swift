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
    var isLoadingCalendar = false
    var hasLoadedCalendar = false
    var calendarError: String?
    var ranking: [Subject] = []
    var seasonal: [Subject] = []
    var trending: [Subject] = []
    var movies: [Subject] = []
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
        let items = calendar.first(where: { $0.weekday.id == todayWeekday })?.items ?? []
        // Put shows the user is already following first, then the better rated ones.
        return items.sorted { lhs, rhs in
            let lhsWatching = library.isWatching(lhs.id)
            let rhsWatching = library.isWatching(rhs.id)
            if lhsWatching != rhsWatching { return lhsWatching }
            let lhsScore = lhs.rating?.score ?? 0
            let rhsScore = rhs.rating?.score ?? 0
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
        }
    }

    var continueWatching: [UserSubjectCollection] {
        library.watching
            .sorted { ($0.updatedAt ?? "") > ($1.updatedAt ?? "") }
            .prefix(12)
            .map { $0 }
    }

    var seasonLabel: String {
        let season = currentSeason()
        return "\(season.year) 年 \(season.month) 月"
    }

    var seasonTag: String {
        let season = currentSeason()
        return "\(season.year)年\(season.month)月"
    }

    private func currentSeason(for date: Date = .now) -> (year: Int, month: Int) {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        let year = components.year ?? 2026
        let month = components.month ?? 1
        let startMonth = ((month - 1) / 3) * 3 + 1
        return (year, startMonth)
    }

    private func isoDate(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
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
        case "character": router.selectedSection = .home; router.homePath = [.character(Int(value) ?? 466)]
        case "person": router.selectedSection = .home; router.homePath = [.person(Int(value) ?? 1)]
        case "episode": router.selectedSection = .home; router.homePath = [.episode(Int(value) ?? 1027)]
        case "comments": router.selectedSection = .home; router.homePath = [.subject(Int(value) ?? 8), .comments(Int(value) ?? 8)]
        case "revisions": router.selectedSection = .home; router.homePath = [.subject(Int(value) ?? 8), .revisions(Int(value) ?? 8)]
        case "blogs": router.selectedSection = .home; router.homePath = [.blogs]
        case "blog": router.selectedSection = .home; router.homePath = [.blog(Int(value) ?? 382206)]
        case "group": router.selectedSection = .profile; router.profilePath = [.group(value.isEmpty ? "pixiv" : value)]
        case "topic": router.selectedSection = .profile; router.profilePath = [.topic(Int(value) ?? 5155)]
        case "timeline": router.selectedSection = .profile; router.profilePath = [.timeline(value.isEmpty ? "sai" : value)]
        case "index": router.selectedSection = .home; router.homePath = [.index(Int(value) ?? 1)]
        case "tag": router.selectedSection = .home; router.homePath = [.tag(value.isEmpty ? "治愈" : value)]
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
        case "friends":
            router.selectedSection = .profile
            router.profilePath = [.friends(value.isEmpty ? "yaron" : value)]
        case "people":
            router.selectedSection = .profile
            router.profilePath = [.people(value.isEmpty ? "yaron" : value)]
        case "ratings":
            router.selectedSection = .profile
            router.profilePath = [.ratings]
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
        guard !isLoadingCalendar else { return }
        didLoadCalendar = true
        isLoadingCalendar = true
        calendarError = nil
        defer {
            isLoadingCalendar = false
            hasLoadedCalendar = true
        }

        do {
            calendar = try await api.calendar().sorted { $0.weekday.id < $1.weekday.id }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "放送表加载失败"
            calendarError = message
            showToast(message, isError: true)
        }
    }

    func loadHome(force: Bool = false) async {
        guard force || !didLoadHome else { return }
        guard !isLoadingHome else { return }
        isLoadingHome = true
        didLoadHome = true
        defer { isLoadingHome = false }

        let season = currentSeason()
        let today = isoDate(Date())
        let recentStart = isoDate(Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date())
        let includeNSFW = settings.showNSFW

        var trendingFilter = SubjectSearchFilter()
        trendingFilter.type = [SubjectType.anime.rawValue]
        trendingFilter.airDate = [">=\(recentStart)", "<=\(today)"]
        trendingFilter.nsfw = includeNSFW ? nil : false

        var movieFilter = SubjectSearchFilter()
        movieFilter.type = [SubjectType.anime.rawValue]
        movieFilter.tag = ["剧场版"]
        movieFilter.nsfw = includeNSFW ? nil : false

        async let trendingPage = api.searchSubjects(
            keyword: "",
            sort: "heat",
            filter: trendingFilter,
            limit: 18,
            cacheKey: "home-trending-\(recentStart)-\(today)-\(includeNSFW ? 1 : 0)",
            ttl: 1_800
        )
        async let moviePage = api.searchSubjects(
            keyword: "",
            sort: "heat",
            filter: movieFilter,
            limit: 16,
            cacheKey: "home-movies-\(includeNSFW ? 1 : 0)",
            ttl: 3_600
        )
        async let rankingPage = api.browseSubjects(
            type: SubjectType.anime.rawValue,
            sort: "rank",
            limit: 12,
            force: force
        )
        async let seasonalPage = api.browseSubjects(
            type: SubjectType.anime.rawValue,
            sort: "rank",
            year: season.year,
            month: season.month,
            limit: 18,
            force: force
        )

        let trendingResult = try? await trendingPage
        let movieResult = try? await moviePage
        let rankingResult = try? await rankingPage
        let seasonalResult = try? await seasonalPage

        let loadedTrending = Array(rankingPageFilter(trendingResult?.data ?? []).prefix(8))
        let loadedRanking = Array(rankingPageFilter(rankingResult?.data ?? []).prefix(12))
        let loadedMovies = Array(rankingPageFilter(movieResult?.data ?? []).prefix(16))
        var loadedSeasonal = Array(rankingPageFilter(seasonalResult?.data ?? []).prefix(18))

        // Early in a season there may not be enough ranked entries yet; show the
        // complete date-ordered slate instead of an almost empty shelf.
        if loadedSeasonal.count < 4 {
            if let fallback = try? await api.browseSubjects(
                type: SubjectType.anime.rawValue,
                sort: "date",
                year: season.year,
                month: season.month,
                limit: 18,
                force: force
            ) {
                loadedSeasonal = Array(rankingPageFilter(fallback.data).prefix(18))
            }
        }

        if !loadedTrending.isEmpty {
            trending = loadedTrending
        } else if trending.isEmpty, !loadedSeasonal.isEmpty {
            trending = Array(loadedSeasonal.prefix(6))
        }
        if !loadedRanking.isEmpty { ranking = loadedRanking }
        if !loadedSeasonal.isEmpty { seasonal = loadedSeasonal }
        if !loadedMovies.isEmpty { movies = loadedMovies }

        if loadedTrending.isEmpty && loadedRanking.isEmpty && loadedSeasonal.isEmpty && loadedMovies.isEmpty {
            showToast("发现页加载失败，请检查网络后重试", isError: true)
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

    func openCategories() {
        router.selectedSection = .categories
        #if os(macOS)
        router.macPath.removeAll()
        #endif
    }

    func openCategory(type: SubjectType = .anime, sort: CategorySort = .heat, year: Int? = nil, tag: String? = nil) {
        categories.type = type
        categories.sort = sort
        categories.year = year
        categories.tag = tag
        categories.selections = [:]
        router.setPath([], for: .categories)
        router.selectedSection = .categories
        #if os(macOS)
        router.macPath.removeAll()
        #endif
    }

    func openLibrary() {
        router.setPath([], for: .library)
        router.selectedSection = .library
        #if os(macOS)
        router.macPath.removeAll()
        #endif
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
