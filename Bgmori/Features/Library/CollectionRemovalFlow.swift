import SwiftUI

/// The public Bangumi API has no subject-collection delete endpoint.
/// Complete removal on the website, then reconcile against the server.
struct CollectionRemovalFlow: ViewModifier {
    let subjectID: Int
    let title: String
    @Binding var isPresented: Bool
    var onRemoved: () -> Void = {}

    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var awaitingReturn = false
    @State private var isRefreshing = false
    @State private var errorText: String?

    func body(content: Content) -> some View {
        content
            .confirmationDialog("移除《\(title)》的收藏", isPresented: $isPresented, titleVisibility: .visible) {
                Button("前往 Bangumi 移除") {
                    openURL(URL(string: "https://bgm.tv/subject/\(subjectID)")!) { accepted in
                        awaitingReturn = accepted
                        if !accepted { app.showToast("无法打开浏览器，请稍后重试。", isError: true) }
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("Bangumi 暂未开放删除收藏接口。请在网页中登录同一账号，在收藏区域选择移除；返回后会自动同步。")
            }
            .alert("收藏同步失败", isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )) {
                Button("重试") { Task { await refresh() } }
                Button("取消", role: .cancel) { awaitingReturn = false }
            } message: {
                Text(errorText ?? "请稍后重试")
            }
            #if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                if awaitingReturn { Task { await refresh() } }
            }
            #else
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, awaitingReturn { Task { await refresh() } }
            }
            #endif
    }

    @MainActor
    private func refresh() async {
        guard !isRefreshing else { return }
        guard let username = app.auth.username else {
            errorText = "请先登录 Bangumi，再下拉刷新收藏。"
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        // Force bypasses both fresh and stale cache; a failure preserves local data.
        guard await app.library.loadAll(username: username, force: true) else {
            errorText = app.library.lastError ?? "收藏正在同步，请稍后重试。"
            return
        }
        awaitingReturn = false
        if app.library.collection(for: subjectID) == nil {
            app.showToast("收藏已移除")
            onRemoved()
        } else {
            app.showToast("收藏已同步")
        }
    }
}
