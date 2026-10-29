import SwiftUI

/// A continuous Discover shelf with crisp posters and circular paging.
struct DiscoverHero: View {
    let subjects: [HomeRefreshItem<Subject>]
    let seasonLabel: String
    @Binding var selection: Int?
    let isActive: Bool
    var onScrollPhaseChange: (ScrollPhase) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var scrollPhase: ScrollPhase = .idle
    @State private var visiblePage: String?
    #if os(macOS)
    @State private var scrollMetrics = ScrollMetrics()

    private struct ScrollMetrics: Equatable {
        var offset: CGFloat = 0
        var width: CGFloat = 0
    }
    #endif

    private struct Page: Identifiable {
        let position: Int
        let subject: HomeRefreshItem<Subject>
        let copy: Int
        var id: String { "\(subject.id)-\(copy)" }
    }

    private var selectedIndex: Int {
        guard let selection,
              let index = subjects.firstIndex(where: { $0.id == selection }) else { return 0 }
        return index
    }

    // Keep a full copy on either side so trackpad momentum has room to settle.
    // Recenter after both the phase and the visible target have reached idle.
    private var pages: [Page] {
        guard !subjects.isEmpty else { return [] }
        let copies = subjects.count > 1 ? Array(-1...1) : [0]
        return copies.flatMap { copy in
            subjects.indices.map { index in
                Page(position: copy * subjects.count + index, subject: subjects[index], copy: copy)
            }
        }
    }

    var body: some View {
        #if os(macOS)
        ScrollViewReader { proxy in
            content
                .task(id: "\(scrollMetrics)-\(scrollPhase)") {
                    guard scrollPhase == .idle else { return }
                    // Mouse wheels can deliver unphased events: macOS never enters
                    // decelerating and native paging leaves a partially visible card.
                    do { try await Task.sleep(for: .milliseconds(160)) }
                    catch { return }
                    guard !Task.isCancelled, scrollPhase == .idle else { return }
                    settleMacScroll(using: proxy)
                }
        }
        #else
        content
            .task(id: "\(visiblePage ?? "")-\(scrollPhase)") {
                guard scrollPhase == .idle else { return }
                // SwiftUI can publish the final target after the idle callback.
                await Task.yield()
                guard !Task.isCancelled, scrollPhase == .idle else { return }
                recenterIfNeeded()
            }
        #endif
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 0) {
                    ForEach(pages) { page in
                        let index = subjectIndex(for: page.position)
                        let subject = page.subject
                        NavigationLink(value: Route.subject(subject.id)) {
                            HeroSubjectCard(content: subject, seasonLabel: seasonLabel)
                        }
                        .buttonStyle(.plain)
                        .containerRelativeFrame(.horizontal)
                        .id(page.id)
                        .accessibilityLabel("\(subject.value.displayTitle)，第 \(index + 1) 部，共 \(subjects.count) 部")
                        .accessibilityIdentifier("home-hot-page-\(page.position)")
                    }
                }
                .scrollTargetLayout()
            }
            .frame(height: DiscoverHeroMetrics.height(for: dynamicTypeSize))
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $visiblePage)
            .accessibilityIdentifier("home-hot-carousel")
            .onScrollPhaseChange { _, phase in
                scrollPhase = phase
                onScrollPhaseChange(phase)
            }
            #if os(macOS)
            .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
                ScrollMetrics(offset: geometry.contentOffset.x + geometry.contentInsets.leading,
                              width: geometry.containerSize.width)
            } action: { _, metrics in
                scrollMetrics = metrics
            }
            #endif
            .padding(.horizontal, 20)

            if subjects.count > 1 {
                pager
            }
        }
        .task(id: autoAdvanceKey) {
            guard isActive, subjects.count > 1, scenePhase == .active,
                  scrollPhase == .idle, !reduceMotion, !voiceOverEnabled else { return }
            do {
                try await Task.sleep(for: .seconds(6))
            } catch {
                return
            }
            guard !Task.isCancelled, isActive else { return }
            advance(by: 1)
        }
        .onChange(of: subjects.map(\.id), initial: true) { _, ids in
            guard !ids.isEmpty else {
                selection = nil
                visiblePage = nil
                return
            }
            let index = selection.flatMap { ids.firstIndex(of: $0) } ?? 0
            selection = ids[index]
            jump(to: index)
        }
        .onChange(of: visiblePage) { _, page in
            guard let page = pages.first(where: { $0.id == page }) else { return }
            selection = page.subject.id
        }
    }

    private var autoAdvanceKey: String {
        "\(isActive)-\(visiblePage ?? "")-\(subjects.map(\.id))-\(scenePhase)-\(scrollPhase)-\(reduceMotion)-\(voiceOverEnabled)"
    }

    private var pager: some View {
        HStack(spacing: 0) {
            ForEach(subjects.indices, id: \.self) { index in
                Button {
                    select(page: index)
                } label: {
                    Capsule()
                        .fill(index == selectedIndex ? Color.brandPink : Color.primary.opacity(0.16))
                        .frame(width: index == selectedIndex ? 16 : 6, height: 6)
                        .frame(width: 20, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("第 \(index + 1) 部，共 \(subjects.count) 部")
                .accessibilityIdentifier("home-hot-dot-\(index)")
                .accessibilityAddTraits(index == selectedIndex ? .isSelected : [])
            }
        }
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("热播作品分页")
        .accessibilityAction(named: Text("上一部")) { advance(by: -1) }
        .accessibilityAction(named: Text("下一部")) { advance(by: 1) }
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: selectedIndex)
    }

    private func subjectIndex(for page: Int) -> Int {
        ((page % subjects.count) + subjects.count) % subjects.count
    }

    private func advance(by delta: Int) {
        guard subjects.count > 1 else { return }
        select(page: selectedIndex + delta)
    }

    private func select(page: Int) {
        guard !subjects.isEmpty else { return }
        if reduceMotion {
            jump(to: subjectIndex(for: page))
        } else {
            withAnimation(.snappy(duration: 0.32)) {
                visiblePage = pages.first(where: { $0.position == page })?.id
            }
        }
    }

    private func recenterIfNeeded() {
        guard let page = pages.first(where: { $0.id == visiblePage }),
              page.copy != 0 else { return }
        jump(to: subjectIndex(for: page.position))
    }

    #if os(macOS)
    private func settleMacScroll(using proxy: ScrollViewProxy) {
        guard scrollMetrics.width > 0, !pages.isEmpty else { return }
        let slot = max(0, min(pages.count - 1, Int((scrollMetrics.offset / scrollMetrics.width).rounded())))
        let page = pages[slot]
        let distance = abs(scrollMetrics.offset - CGFloat(slot) * scrollMetrics.width)
        if distance > 1 {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
                proxy.scrollTo(page.id, anchor: .leading)
            }
        } else if page.copy != 0,
                  let original = pages.first(where: { $0.position == subjectIndex(for: page.position) }) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                proxy.scrollTo(original.id, anchor: .leading)
            }
        }
    }
    #endif

    private func jump(to page: Int) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            visiblePage = pages.first(where: { $0.position == page })?.id
        }
    }
}

private enum DiscoverHeroMetrics {
    static func height(for size: DynamicTypeSize) -> CGFloat {
        if size.isAccessibilitySize { return 440 }
        #if os(macOS)
        return 306
        #else
        return 326
        #endif
    }
}

private struct HeroSubjectCard: View {
    let content: HomeRefreshItem<Subject>
    private var subject: Subject { content.value }
    let seasonLabel: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var title: String { subject.displayTitle }
    private var summary: String { subject.summary.trimmed }
    private var score: Double? {
        guard let rating = subject.rating, rating.total > 0 else { return nil }
        return rating.score
    }
    private var doing: Int { subject.collection?.doing ?? 0 }
    private var tint: Color { .subjectTint(subject.type) }

    private var heroTags: [Tag] {
        Array(subject.tags.filter { tag in
            !(tag.name.contains("年") && tag.name.contains("月")) && tag.name != (subject.platform ?? "")
        }.prefix(3))
    }

    private var subjectDateLabel: String {
        guard let date = subject.date, date.count >= 7,
              let month = Int(date.dropFirst(5).prefix(2)) else { return seasonLabel }
        return "\(date.prefix(4)) 年 \(month) 月"
    }

    var body: some View {
        #if os(macOS)
        macOSContent
        #else
        iOSContent
        #endif
    }

    private var macOSContent: some View {
        HStack(alignment: .center, spacing: 30) {
            CachedAsyncImage(url: subject.heroURL, maxPixel: 900, contentMode: .fit, placeholderTint: tint, showsPlaceholderIcon: false, imageIdentity: "subject-\(subject.id)", animatesChanges: false)
                .frame(width: 180, height: 254)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 11) {
                Text(subjectDateLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(.system(.title, weight: .bold))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)

                metaRow(foreground: .secondary)

                if !summary.isEmpty {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 3)
                        .truncationMode(.tail)
                        .frame(maxWidth: 650, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !heroTags.isEmpty {
                    Text(heroTags.map(\.name).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityLabel("标签：\(heroTags.map(\.name).joined(separator: "，"))")
                }
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 6)
        .frame(height: DiscoverHeroMetrics.height(for: dynamicTypeSize))
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var iOSContent: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 16) {
                    CachedAsyncImage(
                        url: subject.heroURL,
                        maxPixel: 1000,
                        contentMode: .fit,
                        placeholderTint: tint,
                        showsPlaceholderIcon: false,
                        imageIdentity: "subject-\(subject.id)",
                        animatesChanges: false
                    )
                    .frame(width: (geometry.size.width - 48) * 0.48, height: coverHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 12) {
                        Text(subjectDateLabel)
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Text(title)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 5)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 12) {
                            if let score {
                                Text(String(format: "%.1f", score))
                                    .fontWeight(.semibold)
                                    .monospacedDigit()
                                    .foregroundStyle(Color.brandPink)
                                    .accessibilityLabel("评分 \(String(format: "%.1f", score))")
                            }
                            Text(subject.episodeCountText)
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)

                        if doing > 0 {
                            Text("\(compactCount(doing))人在看")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: coverHeight)

                if !summary.isEmpty, !dynamicTypeSize.isAccessibilitySize {
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 4)
        }
        .frame(height: DiscoverHeroMetrics.height(for: dynamicTypeSize))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var coverHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 408 : 224
    }

    private func metaRow(foreground: Color) -> some View {
        HStack(spacing: 12) {
            if let score {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(red: 1, green: 0.79, blue: 0.32))
                    Text(String(format: "%.1f", score))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
            }
            if doing > 0 {
                Text("\(compactCount(doing))人在看")
            }
            Text(subject.episodeCountText)
        }
        .font(.subheadline)
        .foregroundStyle(foreground)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }

    private func compactCount(_ value: Int) -> String {
        guard value >= 10_000 else { return "\(value)" }
        return String(format: "%.1f万", Double(value) / 10_000)
    }
}
