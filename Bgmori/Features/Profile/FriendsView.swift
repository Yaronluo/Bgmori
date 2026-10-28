import SwiftUI

struct FriendsView: View {
    @Environment(AppModel.self) private var app
    let username: String

    @State private var friends: [FriendSummary] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                header

                if !hasLoaded {
                    ProgressView("正在读取好友…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 70)
                } else if friends.isEmpty {
                    EmptyStateView(
                        icon: errorText == nil ? "person.2" : "wifi.exclamationmark",
                        title: errorText == nil ? "还没有好友" : "好友加载失败",
                        message: errorText ?? "添加好友后，会显示在这里。",
                        actionTitle: errorText == nil ? nil : "重试"
                    ) {
                        Task { await load(force: true) }
                    }
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 240), spacing: 12, alignment: .top)],
                        alignment: .leading,
                        spacing: 12
                    ) {
                        ForEach(friends) { friend in
                            NavigationLink(value: Route.user(friend.username)) {
                                friendCell(friend)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(friend.name)，@\(friend.username)")
                        }
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 28)
            .padding(.horizontal, 20)
            .bgmDesktopContent(maxWidth: 820)
        }
        .background(Color.bgmBackground)
        .scrollIndicators(.hidden)
        .bgmNavigationTitle("好友")
        .bgmWebFallback(url, isPresented: errorText != nil)
        .task(id: username) { await load() }
        .refreshable { await load(force: true) }
    }

    private var url: URL {
        URL(string: "https://bgm.tv/user/\(username)/friends")!
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(friends.isEmpty ? "同好" : "\(friends.count) 位好友")
                    .font(.system(size: 24, weight: .bold))
                Text("我的好友")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let errorText, !friends.isEmpty {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 2)
    }

    private func friendCell(_ friend: FriendSummary) -> some View {
        HStack(spacing: 12) {
            AvatarView(url: friend.avatarURL, size: 50)
            VStack(alignment: .leading, spacing: 3) {
                Text(friend.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("@\(friend.username)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .profileCard(cornerRadius: 16)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func load(force: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        errorText = nil
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            friends = try await app.social.friends(username: username, force: force)
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
