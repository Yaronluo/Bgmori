import Foundation
import SwiftUI
import UserNotifications

@MainActor
@Observable
final class AppModel {
    let settings: AppSettings
    let api: APIClient
    let auth: AuthManager
    let webSession: BangumiWebSession
    let library: LibraryStore
    let router: AppRouter
    let social: SocialService
    let categories: CategoryStore
    let recentSubjects: RecentSubjectsStore
    let notifications: NotificationManager
    var reminderAccountReady = false
    var pendingReminderResponse: AiringReminderResponse?
    let reminderPreviewNow = Date()
    var calendarUpdatedAt: Date?
    var calendarTimesUpdatedAt: Date?

    var calendar: [CalendarDay] = [] {
        didSet { calendarContentVersion &+= 1 }
    }
    private(set) var calendarContentVersion = 0
    var isLoadingCalendar = false
    var hasLoadedCalendar = false
    var calendarError: String?
    private(set) var calendarAirings: [Int: BgmlistAiring] = [:]
    var reminderAirings: [Int: BgmlistAiring] = [:]
    private(set) var calendarTimesError: String?
    private var calendarTimesTask: Task<Void, Never>?
    private var didLoadCalendarTimes = false
    private(set) var homeContentVersion = 0
    var ranking: [Subject] = []
    var seasonal: [Subject] = []
    var trending: [Subject] = []
    var movies: [Subject] = []
    var isLoadingHome = false
    var hasLoadedHome = false
    var homeError: String?
    var showLogin = false
    var showSettings = false
    var toast: ToastMessage?
    var hasFinishedStartup = false
    var startupMessage = "正在准备首页…"
    var startupError: String?
    var isCheckingConnections = false
    var connectionCheckSummary: String?

    private var didBootstrap = false
    private var isPreparingStartup = false
    private var didLoadCalendar = false
    private var didLoadHome = false

    @ObservationIgnored private var cachedTodayAiring: (libraryRevision: Int, calendarVersion: Int, weekday: Int, value: [LegacySubject])?
    @ObservationIgnored private var cachedContinueWatching: (libraryRevision: Int, value: [UserSubjectCollection])?

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["BGMORI_ECH_ONLY"] == "1" {
            try? MirrorRouting.shared.configure(ConnectionSettings(mode: .encrypted), persistChanges: false)
        }
        #endif
        MirrorRouting.shared.startNetworkMonitoring()
        let settings: AppSettings
        #if DEBUG
        if ProcessInfo.processInfo.environment["BGMORI_PREVIEW_REMINDERS"] == "1"
            || ProcessInfo.processInfo.environment["BGMORI_ISOLATE_REMINDER_SETTINGS"] == "1" {
            let defaults = UserDefaults(suiteName: "BgmoriReminderUIPreview")!
            defaults.removePersistentDomain(forName: "BgmoriReminderUIPreview")
            settings = AppSettings(defaults: defaults)
            if ProcessInfo.processInfo.environment["BGMORI_PREVIEW_REMINDERS"] == "1" {
                settings.reminders.enabled = true
                settings.reminders.individual = true
            }
        } else { settings = AppSettings() }
        #else
        settings = AppSettings()
        #endif
        let api = APIClient()
        let webSession = BangumiWebSession(api: api)
        let auth = AuthManager(api: api, webSession: webSession)
        self.settings = settings
        self.api = api
        self.webSession = webSession
        self.auth = auth
        self.library = LibraryStore(api: api, auth: auth, remover: webSession)
        self.router = AppRouter()
        self.social = SocialService(api: api)
        self.categories = CategoryStore(api: api)
        self.recentSubjects = RecentSubjectsStore()
        self.notifications = NotificationManager.shared
        notifications.onResponse = { [weak self] response in await self?.receiveReminder(response) }
    }

    var isGuest: Bool { !auth.isLoggedIn }
    var displayName: String { auth.displayName }
    var username: String? { auth.username }

    var todayWeekday: Int {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return ((weekday + 5) % 7) + 1
    }

    var todayAiring: [LegacySubject] {
        let weekday = todayWeekday
        if let cached = cachedTodayAiring, cached.libraryRevision == library.revision,
           cached.calendarVersion == calendarContentVersion, cached.weekday == weekday {
            return cached.value
        }
        let items = calendar.first(where: { $0.weekday.id == weekday })?.items ?? []
        // Put shows the user is already following first, then the better rated ones.
        let value = items.sorted { lhs, rhs in
            let lhsWatching = library.isWatching(lhs.id)
            let rhsWatching = library.isWatching(rhs.id)
            if lhsWatching != rhsWatching { return lhsWatching }
            let lhsScore = lhs.rating?.score ?? 0
            let rhsScore = rhs.rating?.score ?? 0
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
        }
        cachedTodayAiring = (library.revision, calendarContentVersion, weekday, value)
        return value
    }

    var continueWatching: [UserSubjectCollection] {
        if let cached = cachedContinueWatching, cached.libraryRevision == library.revision {
            return cached.value
        }
        // `watching` is already ordered by updatedAt.
        let value = Array(library.watching.prefix(12))
        cachedContinueWatching = (library.revision, value)
        return value
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
        guard !didBootstrap else {
            if !hasFinishedStartup && !isPreparingStartup { await prepareStartupContent() }
            return
        }
        didBootstrap = true

        #if DEBUG
        applyDebugRouteIfNeeded()
        #endif

        Task { await api.prepareMirrors() }
        Task { await ImageLoader.shared.trimDisk() }
        if router.selectedSection != .home || !router.homePath.isEmpty || showSettings || showLogin {
            hasFinishedStartup = true
        }

        // The launch screen follows the first page, independently of a potentially
        // large account reconciliation. Keep the root task alive for both.
        async let initialContent: Void = prepareStartupContent()

        await auth.restore()
        if auth.isLoggedIn {
            await library.loadIfNeeded()
        }
        if let response = pendingReminderResponse, response.action == UNNotificationDefaultActionIdentifier, auth.username != nil {
            pendingReminderResponse = nil
            await receiveReminder(response, allowBeforeBootstrap: true)
        }
        await initialContent
        if settings.dailyReminder { await loadCalendarTimes() }
        reminderAccountReady = true
        await updateDailyReminder()
        if let response = pendingReminderResponse {
            pendingReminderResponse = nil
            await receiveReminder(response)
        }
        purgeLegacyURLCacheIfNeeded()
    }

    /// Earlier builds gave URLSession a disk cache that no request ever read.
    /// Clear it once so those megabytes are not left behind forever.
    private func purgeLegacyURLCacheIfNeeded() {
        let key = "didPurgeLegacyURLCache.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        URLCache.shared.removeAllCachedResponses()
    }

    func prepareStartupContent(force: Bool = false) async {
        guard !isPreparingStartup else { return }
        isPreparingStartup = true
        startupError = nil
        startupMessage = "正在准备首页…"
        defer { isPreparingStartup = false }

        async let minimumPresentation: Void = Task.sleep(for: .milliseconds(650))
        let key = "startup-home-v1-\(settings.showNSFW ? 1 : 0)"
        let cached = !force ? await api.cache.read(key, maxAge: 7 * 86_400) : nil
        if let cached, let page = await Self.decodeSnapshot(cached),
           !page.trending.isEmpty || !page.ranking.isEmpty || !page.seasonal.isEmpty {
            trending = rankingPageFilter(page.trending)
            ranking = rankingPageFilter(page.ranking)
            seasonal = rankingPageFilter(page.seasonal)
            movies = rankingPageFilter(page.movies)
            calendar = page.calendar
            hasLoadedHome = true
            hasLoadedCalendar = true
            // Cached content opens immediately; refresh stays in the background.
            guard !Task.isCancelled else { return }
            hasFinishedStartup = true
        }

        async let calendarLoad: Void = loadCalendar(force: force || cached != nil, silently: true)
        async let homeLoad: Void = loadHome(force: force || cached != nil, silently: true)
        await homeLoad
        await calendarLoad
        try? await minimumPresentation
        guard !Task.isCancelled else { return }

        guard !trending.isEmpty || !ranking.isEmpty || !seasonal.isEmpty || !movies.isEmpty else {
            startupError = homeError ?? "首页暂时无法加载，请检查网络后重试。"
            return
        }

        if homeError == nil {
            let snapshot = HomeSnapshot(trending: trending, ranking: ranking, seasonal: seasonal,
                                        movies: movies, calendar: calendar)
            if let data = await Self.encodeSnapshot(snapshot) { await api.cache.write(key, data: data) }
        }
        startupMessage = "正在准备封面…"
        await warmStartupImages()
        guard !Task.isCancelled else { return }
        hasFinishedStartup = true
    }

    private struct HomeSnapshot: Codable, Sendable {
        let trending: [Subject]
        let ranking: [Subject]
        let seasonal: [Subject]
        let movies: [Subject]
        let calendar: [CalendarDay]
    }

    /// Launch reads and writes a ~500 KB snapshot; keeping that on the main
    /// actor costs a visible hitch on older hardware.
    nonisolated private static func decodeSnapshot(_ data: Data) async -> HomeSnapshot? {
        try? JSONDecoder().decode(HomeSnapshot.self, from: data)
    }

    nonisolated private static func encodeSnapshot(_ snapshot: HomeSnapshot) async -> Data? {
        try? JSONEncoder().encode(snapshot)
    }

    private func warmStartupImages() async {
        let hero = trending.first?.heroURL
        let covers = Array(todayAiring.prefix(2)).compactMap(\.coverURL)
        await withTaskGroup(of: Void.self) { group in
            if let hero {
                group.addTask {
                    #if os(macOS)
                    _ = await ImageLoader.shared.image(for: hero, maxPixel: 900)
                    #else
                    _ = await ImageLoader.shared.image(for: hero, maxPixel: 1000)
                    #endif
                }
            }
            for url in covers {
                group.addTask { _ = await ImageLoader.shared.image(for: url, maxPixel: 400) }
            }
        }
    }

    func applyConnectionSettings(_ settings: ConnectionSettings) async throws {
        try MirrorRouting.shared.configure(settings)
        await api.resetConnections()
        await ImageLoader.shared.resetConnections()
        connectionCheckSummary = nil
        Task { await api.prepareMirrors() }
    }

    func checkConnections() async {
        guard !isCheckingConnections else { return }
        isCheckingConnections = true
        connectionCheckSummary = nil
        MirrorRouting.shared.resetHealth()
        defer { isCheckingConnections = false }
        async let web: Void? = try? api.checkWebConnection()
        let subject = try? await api.checkAPIConnection()
        let sample = subject?.coverURL ?? trending.first?.heroURL ?? todayAiring.first?.coverURL
        if let sample { _ = await ImageLoader.shared.checkConnection(sample) }
        _ = await web
        let events = MirrorRouting.shared.diagnostics
        let count = ConnectionService.allCases.filter { service in events.first { $0.service == service }?.succeeded == true }.count
        connectionCheckSummary = sample == nil
            ? "\(count)/3 项连接正常；未取得封面样本，图片检测已跳过"
            : "\(count)/3 项连接正常"
    }

    func enterAppDuringStartup() {
        hasFinishedStartup = true
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
        case "settings", "reminders": showSettings = true
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

    func loadCalendarTimes(force: Bool = false) async {
        if let calendarTimesTask {
            await calendarTimesTask.value
            if !force { return }
        }
        guard force || !didLoadCalendarTimes else { return }
        // The Mac navigation shell can replace its initial CalendarView task.
        // Own this supplementary read until it finishes instead of losing its clock data.
        let task = Task {
            await self.fetchCalendarTimes(force: force)
            self.calendarTimesTask = nil
        }
        calendarTimesTask = task
        await task.value
    }

    private func fetchCalendarTimes(force: Bool) async {
        didLoadCalendarTimes = true
        calendarTimesError = nil

        if !force, let hit = await api.cachedBgmlistSchedule() {
            calendarAirings = hit.value.airings()
            reminderAirings = hit.value.airings(includeEnded: true)
            calendarTimesUpdatedAt = Date().addingTimeInterval(-hit.age)
            if hit.isFresh { return }
            guard await api.beginBackgroundRefresh(hit.cacheKey, minimumInterval: 300) else { return }
        }
        do {
            let schedule = try await api.bgmlistSchedule(force: force)
            calendarAirings = schedule.airings()
            reminderAirings = schedule.airings(includeEnded: true)
            if let hit = await api.cachedBgmlistSchedule() {
                calendarTimesUpdatedAt = Date().addingTimeInterval(-hit.age)
            }
        } catch {
            guard !Task.isCancelled else { return }
            calendarTimesError = "播放时刻更新失败，已保留现有内容"
        }
    }

    func refreshCalendar() async {
        async let list: Void = loadCalendar(force: true)
        async let times: Void = loadCalendarTimes(force: true)
        _ = await (list, times)
    }

    func loadCalendar(force: Bool = false, silently: Bool = false) async {
        guard force || !didLoadCalendar else { return }
        guard !isLoadingCalendar else { return }
        didLoadCalendar = true
        isLoadingCalendar = true
        calendarError = nil
        defer {
            isLoadingCalendar = false
            hasLoadedCalendar = true
        }

        if !force, calendar.isEmpty, let hit = await api.cachedCalendar() {
            calendar = hit.value.sorted { $0.weekday.id < $1.weekday.id }
            calendarUpdatedAt = Date().addingTimeInterval(-hit.age)
            hasLoadedCalendar = true
            if hit.isFresh { return }
            guard await api.beginBackgroundRefresh(hit.cacheKey, minimumInterval: 300) else { return }
        }

        do {
            calendar = try await api.calendar(force: force).sorted { $0.weekday.id < $1.weekday.id }
            if let hit = await api.cachedCalendar() { calendarUpdatedAt = Date().addingTimeInterval(-hit.age) }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "放送表加载失败"
            calendarError = message
            if !silently { showToast(message, isError: true) }
        }
    }

    func loadHome(force: Bool = false, silently: Bool = false) async {
        guard force || !didLoadHome else { return }
        guard !isLoadingHome else { return }
        isLoadingHome = true
        didLoadHome = true
        homeError = nil
        defer {
            isLoadingHome = false
            hasLoadedHome = true
        }

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
            ttl: 1_800,
            force: force
        )
        async let moviePage = api.searchSubjects(
            keyword: "",
            sort: "heat",
            filter: movieFilter,
            limit: 16,
            cacheKey: "home-movies-\(includeNSFW ? 1 : 0)",
            ttl: 3_600,
            force: force
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
        // Observable collections of identity-equal DTOs otherwise suppress
        // notifications when only titles, scores or covers have changed.
        homeContentVersion &+= 1

        if loadedTrending.isEmpty && loadedRanking.isEmpty && loadedSeasonal.isEmpty && loadedMovies.isEmpty {
            let message = "发现页加载失败，请检查网络后重试"
            homeError = message
            if !silently { showToast(message, isError: true) }
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
        if calendarError == nil && homeError == nil { showToast("已刷新") }
    }

    func signIn(email: String, password: String, captcha: String) async {
        await auth.signIn(email: email, password: password, captcha: captcha)
        if auth.isLoggedIn, let username = auth.username {
            showToast("欢迎回来，\(auth.displayName)")
            Task {
                await library.loadAll(username: username, force: true)
                await updateDailyReminder()
            }
        }
    }

    func signOut() {
        auth.signOut()
        library.reset()
        Task { await updateDailyReminder() }
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

    func clearCaches() async {
        await api.clearCache()
        await library.clearSnapshot()
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
        hasFinishedStartup = true
    }
}
