import SwiftUI

/// The idle state of the search page. It stays intentionally lightweight:
/// local history first, then category shortcuts, hand-picked starting points,
/// and finally a live popularity shelf.
struct SearchLandingView: View {
    let recentSearches: [String]
    let recentSubjects: [RecentSubject]
    let includeNSFW: Bool
    let trending: [Subject]
    let isLoadingTrending: Bool
    let trendingError: String?

    let onSearch: (String) -> Void
    let onClearRecentSearches: () -> Void
    let onClearRecentSubjects: () -> Void
    let onBrowseCategory: (SubjectType) -> Void
    let onReloadTrending: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var visibleRecentSubjects: [RecentSubject] {
        recentSubjects.filter { includeNSFW || !$0.nsfw }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            if !recentSearches.isEmpty {
                recentSearchesSection
            }

            if !visibleRecentSubjects.isEmpty {
                recentSubjectsSection
            }

            categorySection
            inspirationSection
            trendingSection
        }
    }

    private var recentSearchesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SearchLandingHeader(
                title: "最近搜索",
                actionTitle: "清空",
                actionIcon: "trash",
                action: onClearRecentSearches
            )

            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(recentSearches, id: \.self) { term in
                    Button {
                        onSearch(term)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.tertiary)
                            Text(term)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color.bgmSecondary, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("搜索 \(term)")
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var recentSubjectsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SearchLandingHeader(
                title: "最近浏览",
                subtitle: "继续上次看到的地方",
                actionTitle: "清空",
                actionIcon: "trash",
                action: onClearRecentSubjects
            )

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(visibleRecentSubjects) { item in
                        NavigationLink(value: Route.subject(item.id)) {
                            CoverCard(title: item.title, subtitle: item.typeName, coverURL: item.coverURL,
                                      tint: .subjectTint(item.type), width: 112)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("最近浏览：\(item.title)")
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var inspirationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SearchLandingHeader(title: "找点灵感")
            LazyVGrid(columns: ideaColumns, alignment: .leading, spacing: 0) {
                ForEach(SearchIdea.samples) { idea in
                    Button { onSearch(idea.term) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: idea.type.icon)
                                .font(.subheadline)
                                .foregroundStyle(Color.subjectTint(idea.type.rawValue))
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(idea.term).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                Text(idea.note).font(.caption).foregroundStyle(.secondary)
                            }
                            .lineLimit(1)
                            Spacer(minLength: 4)
                            Image(systemName: "arrow.up.left").font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                        .overlay(alignment: .bottom) { Rectangle().fill(Color.bgmMuted.opacity(0.18)).frame(height: 0.5) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("搜索 \(idea.term)，\(idea.type.title)")
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SearchLandingHeader(title: "探索分类")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(SubjectType.browsingTypes) { type in
                        Button { onBrowseCategory(type) } label: {
                            Label(type.title, systemImage: type.icon)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.subjectTint(type.rawValue))
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("浏览\(type.title)分类")
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    @ViewBuilder
    private var trendingSection: some View {
        if !trending.isEmpty || isLoadingTrending || trendingError != nil {
            VStack(alignment: .leading, spacing: 14) {
                SearchLandingHeader(title: "本周热门")

                if !trending.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 16) {
                            ForEach(trending) { subject in
                                NavigationLink(value: Route.subject(subject.id)) {
                                    SubjectCard(subject: subject, width: 132)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                } else if isLoadingTrending {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(0..<5, id: \.self) { _ in
                                SearchTrendingPlaceholder()
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .disabled(true)
                } else {
                    trendingErrorRow
                }
            }
        }
    }

    private var trendingErrorRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.secondary)
            Text("热门暂时加载失败")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("重试", action: onReloadTrending)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(Color.brandPink)
        }
        .padding(16)
        .background(Color.bgmSecondary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 20)
    }

    private var ideaColumns: [GridItem] {
        let count: Int
        if dynamicTypeSize.isAccessibilitySize {
            count = 1
        } else {
            #if os(macOS)
            count = 2
            #else
            count = 1
            #endif
        }
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }
}

private struct SearchLandingHeader: View {
    let title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var actionIcon: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 4) {
                        if let actionIcon {
                            Image(systemName: actionIcon)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        Text(actionTitle)
                            .font(.subheadline)
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                #if os(iOS)
                .frame(minHeight: 32)
                #endif
            }
        }
        .padding(.horizontal, 20)
    }
}

private struct SearchTrendingPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.bgmSecondary.opacity(0.7))
                .frame(width: 132, height: 187)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.bgmSecondary.opacity(0.7))
                .frame(width: 100, height: 12)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.bgmSecondary.opacity(0.5))
                .frame(width: 64, height: 10)
        }
        .frame(width: 132)
        .accessibilityHidden(true)
    }
}

private struct SearchIdea: Identifiable {
    let term: String
    let note: String
    let type: SubjectType

    var id: String { term }

    static let samples: [SearchIdea] = [
        SearchIdea(term: "CLANNAD", note: "青春与家族", type: .anime),
        SearchIdea(term: "攻壳机动队", note: "赛博朋克", type: .anime),
        SearchIdea(term: "三体", note: "科幻史诗", type: .book),
        SearchIdea(term: "俄罗斯方块", note: "简单而隽永", type: .game),
        SearchIdea(term: "坂本龙一", note: "听见更多可能", type: .music),
        SearchIdea(term: "重启人生", note: "日剧治愈", type: .real)
    ]
}
