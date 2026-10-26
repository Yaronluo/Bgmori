import SwiftUI

struct CategoryView: View {
    @Environment(AppModel.self) private var app
    @State private var showFilters = false

    private var store: CategoryStore { app.categories }
    private var query: CategoryQuery { store.query(includeNSFW: app.settings.showNSFW) }
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16, alignment: .top)]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                results
            }
            .padding(.top, 12)
            .padding(.bottom, 28)
            .bgmDesktopContent()
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            filterControls
                .bgmFloatingControlMargins()
        }
        .background(Color.bgmCanvas)
        .scrollIndicators(.hidden)
        .bgmLargeNavigationTitle("分类")
        .task(id: query) { await store.load(query) }
        .refreshable { await store.load(query, force: true) }
        .sheet(isPresented: $showFilters) {
            CategoryFilterSheet(store: store, includeNSFW: app.settings.showNSFW)
        }
    }

    private var filterControls: some View {
        #if os(macOS)
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 24) {
                typePicker
                Spacer(minLength: 0)
                filterMenus
            }
            VStack(alignment: .leading, spacing: 8) {
                typePicker
                filterMenus.padding(.horizontal, 8)
            }
        }
        #else
        VStack(alignment: .leading, spacing: 4) {
            typePicker
            filterMenus.padding(.horizontal, 8)
        }
        #endif
    }

    private var typePicker: some View {
        TextTabs(values: SubjectType.browsingTypes, selection: Binding(
            get: { store.type },
            set: { store.selectType($0) }
        ), title: { $0.title })
        .padding(4)
        .frame(maxWidth: 370)
        .bgmFloatingGlass(cornerRadius: 24, shadowRadius: 6)
    }

    private var filterMenus: some View {
        @Bindable var categories = store
        return HStack(spacing: 20) {
            Button {
                showFilters = true
            } label: {
                filterLabel(store.selectedFilterCount == 0 ? "筛选" : "筛选 · \(store.selectedFilterCount)", icon: "line.3.horizontal.decrease")
            }
            .accessibilityLabel("分类筛选")
            .accessibilityIdentifier("category-filters")

            Menu {
                Picker("年份", selection: $categories.year) {
                    Text("全部年份").tag(Int?.none)
                    ForEach(years, id: \.self) { year in
                        Text(String(year)).tag(Optional(year))
                    }
                }
            } label: {
                filterLabel(store.year.map(String.init) ?? "年份")
            }
            .accessibilityLabel("年份：\(store.year.map(String.init) ?? "全部年份")")

            Menu {
                Picker("排序", selection: $categories.sort) {
                    ForEach(CategorySort.allCases) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
                .pickerStyle(.inline)
                Divider()
                Link("在浏览器中查看", destination: query.browserURL)
            } label: {
                filterLabel(store.sort.title, icon: "arrow.up.arrow.down")
            }
            .accessibilityLabel("排序：\(store.sort.title)")
            .accessibilityIdentifier("category-sort")
        }
        .buttonStyle(.plain)
        .tint(.primary)
        #if os(macOS)
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        #endif
        .foregroundStyle(.secondary)
    }

    private func filterLabel(_ title: String, icon: String? = nil) -> some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.caption) }
            Text(title).font(.subheadline)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
        }
        .fixedSize()
        #if os(iOS)
        .frame(minHeight: 40)
        #else
        .frame(minHeight: 32)
        #endif
        .contentShape(Rectangle())
    }

    private var years: [Int] {
        Array((1900...Calendar.current.component(.year, from: Date())).reversed())
    }

    @ViewBuilder
    private var results: some View {
        if store.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 64)
        } else if let error = store.errorText {
            EmptyStateView(icon: "wifi.exclamationmark", title: "暂时无法加载", message: error, actionTitle: "重试") {
                Task { await store.load(query, force: true) }
            }
            Link("在浏览器中查看", destination: query.browserURL)
                .frame(maxWidth: .infinity)
        } else if store.subjects.isEmpty {
            EmptyStateView(icon: store.type.icon, title: "没有符合条件的作品", message: "", actionTitle: "重置筛选") {
                store.tag = nil
                store.selections = [:]
                store.year = nil
                store.sort = .heat
                Task { await store.load(query, force: true) }
            }
            if store.hasMore { pagination }
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                ForEach(store.subjects) { subject in
                    NavigationLink(value: Route.subject(subject.id)) {
                        SubjectCard(subject: subject, width: nil)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)

            if store.hasMore { pagination }
        }
    }

    private var pagination: some View {
        PaginationFooter(offset: store.nextOffset, isLoading: store.isLoadingMore, error: store.pageErrorText) {
            await store.loadMore(query)
        }
        .id(query)
        .padding(.horizontal, 20)
    }
}

private struct CategoryFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: CategoryStore
    let includeNSFW: Bool
    @State private var search = ""

    private let columns = [GridItem(.adaptive(minimum: 86), spacing: 8)]
    private var searchText: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var groups: [CategoryFilterGroup] {
        store.filterGroups.compactMap { group in
            let options = group.options.filter {
                searchText.isEmpty || group.title.localizedCaseInsensitiveContains(searchText)
                || $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.metaTags.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
            }
            return options.isEmpty ? nil : CategoryFilterGroup(title: group.title, options: options)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if store.isLoadingFilters && store.filterGroups.isEmpty {
                        ProgressView("正在同步分类")
                            .frame(maxWidth: .infinity).padding(.vertical, 40)
                    }
                    if let error = store.filtersErrorText {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(error).font(.subheadline).foregroundStyle(.secondary)
                            HStack(spacing: 20) {
                                Button("重试") { Task { await store.loadFilters(for: store.type, force: true) } }
                                Link("在浏览器中查看", destination: store.type.browserURL)
                            }
                        }
                    }
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(group.title).font(.headline)
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                                choice("全部", selected: store.selections[group.id] == nil) {
                                    store.selections[group.id] = nil
                                }
                                ForEach(group.options) { option in
                                    choice(option.title, selected: store.selections[group.id]?.id == option.id) {
                                        store.selections[group.id] = option
                                    }
                                    .disabled(!includeNSFW && option.metaTags.contains("R18"))
                                    .accessibilityIdentifier("category-option-\(group.id)-\(option.id)")
                                }
                            }
                        }
                    }
                    if let tag = store.tag {
                        HStack {
                            Text("标签：\(tag)")
                            Spacer()
                            Button("移除") { store.tag = nil }
                        }
                        .font(.subheadline)
                    }
                    if !searchText.isEmpty {
                        Button("使用标签“\(searchText)”") { store.tag = searchText }
                            .font(.subheadline)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.bgmCanvas)
            .navigationTitle("\(store.type.title)筛选")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $search, prompt: "搜索分类、题材、平台")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("重置") {
                        store.selections = [:]
                        store.tag = nil
                        search = ""
                    }
                    .disabled(store.selectedFilterCount == 0)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .accessibilityIdentifier("category-filters-done")
                        .keyboardShortcut(.defaultAction)
                }
                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        Button("同步官网分类", systemImage: "arrow.clockwise") {
                            Task { await store.loadFilters(for: store.type, force: true) }
                        }
                        Link(destination: store.type.browserURL) {
                            Label("在浏览器中查看", systemImage: "safari")
                        }
                    } label: {
                        Label("更多", systemImage: "ellipsis")
                    }
                }
            }
        }
        .task(id: store.type) { await store.loadFilters(for: store.type) }
        #if os(macOS)
        .frame(width: 660, height: 660)
        #else
        .presentationDetents([.large])
        #endif
    }

    private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 36)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .foregroundStyle(selected ? Color.brandPink : Color.primary)
                .background(selected ? Color.brandPink.opacity(0.12) : Color.bgmSurface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.brandPink.opacity(0.4) : Color.primary.opacity(0.08)))
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
