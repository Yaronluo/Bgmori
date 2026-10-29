import SwiftUI

struct CommentsView: View {
    @Environment(AppModel.self) private var app
    let subjectID: Int
    let episodeID: Int?
    @State private var comments: [SocialComment] = []
    @State private var page = 1
    @State private var isLoading = false
    @State private var hasMore = true
    @State private var errorText: String?
    @State private var blocked: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "blockedCommentUsers") ?? [])
    @State private var stateFilter: CollectionType?
    @State private var sort: CommentSort = .comprehensive
    @State private var ratingFilter: CommentRatingFilter = .all

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if isLoading && comments.isEmpty {
                    ProgressView("加载吐槽…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                } else if comments.isEmpty {
                    EmptyStateView(icon: "text.bubble", title: errorText == nil ? "还没有吐槽" : "吐槽加载失败", message: errorText ?? "", actionTitle: "重试") {
                        Task { await load(page: 1, force: true) }
                    }
                } else {
                    if displayedComments.isEmpty {
                        noMatchesState
                    } else {
                        ForEach(displayedComments) { comment in
                            SocialCommentRow(comment: comment, showsRatingStars: true)
                                .padding(.horizontal, 20)
                                .contextMenu {
                                    Button {
                                        blocked.insert(comment.username)
                                        saveBlocked()
                                    } label: {
                                        Label("屏蔽 \(comment.name)", systemImage: "person.crop.circle.badge.xmark")
                                    }
                                }
                            Divider().padding(.leading, 62)
                        }
                    }
                }
                if !comments.isEmpty && (hasMore || errorText != nil) {
                    PaginationFooter(offset: page, isLoading: isLoading, error: errorText) {
                        await load(page: page + 1)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        #if os(iOS)
        .safeAreaInset(edge: .top, spacing: 0) {
            if episodeID == nil && !comments.isEmpty {
                filterBar
            }
        }
        #else
        .toolbar {
            if episodeID == nil && !comments.isEmpty {
                ToolbarItem(placement: .principal) {
                    filterBar.fixedSize()
                }
                .sharedBackgroundVisibility(.visible)
            }
        }
        #endif
        .refreshable { await load(page: 1, force: true) }
        .scrollIndicators(.hidden)
        .navigationTitle("吐槽")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .bgmWebFallback(URL(string: episodeID.map { "https://bgm.tv/ep/\($0)" } ?? "https://bgm.tv/subject/\(subjectID)/comments")!, isPresented: errorText != nil)
        .task {
            await load(page: 1)
        }
    }

    // MARK: - Filters

    private var filterBar: some View {
        #if os(macOS)
        filterMenus
        #else
        ScrollView(.horizontal, showsIndicators: false) {
            filterMenus
                .padding(.horizontal, 4)
                .bgmFloatingGlass(cornerRadius: 22, shadowRadius: 6)
                .padding(.horizontal, 20)
        }
        .frame(height: 44)
        .scrollClipDisabled()
        .padding(.vertical, 6)
        #endif
    }

    private var filterMenus: some View {
        HStack(spacing: 8) {
            Menu {
                Button {
                    stateFilter = nil
                } label: {
                    menuOption("全部状态", selected: stateFilter == nil)
                }
                Divider()
                ForEach(CollectionType.allCases) { type in
                    Button {
                        stateFilter = type
                    } label: {
                        menuOption(type.title, selected: stateFilter == type)
                    }
                }
            } label: {
                filterChip(
                    stateFilter?.title ?? "全部状态",
                    isActive: stateFilter != nil
                )
            }
            .menuIndicator(.hidden)
            .accessibilityIdentifier("comments-state-filter")

            Menu {
                ForEach(CommentSort.allCases) { option in
                    Button {
                        sort = option
                    } label: {
                        menuOption(option.title, selected: sort == option)
                    }
                }
            } label: {
                filterChip(sort.title, isActive: sort != .comprehensive)
            }
            .menuIndicator(.hidden)
            .accessibilityIdentifier("comments-sort-filter")

            Menu {
                ForEach(CommentRatingFilter.allCases) { option in
                    Button {
                        ratingFilter = option
                    } label: {
                        menuOption(option.title, selected: ratingFilter == option)
                    }
                }
            } label: {
                filterChip(ratingFilter.title, isActive: ratingFilter != .all)
            }
            .menuIndicator(.hidden)
            .accessibilityIdentifier("comments-rating-filter")

            if hasActiveFilters {
                Button("重置") {
                    withAnimation(.snappy(duration: 0.2)) {
                        stateFilter = nil
                        sort = .comprehensive
                        ratingFilter = .all
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.brandPink)
                .padding(.horizontal, 4)
                .frame(height: 32)
                .padding(.vertical, 5)
                .accessibilityIdentifier("comments-filter-reset")
            }
        }
        #if os(macOS)
        .menuStyle(.button)
        #endif
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("comments-filters")
    }

    private func filterChip(_ title: String, isActive: Bool) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .bold))
                .opacity(0.65)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(isActive ? Color.brandPink : Color.primary.opacity(0.82))
        .padding(.horizontal, 10)
        #if os(macOS)
        .frame(minHeight: 32)
        #else
        .frame(minHeight: 44)
        #endif
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func menuOption(_ title: String, selected: Bool) -> some View {
        HStack {
            Text(title)
            if selected {
                Image(systemName: "checkmark")
            }
        }
    }

    private var noMatchesState: some View {
        VStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text("没有符合条件的吐槽")
                .font(.subheadline.weight(.medium))
            Text("已加载的吐槽里没有匹配项，可放宽筛选条件。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if hasActiveFilters {
                Button("清除筛选") {
                    withAnimation(.snappy(duration: 0.2)) {
                        stateFilter = nil
                        sort = .comprehensive
                        ratingFilter = .all
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.brandPink)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.vertical, 42)
    }

    private var hasActiveFilters: Bool {
        stateFilter != nil || sort != .comprehensive || ratingFilter != .all
    }

    // MARK: - Filtering

    private var displayedComments: [SocialComment] {
        var result = comments.filter { !blocked.contains($0.username) }

        if let stateFilter {
            result = result.filter { $0.state?.trimmed == stateFilter.title }
        }

        if ratingFilter != .all {
            result = result.filter { ratingFilter.matches($0.rating) }
        }

        switch sort {
        case .comprehensive:
            break
        case .newest:
            result = sortedByDate(result, ascending: false)
        case .oldest:
            result = sortedByDate(result, ascending: true)
        }
        return result
    }

    private func sortedByDate(_ items: [SocialComment], ascending: Bool) -> [SocialComment] {
        items.sorted { lhs, rhs in
            guard let left = commentTimestamp(lhs) else { return false }
            guard let right = commentTimestamp(rhs) else { return true }
            return ascending ? left < right : left > right
        }
    }

    /// Bangumi renders recent comments as `1d 12h ago` and older ones as
    /// `2026-10-23 21:58`; both shapes need to sort together.
    private func commentTimestamp(_ comment: SocialComment) -> Date? {
        let raw = comment.time.trimmed
        guard !raw.isEmpty else { return nil }

        let lower = raw.lowercased()
        let ns = lower as NSString
        let matches = Self.relativeTimeRegex.matches(in: lower, range: NSRange(location: 0, length: ns.length))
        if !matches.isEmpty {
            var seconds: TimeInterval = 0
            for match in matches {
                guard match.numberOfRanges >= 3,
                      let value = Int(ns.substring(with: match.range(at: 1))),
                      let unit = ns.substring(with: match.range(at: 2)).first else { continue }
                switch unit {
                case "s": seconds += Double(value)
                case "m": seconds += Double(value) * 60
                case "h": seconds += Double(value) * 3_600
                case "d": seconds += Double(value) * 86_400
                case "w": seconds += Double(value) * 604_800
                default: break
                }
            }
            return Date().addingTimeInterval(-seconds)
        }

        return Self.absoluteDateFormatter.date(from: raw)
    }

    private static let relativeTimeRegex = try! NSRegularExpression(pattern: #"(\d+)\s*([smhdw])"#)

    private static let absoluteDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    // MARK: - Loading

    private func load(page: Int, force: Bool = false) async {
        guard !isLoading else { return }

        if page == 1, !force {
            let hit: CacheHit<[SocialComment]>?
            if let episodeID {
                hit = await app.social.cachedEpisodeComments(episodeID: episodeID)
            } else {
                hit = await app.social.cachedSubjectComments(subjectID: subjectID, page: 1)
            }
            if let hit {
                guard !Task.isCancelled else { return }
                comments = hit.value
                self.page = 1
                hasMore = episodeID == nil && hit.value.count >= 20
                errorText = nil
                if hit.isFresh { return }
                guard await app.api.beginBackgroundRefresh(hit.cacheKey, minimumInterval: 120) else { return }
            }
        }

        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            let fetched: [SocialComment]
            if let episodeID {
                fetched = try await app.social.episodeComments(episodeID: episodeID, force: force)
            } else {
                fetched = try await app.social.subjectComments(subjectID: subjectID, page: page, force: force)
            }
            guard !Task.isCancelled else { return }
            if page == 1 {
                comments = fetched
            } else {
                var ids = Set(comments.map(\.id))
                comments.append(contentsOf: fetched.filter { ids.insert($0.id).inserted })
            }
            self.page = page
            hasMore = episodeID == nil && fetched.count >= 20
            errorText = nil
        } catch {
            guard !Task.isCancelled else { return }
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            hasMore = false
        }
    }

    private func saveBlocked() {
        UserDefaults.standard.set(Array(blocked), forKey: "blockedCommentUsers")
    }
}

private enum CommentSort: String, CaseIterable, Identifiable {
    case comprehensive
    case newest
    case oldest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .comprehensive: "综合"
        case .newest: "最新"
        case .oldest: "最早"
        }
    }
}

private enum CommentRatingFilter: String, CaseIterable, Identifiable {
    case all
    case top
    case good
    case average
    case low
    case unrated

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部评分"
        case .top: "9–10 分"
        case .good: "7–8 分"
        case .average: "5–6 分"
        case .low: "1–4 分"
        case .unrated: "未评分"
        }
    }

    func matches(_ rating: Int?) -> Bool {
        switch self {
        case .all:
            return true
        case .top:
            return rating.map { (9...10).contains($0) } ?? false
        case .good:
            return rating.map { (7...8).contains($0) } ?? false
        case .average:
            return rating.map { (5...6).contains($0) } ?? false
        case .low:
            return rating.map { (1...4).contains($0) } ?? false
        case .unrated:
            return rating == nil
        }
    }
}
