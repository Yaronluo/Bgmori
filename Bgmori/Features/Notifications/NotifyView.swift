import SwiftUI

/// The website's 提醒 feed: replies, mentions and friend requests.
struct NotifyView: View {
    @Environment(AppModel.self) private var app

    private var store: NoticeStore { app.notices }

    private var webURL: URL {
        URL(string: "https://bgm.tv/notify/all")!
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if app.auth.isLoggedIn || store.isPreviewing {
                    header
                }

                if !app.auth.isLoggedIn && !store.isPreviewing {
                    EmptyStateView(
                        icon: "person.crop.circle.badge.questionmark",
                        title: "登录后查看提醒",
                        message: "用 Bangumi 账号登录，就能在这里收到回复、提及和好友请求。",
                        actionTitle: "登录"
                    ) {
                        app.showLogin = true
                    }
                    .padding(.top, 20)
                } else if !store.hasLoaded {
                    ProgressView("正在读取提醒…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 70)
                } else if store.notices.isEmpty {
                    EmptyStateView(
                        icon: store.errorText == nil ? "bell" : "wifi.exclamationmark",
                        title: store.errorText == nil ? "还没有提醒" : "提醒加载失败",
                        message: store.errorText ?? "有人回复你、提到你或加你好友时，会出现在这里。",
                        actionTitle: store.errorText == nil ? nil : "重试"
                    ) {
                        Task { await store.load() }
                    }
                    .padding(.top, 12)
                } else {
                    if let error = store.errorText {
                        RefreshFailureNotice(message: error) {
                            Task { await store.load() }
                        }
                    }
                    ForEach(store.notices) { notice in
                        NoticeRow(notice: notice)
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
        .bgmNavigationTitle("提醒")
        .toolbar {
            if app.auth.isLoggedIn || store.isPreviewing {
                ToolbarItem(placement: .primaryAction) {
                    Button("全部已读", systemImage: "checkmark.circle") {
                        Task { await store.markAllRead() }
                    }
                    .labelStyle(.iconOnly)
                    .disabled(store.unreadCount == 0 || store.isMarkingAll)
                    .accessibilityLabel("全部标为已读")
                    .accessibilityIdentifier("notices-mark-all")
                }
            }
        }
        .bgmWebFallback(webURL, isPresented: store.errorText != nil)
        .task { await store.load() }
        .refreshable {
            await store.load()
            await store.refreshUnread(force: true)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(headline)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.primary)
                Text("回复、提及与好友请求")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if store.isMarkingAll {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 2)
    }

    private var headline: String {
        if store.notices.isEmpty { return "提醒" }
        return store.unreadCount > 0 ? "\(store.unreadCount) 条未读" : "全部已读"
    }
}

private struct NoticeRow: View {
    @Environment(AppModel.self) private var app
    let notice: Notice

    var body: some View {
        if let route = notice.route {
            Button { open(route) } label: { card(showsChevron: true) }
                .buttonStyle(.plain)
                .accessibilityHint("打开并标为已读")
        } else {
            card(showsChevron: false)
                .accessibilityElement(children: .combine)
        }
    }

    private func open(_ route: Route) {
        Task { await app.notices.markRead(notice) }
        app.router.push(route)
    }

    private func card(showsChevron: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(url: notice.sender.avatarURL, size: 42)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(notice.sender.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if notice.unread {
                        Circle()
                            .fill(Color.brandPink)
                            .frame(width: 7, height: 7)
                            .accessibilityLabel("未读")
                    }
                }
                Text(notice.actionText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if !notice.title.isEmpty {
                    Text(notice.title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .padding(.top, 1)
                }
                Text(notice.createdAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 6)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .profileCard(cornerRadius: 16)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = [notice.sender.displayName, notice.actionText]
        if !notice.title.isEmpty { parts.append(notice.title) }
        if notice.unread { parts.append("未读") }
        return parts.joined(separator: "，")
    }
}

private extension Notice {
    var route: Route? {
        switch place {
        case .groupTopic(let id): id > 0 ? .topic(id) : nil
        case .episode(let id): id > 0 ? .episode(id) : nil
        case .blog(let id): id > 0 ? .blog(id) : nil
        case .index(let id): id > 0 ? .index(id) : nil
        case .character(let id): id > 0 ? .character(id) : nil
        case .person(let id): id > 0 ? .person(id) : nil
        case .user(let name): name.isEmpty ? nil : .user(name)
        case .webOnly: nil
        }
    }
}
