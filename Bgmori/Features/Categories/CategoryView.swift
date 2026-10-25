import SwiftUI

struct CategoryView: View {
    @Environment(AppModel.self) private var app

    private var store: CategoryStore { app.categories }
    private var query: CategoryQuery { store.query(includeNSFW: app.settings.showNSFW) }
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16, alignment: .top)]

    var body: some View {
        @Bindable var categories = store

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    #if os(macOS)
                    Text("分类").font(.largeTitle.bold())
                    #endif
                    Text("按兴趣，找下一部好作品。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)

                Picker("内容类型", selection: Binding(
                    get: { store.type },
                    set: { store.selectType($0) }
                )) {
                    ForEach(SubjectType.browsingTypes) { type in
                        Text(type.title).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)

                tagPicker

                HStack {
                    Label(store.type.title, systemImage: store.type.icon)
                        .font(.headline)
                    Spacer()
                    Menu {
                        Picker("年份", selection: $categories.year) {
                            Text("全部年份").tag(Int?.none)
                            ForEach(years, id: \.self) { year in
                                Text(String(year)).tag(Optional(year))
                            }
                        }
                    } label: {
                        Text(store.year.map(String.init) ?? "全部年份")
                    }
                    .accessibilityLabel("年份：\(store.year.map(String.init) ?? "全部年份")")

                    Menu {
                        Picker("排序", selection: $categories.sort) {
                            ForEach(CategorySort.allCases) { sort in
                                Text(sort.title).tag(sort)
                            }
                        }
                    } label: {
                        Label(store.sort.title, systemImage: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel("排序：\(store.sort.title)")
                }
                .font(.subheadline)
                .padding(.horizontal, 20)

                results
            }
            .padding(.top, 12)
            .padding(.bottom, 28)
            .bgmDesktopContent()
        }
        .background(Color.bgmCanvas)
        .scrollIndicators(.hidden)
        .bgmLargeNavigationTitle("分类")
        .task(id: query) { await store.load(query) }
        .refreshable { await store.load(query, force: true) }
    }

    private var years: [Int] {
        Array((1900...Calendar.current.component(.year, from: Date())).reversed())
    }

    private var tagPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                tagButton("全部题材", value: nil)
                ForEach(store.type.browsingTags, id: \.self) { tag in
                    tagButton(tag, value: tag)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func tagButton(_ title: String, value: String?) -> some View {
        Button { store.tag = value } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .foregroundStyle(store.tag == value ? Color.brandPink : Color.secondary)
                .background(store.tag == value ? Color.brandPink.opacity(0.12) : Color.bgmSurface, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(store.tag == value ? .isSelected : [])
    }

    @ViewBuilder
    private var results: some View {
        if store.isLoading {
            ProgressView("正在挑选\(store.type.title)…")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 64)
        } else if let error = store.errorText {
            EmptyStateView(icon: "wifi.exclamationmark", title: "暂时无法加载", message: error, actionTitle: "重试") {
                Task { await store.load(query, force: true) }
            }
        } else if store.subjects.isEmpty {
            EmptyStateView(icon: store.type.icon, title: "没有符合条件的作品", message: "试试其他题材或年份。", actionTitle: "重置筛选") {
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
                        SubjectCard(subject: subject, width: 150)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)

            if store.hasMore { pagination }
        }
    }

    private var pagination: some View {
        VStack(spacing: 12) {
            if let error = store.pageErrorText {
                Text(error).font(.caption).foregroundStyle(.secondary)
            }
            if store.isLoadingMore {
                ProgressView("正在加载更多…")
            } else {
                Button(store.pageErrorText == nil ? "加载更多" : "重新加载") {
                    Task { await store.loadMore(query) }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
    }
}
