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
            Form {
                Section {
                    Picker("状态", selection: $status) {
                        ForEach(CollectionType.allCases) { type in
                            Label(type.title, systemImage: type.icon).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("评分") {
                    HStack(spacing: 6) {
                        ForEach(1...10, id: \.self) { value in
                            Button {
                                rate = rate == value ? 0 : value
                            } label: {
                                Image(systemName: value <= rate ? "star.fill" : "star")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(value <= rate ? Color.orange : Color.secondary.opacity(0.45))
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                        Text(rate == 0 ? "未评分" : "\(rate) 分")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Section("进度") {
                    if subject.type == SubjectType.book.rawValue {
                        Stepper("已读 \(watched) / \(max(subject.eps, watched)) 话", value: $watched, in: 0...max(1, max(subject.eps, watched)))
                        Stepper("已读 \(volumes) / \(max(subject.volumes, volumes)) 卷", value: $volumes, in: 0...max(1, max(subject.volumes, volumes)))
                    } else if !mainEpisodes.isEmpty {
                        Stepper("看到第 \(watched) 话 / \(mainEpisodes.count)", value: $watched, in: 0...mainEpisodes.count)
                        Text("保存后会批量更新这一话之前的章节状态。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("该条目没有可记录的章节")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("标签") {
                    TextField("用逗号分隔，例如：日本, TV, 2008", text: $tagsText)
                    if !parsedTags.isEmpty {
                        FlowLayout(spacing: 6, lineSpacing: 6) {
                            ForEach(parsedTags, id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 11))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.bgmSecondary, in: Capsule())
                            }
                        }
                    }
                }

                Section("短评") {
                    TextEditor(text: $comment)
                        .frame(minHeight: 92)
                        .font(.system(size: 13))
                }

                Section {
                    Toggle("仅自己可见", isOn: $isPrivate)
                }

                if let errorText {
                    Section {
                        Text(errorText)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("收藏《\(subject.displayTitle)》")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving { ProgressView() } else { Text("保存").bold() }
                    }
                    .disabled(isSaving)
                }
            }
            .onAppear {
                watched = min(watched, mainEpisodes.count)
            }
        }
        #if os(iOS)
        .presentationDetents([.large])
        #endif
    }

    private var mainEpisodes: [Episode] {
        episodes.filter { $0.type == 0 }.sorted { $0.sort < $1.sort }
    }

    private var parsedTags: [String] {
        tagsText
            .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == " " })
            .map { String($0).trimmed }
            .filter { !$0.isEmpty }
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
