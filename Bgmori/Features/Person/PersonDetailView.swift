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
        .task(id: "\(kind.rawValue)-\(id)") { await load() }
    }

    private var title: String {
        character?.name ?? person?.name ?? "人物"
    }

    private func characterBody(_ character: Character) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(image: character.coverURL, name: character.name, subtitle: character.relation, summary: character.summary)
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
        }
    }

    private func personBody(_ person: PersonDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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
        }
    }

    private func header(image: URL?, name: String, subtitle: String?, summary: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            CachedAsyncImage(url: image, maxPixel: 520, placeholderTint: .brandPink)
                .frame(width: 128, height: 176)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                            Text(item.value.display)
                                .font(.system(size: 12))
                                .frame(maxWidth: .infinity, alignment: .leading)
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12, alignment: .top)], alignment: .leading, spacing: 14) {
                    ForEach(related) { item in
                        NavigationLink(value: Route.subject(item.id)) {
                            VStack(alignment: .leading, spacing: 4) {
                                CachedAsyncImage(url: item.coverURL, maxPixel: 260, placeholderTint: .subjectTint(item.type))
                                    .frame(height: 140)
                                    .frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                Text(item.displayTitle)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(2)
                                Text(item.relation)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func infoBlock<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.bgmSection)
            content()
        }
        .padding(.horizontal, 20)
    }

    private func load() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            switch kind {
            case .character:
                let value = try await app.api.character(id)
                character = value
                related = (try? await app.api.characterSubjects(id)) ?? []
            case .person:
                let value = try await app.api.person(id)
                person = value
                related = (try? await app.api.personSubjects(id)) ?? []
            }
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
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
