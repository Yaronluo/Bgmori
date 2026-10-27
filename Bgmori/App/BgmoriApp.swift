import SwiftUI

@main
struct BgmoriApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            rootView
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            BgmoriCommands(app: app)
        }

        Settings {
            SettingsView()
                .environment(app)
                .environment(\.openURL, browserAction)
                .frame(minWidth: 620, minHeight: 520)
        }
        #else
        WindowGroup {
            rootView
        }
        .defaultSize(width: 430, height: 932)
        #endif
    }

    @ViewBuilder
    private var rootView: some View {
        RootView()
            .environment(app)
            .environment(\.openURL, browserAction)
            .onOpenURL { app.handleOpenURL($0) }
    }

    private var browserAction: OpenURLAction {
        OpenURLAction { url in
            .systemAction(MirrorRouting.shared.canonicalURL(for: url).host == "bgm.tv"
                          ? MirrorRouting.shared.canonicalURL(for: url)
                          : MirrorRouting.shared.preferredURL(for: url))
        }
    }
}

#if os(macOS)
struct BgmoriCommands: Commands {
    let app: AppModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("刷新") {
                Task { await app.refreshAll() }
            }
            .keyboardShortcut("r", modifiers: .command)
        }

        CommandMenu("前往") {
            // Preserve the existing shortcuts; the new category entry uses Command-6.
            ForEach(Array([AppSection.home, .calendar, .library, .search, .profile, .categories].enumerated()), id: \.element) { index, section in
                Button(section.title) {
                    app.router.selectedSection = section
                    app.router.macPath.removeAll()
                }
                .keyboardShortcut(KeyEquivalent(Swift.Character(String(index + 1))), modifiers: .command)
            }
        }
    }
}
#endif
