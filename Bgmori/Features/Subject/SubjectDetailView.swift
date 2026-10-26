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
    @State private var commentsFailed = false
    #if os(macOS)
    @State private var desktopContentWidth: CGFloat = 0
    #endif

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
        .toolbarColorScheme(.dark, for: .navigationBar)
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
            } else {
                ToolbarItem(placement: .primaryAction) {
                    Link(destination: URL(string: "https://bgm.tv/subject/\(subjectID)")!) {
                        Label("在 Safari 中打开", systemImage: "safari")
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

    private func content(_ subject: Subject) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                #if os(macOS)
                desktopHero(subject)
                #else
                hero(subject)
                #endif

                if subject.nsfw && !app.settings.showNSFW {
                    HStack(spacing: 8) {
                        Image(systemName: "eye.slash")
                        Text("该条目包含 NSFW 内容。可在设置中开启后查看详情。")
                        Spacer()
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(12)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 20)
                }

                actionRow(subject)
                #if os(macOS)
                if desktopContentWidth >= 860 {
                    HStack(alignment: .top, spacing: 24) {
                        LazyVStack(alignment: .leading, spacing: 24) {
                            synopsis(subject)
                            supplementalSections(subject)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        infobox(subject).frame(width: 340)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        synopsis(subject)
                        infobox(subject)
                        supplementalSections(subject)
                    }
                }
                #else
                synopsis(subject)
                infobox(subject)
                supplementalSections(subject)
                #endif
            }
            .padding(.bottom, 18)
            #if os(macOS)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { desktopContentWidth = $0 }
            #endif
            .bgmDesktopContent()
        }
        .scrollIndicators(.hidden)
        .background(Color.bgmCanvas)
        #if os(iOS)
        .ignoresSafeArea(.container, edges: .top)
        .safeAreaInset(edge: .bottom) {
            bottomBar(subject)
        }
        #endif
    }

    private func supplementalSections(_ subject: Subject) -> some View {
        Group {
            episodeSection(subject)
            characterSection
            personSection
            relationSection
            commentSection
        }
    }

    #if os(macOS)
    private func desktopHero(_ subject: Subject) -> some View {
        HStack(alignment: .top, spacing: 28) {
            CachedAsyncImage(url: subject.coverURL, maxPixel: 600, placeholderTint: .subjectTint(subject.type))
                .frame(width: 160, height: 226)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: Color.bgmArtworkScrim.opacity(0.12), radius: 10, y: 5)
            VStack(alignment: .leading, spacing: 12) {
                Text(subject.typeName)
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(subject.displayTitle)
                    .font(.system(size: 30, weight: .bold)).lineLimit(3)
                    .textSelection(.enabled)
                if !subject.originalTitle.isEmpty {
                    Text(subject.originalTitle)
                        .font(.title3).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                HStack(spacing: 8) {
                    Text(subject.episodeCountText)
                    if let date = subject.date, !date.isEmpty {
                        Text("·")
                        Text(date)
                    }
                }
                .font(.subheadline).foregroundStyle(.secondary)
                if let rating = subject.rating, rating.total > 0 {
                    HStack(spacing: 10) {
                        Text(rating.scoreText)
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                        RatingStars(score: rating.score)
                        Text("\(rating.total) 人评分")
                            .font(.caption).foregroundStyle(.secondary)
                        if let rank = rating.rank {
                            Text("排名 #\(rank)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
                HStack(spacing: 10) {
                    Button {
                        if app.isGuest { app.showLogin = true }
                        else { showCollectionEditor = true }
                    } label: {
                        Label(app.library.collection(for: subject.id)?.collectionType.title ?? "收藏作品", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
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
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
    }
    #endif

    // MARK: - Hero

    private var heroHeight: CGFloat {
        #if os(iOS)
        360
        #else
        300
        #endif
    }

    private func hero(_ subject: Subject) -> some View {
        ZStack(alignment: .bottomLeading) {
            CachedAsyncImage(url: subject.heroURL, maxPixel: 900, placeholderTint: .subjectTint(subject.type))
                .frame(height: heroHeight)
                .frame(maxWidth: .infinity)
                .blur(radius: 28, opaque: true)
                .overlay {
                    LinearGradient(
                        colors: [.black.opacity(0.1), .black.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .clipped()
                .backgroundExtensionEffect()

            HStack(alignment: .bottom, spacing: 14) {
                CachedAsyncImage(url: subject.coverURL, maxPixel: 500, placeholderTint: .subjectTint(subject.type))
                    .frame(width: 116, height: 164)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 18, y: 10)

                VStack(alignment: .leading, spacing: 6) {
                    Text(subject.displayTitle)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                    if !subject.originalTitle.isEmpty {
                        Text(subject.originalTitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                    HStack(spacing: 8) {
                        Text(subject.typeName)
                        Text("·")
                        Text(subject.episodeCountText)
                        if let date = subject.date, !date.isEmpty {
                            Text("·")
                            Text(date)
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    if let rating = subject.rating {
                        HStack(spacing: 6) {
                            RatingStars(score: rating.score, size: 11)
                            Text(String(format: "%.1f", rating.score))
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            if let rank = rating.rank {
                                Text("#\(rank)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.white.opacity(0.18), in: Capsule())
                            }
                        }
                        .foregroundStyle(.white)
                    }
                }
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .frame(height: heroHeight)
    }

    // MARK: - Action row

    private func actionRow(_ subject: Subject) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            #if os(iOS)
            HStack(spacing: 10) {
                if let collection = app.library.collection(for: subject.id) {
                    CollectionBadge(type: collection.collectionType)
                    if collection.rate > 0 {
                        Label("\(collection.rate) 分", systemImage: "star.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text("看到 \(collection.epStatus) 话")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                } else if app.isGuest {
                    Text("登录后可收藏、评分、记录进度")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    if app.isGuest {
                        app.showLogin = true
                    } else {
                        showCollectionEditor = true
                    }
                } label: {
                    Label(app.library.collection(for: subject.id)?.collectionType.title ?? "收藏", systemImage: "plus")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.glass)
                .tint(.brandPink)
            }

            #endif
            if !subject.tags.isEmpty {
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(subject.tags.prefix(10)) { tag in
                        TagChip(name: tag.name, count: tag.count)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Synopsis

    private func synopsis(_ subject: Subject) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("简介")
                .font(.bgmSection)
            Text(subject.summary.trimmed.isEmpty ? "暂无简介" : subject.summary)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .lineLimit(synopsisExpanded ? nil : 5)
                .fixedSize(horizontal: false, vertical: true)
            if subject.summary.count > 160 {
                Button(synopsisExpanded ? "收起" : "展开") {
                    withAnimation(.snappy) { synopsisExpanded.toggle() }
                }
                .font(.system(size: 12, weight: .semibold))
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Infobox

    @ViewBuilder
    private func infobox(_ subject: Subject) -> some View {
        if !subject.infobox.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("信息")
                    .font(.bgmSection)
                VStack(spacing: 0) {
                    ForEach(subject.infobox.prefix(12)) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Text(item.key)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 80, alignment: .leading)
                            Text(item.value.display)
                                .font(.system(size: 12))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 8)
                        Divider()
                    }
                }
                .padding(.horizontal, 14)
                .background(Color.bgmBackground, in: RoundedRectangle(cornerRadius: 18))
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Episodes

    @ViewBuilder
    private func episodeSection(_ subject: Subject) -> some View {
        if !episodes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("章节")
                        .font(.bgmSection)
                    Spacer()
                    if app.auth.isLoggedIn {
                        Text(progressText(subject))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)

                if episodeTypeOptions.count > 1 {
                    TextTabs(values: episodeTypeOptions, selection: $selectedEpisodeType, title: typeTitle)
                    .padding(.horizontal, 20)
                }

                LazyVStack(spacing: 0) {
                    ForEach(filteredEpisodes) { episode in
                        episodeRow(subject, episode: episode)
                        Divider().padding(.leading, 20)
                    }
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
                    .font(.system(size: 21))
                    .foregroundStyle(watched ? Color.brandPink : Color.secondary.opacity(0.45))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(episode.numberText)  \(episode.displayTitle)")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let airdate = episode.airdate, !airdate.isEmpty {
                        Text(airdate)
                    }
                    Text("\(episode.comment) 条吐槽")
                }
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            }

            Spacer()

            NavigationLink(value: Route.episode(episode.id)) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.quaternary)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
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

    private func progressText(_ subject: Subject) -> String {
        let total = episodes.filter { $0.type == 0 }.count
        let watched = app.library.episodeTypes[subject.id]
            .map { map in map.filter { $0.value == EpisodeCollectionType.done.rawValue }.count }
        return "\(watched ?? app.library.collection(for: subject.id)?.epStatus ?? 0)/\(total)"
    }

    // MARK: - Characters & staff

    @ViewBuilder
    private var characterSection: some View {
        if !characters.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("角色")
                    .font(.bgmSection)
                    .padding(.horizontal, 20)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(characters) { character in
                            NavigationLink(value: Route.character(character.id)) {
                                VStack(alignment: .leading, spacing: 6) {
                                    CachedAsyncImage(url: character.coverURL, maxPixel: 260, placeholderTint: .brandPink)
                                        .frame(width: 96, height: 132)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    Text(character.name)
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(2)
                                        .frame(width: 96, alignment: .leading)
                                    Text(character.actors.first?.name ?? " ")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .frame(width: 96, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    @ViewBuilder
    private var personSection: some View {
        if !persons.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("制作人员")
                    .font(.bgmSection)
                    .padding(.horizontal, 20)
                VStack(spacing: 0) {
                    ForEach(persons.prefix(12)) { person in
                        NavigationLink(value: Route.person(person.id)) {
                            HStack(spacing: 10) {
                                CachedAsyncImage(url: person.coverURL, maxPixel: 120, placeholderTint: .purple)
                                    .frame(width: 36, height: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(person.name)
                                        .font(.system(size: 13, weight: .medium))
                                    Text(person.relation ?? person.career.first ?? "")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 66)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var relationSection: some View {
        if !relations.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("关联条目")
                    .font(.bgmSection)
                    .padding(.horizontal, 20)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(relations) { relation in
                            NavigationLink(value: Route.subject(relation.id)) {
                                VStack(alignment: .leading, spacing: 6) {
                                    CachedAsyncImage(url: relation.coverURL, maxPixel: 280, placeholderTint: .subjectTint(relation.type))
                                        .frame(width: 100, height: 138)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    Text(relation.displayTitle)
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(2)
                                        .frame(width: 100, alignment: .leading)
                                    Text(relation.relation)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .frame(width: 100, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    // MARK: - Comments

    @ViewBuilder
    private var commentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("吐槽")
                    .font(.bgmSection)
                Spacer()
                if !comments.isEmpty {
                    NavigationLink(value: Route.comments(subjectID)) {
                        Text("查看全部")
                            .font(.system(size: 12, weight: .semibold))
                    }
                } else {
                    Link("在网页查看", destination: URL(string: "https://bgm.tv/subject/\(subjectID)/comments")!)
                        .font(.system(size: 12))
                }
            }
            .padding(.horizontal, 20)

            if comments.isEmpty {
                Text(commentsFailed ? "吐槽加载失败，可点右上角在网页查看。" : "还没有吐槽，或正在加载。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(comments.prefix(3)) { comment in
                        SocialCommentRow(comment: comment)
                        Divider().padding(.leading, 52)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }



    // MARK: - Bottom bar

    private func bottomBar(_ subject: Subject) -> some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
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
                    .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .tint(.brandPink)

                if subject.type != SubjectType.book.rawValue {
                    Button {
                        guard app.auth.isLoggedIn else { app.showLogin = true; return }
                        markNextEpisode(subject)
                    } label: {
                        Label(app.auth.isLoggedIn ? nextEpisodeLabel(subject) : "记录进度", systemImage: "checkmark.circle")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.glass)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
    }

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
