import SwiftUI

struct CategoryView: View {
    @Environment(AppModel.self) private var app

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
            Menu {
                Picker("题材", selection: $categories.tag) {
                    Text("全部题材").tag(String?.none)
                    ForEach(store.type.browsingTags, id: \.self) { tag in
                        Text(tag).tag(Optional(tag))
                    }
                }
            } label: {
                filterLabel(store.tag ?? "题材")
            }
            .accessibilityLabel("题材：\(store.tag ?? "全部题材")")

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
            } label: {
                filterLabel(store.sort.title, icon: "arrow.up.arrow.down")
            }
            .accessibilityLabel("排序：\(store.sort.title)")
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
        } else if store.subjects.isEmpty {
            EmptyStateView(icon: store.type.icon, title: "没有符合条件的作品", message: "", actionTitle: "重置筛选") {
                store.tag = nil
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
