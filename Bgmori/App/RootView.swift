import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif

    var body: some View {
        @Bindable var model = app

        ZStack {
            Color.bgmCanvas.ignoresSafeArea()
            if app.hasFinishedStartup {
                Group {
                    #if os(macOS)
                    MacShell()
                    #else
                    PhoneShell()
                    #endif
                }
                .transition(.opacity)
            } else {
                StartupView()
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: app.hasFinishedStartup)
        .tint(.brandPink)
        .preferredColorScheme(app.settings.appearance.colorScheme)
        #if DEBUG
        .overlay {
            if DebugLayoutPreview.isEnabled { DebugLayoutPreview() }
        }
        #endif
        .overlay(alignment: .top) {
            if app.hasFinishedStartup, let toast = app.toast {
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
        #if os(macOS)
        .onChange(of: model.showSettings) { _, shouldShow in
            guard shouldShow else { return }
            openSettings()
            model.showSettings = false
        }
        #else
        .sheet(isPresented: $model.showSettings) {
            NavigationStack {
                SettingsView()
            }
            .environment(app)
        }
        #endif
        .task {
            await app.bootstrap()
        }
        .task(id: app.reminderInput) {
            await app.updateDailyReminder()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await app.refreshReminderData() }
                Task { await app.refreshNoticesBadge() }
            } else if newPhase == .background {
                app.scheduleReminderBackgroundRefresh()
            }
        }
    }
}

private struct StartupView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false
    @State private var isTakingLonger = false

    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 18) {
                Image("BrandIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 104, height: 104)
                    .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                    .scaleEffect(reduceMotion ? 1 : (isBreathing ? 1.025 : 0.975))
                    .accessibilityHidden(true)
                Text("Bgmori")
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.bgmInk)
            }

            VStack(spacing: 16) {
                if let error = app.startupError {
                    Text(error)
                        .foregroundStyle(Color.bgmMuted)
                        .multilineTextAlignment(.center)
                    Button("重试", systemImage: "arrow.clockwise") {
                        Task { await app.prepareStartupContent(force: true) }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("startup-retry")
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(app.startupMessage)
                    Text(isTakingLonger ? "网络有些慢，仍在加载…" : app.startupMessage)
                        .foregroundStyle(Color.bgmMuted)
                }
                if isTakingLonger || app.startupError != nil {
                    Button("先进入应用") { app.enterAppDuringStartup() }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.brandPink)
                        .accessibilityIdentifier("startup-continue")
                }
            }
            .font(.subheadline)
        }
        .padding(32)
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgmCanvas.ignoresSafeArea())
        .accessibilityIdentifier("startup-screen")
        .task(id: reduceMotion) {
            isBreathing = false
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
        .task {
            do {
                try await Task.sleep(for: .seconds(10))
                isTakingLonger = true
            } catch { /* Leaving the launch screen cancels this hint. */ }
        }
    }
}

#if os(iOS)
struct PhoneShell: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var router = app.router

        TabView(selection: $router.selectedSection) {
            ForEach(AppSection.phoneTabs) { section in
                NavigationStack(path: Binding(
                    get: { router.path(for: section) },
                    set: { router.setPath($0, for: section) }
                )) {
                    SectionRootView(section: section)
                        .navigationDestination(for: Route.self) { route in
                            RouteView(route: route)
                        }
                }
                .toolbar(router.isShowingSubject ? .hidden : .visible, for: .tabBar)
                .tabItem {
                    Label(section == .calendar ? "每日放送" : section.title, systemImage: section.icon)
                }
                .tag(section)
            }
        }
        .tabBarMinimizeBehavior(.never)
        .background(Color.bgmCanvas)
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
                        Label {
                            Text(section.title)
                                .foregroundStyle(Color.bgmInk)
                        } icon: {
                            Image(systemName: section.icon)
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(Color.brandPink)
                        }
                        .labelStyle(.titleAndIcon)
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
                                Button("登录") { app.showLogin = true }
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
            ToolbarItemGroup(placement: .topBarTrailing) {
                noticeButton
                Button("搜索", systemImage: "magnifyingglass") {
                    app.router.openSearch()
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.circle)
                .accessibilityIdentifier("global-search")
            }
        }
        #else
        .toolbar {
            ToolbarItem(placement: .primaryAction) { noticeButton }
        }
        #endif
    }

    private var noticeButton: some View {
        Button {
            app.router.push(.notify)
        } label: {
            Image(systemName: app.notices.unreadCount > 0 ? "bell.badge" : "bell")
        }
        .labelStyle(.iconOnly)
        .buttonBorderShape(.circle)
        .accessibilityLabel(app.notices.unreadCount > 0 ? "提醒，\(app.notices.unreadCount) 条未读" : "提醒")
        .accessibilityIdentifier("global-notices")
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
        case .notify: NotifyView()
        }
    }
}
