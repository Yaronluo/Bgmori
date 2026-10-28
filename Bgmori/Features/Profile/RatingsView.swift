import SwiftUI

private enum RatingSort: String, CaseIterable, Identifiable {
    case score
    case updated
    case title

    var id: String { rawValue }

    var title: String {
        switch self {
        case .score: "评分"
        case .updated: "最近更新"
        case .title: "标题"
        }
    }
}

struct RatingsView: View {
    @Environment(AppModel.self) private var app
    @State private var sort: RatingSort = .score

    var body: some View {
        Group {
            if app.isGuest {
                LoginPromptView(title: "登录后查看评分", message: "评分与短评会跟随你的账号同步。") {
                    app.showLogin = true
                }
            } else {
                content
            }
        }
        .background(Color.bgmBackground)
        .bgmNavigationTitle("我的评分")
        .task {
            if !app.isGuest { await app.library.loadIfNeeded() }
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                summary
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)

                if rated.isEmpty {
                    if app.library.isLoading {
                        ProgressView("同步收藏…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                    } else {
                        EmptyStateView(
                            icon: "star",
                            title: "还没有评分",
                            message: "在条目页给作品打分后，会显示在这里。",
                            actionTitle: "去收藏看看"
                        ) {
                            app.router.selectedSection = .library
                            #if os(macOS)
                            app.router.macPath.removeAll()
                            #endif
                        }
                    }
                } else {
                    ForEach(sorted) { item in
                        NavigationLink(value: Route.subject(item.subjectId)) {
                            CollectionReviewRow(item: item)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.horizontal, 20)
                    }
                }

                Color.clear.frame(height: 20)
            }
            .padding(.top, 8)
            .bgmDesktopContent(maxWidth: 820)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            if let username = app.auth.username {
                await app.library.loadAll(username: username, force: true)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("排序", selection: $sort) {
                        ForEach(RatingSort.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("排序")
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(averageText)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("平均评分")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider().frame(height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(rated.count)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("已评分")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider().frame(height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(app.library.collections.count)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("全部收藏")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            RatingDistributionBars(counts: distribution, height: 34)
        }
        .padding(18)
        .profileCard()
    }

    private var rated: [UserSubjectCollection] {
        app.library.collections.values.filter { $0.rate > 0 }
    }

    private var sorted: [UserSubjectCollection] {
        let items = rated
        switch sort {
        case .score:
            return items.sorted {
                if $0.rate != $1.rate { return $0.rate > $1.rate }
                return ($0.updatedAt ?? "") > ($1.updatedAt ?? "")
            }
        case .updated:
            return items.sorted { ($0.updatedAt ?? "") > ($1.updatedAt ?? "") }
        case .title:
            return items.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }

    private var averageText: String {
        guard !rated.isEmpty else { return "—" }
        let value = Double(rated.reduce(0) { $0 + $1.rate }) / Double(rated.count)
        return String(format: "%.1f", value)
    }

    private var distribution: [Int] {
        var counts = Array(repeating: 0, count: 10)
        for item in rated where item.rate > 0 {
            counts[min(max(item.rate, 1), 10) - 1] += 1
        }
        return counts
    }
}
