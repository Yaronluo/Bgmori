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
            #if os(iOS)
            NavigationStack {
                SettingsView()
            }
            .environment(app)
            #else
            SettingsView()
                .environment(app)
                .frame(minWidth: 620, minHeight: 520)
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

    var body: some View {
        @Bindable var router = app.router

        TabView(selection: $router.selectedSection) {
            NavigationStack(path: $router.homePath) {
                HomeView()
                    .navigationDestination(for: Route.self) { RouteView(route: $0) }
            }
            .toolbar(.hidden, for: .tabBar)
            .tabItem { Label("发现", systemImage: "square.grid.2x2") }
            .tag(AppSection.home)

            NavigationStack(path: $router.calendarPath) {
                CalendarView()
                    .navigationDestination(for: Route.self) { RouteView(route: $0) }
            }
            .toolbar(.hidden, for: .tabBar)
            .tabItem { Label("放送", systemImage: "calendar") }
            .tag(AppSection.calendar)

            NavigationStack(path: $router.libraryPath) {
                LibraryView()
                    .navigationDestination(for: Route.self) { RouteView(route: $0) }
            }
            .toolbar(.hidden, for: .tabBar)
            .tabItem { Label("收藏", systemImage: "books.vertical") }
            .tag(AppSection.library)

            NavigationStack(path: $router.searchPath) {
                SearchView()
                    .navigationDestination(for: Route.self) { RouteView(route: $0) }
            }
            .toolbar(.hidden, for: .tabBar)
            .tabItem { Label("搜索", systemImage: "magnifyingglass") }
            .tag(AppSection.search)

            NavigationStack(path: $router.profilePath) {
                ProfileView()
                    .navigationDestination(for: Route.self) { RouteView(route: $0) }
            }
            .toolbar(.hidden, for: .tabBar)
            .tabItem { Label("我的", systemImage: "person.crop.circle") }
            .tag(AppSection.profile)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !router.isShowingSubject {
                BgmoriTabBar(selection: $router.selectedSection)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
        }
    }
}

struct BgmoriTabBar: View {
    @Binding var selection: AppSection
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionAnimation

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppSection.allCases) { section in
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                        selection = section
                    }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: selection == section ? section.filledIcon : section.icon)
                            .font(.system(size: 21, weight: .medium))
                        Text(section.title)
                            .font(.caption2.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(selection == section ? Color.brandPink : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if selection == section {
                            Capsule().fill(Color.brandPink.opacity(0.10))
                                .matchedGeometryEffect(id: "selection", in: selectionAnimation)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == section ? .isSelected : [])
            }
        }
        .padding(5)
        .background {
            if reduceTransparency {
                Capsule().fill(Color.bgmSurface)
                    .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
            } else {
                Capsule().fill(Color.clear)
                    .glassEffect(.regular, in: Capsule())
            }
        }
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
        }
        .frame(minWidth: 960, minHeight: 640)
    }
}
#endif

struct SectionRootView: View {
    let section: AppSection

    var body: some View {
        switch section {
        case .home: HomeView()
        case .calendar: CalendarView()
        case .library: LibraryView()
        case .search: SearchView()
        case .profile: ProfileView()
        }
    }
}

struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .subject(let id): SubjectDetailView(subjectID: id)
        case .episode(let id): EpisodeDetailView(episodeID: id)
        case .character(let id): PersonDetailView(kind: .character, id: id)
        case .person(let id): PersonDetailView(kind: .person, id: id)
        case .user(let name): UserProfileView(username: name)
        case .comments(let id): CommentsView(subjectID: id, episodeID: nil)
        case .blog(let id): BlogDetailView(blogID: id)
        case .group(let name): GroupDetailView(groupName: name)
        case .topic(let id): TopicDetailView(topicID: id)
        case .timeline(let name): TimelineView(username: name)
        case .index(let id): IndexDetailView(indexID: id)
        case .revisions(let id): RevisionsView(subjectID: id)
        case .tag(let name): TagResultsView(tag: name)
        }
    }
}
