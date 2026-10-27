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
                .padding(.horizontal, 20)
                #if os(macOS)
                .frame(maxWidth: 1120)
                .padding(.horizontal, 28)
                #endif
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(Color.bgmCanvas)
                .overlay(alignment: .bottom) { Divider() }
        }
        .background(Color.bgmCanvas)
        .scrollIndicators(.hidden)
        .bgmNavigationTitle("分类")
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
        HStack(spacing: 12) {
            typePicker
            Button {
                showFilters = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.subheadline)
                    .foregroundStyle(hasActiveFilters ? Color.brandPink : Color.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("分类筛选")
            .accessibilityValue(hasActiveFilters ? "已设置筛选条件" : "全部年份，\(store.sort.title)")
            .accessibilityIdentifier("category-filters")
        }
        #endif
    }

    private var typePicker: some View {
        TextTabs(values: SubjectType.browsingTypes, selection: Binding(
            get: { store.type },
            set: { store.selectType($0) }
        ), title: { $0.title }, horizontalPadding: 10, usesUnderline: true)
    }

    private var hasActiveFilters: Bool {
        store.selectedFilterCount > 0 || store.year != nil || store.sort != .heat
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

            YearPickerButton(selection: $categories.year) {
                filterLabel(store.year.map(String.init) ?? "年份")
            }

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
            if store.sort == .heat {
                Button("改看收藏热度") {
                    store.sort = .collects
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.bordered)
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
            if store.refreshErrorText != nil {
                RefreshFailureNotice(message: "刷新失败，显示的是缓存结果") {
                    Task { await store.load(query, force: true) }
                }
                .padding(.horizontal, 20)
                .accessibilityIdentifier("category-refresh-error")
            }
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
        PaginationFooter(offset: store.nextOffset, isLoading: store.isLoadingMore, error: store.pageErrorText,
                         retry: { await store.loadMore(query, force: true) }) {
            await store.loadMore(query)
        }
        .id(query)
        .padding(.horizontal, 20)
    }
}

private struct CategoryFilterSheet: View {
    @Bindable var store: CategoryStore
    let includeNSFW: Bool
    @State private var search = ""

    private var searchText: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canReset: Bool {
        #if os(iOS)
        store.selectedFilterCount > 0 || store.year != nil || store.sort != .heat
        #else
        store.selectedFilterCount > 0
        #endif
    }

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
        FilterSheet("\(store.type.title)筛选", canReset: canReset, reset: {
            store.selections = [:]
            store.tag = nil
            #if os(iOS)
            store.year = nil
            store.sort = .heat
            #endif
            search = ""
        }, accessory: AnyView(catalogMenu)) {
            VStack(spacing: 0) {
                #if os(iOS)
                HStack(spacing: 24) {
                    YearPickerButton(selection: $store.year) {
                        Label(store.year.map(String.init) ?? "全部年份", systemImage: "calendar")
                    }
                    Menu {
                        Picker("排序", selection: $store.sort) {
                            ForEach(CategorySort.allCases) { sort in
                                Text(sort.title).tag(sort)
                            }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Label(store.sort.title, systemImage: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel("排序：\(store.sort.title)")
                    .accessibilityIdentifier("category-sort")
                    Spacer(minLength: 0)
                }
                .font(.subheadline)
                .frame(minHeight: 44)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                Divider().padding(.horizontal, 20)
                #endif
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索分类、题材、平台", text: $search)
                        .textFieldStyle(.plain)
                        .accessibilityIdentifier("category-filter-search")
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                            .accessibilityLabel("清除搜索")
                    }
                }
                .padding(10)
                .background(Color.bgmSecondary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
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
                            .padding(.vertical, 12)
                        }
                        ForEach(groups) { group in
                            filterGroup(group)
                            Divider()
                        }
                        if let tag = store.tag {
                            HStack {
                                Text("标签：\(tag)")
                                Spacer()
                                Button("移除") { store.tag = nil }
                            }
                            .font(.subheadline).padding(.vertical, 14)
                        }
                        if !searchText.isEmpty {
                            Button("使用标签“\(searchText)”") { store.tag = searchText }
                                .font(.subheadline).padding(.vertical, 14)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }
            }
        }
        .task(id: store.type) { await store.loadFilters(for: store.type) }
        #if os(macOS)
        .frame(width: 660, height: 580)
        #else
        .presentationDetents([.large])
        #endif
    }

    private var catalogMenu: some View {
        Menu {
            Button("同步官网分类", systemImage: "arrow.clockwise") {
                Task { await store.loadFilters(for: store.type, force: true) }
            }
            Link(destination: store.type.browserURL) {
                Label("在浏览器中查看", systemImage: "safari")
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("更多")
    }

    private func filterGroup(_ group: CategoryFilterGroup) -> some View {
        #if os(macOS)
        HStack(alignment: .top, spacing: 16) {
            Text(group.title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading).padding(.top, 8)
            options(group)
        }
        .padding(.vertical, 14)
        #else
        VStack(alignment: .leading, spacing: 10) {
            Text(group.title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            options(group)
        }
        .padding(.vertical, 14)
        #endif
    }

    private func options(_ group: CategoryFilterGroup) -> some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            choice("全部", selected: store.selections[group.id] == nil) {
                store.selections[group.id] = nil
            }
            .accessibilityIdentifier("category-option-\(group.id)-all")
            ForEach(group.options) { option in
                choice(option.title, selected: store.selections[group.id]?.id == option.id) {
                    store.selections[group.id] = option
                }
                .disabled(!includeNSFW && option.metaTags.contains("R18"))
                .accessibilityIdentifier("category-option-\(group.id)-\(option.id)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .fixedSize()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(selected ? Color.brandPink : Color.primary)
                .background(selected ? Color.brandPink.opacity(0.12) : Color.bgmSecondary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
