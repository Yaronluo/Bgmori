import SwiftUI

struct CachedAsyncImage: View {
    let url: URL?
    var maxPixel: Int = 400
    var contentMode: ContentMode = .fill
    var placeholderTint: Color = .bgmSecondary
    var showsPlaceholderIcon = true
    var imageIdentity: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var presentation = ImagePresentation()

    private var request: ImagePresentation.Request {
        .init(url: url, maxPixel: maxPixel, identity: imageIdentity)
    }

    var body: some View {
        ZStack {
            if let image = presentation.image(for: request) {
                Image(decorative: image.cgImage, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .contentTransition(.opacity)
                    .transition(.opacity)
            } else {
                LinearGradient(
                    colors: [placeholderTint.opacity(0.55), placeholderTint.opacity(0.22)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    if showsPlaceholderIcon {
                        Image(systemName: "photo")
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
        .clipped()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: presentation.replacementVersion)
        .task(id: request) {
            await presentation.load(request)
        }
    }
}

/// Fills its frame like `CachedAsyncImage(contentMode: .fill)`, but anchors the
/// crop so tall character artwork keeps the head in view.
struct FocusedAsyncImage: View {
    let url: URL?
    var maxPixel: Int = 400
    var placeholderTint: Color = .bgmSecondary
    var focus: UnitPoint = .top

    @State private var presentation = ImagePresentation()

    private var request: ImagePresentation.Request { .init(url: url, maxPixel: maxPixel) }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image = presentation.image(for: request) {
                    let size = CGSize(width: CGFloat(image.cgImage.width), height: CGFloat(image.cgImage.height))
                    let scale = max(proxy.size.width / max(size.width, 1), proxy.size.height / max(size.height, 1))
                    let width = size.width * scale
                    let height = size.height * scale

                    Image(decorative: image.cgImage, scale: 1)
                        .resizable()
                        .frame(width: width, height: height)
                        .position(
                            x: (proxy.size.width - width) * focus.x + width / 2,
                            y: (proxy.size.height - height) * focus.y + height / 2
                        )
                } else {
                    LinearGradient(
                        colors: [placeholderTint.opacity(0.55), placeholderTint.opacity(0.22)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 18, weight: .light))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .task(id: request) {
            await presentation.load(request)
        }
    }
}

struct CoverCard: View {
    @Environment(\.displayScale) private var displayScale

    let title: String
    var subtitle: String? = nil
    let coverURL: URL?
    var badge: String? = nil
    var progress: Double? = nil
    var tint: Color = .brandPink
    var width: CGFloat? = 132
    /// A small leaderboard number shown in the artwork's leading corner.
    var rank: Int? = nil
    var imageIdentity: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                CachedAsyncImage(url: coverURL, maxPixel: Int(ceil(max(geometry.size.width, geometry.size.height) * displayScale)), placeholderTint: tint, imageIdentity: imageIdentity)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        if let rank {
                            rankBadge(rank)
                        }
                    }
            }
            .aspectRatio(1 / 1.42, contentMode: .fit)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2, reservesSpace: true)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("cover-card-title")

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(subtitle ?? "")
                    .foregroundStyle(.secondary)
                    .lineLimit(1, reservesSpace: true)
                Spacer(minLength: 0)
                if let badge, !badge.isEmpty {
                    Text(badge)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(Color.brandPink)
                        .fixedSize()
                }
            }
            .font(.caption)

            if let progress {
                ProgressView(value: max(0, min(progress, 1)))
                    .tint(.brandPink)
                    .opacity(progress > 0 ? 1 : 0)
                    .accessibilityHidden(progress <= 0)
                    .accessibilityLabel("观看进度")
            }
        }
        .frame(width: width)
        .contentShape(Rectangle())
    }

    private func rankBadge(_ rank: Int) -> some View {
        Text("#\(rank)")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(rank <= 3 ? Color(red: 1, green: 0.84, blue: 0.46) : .white)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.bgmArtworkScrim.opacity(0.62), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.bgmOnArtwork.opacity(0.16), lineWidth: 0.5))
            .padding(7)
            .accessibilityLabel("第 \(rank) 名")
    }
}

struct SubjectCard: View {
    let subject: Subject
    var width: CGFloat? = 132
    var rank: Int? = nil

    var body: some View {
        let detail = subject.episodeCountText
        return CoverCard(
            title: subject.displayTitle,
            subtitle: detail.isEmpty || detail == subject.typeName ? subject.typeName : "\(subject.typeName) · \(detail)",
            coverURL: subject.coverURL,
            badge: subject.rating.map { String(format: "%.1f", $0.score) },
            tint: .subjectTint(subject.type),
            width: width,
            rank: rank
        )
    }
}

struct SubjectSummaryCard: View {
    let subject: SubjectSummary
    var progress: Double? = nil
    var badge: String? = nil
    var width: CGFloat? = 132

    var body: some View {
        CoverCard(
            title: subject.displayTitle,
            subtitle: "\(SubjectType.title(for: subject.type)) · \(subject.ratingText)",
            coverURL: subject.coverURL,
            badge: badge,
            progress: progress,
            tint: .subjectTint(subject.type),
            width: width,
            imageIdentity: "subject-\(subject.id)"
        )
    }
}

struct AiringCard: View {
    let subject: LegacySubject
    var isWatching = false
    var width: CGFloat = 120
    var contentRevision: Data? = nil

    var body: some View {
        CoverCard(
            title: subject.displayTitle,
            subtitle: isWatching ? "在看 · 今日更新" : "今日更新",
            coverURL: subject.coverURL,
            badge: subject.rating.map { String(format: "%.1f", $0.score) },
            tint: .subjectTint(subject.type),
            width: width,
            imageIdentity: "subject-\(subject.id)"
        )
    }
}

struct SubjectRow: View {
    let title: String
    var subtitle: String? = nil
    let coverURL: URL?
    var trailing: String? = nil
    var tint: Color = .brandPink

    var body: some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: coverURL, maxPixel: 220, placeholderTint: tint)
                .frame(width: 56, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2, reservesSpace: true)
                    .truncationMode(.tail)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            if let trailing {
                Text(trailing)
                    .font(.bgmNumber)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct CollectionBadge: View {
    let type: CollectionType

    var body: some View {
        Label(type.title, systemImage: type.icon)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(Color.collectionTint(type.rawValue))
            .background(Color.collectionTint(type.rawValue).opacity(0.12), in: Capsule())
    }
}

struct TagChip: View {
    let name: String
    var count: Int? = nil
    var isSelected = false
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button(action: action) { chipContent }
                .buttonStyle(.plain)
        } else {
            chipContent
        }
    }

    private var chipContent: some View {
        HStack(spacing: 4) {
            Text(name)
                .font(.caption)
            if let count {
                Text("\(count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        #if os(macOS)
        .padding(.vertical, 5)
        #else
        .padding(.vertical, 9)
        #endif
        .foregroundStyle(isSelected ? Color.bgmCanvas : Color.primary)
        .background(isSelected ? Color.brandPink : Color.bgmSecondary, in: Capsule())
    }
}

/// A titled panel used by detail pages. The card clips its content so horizontal
/// shelves stay inside the rounded surface.
struct SectionCard<Content: View>: View {
    let title: String
    var accessory: AnyView?
    let content: Content

    init(_ title: String, accessory: AnyView? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.accessory = accessory
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    #if os(iOS)
                    .font(.system(size: 17, weight: .semibold))
                    #else
                    .font(.system(size: 15, weight: .semibold))
                    #endif
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                accessory
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bgmPanel(cornerRadius: 16)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct SectionExpansionFooter: View {
    @Binding var isExpanded: Bool
    let remainingCount: Int
    let unit: String
    let sectionName: String
    let identifier: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if remainingCount > 0 {
            VStack(spacing: 12) {
                Divider().opacity(0.45)
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.24)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(isExpanded ? "收起\(sectionName)" : "查看其余 \(remainingCount) \(unit)")
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.brandPink)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(isExpanded ? "已展开" : "已收起")
                .accessibilityIdentifier(identifier)
            }
        }
    }
}

struct SectionCollapseButton: View {
    @Binding var isExpanded: Bool
    let identifier: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if isExpanded {
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.24)) {
                    isExpanded = false
                }
            } label: {
                Label("收起", systemImage: "chevron.up")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.brandPink)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("\(identifier)-collapse")
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var width: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            width = max(width, x)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? width, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

struct LoginPromptView: View {
    let title: String
    let message: String
    var actionTitle = "登录 Bangumi"
    var action: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "books.vertical")
        } description: {
            if !message.isEmpty { Text(message) }
        } actions: {
            Button(actionTitle, action: action)
                .buttonStyle(.glassProminent)
                .foregroundStyle(Color.bgmCanvas)
                .tint(.brandPink)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
    }
}

struct LoadingCard: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.bgmSecondary.opacity(0.6))
            .frame(height: 180)
            .overlay {
                ProgressView()
            }
    }
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    var isError = false
}

struct ToastView: View {
    let message: ToastMessage

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: message.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(message.isError ? .orange : .green)
            Text(message.text)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .modifier(ToastGlassModifier())
        .padding(.horizontal, 20)
    }
}

private struct ToastGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        GlassSurface(shape: AnyShape(Capsule())) { content }
    }
}

struct AvatarView: View {
    let url: URL?
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let url {
                CachedAsyncImage(url: url, maxPixel: Int(size * 3), placeholderTint: .brandPink)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(Color.brandPink, Color.brandPink.opacity(0.10))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

extension View {
    @ViewBuilder
    func bgmSearchable(text: Binding<String>, prompt: String) -> some View {
        #if os(iOS)
        searchable(text: text, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
        #else
        searchable(text: text, prompt: prompt)
        #endif
    }

    func bgmCardBackground(cornerRadius: CGFloat = 18) -> some View {
        background(Color.bgmSurface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @ViewBuilder
    func bgmLargeNavigationTitle(_ title: String) -> some View {
        #if os(iOS)
        navigationTitle(title).navigationBarTitleDisplayMode(.large)
        #else
        navigationTitle(title)
        #endif
    }

    @ViewBuilder
    func bgmNavigationTitle(_ title: String) -> some View {
        #if os(iOS)
        navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        #else
        navigationTitle(title)
        #endif
    }
}

struct FilterSheet<Content: View>: View {
    let title: String
    var canReset: Bool
    let reset: () -> Void
    var accessory: AnyView?
    let content: Content
    @Environment(\.dismiss) private var dismiss

    init(_ title: String, canReset: Bool = true, reset: @escaping () -> Void,
         accessory: AnyView? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.canReset = canReset
        self.reset = reset
        self.accessory = accessory
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.title3.weight(.semibold))
                Spacer()
                accessory
            }
            .padding(20)
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Divider()
            HStack {
                Button("重置筛选", action: reset)
                    .disabled(!canReset)
                    .accessibilityIdentifier("filter-reset")
                Spacer()
                Button("完成") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("filters-done")
            }
            .padding(16)
        }
        .background(Color.bgmCanvas)
        #if os(macOS)
        .onExitCommand { dismiss() }
        #endif
    }
}

struct YearPickerButton<Label: View>: View {
    @Binding var selection: Int?
    let earliestYear: Int
    let label: Label
    @State private var isPresented = false

    init(selection: Binding<Int?>, earliestYear: Int = 1900, @ViewBuilder label: () -> Label) {
        _selection = selection
        self.earliestYear = earliestYear
        self.label = label()
    }

    private var years: [Int] {
        Array((earliestYear...Calendar.current.component(.year, from: Date())).reversed())
    }

    var body: some View {
        Button { isPresented = true } label: { label }
            .buttonStyle(.plain)
            .accessibilityLabel("年份：\(selection.map(String.init) ?? "全部年份")")
            .accessibilityIdentifier("year-picker")
            .popover(isPresented: $isPresented, arrowEdge: .top) {
                VStack(spacing: 4) {
                    option(nil)
                    Divider()
                    ScrollViewReader { proxy in
                        ScrollView(.vertical) {
                            LazyVStack(spacing: 2) {
                                ForEach(years, id: \.self) { year in
                                    option(year).id(year)
                                }
                            }
                        }
                        .scrollIndicators(.visible)
                        .accessibilityLabel("年份列表")
                        .accessibilityIdentifier("year-list")
                        .onAppear {
                            if let selection { proxy.scrollTo(selection, anchor: .center) }
                        }
                    }
                }
                .padding(8)
                #if os(macOS)
                .frame(width: 180, height: 320)
                #else
                .frame(width: 210, height: 360)
                #endif
                .foregroundStyle(.primary)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("year-options")
                .presentationCompactAdaptation(.popover)
            }
    }

    private func option(_ year: Int?) -> some View {
        Button {
            selection = year
            isPresented = false
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .frame(width: 16)
                    .opacity(selection == year ? 1 : 0)
                Text(year.map(String.init) ?? "全部年份")
                    .font(.subheadline)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            #if os(macOS)
            .frame(minHeight: 32)
            #else
            .frame(minHeight: 44)
            #endif
            .background(selection == year ? Color.bgmSecondary : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(year.map(String.init) ?? "全部年份")
        .accessibilityIdentifier("year-option-\(year.map(String.init) ?? "all")")
        .accessibilityAddTraits(selection == year ? .isSelected : [])
    }
}

struct TextTabs<Value: Hashable>: View {
    let values: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    var horizontalPadding: CGFloat = 14
    var usesUnderline = false
    var itemSpacing: CGFloat = 2
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionAnimation

    private var controlHeight: CGFloat {
        #if os(macOS)
        32
        #else
        usesUnderline ? 44 : 40
        #endif
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            tabs
            ScrollView(.horizontal, showsIndicators: false) { tabs.fixedSize(horizontal: true, vertical: false) }
        }
    }

    private var tabs: some View {
        HStack(spacing: itemSpacing) {
            ForEach(values, id: \.self) { value in
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                        selection = value
                    }
                } label: {
                    Text(title(value))
                        .font(.subheadline.weight(selection == value ? .semibold : .regular))
                        .foregroundStyle(selection == value ? (usesUnderline ? Color.brandPink : Color.primary) : Color.secondary)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, horizontalPadding)
                        .frame(minHeight: controlHeight)
                        .background {
                            if selection == value && !usesUnderline {
                                Capsule().fill(Color.primary.opacity(0.07))
                                    .matchedGeometryEffect(id: "selection", in: selectionAnimation)
                            }
                        }
                        .overlay(alignment: .bottom) {
                            if selection == value && usesUnderline {
                                Capsule().fill(Color.brandPink)
                                    .frame(width: 20, height: 2)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
    }
}

struct PaginationFooter: View {
    let offset: Int
    let isLoading: Bool
    let error: String?
    var retry: (() async -> Void)? = nil
    let load: () async -> Void
    @State private var isVisible = false

    var body: some View {
        VStack(spacing: 8) {
            if let error {
                Text(error).font(.caption).foregroundStyle(.secondary)
                Button("重试") { Task { await (retry ?? load)() } }
            } else if isLoading {
                ProgressView()
            } else {
                Color.clear.frame(height: 1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.vertical, 12)
        .onScrollVisibilityChange(threshold: 0.1) { isVisible = $0 }
        .task(id: "\(offset)-\(isVisible)") {
            guard isVisible, error == nil else { return }
            await load()
        }
    }
}

extension View {
    func bgmWebFallback(_ url: URL) -> some View {
        toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("更多", systemImage: "ellipsis") {
                    Link("在 Safari 中打开", destination: url)
                }
            }
        }
    }
}

/// A compact, non-blocking retry row shown when cached content is still on
/// screen but a user-initiated or background refresh failed.
struct RefreshFailureNotice: View {
    let message: String
    var action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button("重试", action: action)
                .font(.system(size: 11.5, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(Color.brandPink)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
