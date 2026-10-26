import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = app

        Group {
            #if os(macOS)
            MacShell()
            #else
            PhoneShell()
            #endif
        }
        .tint(.brandPink)
        .preferredColorScheme(app.settings.appearance.colorScheme)
        .overlay(alignment: .top) {
            if let toast = app.toast {
                ToastView(message: toast)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: app.toast)
        .sheet(isPresented: $model.showLogin) {
            LoginView()
                .environment(app)
        }
        .sheet(isPresented: $model.showSettings) {
            NavigationStack {
                SettingsView()
            }
            .environment(app)
            #if os(macOS)
            .frame(width: 680, height: 620)
            #endif
        }
        .task {
            await app.bootstrap()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            if app.settings.dailyReminder {
                Task { await app.updateDailyReminder() }
            }
        }
    }
}

#if os(iOS)
struct PhoneShell: View {
    @Environment(AppModel.self) private var app
    @State private var visitedSections: Set<AppSection> = []

    var body: some View {
        @Bindable var router = app.router

        // Keep each tab's navigation history while search and calendar are pushed pages.
        ZStack {
            ForEach(AppSection.phoneTabs.filter { visitedSections.contains($0) || $0 == router.selectedSection }) { section in
                NavigationStack(path: Binding(
                    get: { router.path(for: section) },
                    set: { router.setPath($0, for: section) }
                )) {
                    SectionRootView(section: section)
                        .modifier(PhoneTabBarInset(section: section))
                        .navigationDestination(for: Route.self) { route in
                            RouteView(route: route)
                                .modifier(PhoneTabBarInset(section: section, route: route))
                        }
                }
                .opacity(router.selectedSection == section ? 1 : 0)
                .allowsHitTesting(router.selectedSection == section)
                .accessibilityHidden(router.selectedSection != section)
            }
        }
        .onChange(of: router.selectedSection, initial: true) { old, new in
            visitedSections.formUnion([old, new])
        }
    }
}

/// Reserve space in each page's scroll container, inside its navigation stack.
private struct PhoneTabBarInset: ViewModifier {
    let section: AppSection
    var route: Route? = nil
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        @Bindable var router = app.router
        content.safeAreaInset(edge: .bottom, spacing: 12) {
            if router.selectedSection == section,
               router.path(for: section).last == route,
               !router.isShowingSubject {
                BgmoriTabBar(selection: $router.selectedSection)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)
            }
        }
    }
}

struct BgmoriTabBar: View {
    @Binding var selection: AppSection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionAnimation

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppSection.phoneTabs) { section in
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                        selection = section
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: selection == section ? section.filledIcon : section.icon)
                            .font(.system(size: 19, weight: .medium))
                        Text(section.title)
                            .font(.caption2.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(selection == section ? Color.brandPink : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background {
                        if selection == section {
                            Capsule().fill(Color.brandPink.opacity(0.10))
                                .matchedGeometryEffect(id: "selection", in: selectionAnimation)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tab-\(section.rawValue)")
                .accessibilityAddTraits(selection == section ? .isSelected : [])
            }
        }
        .padding(4)
        .bgmFloatingGlass(cornerRadius: 30)
    }
}
#endif

#if os(macOS)
struct MacShell: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var router = app.router

        NavigationSplitView {
            List(selection: Binding<AppSection?>(
                get: { router.selectedSection },
                set: { value in
                    guard let value, value != router.selectedSection else { return }
                    router.selectedSection = value
                    router.macPath.removeAll()
                }
            )) {
                Section("浏览") {
                    ForEach(AppSection.allCases) { section in
                        Label(section.title, systemImage: section.icon)
                            .tag(section)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 14) {
                    Divider()
                    HStack(spacing: 10) {
                        AvatarView(url: app.auth.user?.avatarURL, size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.isGuest ? "游客模式" : app.displayName)
                                .font(.subheadline.weight(.medium))
                            if app.isGuest {
                                Button("登录 Bangumi") { app.showLogin = true }
                                    .buttonStyle(.link)
                                    .font(.caption)
                            }
                        }
                        Spacer(minLength: 0)
                        SettingsLink {
                            Image(systemName: "gearshape")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("设置")
                    }
                }
                .padding(16)
            }
        } detail: {
            NavigationStack(path: $router.macPath) {
                SectionRootView(section: router.selectedSection)
                    .navigationDestination(for: Route.self) { RouteView(route: $0) }
            }
            // Keep the window backdrop stable while the detail column swaps
            // pages, so the glass sidebar toggle does not flash white.
            .background(Color.bgmCanvas)
        }
        .background(Color.bgmCanvas)
        .frame(minWidth: 960, minHeight: 640)
    }
}
#endif

struct SectionRootView: View {
    @Environment(AppModel.self) private var app
    let section: AppSection

    var body: some View {
        Group {
            switch section {
            case .home: HomeView()
            case .categories: CategoryView()
            case .calendar: CalendarView()
            case .library: LibraryView()
            case .search: SearchView()
            case .profile: ProfileView()
            }
        }
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("搜索", systemImage: "magnifyingglass") {
                    app.router.openSearch()
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.circle)
                .accessibilityIdentifier("global-search")
            }
        }
        #endif
    }
}

struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .search: SearchView()
        case .calendar: CalendarView()
        case .subject(let id): SubjectDetailView(subjectID: id)
        case .episode(let id): EpisodeDetailView(episodeID: id)
        case .character(let id): PersonDetailView(kind: .character, id: id)
        case .person(let id): PersonDetailView(kind: .person, id: id)
        case .user(let name): UserProfileView(username: name)
        case .comments(let id): CommentsView(subjectID: id, episodeID: nil)
        case .blogs: BlogListView()
        case .blog(let id): BlogDetailView(blogID: id)
        case .friends(let name): FriendsView(username: name)
        case .people(let name): PeopleCollectionView(username: name)
        case .ratings: RatingsView()
        case .group(let name): GroupDetailView(groupName: name)
        case .topic(let id): TopicDetailView(topicID: id)
        case .timeline(let name): TimelineView(username: name)
        case .index(let id): IndexDetailView(indexID: id)
        case .revisions(let id): RevisionsView(subjectID: id)
        case .tag(let name): TagResultsView(tag: name)
        }
    }
}
