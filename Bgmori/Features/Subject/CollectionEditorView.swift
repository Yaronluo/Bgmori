import SwiftUI

struct CollectionEditorView: View {
    let subject: Subject
    let episodes: [Episode]
    let collection: UserSubjectCollection?

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var status: CollectionType
    @State private var rate: Int
    @State private var watched: Int
    @State private var volumes: Int
    @State private var tagsText: String
    @State private var comment: String
    @State private var isPrivate: Bool
    @State private var isSaving = false
    @State private var errorText: String?

    init(subject: Subject, episodes: [Episode], collection: UserSubjectCollection?) {
        self.subject = subject
        self.episodes = episodes
        self.collection = collection
        _status = State(initialValue: collection?.collectionType ?? .wish)
        _rate = State(initialValue: collection?.rate ?? 0)
        _watched = State(initialValue: collection?.epStatus ?? 0)
        _volumes = State(initialValue: collection?.volStatus ?? 0)
        _tagsText = State(initialValue: collection?.tags.joined(separator: ", ") ?? "")
        _comment = State(initialValue: collection?.comment ?? "")
        _isPrivate = State(initialValue: collection?.isPrivate ?? false)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    subjectHeader
                    Divider()
                    statusSection

                    #if os(macOS)
                    HStack(alignment: .top, spacing: 32) {
                        ratingSection
                            .frame(maxWidth: .infinity)
                        progressSection
                            .frame(maxWidth: .infinity)
                    }
                    #else
                    ratingSection
                    progressSection
                    #endif

                    Divider()
                    tagsSection
                    commentSection
                    privacyRow

                    if let errorText {
                        Label(errorText, systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("collection-save-error")
                    }
                }
                .padding(24)
                .disabled(isSaving)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.bgmCanvas)
            .navigationTitle("编辑收藏")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(isSaving)
                        .accessibilityIdentifier("collection-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving { ProgressView() } else { Text("保存").bold() }
                    }
                    .disabled(isSaving)
                    .accessibilityIdentifier("collection-save")
                }
            }
            .onAppear {
                if subject.type != SubjectType.book.rawValue, !mainEpisodes.isEmpty {
                    watched = min(max(watched, app.library.watchedCount(for: subject.id)), mainEpisodes.count)
                }
            }
        }
        .tint(.brandPink)
        .interactiveDismissDisabled(isSaving)
        #if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #else
        .frame(width: 640, height: 710)
        #endif
    }

    private var subjectHeader: some View {
        HStack(spacing: 14) {
            CachedAsyncImage(url: subject.coverURL, maxPixel: 240, contentMode: .fit,
                             placeholderTint: .subjectTint(subject.type))
                .frame(width: 50, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(subject.displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text([subject.typeName, subject.date.map { String($0.prefix(4)) }]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("收藏状态")
            Picker("收藏状态", selection: $status) {
                ForEach(CollectionType.allCases) { type in
                    Text(type.title).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("collection-status")
        }
    }

    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("我的评分")
                Spacer()
                if rate > 0 {
                    Button("清除") { rate = 0 }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("collection-rating-clear")
                }
                Text(rate == 0 ? "未评分" : "\(rate) 分")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(rate == 0 ? Color.secondary : Color.brandPink)
                    .accessibilityIdentifier("collection-rating-value")
            }
            Slider(value: Binding(get: { Double(rate) }, set: { rate = Int($0) }), in: 0...10, step: 1) {
                Text("我的评分")
            } minimumValueLabel: {
                Text("0").font(.caption).foregroundStyle(.tertiary)
            } maximumValueLabel: {
                Text("10").font(.caption).foregroundStyle(.tertiary)
            }
            .labelsHidden()
            .accessibilityValue(rate == 0 ? "未评分" : "\(rate) 分")
            .accessibilityIdentifier("collection-rating")
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("阅读进度", alternative: "观看进度")
            if subject.type == SubjectType.book.rawValue {
                progressControl("话数", value: $watched, total: subject.eps, identifier: "collection-episodes")
                progressControl("卷数", value: $volumes, total: subject.volumes, identifier: "collection-volumes")
            } else if !mainEpisodes.isEmpty {
                progressControl("已看", value: $watched, total: mainEpisodes.count, identifier: "collection-episodes")
                Text("保存时同步此前的章节进度")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("暂无可记录的章节")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func progressControl(_ title: String, value: Binding<Int>, total: Int, identifier: String) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(total > 0 ? "\(value.wrappedValue) / \(max(total, value.wrappedValue))" : "\(value.wrappedValue)")
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .accessibilityIdentifier("\(identifier)-value")
                Stepper(title, value: value, in: 0...max(1, total, value.wrappedValue))
                    .labelsHidden()
                    .accessibilityLabel(title)
                    .accessibilityValue("\(value.wrappedValue)")
                    .accessibilityIdentifier(identifier)
            }
            if total > 0 {
                ProgressView(value: min(Double(value.wrappedValue) / Double(total), 1))
                    .progressViewStyle(.linear)
                    .controlSize(.mini)
                    .accessibilityHidden(true)
            }
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("标签")
            TextField("添加标签，用逗号分隔", text: $tagsText)
                .font(.subheadline)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Color.bgmSecondary, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("标签，用逗号分隔")
                .accessibilityIdentifier("collection-tags")
            if !parsedTags.isEmpty {
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(parsedTags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption)
                            .foregroundStyle(Color.brandPink)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.brandPink.opacity(0.08), in: Capsule())
                    }
                }
            }
        }
    }

    private var commentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("短评")
            TextEditor(text: $comment)
                .font(.subheadline)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 112)
                .background(Color.bgmSecondary, in: RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topLeading) {
                    if comment.isEmpty {
                        Text("写下你的感受…")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .padding(13)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityLabel("短评")
                .accessibilityIdentifier("collection-comment")
        }
    }

    private var privacyRow: some View {
        HStack {
            Label("仅自己可见", systemImage: "lock")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Toggle("仅自己可见", isOn: $isPrivate)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityIdentifier("collection-private")
        }
    }

    private func sectionTitle(_ title: String, alternative: String? = nil) -> some View {
        Text(subject.type == SubjectType.book.rawValue ? title : (alternative ?? title))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
    }

    private var mainEpisodes: [Episode] {
        episodes.filter { $0.type == 0 }.sorted { $0.sort < $1.sort }
    }

    private var parsedTags: [String] {
        var seen = Set<String>()
        return tagsText
            .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == " " })
            .map { String($0).trimmed }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private func save() async {
        isSaving = true
        errorText = nil
        defer { isSaving = false }

        var patch = CollectionPatch()
        patch.type = status.rawValue
        patch.rate = rate
        patch.comment = comment
        patch.tags = parsedTags
        patch.isPrivate = isPrivate
        if subject.type == SubjectType.book.rawValue {
            patch.epStatus = watched
            patch.volStatus = volumes
        }

        do {
            try await app.library.save(subject: subject, patch: patch)
            if subject.type != SubjectType.book.rawValue, !mainEpisodes.isEmpty {
                await app.library.setProgress(subject: subject, episodes: episodes, watchedCount: watched)
            }
            app.showToast("收藏已更新")
            dismiss()
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
