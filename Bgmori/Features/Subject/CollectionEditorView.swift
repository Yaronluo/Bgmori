import SwiftUI

struct CollectionEditorView: View {
    let subject: Subject
    let episodes: [Episode]
    let collection: UserSubjectCollection?

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Namespace private var statusAnimation

    @State private var status: CollectionType
    @State private var rate: Int
    @State private var watched: Int
    @State private var volumes: Int
    @State private var tagsText: String
    @State private var comment: String
    @State private var isPrivate: Bool
    @State private var isSaving = false
    @State private var errorText: String?
    @State private var showRemoval = false

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
                VStack(alignment: .leading, spacing: 26) {
                    subjectHeader
                    statusSection
                    ratingSection
                    progressSection

                    Divider()

                    tagsSection
                    commentSection
                    privacyRow

                    if collection != nil {
                        removeButton
                    }

                    if let errorText {
                        Label(errorText, systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("collection-save-error")
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 6)
                .padding(.bottom, 30)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
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
        .modifier(CollectionRemovalFlow(
            subjectID: subject.id,
            title: subject.displayTitle,
            isPresented: $showRemoval,
            onRemoved: { dismiss() }
        ))
        #if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #else
        .frame(width: 650, height: 730)
        #endif
    }

    // MARK: - Header

    private var subjectHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                CachedAsyncImage(
                    url: subject.coverURL,
                    maxPixel: 240,
                    contentMode: .fit,
                    placeholderTint: .subjectTint(subject.type)
                )
                .frame(width: 52, height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .shadow(color: .black.opacity(0.10), radius: 6, y: 3)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(subject.displayTitle)
                        .font(.headline)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(headerMeta)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            Divider()
        }
    }

    private var headerMeta: String {
        var parts: [String] = [subject.typeName]
        if let year = subject.date?.prefix(4), !year.isEmpty {
            parts.append(String(year))
        }
        let count = subject.type == SubjectType.book.rawValue
            ? (subject.volumes > 0 ? "\(subject.volumes) 卷" : nil)
            : (mainEpisodes.count > 0 ? "全 \(mainEpisodes.count) 话" : nil)
        if let count {
            parts.append(count)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Status

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("收藏状态")

            HStack(spacing: 4) {
                ForEach(CollectionType.allCases) { type in
                    let tint = Color.collectionTint(type.rawValue)
                    let isSelected = status == type
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            status = type
                        }
                    } label: {
                        Text(type.title)
                            .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? tint : Color.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background {
                                if isSelected {
                                    Capsule()
                                        .fill(tint.opacity(0.14))
                                        .matchedGeometryEffect(id: "collection-status", in: statusAnimation)
                                }
                            }
                            .overlay {
                                if isSelected {
                                    Capsule().strokeBorder(tint.opacity(0.22), lineWidth: 0.8)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("collection-status-\(type.rawValue)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    // MARK: - Rating

    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("我的评分")

                Spacer(minLength: 8)

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

            HStack(spacing: 10) {
                InteractiveStarRating(rating: $rate)
                    .accessibilityIdentifier("collection-rating")
                Spacer(minLength: 0)
            }

            Text("轻点星星的左右半边，可评 1–10 分")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(subject.type == SubjectType.book.rawValue ? "阅读进度" : "观看进度")

            if subject.type == SubjectType.book.rawValue {
                progressControl("话数", value: $watched, total: subject.eps, identifier: "collection-episodes")
                progressControl("卷数", value: $volumes, total: subject.volumes, identifier: "collection-volumes")
            } else if !mainEpisodes.isEmpty {
                progressControl("已看", value: $watched, total: mainEpisodes.count, identifier: "collection-episodes")
                Text("保存时同步此前的章节进度")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Text("暂无可记录的章节")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func progressControl(_ title: String, value: Binding<Int>, total: Int, identifier: String) -> some View {
        let upperBound = max(max(total, value.wrappedValue), 1)
        let canDecrease = value.wrappedValue > 0
        let canIncrease = total <= 0 || value.wrappedValue < total

        return VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Text("\(value.wrappedValue)")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("\(identifier)-value")

                if total > 0 {
                    Text("/ \(total)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                stepButton("minus", enabled: canDecrease) {
                    value.wrappedValue = max(0, value.wrappedValue - 1)
                }
                .accessibilityLabel("减少\(title)")

                Slider(
                    value: Binding(
                        get: { Double(value.wrappedValue) },
                        set: { value.wrappedValue = Int($0.rounded()) }
                    ),
                    in: 0...Double(upperBound),
                    step: 1
                )
                .tint(.brandPink)
                .accessibilityLabel(title)
                .accessibilityValue("\(value.wrappedValue)")
                .accessibilityIdentifier(identifier)

                stepButton("plus", enabled: canIncrease) {
                    value.wrappedValue = min(upperBound, value.wrappedValue + 1)
                }
                .accessibilityLabel("增加\(title)")
            }
        }
    }

    private func stepButton(_ systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(enabled ? Color.primary.opacity(0.72) : Color.secondary.opacity(0.35))
                .frame(width: 30, height: 30)
                .background(Color.primary.opacity(0.055), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Tags & comment

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("标签")

            HStack(spacing: 8) {
                Image(systemName: "tag")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                TextField("添加标签，用逗号分隔", text: $tagsText)
                    .font(.subheadline)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("标签，用逗号分隔")
                    .accessibilityIdentifier("collection-tags")
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 42)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

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
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("短评")
                Spacer(minLength: 8)
                if !comment.isEmpty {
                    Text("\(comment.count) 字")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }

            TextEditor(text: $comment)
                .font(.subheadline)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 112)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Color.primary.opacity(0.055), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("仅自己可见")
                    .font(.subheadline)
                Text("不会出现在公开的收藏页面")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Toggle("仅自己可见", isOn: $isPrivate)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.brandPink)
                .accessibilityIdentifier("collection-private")
        }
    }

    private var removeButton: some View {
        Button(role: .destructive) {
            showRemoval = true
        } label: {
            Label("移除收藏…", systemImage: "trash")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.red)
        .accessibilityIdentifier("collection-remove")
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
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

// MARK: - Star rating

private struct InteractiveStarRating: View {
    @Binding var rating: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let starCount = 5
    private let starSize: CGFloat = 32

    var body: some View {
        HStack(spacing: 9) {
            ForEach(0..<starCount, id: \.self) { index in
                GeometryReader { proxy in
                    ZStack {
                        Image(systemName: "star")
                            .font(.system(size: 28, weight: .regular))
                            .foregroundStyle(Color.primary.opacity(0.13))

                        Image(systemName: "star.fill")
                            .font(.system(size: 28, weight: .regular))
                            .foregroundStyle(Color(red: 0.96, green: 0.70, blue: 0.16))
                            .mask(alignment: .leading) {
                                Rectangle()
                                    .frame(width: proxy.size.width * fillFraction(for: index))
                            }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                let rightHalf = value.location.x >= proxy.size.width / 2
                                let newValue = index * 2 + (rightHalf ? 2 : 1)
                                withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) {
                                    rating = newValue
                                }
                            }
                    )
                }
                .frame(width: starSize, height: starSize)
                .accessibilityHidden(true)
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: rating)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("我的评分")
        .accessibilityValue(rating == 0 ? "未评分" : "\(rating) 分")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                rating = min(10, rating + 1)
            case .decrement:
                rating = max(0, rating - 1)
            @unknown default:
                break
            }
        }
    }

    private func fillFraction(for index: Int) -> CGFloat {
        let stars = Double(rating) / 2
        return CGFloat(max(0, min(1, stars - Double(index))))
    }
}
