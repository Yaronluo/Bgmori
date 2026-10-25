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
            LazyVStack(alignment: .leading, spacing: 16) {
                searchField
                scopePicker

                if query.trimmed.isEmpty {
                    recentSection
                    discoverHint
                } else if isSearching {
                    ProgressView("搜索中…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                } else if let errorText {
                    EmptyStateView(icon: "wifi.exclamationmark", title: "搜索失败", message: errorText)
                } else if results.isEmpty {
                    EmptyStateView(icon: "magnifyingglass", title: "没有找到", message: "换个关键词，或去 Bangumi 网页搜索。")
                } else {
                    resultGrid
                }
            }
            .padding(.top, 8)
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
        #if os(macOS)
        .navigationTitle("搜索")
        #else
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showFilters) {
            SearchFilterView(type: $typeFilter, year: $yearFilter, sort: $sort)
                #if os(iOS)
                .presentationDetents([.medium])
                #endif
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("搜索条目、角色、人物", text: $query)
                    .font(.system(size: 15))
                    .textFieldStyle(.plain)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .onSubmit {
                        remember()
                        Task { await search() }
                    }
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color.bgmSecondary.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )

            Button {
                showFilters = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.glass)
            .disabled(scope != .subject)
            .opacity(scope == .subject ? 1 : 0.4)
            .accessibilityLabel("筛选")
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }

    private var scopePicker: some View {
        Picker("范围", selection: $scope) {
            ForEach(SearchScope.allCases) { value in
                Text(value.title).tag(value)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("最近搜索")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if !recent.isEmpty {
                    Button("清空") {
                        recent.removeAll()
                        UserDefaults.standard.set(recent, forKey: "recentSearches")
                    }
                    .font(.system(size: 12))
                }
            }
            .padding(.horizontal, 20)

            if recent.isEmpty {
                Text("还没有搜索记录")
                    .font(.system(size: 12))
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
        VStack(alignment: .leading, spacing: 10) {
            Text("试试这些")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 20)
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(["CLANNAD", "攻壳机动队", "俄罗斯方块", "坂本龙一", "2026"], id: \.self) { term in
                    TagChip(name: term) {
                        query = term
                    }
                }
            }
            .padding(.horizontal, 20)
        }
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
                        .font(.system(size: 12))
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
