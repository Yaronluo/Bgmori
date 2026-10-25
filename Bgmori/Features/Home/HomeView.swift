import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                header

                if app.isGuest {
                    guestCard
                }

                if !app.continueWatching.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "继续观看", subtitle: "从上次停下的地方接上")
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 14) {
                                ForEach(app.continueWatching) { item in
                                    NavigationLink(value: Route.subject(item.subjectId)) {
                                        CoverCard(
                                            title: item.title,
                                            subtitle: "看到 \(item.epStatus) 话",
                                            coverURL: item.coverURL,
                                            badge: item.collectionType.title,
                                            progress: item.progressFraction,
                                            tint: .subjectTint(item.subjectType),
                                            width: 148
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }

                if !app.todayAiring.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "今日放送", subtitle: weekdayText, actionTitle: "全部") {
                            app.router.selectedSection = .calendar
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 14) {
                                ForEach(app.todayAiring.prefix(12)) { item in
                                    NavigationLink(value: Route.subject(item.id)) {
                                        AiringCard(subject: item, isWatching: app.library.isWatching(item.id), width: 126)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }

                if !app.seasonal.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "本季新番", subtitle: app.seasonLabel)
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 14) {
                                ForEach(app.seasonal) { subject in
                                    NavigationLink(value: Route.subject(subject.id)) {
                                        SubjectCard(subject: subject, width: 136)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }

                if !app.ranking.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "排行榜", subtitle: "Bangumi 动画排名")
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 14) {
                                ForEach(Array(app.ranking.enumerated()), id: \.element.id) { index, subject in
                                    NavigationLink(value: Route.subject(subject.id)) {
                                        CoverCard(
                                            title: subject.displayTitle,
                                            subtitle: "\(subject.ratingText) 分",
                                            coverURL: subject.coverURL,
                                            badge: "#\(index + 1)",
                                            tint: .subjectTint(subject.type),
                                            width: 132
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }

                communitySection

                if app.isLoadingHome && app.ranking.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView("加载首页…")
                        Spacer()
                    }
                    .padding(.vertical, 30)
                }

                Text("数据来自 Bangumi · Bgmori 是非官方客户端")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                    .padding(.bottom, 26)
            }
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await app.refreshAll()
        }
        #if os(macOS)
        .navigationTitle("首页")
        #else
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if app.isGuest {
                        app.showLogin = true
                    } else {
                        app.router.selectedSection = .profile
                    }
                } label: {
                    AvatarView(url: app.auth.user?.avatarURL, size: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("账户")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(greeting)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Bgmori")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [Color.brandPink, Color.brandPink.opacity(0.65)], startPoint: .leading, endPoint: .trailing)
                    )
                Text(Date.now.formatted(.dateTime.month().day().weekday(.wide)))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private var guestCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(
                    LinearGradient(colors: [Color.brandPink, Color.brandPink.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text("登录后同步你的收藏")
                    .font(.system(size: 15, weight: .semibold))
                Text("评分、进度、吐槽和在看列表都会跟着你。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("登录") { app.showLogin = true }
                .buttonStyle(.glassProminent)
                .tint(.brandPink)
        }
        .padding(16)
        .bgmCardBackground(cornerRadius: 20)
        .padding(.horizontal, 20)
    }

    private var communitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "社区", subtitle: "只读浏览 Bangumi 的公开内容")
            HStack(spacing: 12) {
                NavigationLink {
                    GroupListView()
                } label: {
                    CommunityCard(icon: "person.3", title: "小组", subtitle: "话题与讨论")
                }
                .buttonStyle(.plain)

                NavigationLink {
                    BlogListView()
                } label: {
                    CommunityCard(icon: "text.book.closed", title: "日志", subtitle: "大家的 ACGN 随笔")
                }
                .buttonStyle(.plain)

                if let username = app.auth.username {
                    NavigationLink {
                        TimelineView(username: username)
                    } label: {
                        CommunityCard(icon: "clock.arrow.circlepath", title: "时光机", subtitle: "你的收藏轨迹")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11: return "早上好"
        case 11..<14: return "中午好"
        case 14..<18: return "下午好"
        default: return "晚上好"
        }
    }

    private var weekdayText: String {
        app.calendar.first(where: { $0.weekday.id == app.todayWeekday })?.weekday.cn ?? "今天"
    }
}

struct CommunityCard: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.brandPink)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .bgmCardBackground(cornerRadius: 16)
    }
}
