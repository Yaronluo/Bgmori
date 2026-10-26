import Foundation

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case home
    case categories
    case calendar
    case library
    case search
    case profile

    var id: String { rawValue }

    static let phoneTabs: [AppSection] = [.home, .categories, .library, .profile]

    var title: String {
        switch self {
        case .home: "发现"
        case .categories: "分类"
        case .calendar: "放送"
        case .library: "收藏"
        case .search: "搜索"
        case .profile: "我的"
        }
    }

    var icon: String {
        switch self {
        case .home: "square.grid.2x2"
        case .categories: "square.stack.3d.up"
        case .calendar: "calendar"
        case .library: "books.vertical"
        case .search: "magnifyingglass"
        case .profile: "person.crop.circle"
        }
    }

    var filledIcon: String {
        switch self {
        case .home: "square.grid.2x2.fill"
        case .categories: "square.stack.3d.up.fill"
        case .calendar: "calendar"
        case .library: "books.vertical.fill"
        case .search: "magnifyingglass"
        case .profile: "person.crop.circle.fill"
        }
    }
}

enum Route: Hashable {
    case search
    case calendar
    case subject(Int)
    case episode(Int)
    case character(Int)
    case person(Int)
    case user(String)
    case comments(Int)
    case blogs
    case blog(Int)
    case friends(String)
    case people(String)
    case ratings
    case group(String)
    case topic(Int)
    case timeline(String)
    case index(Int)
    case revisions(Int)
    case tag(String)
}

@MainActor
@Observable
final class AppRouter {
    var selectedSection: AppSection = .home
    var homePath: [Route] = []
    var categoriesPath: [Route] = []
    var calendarPath: [Route] = []
    var libraryPath: [Route] = []
    var searchPath: [Route] = []
    var profilePath: [Route] = []
    var macPath: [Route] = []
    var searchQuery: String = ""

    func openSearch(query: String? = nil) {
        if let query { searchQuery = query }
        #if os(iOS)
        if !AppSection.phoneTabs.contains(selectedSection) { selectedSection = .home }
        if path(for: selectedSection).last != .search { push(.search) }
        #else
        selectedSection = .search
        macPath.removeAll()
        #endif
    }

    func openCalendar() {
        #if os(iOS)
        selectedSection = .home
        if homePath.last != .calendar { homePath.append(.calendar) }
        #else
        selectedSection = .calendar
        macPath.removeAll()
        #endif
    }

    func path(for section: AppSection) -> [Route] {
        switch section {
        case .home: homePath
        case .categories: categoriesPath
        case .calendar: calendarPath
        case .library: libraryPath
        case .search: searchPath
        case .profile: profilePath
        }
    }

    func setPath(_ path: [Route], for section: AppSection) {
        switch section {
        case .home: homePath = path
        case .categories: categoriesPath = path
        case .calendar: calendarPath = path
        case .library: libraryPath = path
        case .search: searchPath = path
        case .profile: profilePath = path
        }
    }

    var isShowingSubject: Bool {
        #if os(macOS)
        if case .subject = macPath.last { return true }
        return false
        #else
        let paths: [[Route]]
        switch selectedSection {
        case .home: paths = [homePath]
        case .categories: paths = [categoriesPath]
        case .calendar: paths = [calendarPath]
        case .library: paths = [libraryPath]
        case .search: paths = [searchPath]
        case .profile: paths = [profilePath]
        }
        return paths.contains { path in
            if case .subject = path.last { return true }
            return false
        }
        #endif
    }

    func push(_ route: Route, in section: AppSection? = nil) {
        let target = section ?? selectedSection
        selectedSection = target
        #if os(macOS)
        macPath.append(route)
        #else
        switch target {
        case .home: homePath.append(route)
        case .categories: categoriesPath.append(route)
        case .calendar: calendarPath.append(route)
        case .library: libraryPath.append(route)
        case .search: searchPath.append(route)
        case .profile: profilePath.append(route)
        }
        #endif
    }

    func resetCurrent() {
        #if os(macOS)
        macPath.removeAll()
        #else
        switch selectedSection {
        case .home: homePath.removeAll()
        case .categories: categoriesPath.removeAll()
        case .calendar: calendarPath.removeAll()
        case .library: libraryPath.removeAll()
        case .search: searchPath.removeAll()
        case .profile: profilePath.removeAll()
        }
        #endif
    }

    func handle(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        if components.scheme == "bgmori" {
            let host = components.host ?? ""
            let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            switch host {
            case "subject":
                if let id = Int(path) { push(.subject(id)) }
            case "episode":
                if let id = Int(path) { push(.episode(id)) }
            case "user":
                if !path.isEmpty { push(.user(path)) }
            case "blog":
                if let id = Int(path) { push(.blog(id)) }
            case "group":
                if !path.isEmpty { push(.group(path)) }
            case "topic":
                if let id = Int(path) { push(.topic(id)) }
            case "index":
                if let id = Int(path) { push(.index(id)) }
            case "search":
                openSearch(query: components.queryItems?.first(where: { $0.name == "q" })?.value ?? "")
            default:
                break
            }
            return
        }

        guard components.host == "bgm.tv" || components.host == "bangumi.tv" else { return }
        let parts = components.path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return }
        switch parts[0] {
        case "subject":
            if let id = Int(parts[1]) { push(.subject(id)) }
        case "ep":
            if let id = Int(parts[1]) { push(.episode(id)) }
        case "user":
            push(.user(parts[1]))
        case "blog":
            if let id = Int(parts[1]) { push(.blog(id)) }
        case "group":
            if parts[1] == "topic", parts.count >= 3, let id = Int(parts[2]) {
                push(.topic(id))
            } else {
                push(.group(parts[1]))
            }
        case "index":
            if let id = Int(parts[1]) { push(.index(id)) }
        default:
            break
        }
    }
}
