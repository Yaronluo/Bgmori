import SwiftUI

enum PersonKind: String, Hashable {
    case character
    case person
}

struct PersonDetailView: View {
    @Environment(AppModel.self) private var app
    let kind: PersonKind
    let id: Int

    @State private var character: Character?
    @State private var person: PersonDetail?
    @State private var related: [RelatedSubject] = []
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var isCollected = false
    @State private var isSaving = false
    @State private var relatedLoading = false
    @State private var relatedError: String?
    @State private var refreshError: String?
    @State private var loadedKey: String?
    @State private var isRefreshing = false

    var body: some View {
        Group {
            if let character {
                characterBody(character)
            } else if let person {
                personBody(person)
            } else if isLoading {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyStateView(icon: "person.crop.circle.badge.exclamationmark", title: "加载失败", message: errorText ?? "请稍后再试", actionTitle: "重试") {
                    Task { await load() }
                }
            }
        }
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    guard app.auth.isLoggedIn else { app.showLogin = true; return }
                    Task { await toggleCollection() }
                } label: {
                    Label(isCollected ? "已收藏" : "收藏", systemImage: isCollected ? "heart.fill" : "heart")
                }
                .disabled(isSaving)
            }
        }
        .bgmWebFallback(URL(string: "https://bgm.tv/\(kind == .character ? "character" : "person")/\(id)")!)
        .task(id: "\(kind.rawValue)-\(id)") {
            prepareIfNeeded()
            await load()
        }
    }

    private var title: String {
        character?.name ?? person?.name ?? "人物"
    }

    private func characterBody(_ character: Character) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if refreshError != nil {
                    RefreshFailureNotice(message: "人物资料更新失败，显示的是缓存内容") {
                        Task { await loadBase(force: true) }
                    }
                    .padding(.horizontal, 20)
                }
                header(image: character.images?.heroURL ?? character.coverURL, name: character.name, subtitle: character.relation, summary: character.summary)
                if !character.actors.isEmpty {
                    infoBlock(title: "声优") {
                        FlowLayout(spacing: 8, lineSpacing: 8) {
                            ForEach(character.actors) { actor in
                                Text(actor.name)
                                    .font(.system(size: 12))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.bgmSecondary.opacity(0.7), in: Capsule())
                            }
                        }
                    }
                }
                infobox(character.infobox)
                relatedSection
            }
            .padding(.top, 10)
            .bgmDesktopContent(maxWidth: 1000)
        }
        .refreshable { await refreshAll() }
    }

    private func personBody(_ person: PersonDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if refreshError != nil {
                    RefreshFailureNotice(message: "人物资料更新失败，显示的是缓存内容") {
                        Task { await loadBase(force: true) }
                    }
                    .padding(.horizontal, 20)
                }
                header(image: person.coverURL, name: person.name, subtitle: person.career.first, summary: person.summary ?? "")
                if !person.career.isEmpty {
                    infoBlock(title: "职业") {
                        FlowLayout(spacing: 8, lineSpacing: 8) {
                            ForEach(person.career, id: \.self) { career in
                                Text(career)
                                    .font(.system(size: 12))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.bgmSecondary.opacity(0.7), in: Capsule())
                            }
                        }
                    }
                }
                infobox(person.infobox)
                relatedSection
            }
            .padding(.top, 10)
            .bgmDesktopContent(maxWidth: 1000)
        }
        .refreshable { await refreshAll() }
    }

    private func header(image: URL?, name: String, subtitle: String?, summary: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            CachedAsyncImage(url: image, maxPixel: 800, contentMode: .fit, placeholderTint: .brandPink)
                .frame(width: 128, height: 176)
                .background(Color.bgmSecondary.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isImage)
                .accessibilityLabel("\(name)完整图片")
                .accessibilityIdentifier("person-portrait")
            VStack(alignment: .leading, spacing: 8) {
                Text(name)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                if !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func infobox(_ items: [InfoboxItem]) -> some View {
        if !items.isEmpty {
            infoBlock(title: "信息") {
                VStack(spacing: 0) {
                    ForEach(items.prefix(12)) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Text(item.key)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 74, alignment: .leading)
                            Text(item.linkedText)
                                .font(.system(size: 12))
                                .tint(Color.brandPink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("infobox-value-\(item.key)")
                        }
                        .padding(.vertical, 7)
                        Divider()
                    }
                }
                .padding(.horizontal, 12)
                .bgmCardBackground(cornerRadius: 12)
            }
        }
    }

    @ViewBuilder
    private var relatedSection: some View {
        if !related.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("参与作品")
                    .font(.bgmSection)
                    .padding(.horizontal, 20)
                if relatedError != nil {
                    RefreshFailureNotice(message: "参与作品更新失败，显示的是缓存内容") {
                        Task { await loadRelated(force: true) }
                    }
                    .padding(.horizontal, 20)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 16, alignment: .top)], alignment: .leading, spacing: 20) {
                    ForEach(related) { item in
                        NavigationLink(value: Route.subject(item.id)) {
                            CoverCard(
                                title: item.displayTitle,
                                subtitle: item.relation,
                                coverURL: item.coverURL,
                                tint: .subjectTint(item.type),
                                width: nil
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("person-related-\(item.id)")
                    }
                }
                .padding(.horizontal, 20)
            }
        } else if let relatedError {
            VStack(alignment: .leading, spacing: 10) {
                Text("参与作品")
                    .font(.bgmSection)
                Text(relatedError)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Button("重试") {
                    Task { await loadRelated(force: true) }
                }
                .font(.system(size: 12, weight: .semibold))
                .buttonStyle(.glass)
            }
            .padding(.horizontal, 20)
        } else if relatedLoading {
            VStack(alignment: .leading, spacing: 10) {
                Text("参与作品")
                    .font(.bgmSection)
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("加载中…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func infoBlock<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.bgmSection)
            content()
        }
        .padding(.horizontal, 20)
    }

    private func prepareIfNeeded() {
        let key = "\(kind.rawValue)-\(id)"
        guard loadedKey != key else { return }
        loadedKey = key
        character = nil
        person = nil
        related = []
        relatedError = nil
        refreshError = nil
        errorText = nil
        isLoading = true
        relatedLoading = true
    }

    private func load() async {
        async let base: Void = loadBase(force: false)
        async let linked: Void = loadRelated(force: false)
        _ = await (base, linked)
    }

    private func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        async let base: Void = loadBase(force: true)
        async let linked: Void = loadRelated(force: true)
        _ = await (base, linked)
    }

    private func loadBase(force: Bool) async {
        let key = "\(kind.rawValue)-\(id)"
        if !force {
            if kind == .character, let hit = await app.api.cachedCharacter(id) {
                guard !Task.isCancelled, loadedKey == key else { return }
                character = hit.value
                isLoading = false
                if hit.isFresh { return }
                guard await app.api.beginBackgroundRefresh(hit.cacheKey, minimumInterval: 120) else { return }
            } else if kind == .person, let hit = await app.api.cachedPerson(id) {
                guard !Task.isCancelled, loadedKey == key else { return }
                person = hit.value
                isLoading = false
                if hit.isFresh { return }
                guard await app.api.beginBackgroundRefresh(hit.cacheKey, minimumInterval: 120) else { return }
            }
        }
        if character == nil && person == nil { isLoading = true }
        if force { refreshError = nil }
        do {
            switch kind {
            case .character:
                let value = try await app.api.character(id)
                guard !Task.isCancelled, loadedKey == key else { return }
                character = value
            case .person:
                let value = try await app.api.person(id)
                guard !Task.isCancelled, loadedKey == key else { return }
                person = value
            }
            errorText = nil
            refreshError = nil
            isLoading = false
        } catch {
            guard !Task.isCancelled, !Self.isCancellation(error) else { return }
            if character == nil && person == nil {
                errorText = Self.message(for: error)
            } else {
                refreshError = Self.message(for: error)
            }
            isLoading = false
        }
    }

    private func loadRelated(force: Bool) async {
        let key = "\(kind.rawValue)-\(id)"
        if !force {
            let hit: CacheHit<[RelatedSubject]>?
            switch kind {
            case .character: hit = await app.api.cachedCharacterSubjects(id)
            case .person: hit = await app.api.cachedPersonSubjects(id)
            }
            if let hit {
                guard !Task.isCancelled, loadedKey == key else { return }
                related = hit.value
                relatedError = nil
                relatedLoading = false
                if hit.isFresh { return }
                guard await app.api.beginBackgroundRefresh(hit.cacheKey, minimumInterval: 120) else { return }
            }
        }
        if force { relatedError = nil }
        if related.isEmpty { relatedLoading = true }
        defer { relatedLoading = false }
        do {
            switch kind {
            case .character:
                related = try await app.api.characterSubjects(id)
            case .person:
                related = try await app.api.personSubjects(id)
            }
            guard !Task.isCancelled, loadedKey == key else { return }
            relatedError = nil
        } catch {
            guard !Task.isCancelled, !Self.isCancellation(error) else { return }
            relatedError = Self.message(for: error)
        }
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let api = error as? APIError, case .cancelled = api { return true }
        return (error as? URLError)?.code == .cancelled
    }

    private func toggleCollection() async {
        isSaving = true
        defer { isSaving = false }
        do {
            switch kind {
            case .character:
                try await app.api.collectCharacter(id, collected: !isCollected)
            case .person:
                try await app.api.collectPerson(id, collected: !isCollected)
            }
            isCollected.toggle()
            app.showToast(isCollected ? "已收藏" : "已取消收藏")
        } catch {
            app.showToast((error as? LocalizedError)?.errorDescription ?? "操作失败", isError: true)
        }
    }
}
