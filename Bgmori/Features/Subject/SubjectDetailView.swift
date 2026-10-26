import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct SubjectDetailView: View {
    @Environment(AppModel.self) private var app
    let subjectID: Int

    @State private var subject: Subject?
    @State private var episodes: [Episode] = []
    @State private var characters: [Character] = []
    @State private var persons: [Person] = []
    @State private var relations: [RelatedSubject] = []
    @State private var comments: [SocialComment] = []
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var selectedEpisodeType = 0
    @State private var showCollectionEditor = false
    @State private var synopsisExpanded = false
    @State private var expandedInfoKeys: Set<String> = []
    @State private var commentsFailed = false
    @State private var contentWidth: CGFloat = 0
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var isWideLayout: Bool {
        #if os(macOS)
        contentWidth >= 880
        #else
        false
        #endif
    }

    /// Approximate text width of the synopsis card, used to decide whether the
    /// collapsed state actually hides anything.
    private var synopsisTextWidth: CGFloat {
        let cardWidth = isWideLayout ? contentWidth - 340 : contentWidth
        return max(cardWidth - 32, 180)
    }

    private func synopsisOverflows(_ text: String) -> Bool {
        #if os(iOS)
        let fontSize: CGFloat = 17
        #else
        let fontSize: CGFloat = 13
        #endif
        let charsPerLine = max(Int(synopsisTextWidth / (fontSize * 1.05)), 8)
        return text.count > charsPerLine * 5
    }

    private var pageMargin: CGFloat {
        #if os(iOS)
        18
        #else
        0
        #endif
    }

    var body: some View {
        Group {
            if let subject {
                content(subject)
            } else if isLoading {
                ProgressView("加载条目…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "条目加载失败",
                    message: errorText ?? "请稍后再试",
                    actionTitle: "重试"
                ) {
                    Task { await load() }
                }
            }
        }
        .navigationTitle(subject?.displayTitle ?? "条目")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        #endif
        .toolbar {
            if let subject {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: subject.url ?? URL(string: "https://bgm.tv/subject/\(subjectID)")!) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Link("在 Safari 打开", destination: subject.url ?? URL(string: "https://bgm.tv/subject/\(subjectID)")!)
                        Button {
                            app.router.push(.revisions(subjectID))
                        } label: {
                            Label("编辑历史", systemImage: "clock.arrow.circlepath")
                        }
                        Button {
                            #if os(iOS)
                            UIPasteboard.general.string = subject.url?.absoluteString
                            #else
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(subject.url?.absoluteString ?? "", forType: .string)
                            #endif
                            app.showToast("链接已复制")
                        } label: {
                            Label("复制链接", systemImage: "doc.on.doc")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .task(id: subjectID) {
            await load()
        }
        .sheet(isPresented: $showCollectionEditor) {
            if let subject {
                CollectionEditorView(
                    subject: subject,
                    episodes: episodes,
                    collection: app.library.collection(for: subjectID)
                )
                .environment(app)
            }
        }
    }

    // MARK: - Page

    private func content(_ subject: Subject) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                #if os(iOS)
                phoneHeader(subject)
                #endif

                VStack(alignment: .leading, spacing: 16) {
                    #if os(macOS)
                    desktopHeader(subject)
                        .padding(.bottom, 4)
                    #else
                    statusRow(subject)
                    #endif

                    if subject.nsfw && !app.settings.showNSFW {
                        nsfwBanner
                    }

                    tagsRow(subject)
                    cards(subject)
                    footer(subject)
                }
                .padding(.horizontal, pageMargin)
                .padding(.top, pageTopPadding)
                .padding(.bottom, 28)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
                .bgmDesktopContent(maxWidth: 1180)
            }
        }
        .scrollIndicators(.hidden)
        #if os(iOS)
        .background(Color.bgmBackground)
        .ignoresSafeArea(.container, edges: .top)
        .safeAreaInset(edge: .bottom) {
            bottomBar(subject)
        }
        #else
        .background(Color.bgmCanvas)
        #endif
    }

    private var pageTopPadding: CGFloat {
        #if os(iOS)
        16
        #else
        6
        #endif
    }

    private var nsfwBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.slash")
            Text("该条目包含 NSFW 内容。可在设置中开启后查看详情。")
            Spacer(minLength: 0)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func cards(_ subject: Subject) -> some View {
        if isWideLayout {
            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 16) {
                    synopsisCard(subject)
                    episodeCard(subject)
                    characterCard
                    staffCard
                    relatedCard
                    commentCard
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 16) {
                    infoCard(subject)
                }
                .frame(width: 320)
            }
        } else {
            VStack(spacing: 16) {
                synopsisCard(subject)
                infoCard(subject)
                ratingCard(subject)
                episodeCard(subject)
                characterCard
                staffCard
                relatedCard
                commentCard
            }
        }
    }

    // MARK: - Header

    private func cover(_ subject: Subject, width: CGFloat, height: CGFloat, radius: CGFloat) -> some View {
        CachedAsyncImage(url: subject.coverURL, maxPixel: 640, placeholderTint: .subjectTint(subject.type))
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            }
            .shadow(color: Color.bgmArtworkScrim.opacity(0.18), radius: 14, y: 7)
    }

    #if os(macOS)
    private func desktopHeader(_ subject: Subject) -> some View {
        HStack(alignment: .top, spacing: 26) {
            cover(subject, width: 164, height: 232, radius: 14)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(subject.typeName)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .foregroundStyle(Color.subjectTint(subject.type))
                        .background(Color.subjectTint(subject.type).opacity(0.12), in: Capsule())

                    Text(metaLine(subject))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Text(subject.displayTitle)
                    .font(.system(size: 30, weight: .bold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                if !subject.originalTitle.isEmpty {
                    Text(subject.originalTitle)
                        .font(.system(size: 13.5))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if contentWidth < 940 {
                    ratingLine(subject)
                        .padding(.top, 2)
                }

                actionButtons(subject)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if contentWidth >= 940 {
                ratingPanel(subject)
            }
        }
    }

    @ViewBuilder
    private func ratingPanel(_ subject: Subject) -> some View {
        if let rating = subject.rating, rating.total > 0 {
            let buckets = ratingBuckets(rating)
            let peak = max(buckets.map(\.count).max() ?? 0, 1)

            VStack(alignment: .leading, spacing: 9) {
                Text("评分")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(rating.scoreText)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("/ 10")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 6) {
                    RatingStars(score: rating.score, size: 12)
                    if let rank = rating.rank, rank > 0 {
                        Text("#\(rank.formatted())")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                    }
                }

                Text("\(rating.total.formatted()) 人评分")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(buckets) { bucket in
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(Color.brandPink.opacity(bucket.count == peak ? 0.85 : 0.32))
                            .frame(maxWidth: .infinity)
                            .frame(height: 5 + 24 * CGFloat(bucket.count) / CGFloat(peak))
                    }
                }
                .frame(height: 30, alignment: .bottom)
                .padding(.top, 3)
            }
            .padding(16)
            .frame(width: 236, alignment: .leading)
            .bgmPanel(cornerRadius: 16)
        }
    }

    #endif

    private func ratingBuckets(_ rating: Rating) -> [RatingBucket] {
        (1...10).map { score in
            RatingBucket(score: score, count: rating.count[String(score)] ?? 0)
        }
    }

    #if os(iOS)
    private func phoneHeader(_ subject: Subject) -> some View {
        ZStack(alignment: .bottomLeading) {
            CachedAsyncImage(url: subject.heroURL, maxPixel: 900, placeholderTint: .subjectTint(subject.type))
                .frame(height: 348)
                .frame(maxWidth: .infinity)
                .blur(radius: 30, opaque: true)
                .overlay {
                    LinearGradient(
                        colors: [.black.opacity(0.52), .black.opacity(0.64)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .clipped()
                .backgroundExtensionEffect()

            HStack(alignment: .bottom, spacing: 14) {
                cover(subject, width: 116, height: 164, radius: 12)

                VStack(alignment: .leading, spacing: 7) {
                    Text(subject.displayTitle)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(3)

                    if !subject.originalTitle.isEmpty {
                        Text(subject.originalTitle)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(2)
                    }

                    Text("\(subject.typeName) · \(metaLine(subject))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)

                    ratingLine(subject, onArtwork: true)
                }
                .padding(.bottom, 10)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 22)
        }
        .frame(height: 348)
    }
    #endif

    @ViewBuilder
    private func ratingLine(_ subject: Subject, onArtwork: Bool = false) -> some View {
        if let rating = subject.rating, rating.total > 0 {
            if onArtwork {
                HStack(spacing: 6) {
                    RatingStars(score: rating.score, size: 11)
                    Text(rating.scoreText)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    if let rank = rating.rank, rank > 0 {
                        Text("#\(rank)")
                            .font(.system(size: 9.5, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.white.opacity(0.18), in: Capsule())
                    }
                }
                .foregroundStyle(.white)
            } else {
                HStack(alignment: .center, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(rating.scoreText)
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("/ 10")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        RatingStars(score: rating.score, size: 12)
                        Text(ratingDetailText(rating))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func ratingDetailText(_ rating: Rating) -> String {
        var parts = ["\(rating.total.formatted()) 人评分"]
        if let rank = rating.rank, rank > 0 {
            parts.append("Bangumi 排名 #\(rank.formatted())")
        }
        return parts.joined(separator: " · ")
    }

    private func metaLine(_ subject: Subject) -> String {
        var parts: [String] = []
        if let total = episodeTotal(subject) {
            parts.append("全 \(total) \(episodeUnit(subject))")
        }
        if let date = subject.date, !date.isEmpty {
            parts.append(date)
        }
        if parts.isEmpty {
            parts.append(subject.platform ?? subject.typeName)
        }
        return parts.joined(separator: " · ")
    }

    private func episodeUnit(_ subject: Subject) -> String {
        subject.type == SubjectType.music.rawValue ? "曲" : "话"
    }

    private func episodeTotal(_ subject: Subject) -> Int? {
        let mainCount = episodes.filter { $0.type == 0 }.count
        if mainCount > 0 { return mainCount }
        let count = subject.totalEpisodes > 0 ? subject.totalEpisodes : subject.eps
        return count > 0 ? count : nil
    }

    #if os(macOS)
    private func actionButtons(_ subject: Subject) -> some View {
        HStack(spacing: 10) {
            Button {
                if app.isGuest {
                    app.showLogin = true
                } else {
                    showCollectionEditor = true
                }
            } label: {
                Label(
                    app.library.collection(for: subject.id)?.collectionType.title ?? "收藏作品",
                    systemImage: app.library.collection(for: subject.id)?.collectionType.icon ?? "plus"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(.brandPink)

            if subject.type != SubjectType.book.rawValue {
                Button {
                    guard app.auth.isLoggedIn else { app.showLogin = true; return }
                    markNextEpisode(subject)
                } label: {
                    Label(app.isGuest ? "记录进度" : nextEpisodeLabel(subject), systemImage: "checkmark.circle")
                }
                .buttonStyle(.bordered)
            }
        }
        .controlSize(.large)
    }
    #endif

    #if os(iOS)
    @ViewBuilder
    private func statusRow(_ subject: Subject) -> some View {
        if let collection = app.library.collection(for: subject.id) {
            HStack(spacing: 8) {
                CollectionBadge(type: collection.collectionType)
                if collection.rate > 0 {
                    Label("\(collection.rate) 分", systemImage: "star.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Text("看到 \(collection.epStatus) 话")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        } else if app.isGuest {
            Text("登录后可收藏、评分、记录进度")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    #endif

    // MARK: - Tags

    @ViewBuilder
    private func tagsRow(_ subject: Subject) -> some View {
        let tags = visibleTags(subject)
        if !tags.isEmpty {
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(tags) { tag in
                    NavigationLink(value: Route.tag(tag.name)) {
                        SubjectTagChip(name: tag.name, count: tag.count)
                    }
                    .buttonStyle(TagPressStyle())
                    #if os(macOS)
                    .help("查看标签「\(tag.name)」")
                    #endif
                    .accessibilityLabel("标签 \(tag.name)，\(tag.count) 部作品")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func visibleTags(_ subject: Subject) -> [Tag] {
        let titles = [subject.name, subject.nameCn].map(normalizedTitle)
        #if os(iOS)
        let limit = 6
        #else
        let limit = isWideLayout ? 8 : 6
        #endif
        var result: [Tag] = []
        for tag in subject.tags where !tag.name.isEmpty {
            let name = normalizedTitle(tag.name)
            if titles.contains(name) { continue }
            if name.count >= 8, titles.contains(where: { $0.contains(name) }) { continue }
            result.append(tag)
            if result.count >= limit { break }
        }
        return result
    }

    private func normalizedTitle(_ value: String) -> String {
        value
            .replacingOccurrences(of: "。", with: "")
            .replacingOccurrences(of: "、", with: "")
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }

    // MARK: - Synopsis

    private func synopsisCard(_ subject: Subject) -> some View {
        let text = subject.summary.trimmed
        let overflows = synopsisOverflows(text)
        return SectionCard("简介") {
            if text.isEmpty {
                Text("暂无简介")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Text(text)
                    .font(.body)
                    .foregroundStyle(.primary.opacity(0.84))
                    .lineSpacing(4)
                    .lineLimit(overflows && !synopsisExpanded ? 5 : nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                if overflows {
                    Button(synopsisExpanded ? "收起" : "展开全部") {
                        withAnimation(.snappy(duration: 0.24)) { synopsisExpanded.toggle() }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.brandPink)
                }
            }
        }
    }

    // MARK: - Infobox

    @ViewBuilder
    private func infoCard(_ subject: Subject) -> some View {
        let items = visibleInfobox(subject)
        if !items.isEmpty {
            SectionCard("信息") {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        infoRow(item)
                        if item.id != items.last?.id {
                            Divider().opacity(0.55)
                        }
                    }
                }
            }
        }
    }

    private func visibleInfobox(_ subject: Subject) -> [InfoboxItem] {
        var items: [InfoboxItem] = []
        for item in subject.infobox {
            let value = item.value.display.trimmed
            if value.isEmpty { continue }
            if item.key == "话数" { continue }
            if item.key == "中文名", value == subject.displayTitle { continue }
            items.append(item)
            if items.count >= 14 { break }
        }
        return items
    }

    private var infoValueSize: CGFloat {
        #if os(iOS)
        13
        #else
        12
        #endif
    }

    private var infoKeyWidth: CGFloat {
        #if os(iOS)
        68
        #else
        58
        #endif
    }

    private func infoRow(_ item: InfoboxItem) -> some View {
        let value = item.value.display.trimmed
        let isLink = value.hasPrefix("http"), url = URL(string: value)
        let isExpanded = expandedInfoKeys.contains(item.id)
        let canExpand = !isLink && value.count > 60

        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(item.key)
                #if os(iOS)
                .font(.system(size: 12.5, weight: .medium))
                #else
                .font(.system(size: 11, weight: .medium))
                #endif
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: infoKeyWidth, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                if isLink, let url {
                    Link(destination: url) {
                        Text(value)
                            .font(.system(size: infoValueSize))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .foregroundStyle(Color.brandPink)
                } else {
                    Text(value)
                        .font(.system(size: infoValueSize))
                        .foregroundStyle(.primary.opacity(0.85))
                        .lineSpacing(2)
                        .lineLimit(isExpanded ? nil : 3)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                if canExpand {
                    Button(isExpanded ? "收起" : "展开") {
                        withAnimation(.snappy(duration: 0.2)) {
                            if isExpanded {
                                expandedInfoKeys.remove(item.id)
                            } else {
                                expandedInfoKeys.insert(item.id)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.brandPink)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 7)
    }

    // MARK: - Rating

    @ViewBuilder
    private func ratingCard(_ subject: Subject) -> some View {
        if let rating = subject.rating, rating.total > 0 {
            let buckets = ratingBuckets(rating)
            let peak = max(buckets.map(\.count).max() ?? 0, 1)

            SectionCard("评分分布", accessory: AnyView(
                Text("\(rating.scoreText) 分")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.brandPink)
            )) {
                VStack(spacing: 5) {
                    ForEach(buckets.reversed()) { bucket in
                        HStack(spacing: 8) {
                            Text("\(bucket.score)")
                                .font(.system(size: 9.5, weight: .medium, design: .rounded).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 14, alignment: .trailing)

                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.06))
                                Capsule()
                                    .fill(Color.brandPink.opacity(bucket.score >= 8 ? 0.85 : 0.45))
                                    .scaleEffect(
                                        x: max(CGFloat(bucket.count) / CGFloat(peak), 0.015),
                                        y: 1,
                                        anchor: .leading
                                    )
                            }
                            .frame(height: 6)

                            Text("\(bucket.count)")
                                .font(.system(size: 9.5, weight: .medium, design: .rounded).monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                }
                .frame(maxWidth: 480, alignment: .leading)
            }
        }
    }

    // MARK: - Episodes

    @ViewBuilder
    private func episodeCard(_ subject: Subject) -> some View {
        if !episodes.isEmpty {
            SectionCard(
                subject.type == SubjectType.music.rawValue ? "曲目" : "章节",
                accessory: AnyView(episodeProgress(subject))
            ) {
                if episodeTypeOptions.count > 1 {
                    Picker("章节类型", selection: $selectedEpisodeType) {
                        ForEach(episodeTypeOptions, id: \.self) { type in
                            Text(typeTitle(type)).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 240)
                }

                VStack(spacing: 0) {
                    ForEach(Array(filteredEpisodes.indices), id: \.self) { index in
                        if index > 0 {
                            Divider()
                                .opacity(0.55)
                                .padding(.leading, 30)
                        }
                        episodeRow(subject, episode: filteredEpisodes[index])
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func episodeProgress(_ subject: Subject) -> some View {
        if app.auth.isLoggedIn {
            let total = filteredEpisodes.count
            let watched = watchedCount(subject)

            HStack(spacing: 8) {
                Text("已看 \(watched)/\(total)")
                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)

                Capsule()
                    .fill(Color.primary.opacity(0.09))
                    .frame(width: 52, height: 5)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Color.brandPink)
                            .frame(width: 52 * CGFloat(min(watched, total)) / CGFloat(max(total, 1)), height: 5)
                    }
            }
        }
    }

    private func episodeRow(_ subject: Subject, episode: Episode) -> some View {
        let marked = app.library.episodeType(episode.id, subjectID: subject.id) == EpisodeCollectionType.done.rawValue
        let counted = (app.library.collection(for: subject.id)?.epStatus ?? 0) >= Int(episode.ep ?? 0)
        let watched = marked || counted

        return HStack(spacing: 10) {
            Button {
                guard app.auth.isLoggedIn else {
                    app.showLogin = true
                    return
                }
                Task {
                    await app.library.setEpisode(
                        subject: subject,
                        episode: episode,
                        type: watched ? EpisodeCollectionType.none.rawValue : EpisodeCollectionType.done.rawValue
                    )
                }
            } label: {
                Image(systemName: watched ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(watched ? Color.brandPink : Color.secondary.opacity(0.4))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            #if os(macOS)
            .help(watched ? "取消这一话" : "标记为已看")
            #endif

            NavigationLink(value: Route.episode(episode.id)) {
                episodeRowLabel(episode)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .contextMenu {
            Button("标记到这话") {
                guard app.auth.isLoggedIn else { app.showLogin = true; return }
                if let index = filteredEpisodes.firstIndex(where: { $0.id == episode.id }) {
                    Task { await app.library.setProgress(subject: subject, episodes: episodes, watchedCount: index + 1) }
                }
            }
            Button("取消这一话") {
                Task {
                    await app.library.setEpisode(subject: subject, episode: episode, type: EpisodeCollectionType.none.rawValue)
                }
            }
        }
    }

    @ViewBuilder
    private func episodeRowLabel(_ episode: Episode) -> some View {
        #if os(macOS)
        HStack(spacing: 12) {
            Text(episode.numberText)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .leading)

            Text(episode.displayTitle)
                .font(.system(size: 13.5, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 12)

            if let airdate = episode.airdate, !airdate.isEmpty {
                Text(airdate)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            Text("\(episode.comment) 条吐槽")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(minWidth: 62, alignment: .trailing)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.quaternary)
        }
        #else
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(episode.numberText)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(episode.displayTitle)
                        .font(.system(size: 15, weight: .medium))
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    if let airdate = episode.airdate, !airdate.isEmpty {
                        Text(airdate)
                    }
                    Text("\(episode.comment) 条吐槽")
                }
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 6)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.quaternary)
        }
        #endif
    }

    private var episodeTypeOptions: [Int] {
        Array(Set(episodes.map(\.type))).sorted()
    }

    private var filteredEpisodes: [Episode] {
        episodes.filter { $0.type == selectedEpisodeType }.sorted { $0.sort < $1.sort }
    }

    private func typeTitle(_ type: Int) -> String {
        switch type {
        case 0: "本篇"
        case 1: "SP"
        case 2: "OP"
        case 3: "ED"
        default: "其他"
        }
    }

    private func watchedCount(_ subject: Subject) -> Int {
        let ids = Set(filteredEpisodes.map(\.id))
        if let map = app.library.episodeTypes[subject.id] {
            return map.filter { ids.contains($0.key) && $0.value == EpisodeCollectionType.done.rawValue }.count
        }
        return min(app.library.collection(for: subject.id)?.epStatus ?? 0, filteredEpisodes.count)
    }

    // MARK: - Characters & staff

    @ViewBuilder
    private var characterCard: some View {
        if !characters.isEmpty {
            SectionCard("角色", accessory: AnyView(accessoryText("\(characters.count) 位"))) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 82), spacing: 12, alignment: .top)],
                    alignment: .leading,
                    spacing: 14
                ) {
                    ForEach(characters) { character in
                        NavigationLink(value: Route.character(character.id)) {
                            VStack(alignment: .leading, spacing: 6) {
                                Color.bgmSecondary.opacity(0.6)
                                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
                                    .overlay {
                                        CachedAsyncImage(
                                            url: character.coverURL,
                                            maxPixel: 420,
                                            contentMode: .fit,
                                            placeholderTint: .brandPink
                                        )
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                                    }

                                Text(character.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)

                                Text(character.actors.first?.name ?? " ")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var staffCard: some View {
        if !persons.isEmpty {
            SectionCard("制作人员", accessory: AnyView(accessoryText("\(persons.count) 位"))) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 190), spacing: 12, alignment: .leading)],
                    alignment: .leading,
                    spacing: 2
                ) {
                    ForEach(persons.prefix(12)) { person in
                        NavigationLink(value: Route.person(person.id)) {
                            HStack(spacing: 10) {
                                CachedAsyncImage(url: person.coverURL, maxPixel: 160, contentMode: .fit)
                                    .frame(width: 32, height: 42)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(person.name)
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(1)
                                    Text(person.relation ?? person.career.first ?? " ")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var relatedCard: some View {
        if !relations.isEmpty {
            SectionCard("关联条目", accessory: AnyView(accessoryText("\(relations.count) 部"))) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(relations) { relation in
                            NavigationLink(value: Route.subject(relation.id)) {
                                VStack(alignment: .leading, spacing: 6) {
                                    CachedAsyncImage(url: relation.coverURL, maxPixel: 300, placeholderTint: .subjectTint(relation.type))
                                        .frame(width: 92, height: 128)
                                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                                    Text(relation.displayTitle)
                                        .font(.system(size: 11.5, weight: .medium))
                                        .lineLimit(2, reservesSpace: true)
                                        .truncationMode(.tail)
                                        .frame(width: 92, alignment: .leading)

                                    Text(relation.relation)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .frame(width: 92, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func accessoryText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.tertiary)
    }

    // MARK: - Comments

    @ViewBuilder
    private var commentCard: some View {
        SectionCard("吐槽", accessory: AnyView(commentAccessory)) {
            if comments.isEmpty {
                Text(commentsFailed ? "吐槽加载失败，可点上方在网页查看。" : "还没有吐槽，或正在加载。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(comments.prefix(3)) { comment in
                        SocialCommentRow(comment: comment)
                        if comment.id != comments.prefix(3).last?.id {
                            Divider().padding(.leading, 44).opacity(0.55)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var commentAccessory: some View {
        if comments.isEmpty {
            Link("在网页查看", destination: URL(string: "https://bgm.tv/subject/\(subjectID)/comments")!)
                .font(.system(size: 11, weight: .medium))
        } else {
            NavigationLink(value: Route.comments(subjectID)) {
                HStack(spacing: 2) {
                    Text("查看全部")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
        }
    }

    private func footer(_ subject: Subject) -> some View {
        HStack(spacing: 8) {
            Link(destination: subject.url ?? URL(string: "https://bgm.tv/subject/\(subjectID)")!) {
                Label("在 Bangumi 查看", systemImage: "arrow.up.right.square")
            }
            Spacer()
            Text("ID \(subject.id)")
                .monospacedDigit()
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }

    // MARK: - Bottom bar

    #if os(iOS)
    @ViewBuilder
    private func bottomBar(_ subject: Subject) -> some View {
        if reduceTransparency {
            bottomBarContent(subject)
                .padding(5)
                .background(Color.bgmSurface, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 10)
        } else {
            bottomBarContent(subject)
                .padding(5)
                .glassEffect(.regular, in: Capsule())
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private func bottomBarContent(_ subject: Subject) -> some View {
        HStack(spacing: 8) {
            Button {
                if app.isGuest {
                    app.showLogin = true
                } else {
                    showCollectionEditor = true
                }
            } label: {
                Label(
                    app.library.collection(for: subject.id)?.collectionType.title ?? "收藏",
                    systemImage: app.library.collection(for: subject.id)?.collectionType.icon ?? "plus"
                )
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(Color.bgmCanvas)
                .background(Color.brandPink, in: Capsule())
            }
            .buttonStyle(.plain)

            if subject.type != SubjectType.book.rawValue {
                Button {
                    guard app.auth.isLoggedIn else { app.showLogin = true; return }
                    markNextEpisode(subject)
                } label: {
                    Label(app.auth.isLoggedIn ? nextEpisodeLabel(subject) : "记录进度", systemImage: "checkmark.circle")
                        .font(.system(size: 12.5, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
    #endif

    private func nextEpisodeLabel(_ subject: Subject) -> String {
        let main = episodes.filter { $0.type == 0 }.sorted { $0.sort < $1.sort }
        let watched = app.library.episodeTypes[subject.id]
            .map { map in map.filter { $0.value == EpisodeCollectionType.done.rawValue }.count }
            ?? (app.library.collection(for: subject.id)?.epStatus ?? 0)
        let next = min(watched + 1, main.count)
        return watched >= main.count && !main.isEmpty ? "已看完" : "看到 \(next) 话"
    }

    private func markNextEpisode(_ subject: Subject) {
        let main = episodes.filter { $0.type == 0 }.sorted { $0.sort < $1.sort }
        let watched = app.library.episodeTypes[subject.id]
            .map { map in map.filter { $0.value == EpisodeCollectionType.done.rawValue }.count }
            ?? (app.library.collection(for: subject.id)?.epStatus ?? 0)
        if watched >= main.count {
            app.showToast("已经看完了")
            return
        }
        let next = main[watched]
        Task {
            await app.library.setEpisode(subject: subject, episode: next, type: EpisodeCollectionType.done.rawValue)
        }
    }

    // MARK: - Load

    private func load() async {
        isLoading = true
        errorText = nil
        commentsFailed = false
        defer { isLoading = false }

        do {
            let subject = try await app.api.subject(subjectID)
            self.subject = subject
            if !subject.nsfw || app.settings.showNSFW {
                app.recentSubjects.record(subject)
            }
            if selectedEpisodeType == 0, !episodes.contains(where: { $0.type == 0 }) {
                selectedEpisodeType = 0
            }

            async let episodesTask = app.api.allEpisodes(subjectID: subjectID)
            async let charactersTask = app.api.subjectCharacters(subjectID)
            async let personsTask = app.api.subjectPersons(subjectID)
            async let relationsTask = app.api.subjectRelations(subjectID)

            let (eps, chars, staff, rels) = try await (episodesTask, charactersTask, personsTask, relationsTask)
            episodes = eps
            characters = chars
            persons = staff
            relations = rels

            if app.auth.isLoggedIn {
                await app.library.loadEpisodes(subjectID: subjectID)
            }
            do {
                comments = try await app.social.subjectComments(subjectID: subjectID)
            } catch {
                comments = []
                commentsFailed = true
            }
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Supporting views

private struct RatingBucket: Identifiable {
    let score: Int
    let count: Int

    var id: Int { score }
}

private struct TagPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

private struct SubjectTagChip: View {
    let name: String
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            Text(name)
                #if os(iOS)
                .font(.system(size: 12.5, weight: .medium))
                #else
                .font(.system(size: 11.5, weight: .medium))
                #endif
                .foregroundStyle(.primary.opacity(0.8))
            Text("\(count)")
                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.05), in: Capsule())
    }
}

struct SocialCommentRow: View {
    let comment: SocialComment
    var compact = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(url: comment.avatarURL, size: compact ? 28 : 34)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(comment.name)
                        .font(.system(size: 12, weight: .semibold))
                    if let state = comment.state {
                        Text(state)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    if let rating = comment.rating {
                        Text("\(rating)")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    Text(comment.time)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                Text(comment.text)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(compact ? 4 : nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 10)
    }
}
