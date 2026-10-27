import Foundation

@main
struct NavigationTests {
    @MainActor
    static func main() {
        precondition(AppSection.phoneTabs == [.home, .categories, .calendar, .library, .profile])
        let router = AppRouter()
        router.selectedSection = .categories
        router.categoriesPath = [.subject(8)]
        router.openSearch(query: "星际")
        precondition(router.searchQuery == "星际")

        let blogs = AppRouter()
        blogs.push(.blogs, in: .profile)
        blogs.push(.blog(382246))
        #if os(iOS)
        precondition(blogs.profilePath == [.blogs, .blog(382246)])
        blogs.setPath([.blogs], for: .profile)
        precondition(blogs.profilePath.last == .blogs)
        #else
        precondition(blogs.macPath == [.blogs, .blog(382246)])
        blogs.macPath.removeLast()
        precondition(blogs.macPath.last == .blogs)
        #endif
        print("PASS: blog list and detail share a navigation path with back history")

        #if os(iOS)
        precondition(router.selectedSection == .categories)
        precondition(router.categoriesPath == [.subject(8), .search])
        router.openSearch()
        precondition(router.categoriesPath == [.subject(8), .search], "Search must not push twice")
        router.push(.subject(9))
        precondition(router.isShowingSubject)
        router.setPath(Array(router.categoriesPath.dropLast()), for: .categories)
        precondition(!router.isShowingSubject && router.categoriesPath.last == .search)
        router.setPath(Array(router.categoriesPath.dropLast()), for: .categories)
        precondition(router.categoriesPath == [.subject(8)], "Back from search must preserve earlier history")
        router.selectedSection = .profile
        let homeHistory = router.homePath
        router.openCalendar()
        precondition(router.selectedSection == .calendar && router.calendarPath.isEmpty)
        precondition(router.homePath == homeHistory, "Calendar must not alter Discover history")
        router.push(.subject(8))
        router.selectedSection = .profile
        router.openCalendar()
        precondition(router.calendarPath == [.subject(8)], "Calendar keeps its own navigation history")
        router.setPath([], for: .calendar)
        precondition(router.selectedSection == .calendar)
        router.selectedSection = .library
        router.handle(url: URL(string: "bgmori://search?q=CLANNAD")!)
        precondition(router.selectedSection == .library && router.libraryPath == [.search])
        precondition(router.searchQuery == "CLANNAD")
        print("PASS iPhone: five tabs, search/back/history, independent calendar history, search deep link")
        #else
        precondition(router.selectedSection == .search && router.macPath.isEmpty)
        router.macPath = [.subject(9)]
        router.openCalendar()
        precondition(router.selectedSection == .calendar && router.macPath.isEmpty)
        precondition(router.categoriesPath == [.subject(8)])
        router.handle(url: URL(string: "bgmori://search?q=CLANNAD")!)
        precondition(router.selectedSection == .search && router.searchQuery == "CLANNAD")
        print("PASS Mac: sidebar search/calendar and existing navigation histories")
        #endif
    }
}
