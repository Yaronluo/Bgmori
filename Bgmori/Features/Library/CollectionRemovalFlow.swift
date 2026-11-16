import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Removes a subject collection without leaving the app. The public API has no
/// delete endpoint, so this uses the website session saved at login and then
/// verifies the result through the API. A failed or expired session falls back
/// to re-login or the website.
struct CollectionRemovalFlow: ViewModifier {
    let subjectID: Int
    let title: String
    @Binding var isPresented: Bool
    var onRemoved: () -> Void = {}
    var onNeedsLogin: () -> Void = {}

    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var isRemoving = false
    @State private var removalLabel = "取消追番"
    @State private var failure: RemovalFailure?
    @State private var awaitingReturn = false

    private var collection: UserSubjectCollection? {
        app.library.collection(for: subjectID)
    }

    private var isWatchingAnime: Bool {
        collection?.subjectType == SubjectType.anime.rawValue && collection?.collectionType == .doing
    }

    private var actionTitle: String {
        isWatchingAnime ? "取消追番" : "移除收藏"
    }

    func body(content: Content) -> some View {
        content
            .alert(
                "\(actionTitle)《\(title)》？",
                isPresented: $isPresented
            ) {
                Button(actionTitle, role: .destructive) {
                    Task { await remove() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("会同时在 Bangumi 官网移除这条收藏，之后仍可在官网上重新收藏。")
            }
            .background {
                // Keep the failure alert in a separate subtree so it can never
                // replace the confirmation alert.
                Color.clear
                    .alert(
                        failure?.title ?? "操作失败",
                        isPresented: Binding(
                            get: { failure != nil },
                            set: { if !$0 { failure = nil } }
                        )
                    ) {
                        if failure?.needsLogin == true {
                            Button("重新登录") {
                                failure = nil
                                onNeedsLogin()
                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(250))
                                    app.showLogin = true
                                }
                            }
                        } else {
                            Button("重试") {
                                failure = nil
                                Task { await remove() }
                            }
                        }
                        Button("在网页中移除") {
                            failure = nil
                            awaitingReturn = true
                            if let url = URL(string: "https://bgm.tv/subject/\(subjectID)") {
                                openURL(url)
                            }
                        }
                        Button("取消", role: .cancel) { failure = nil }
                    } message: {
                        Text(failure?.message ?? "")
                    }
            }
            .overlay {
                if isRemoving {
                    ZStack {
                        Color.black.opacity(0.08)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture {}
                        ProgressView("正在\(removalLabel)…")
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(.regularMaterial, in: Capsule())
                            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                            .accessibilityIdentifier("collection-removal-progress")
                    }
                }
            }
            #if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                if awaitingReturn { Task { await refreshAfterWebRemoval() } }
            }
            #else
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, awaitingReturn { Task { await refreshAfterWebRemoval() } }
            }
            #endif
    }

    @MainActor
    private func refreshAfterWebRemoval() async {
        guard awaitingReturn, let username = app.auth.username else { return }
        awaitingReturn = false
        guard await app.library.loadAll(username: username, force: true) else {
            app.showToast("收藏同步失败，请下拉刷新", isError: true)
            return
        }
        if app.library.collection(for: subjectID) == nil {
            app.showToast("收藏已移除")
            onRemoved()
        } else {
            app.showToast("收藏已同步")
        }
    }

    @MainActor
    private func remove() async {
        guard !isRemoving else { return }
        isRemoving = true
        let action = actionTitle
        removalLabel = action
        defer { isRemoving = false }

        do {
            try await app.library.removeCollection(subjectID: subjectID)
            app.showToast(action == "取消追番" ? "已取消追番" : "已移除收藏")
            onRemoved()
            Task { await app.updateDailyReminder() }
        } catch let error as BangumiWebSessionError {
            switch error {
            case .signInRequired, .sessionExpired:
                failure = RemovalFailure(
                    title: "无法\(action)",
                    message: "应用内\(action)需要一次有效的官网登录。请重新登录后再试；也可以在网页中移除。",
                    needsLogin: true
                )
            default:
                failure = RemovalFailure(
                    title: "无法\(action)",
                    message: error.localizedDescription,
                    needsLogin: false
                )
            }
        } catch APIError.unauthorized {
            failure = RemovalFailure(
                title: "无法\(action)",
                message: "登录已过期，请重新登录后再试。",
                needsLogin: true
            )
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            failure = RemovalFailure(title: "无法\(action)", message: message, needsLogin: false)
        }
    }
}

private struct RemovalFailure: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let needsLogin: Bool
}
