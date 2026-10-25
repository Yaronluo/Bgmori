import SwiftUI

enum SearchScope: String, CaseIterable, Identifiable {
    case subject
    case character
    case person

    var id: String { rawValue }

    var title: String {
        switch self {
        case .subject: "条目"
        case .character: "角色"
        case .person: "人物"
        }
    }
}

enum SearchItem: Identifiable {
    case subject(Subject)
    case character(Character)
    case person(Person)

    var id: String {
        switch self {
        case .subject(let value): "s-\(value.id)"
        case .character(let value): "c-\(value.id)"
        case .person(let value): "p-\(value.id)"
        }
    }
}

struct SearchView: View {
    @Environment(AppModel.self) private var app
    @State private var query = ""
    @State private var scope: SearchScope = .subject
    @State private var results: [SearchItem] = []
    @State private var isSearching = false
    @State private var errorText: String?
    @State private var showFilters = false
    @State private var typeFilter: SubjectType?
    @State private var yearFilter: Int?
    @State private var sort = "match"
    @State private var recent: [String] = UserDefaults.standard.stringArray(forKey: "recentSearches") ?? []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                #if os(macOS)
                VStack(alignment: .leading, spacing: 18) {
                    Text("搜索").font(.largeTitle.bold())
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("搜索作品、角色、创作者", text: $query)
                            .textFieldStyle(.plain)
                            .onSubmit {
                                remember()
                                Task { await search() }
                            }
                        if !query.isEmpty {
                            Button("清除", systemImage: "xmark.circle.fill") { query = "" }
                                .labelStyle(.iconOnly).buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.title3)
                    .padding(14)
                    .background(Color.bgmSurface, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.10)))
                }
                .padding(.horizontal, 20)
                #endif
                scopePicker

                if query.trimmed.isEmpty {
                    recentSection
                    discoverHint
                } else if isSearching {
                    ProgressView("搜索中…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                } else if let errorText {
                    EmptyStateView(icon: "wifi.exclamationmark", title: "搜索失败", message: errorText, actionTitle: "重试") {
                        Task { await search() }
                    }
                } else if results.isEmpty {
                    EmptyStateView(icon: "magnifyingglass", title: "没有找到", message: "换个关键词，或去 Bangumi 网页搜索。")
                } else {
                    resultGrid
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 28)
            .bgmDesktopContent(maxWidth: 820)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            if query.isEmpty, !app.router.searchQuery.isEmpty {
                query = app.router.searchQuery
            }
        }
        .onChange(of: app.router.searchQuery) { _, newValue in
            if !newValue.isEmpty, newValue != query { query = newValue }
        }
        .task(id: "\(query)|\(scope.rawValue)|\(typeFilter?.rawValue ?? 0)|\(yearFilter ?? 0)|\(sort)") {
            try? await Task.sleep(nanoseconds: 380_000_000)
            guard !Task.isCancelled else { return }
            await search()
        }
        .background(Color.bgmCanvas)
        .bgmLargeNavigationTitle("搜索")
        #if os(iOS)
        .bgmSearchable(text: $query, prompt: "作品、角色、创作者")
        #endif
        .onSubmit(of: .search) {
            remember()
            Task { await search() }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("筛选", systemImage: "slider.horizontal.3") { showFilters = true }
                    .disabled(scope != .subject)
            }
        }
        .sheet(isPresented: $showFilters) {
            SearchFilterView(type: $typeFilter, year: $yearFilter, sort: $sort)
                #if os(iOS)
                .presentationDetents([.medium])
                #endif
        }
    }

    private var scopePicker: some View {
        Picker("范围", selection: $scope) {
            ForEach(SearchScope.allCases) { value in
                Text(value.title).tag(value)
            }
        }
        .pickerStyle(.segmented)
        #if os(macOS)
        .labelsHidden()
        .frame(width: 240)
        #endif
        .padding(.horizontal, 20)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("最近搜索")
                    .font(.title3.weight(.bold))
                Spacer()
                if !recent.isEmpty {
                    Button("清空") {
                        recent.removeAll()
                        UserDefaults.standard.set(recent, forKey: "recentSearches")
                    }
                    .font(.subheadline)
                    #if os(macOS)
                    .buttonStyle(.link)
                    #endif
                }
            }
            .padding(.horizontal, 20)

            if recent.isEmpty {
                Text("还没有搜索记录")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 20)
            } else {
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(recent, id: \.self) { term in
                        TagChip(name: term) {
                            query = term
                            remember()
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var discoverHint: some View {
        let suggestions = [
            ("CLANNAD", "动画 · 写给青春的故事", "tv"),
            ("攻壳机动队", "动画 · 走进赛博世界", "sparkles.tv"),
            ("俄罗斯方块", "游戏 · 简单而隽永", "gamecontroller"),
            ("坂本龙一", "音乐 · 听见更多可能", "music.note")
        ]
        return VStack(alignment: .leading, spacing: 16) {
            Text("找点灵感")
                .font(.title3.weight(.bold))
            VStack(spacing: 0) {
                ForEach(suggestions, id: \.0) { term, detail, icon in
                    Button {
                        scope = .subject
                        query = term
                        remember()
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: icon)
                                .font(.title3)
                                .foregroundStyle(Color.brandPink)
                                .frame(width: 40, height: 40)
                                .background(Color.brandPink.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(term).font(.body.weight(.medium)).foregroundStyle(.primary)
                                Text(detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.left")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if term != suggestions.last?.0 {
                        Divider().padding(.leading, 68)
                    }
                }
            }
            .background(Color.bgmSurface, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 20)
    }

    private var resultGrid: some View {
        Group {
            switch scope {
            case .subject:
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16, alignment: .top)], alignment: .leading, spacing: 20) {
                    ForEach(results) { item in
                        if case .subject(let subject) = item {
                            NavigationLink(value: Route.subject(subject.id)) {
                                SubjectCard(subject: subject, width: 150)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)
            case .character, .person:
                LazyVStack(spacing: 0) {
                    ForEach(results) { item in
                        switch item {
                        case .character(let character):
                            NavigationLink(value: Route.character(character.id)) {
                                personRow(title: character.name, subtitle: character.actors.first?.name, image: character.coverURL, tint: .brandPink)
                            }
                            .buttonStyle(.plain)
                        case .person(let person):
                            NavigationLink(value: Route.person(person.id)) {
                                personRow(title: person.name, subtitle: person.career.first, image: person.coverURL, tint: .purple)
                            }
                            .buttonStyle(.plain)
                        case .subject:
                            EmptyView()
                        }
                    }
                }
            }
        }
    }

    private func personRow(title: String, subtitle: String?, image: URL?, tint: Color) -> some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: image, maxPixel: 220, placeholderTint: tint)
                .frame(width: 52, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func search() async {
        let keyword = query.trimmed
        guard !keyword.isEmpty else {
            results = []
            errorText = nil
            return
        }
        isSearching = true
        errorText = nil
        defer { isSearching = false }

        do {
            switch scope {
            case .subject:
                var filter = SubjectSearchFilter()
                filter.type = typeFilter.map { [$0.rawValue] }
                filter.nsfw = app.settings.showNSFW ? nil : false
                if let yearFilter {
                    filter.airDate = [">=\(yearFilter)-01-01", "<\(yearFilter + 1)-01-01"]
                }
                let page = try await app.api.searchSubjects(keyword: keyword, sort: sort, filter: filter)
                results = page.data.map(SearchItem.subject)
            case .character:
                let page = try await app.api.searchCharacters(keyword: keyword)
                results = page.data.map(SearchItem.character)
            case .person:
                let page = try await app.api.searchPersons(keyword: keyword)
                results = page.data.map(SearchItem.person)
            }
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            results = []
        }
    }

    private func remember() {
        let term = query.trimmed
        guard !term.isEmpty else { return }
        recent.removeAll { $0 == term }
        recent.insert(term, at: 0)
        if recent.count > 10 { recent = Array(recent.prefix(10)) }
        UserDefaults.standard.set(recent, forKey: "recentSearches")
    }
}

struct SearchFilterView: View {
    @Binding var type: SubjectType?
    @Binding var year: Int?
    @Binding var sort: String
    @Environment(\.dismiss) private var dismiss

    private let years: [Int] = Array((1990...Calendar.current.component(.year, from: Date())).reversed())

    var body: some View {
        NavigationStack {
            Form {
                Picker("类型", selection: $type) {
                    Text("全部").tag(SubjectType?.none)
                    ForEach(SubjectType.allCases) { value in
                        Text(value.title).tag(Optional(value))
                    }
                }
                Picker("年份", selection: $year) {
                    Text("全部年份").tag(Int?.none)
                    ForEach(years, id: \.self) { value in
                        Text("\(value)").tag(Optional(value))
                    }
                }
                Picker("排序", selection: $sort) {
                    Text("匹配度").tag("match")
                    Text("热度").tag("heat")
                    Text("排名").tag("rank")
                    Text("评分").tag("score")
                }
                Button("重置筛选") {
                    type = nil
                    year = nil
                    sort = "match"
                }
            }
            .navigationTitle("筛选")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
