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
                        .navigationDestination(for: Route.self) { RouteView(route: $0) }
                }
                .opacity(router.selectedSection == section ? 1 : 0)
                .allowsHitTesting(router.selectedSection == section)
                .accessibilityHidden(router.selectedSection != section)
            }
        }
        .onChange(of: router.selectedSection, initial: true) { old, new in
            visitedSections.formUnion([old, new])
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
            ForEach(AppSection.phoneTabs) { section in
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
        case .blog(let id): BlogDetailView(blogID: id)
        case .group(let name): GroupDetailView(groupName: name)
        case .topic(let id): TopicDetailView(topicID: id)
        case .timeline(let name): TimelineView(username: name)
        case .index(let id): IndexDetailView(indexID: id)
        case .revisions(let id): RevisionsView(subjectID: id)
        }
    }
}
