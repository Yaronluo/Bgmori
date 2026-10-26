import SwiftUI

/// A continuous Discover shelf with a soft artwork backdrop and circular paging.
struct DiscoverHero: View {
    let subjects: [Subject]
    let seasonLabel: String
    @Binding var selection: Int?
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var scrollPhase: ScrollPhase = .idle
    @State private var visiblePage: Int?

    private var selectedIndex: Int {
        guard let selection,
              let index = subjects.firstIndex(where: { $0.id == selection }) else { return 0 }
        return index
    }

    // Duplicate only the two boundary pages. Once a swipe settles on a copy,
    // move to its identical original without animation to allow the next swipe.
    private var pages: [Int] {
        guard !subjects.isEmpty else { return [] }
        return subjects.count > 1 ? Array(-1...subjects.count) : [0]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 0) {
                    ForEach(pages, id: \.self) { page in
                        let index = subjectIndex(for: page)
                        let subject = subjects[index]
                        NavigationLink(value: Route.subject(subject.id)) {
                            HeroSubjectCard(subject: subject, seasonLabel: seasonLabel)
                        }
                        .buttonStyle(.plain)
                        .containerRelativeFrame(.horizontal)
                        .id(page)
                        .accessibilityLabel("\(subject.displayTitle)，第 \(index + 1) 部，共 \(subjects.count) 部")
                        .accessibilityIdentifier("home-hot-page-\(page)")
                    }
                }
                .scrollTargetLayout()
            }
            .frame(height: DiscoverHeroMetrics.height(for: dynamicTypeSize))
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $visiblePage)
            .onScrollPhaseChange { _, phase in
                scrollPhase = phase
                if phase == .idle { recenterIfNeeded() }
            }
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
            guard let page, !subjects.isEmpty else { return }
            selection = subjects[subjectIndex(for: page)].id
        }
    }

    private var autoAdvanceKey: String {
        "\(isActive)-\(visiblePage ?? 0)-\(subjects.map(\.id))-\(scenePhase)-\(scrollPhase)-\(reduceMotion)-\(voiceOverEnabled)"
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
        (page + subjects.count) % subjects.count
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
                visiblePage = page
            }
        }
    }

    private func recenterIfNeeded() {
        guard let page = visiblePage, !subjects.isEmpty,
              !subjects.indices.contains(page) else { return }
        jump(to: subjectIndex(for: page))
    }

    private func jump(to page: Int) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            visiblePage = page
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
    let subject: Subject
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
            CachedAsyncImage(url: subject.heroURL, maxPixel: 900, contentMode: .fit, placeholderTint: tint, showsPlaceholderIcon: false)
                .mask { posterEdgeFade }
                .frame(width: 180, height: 254)

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
                    HStack(spacing: 6) {
                        ForEach(heroTags) { tag in
                            Text(tag.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Color.primary.opacity(0.05), in: Capsule())
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("标签：\(heroTags.map(\.name).joined(separator: "，"))")
                }
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(26)
        .frame(height: DiscoverHeroMetrics.height(for: dynamicTypeSize))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { artworkBackdrop }
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
                        showsPlaceholderIcon: false
                    )
                    .mask { posterEdgeFade }
                    .frame(width: (geometry.size.width - 48) * 0.48, height: coverHeight)

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
            .padding(16)
        }
        .frame(height: DiscoverHeroMetrics.height(for: dynamicTypeSize))
        .background { artworkBackdrop }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var artworkBackdrop: some View {
        GeometryReader { geometry in
            CachedAsyncImage(url: subject.heroURL, maxPixel: 400, placeholderTint: tint, showsPlaceholderIcon: false)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .blur(radius: 36)
                .opacity(0.18)
                .mask {
                    LinearGradient(
                        stops: [.init(color: .clear, location: 0), .init(color: .white, location: 0.18),
                                .init(color: .white, location: 0.62), .init(color: .clear, location: 1)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .mask {
                        LinearGradient(
                            stops: [.init(color: .clear, location: 0), .init(color: .white, location: 0.12),
                                    .init(color: .white, location: 0.55), .init(color: .clear, location: 1)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    }
                }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var posterEdgeFade: some View {
        LinearGradient(
            stops: [.init(color: .clear, location: 0), .init(color: .white, location: 0.035),
                    .init(color: .white, location: 0.965), .init(color: .clear, location: 1)],
            startPoint: .leading, endPoint: .trailing
        )
        .mask {
            LinearGradient(
                stops: [.init(color: .clear, location: 0), .init(color: .white, location: 0.025),
                        .init(color: .white, location: 0.975), .init(color: .clear, location: 1)],
                startPoint: .top, endPoint: .bottom
            )
        }
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
