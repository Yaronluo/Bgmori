import SwiftUI

struct PeopleCollectionView: View {
    @Environment(AppModel.self) private var app
    let username: String

    @State private var characters: [UserCharacterCollection] = []
    @State private var persons: [UserPersonCollection] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorText: String?

    private var total: Int { characters.count + persons.count }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                header

                if !hasLoaded {
                    ProgressView("正在读取人物收藏…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 70)
                } else if characters.isEmpty && persons.isEmpty {
                    EmptyStateView(
                        icon: errorText == nil ? "person.crop.rectangle.stack" : "wifi.exclamationmark",
                        title: errorText == nil ? "还没有人物收藏" : "人物收藏加载失败",
                        message: errorText ?? "收藏角色或人物后，会显示在这里。",
                        actionTitle: errorText == nil ? nil : "重试"
                    ) {
                        Task { await load(force: true) }
                    }
                } else {
                    if !characters.isEmpty {
                        section(title: "角色", subtitle: "\(characters.count) 位") {
                            ForEach(characters) { item in
                                NavigationLink(value: Route.character(item.id)) {
                                    characterCard(item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !persons.isEmpty {
                        section(title: "人物", subtitle: "\(persons.count) 位") {
                            ForEach(persons) { item in
                                NavigationLink(value: Route.person(item.id)) {
                                    personCard(item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if let errorText {
                        Text(errorText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 2)
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
        .bgmNavigationTitle("人物收藏")
        .bgmWebFallback(URL(string: "https://bgm.tv/user/\(username)/mono")!, isPresented: errorText != nil)
        .task(id: username) { await load() }
        .refreshable { await load(force: true) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(total == 0 ? "角色与人物" : "\(total) 位角色与人物")
                .font(.system(size: 24, weight: .bold))
            Text("由你收藏的角色、机体与人物")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private func section<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 2)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 132), spacing: 14, alignment: .top)],
                alignment: .leading,
                spacing: 18
            ) {
                content()
            }
        }
    }

    private func characterCard(_ item: UserCharacterCollection) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            FocusedAsyncImage(url: item.coverURL, maxPixel: 360, placeholderTint: .brandPink, focus: .top)
                .aspectRatio(0.78, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(item.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2, reservesSpace: true)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)

            Text(item.typeName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityLabel("\(item.name)，\(item.typeName)")
    }

    private func personCard(_ item: UserPersonCollection) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            FocusedAsyncImage(url: item.coverURL, maxPixel: 360, placeholderTint: .collectionTint(1), focus: .top)
                .aspectRatio(0.78, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(item.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2, reservesSpace: true)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)

            Text(item.careerText.isEmpty ? item.typeName : "\(item.typeName) · \(item.careerText)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityLabel("\(item.name)，\(item.typeName)")
    }

    private func load(force: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        errorText = nil
        defer {
            isLoading = false
            hasLoaded = true
        }

        let auth = app.auth.isLoggedIn
        do {
            characters = try await app.api.userCharacterCollections(username, limit: 100, auth: auth, force: force).data
        } catch {
            if characters.isEmpty {
                errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
        do {
            persons = try await app.api.userPersonCollections(username, limit: 100, auth: auth, force: force).data
        } catch {
            if persons.isEmpty {
                errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
