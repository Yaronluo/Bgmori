import SwiftUI

/// The editorial first shelf on Discover: one large subject at a time with
/// swipe/trackpad paging, arrow controls, and a compact page indicator.
struct DiscoverHero: View {
    let subjects: [Subject]
    let seasonLabel: String
    @Binding var selection: Int?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var selectedIndex: Int {
        guard let selection,
              let index = subjects.firstIndex(where: { $0.id == selection }) else { return 0 }
        return index
    }

    private var cardHeight: CGFloat {
        DiscoverHeroMetrics.height(for: dynamicTypeSize)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 0) {
                    ForEach(Array(subjects.enumerated()), id: \.element.id) { index, subject in
                        NavigationLink(value: Route.subject(subject.id)) {
                            HeroSubjectCard(
                                subject: subject,
                                index: index,
                                count: subjects.count,
                                seasonLabel: seasonLabel
                            )
                        }
                        .buttonStyle(.plain)
                        .containerRelativeFrame(.horizontal)
                        .id(subject.id)
                        .accessibilityLabel(accessibilityLabel(for: subject, index: index))
                    }
                }
                .scrollTargetLayout()
            }
            .frame(height: cardHeight)
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $selection)
            .padding(.horizontal, 20)

            if subjects.count > 1 {
                pager
            }
        }
        .onChange(of: subjects.map(\.id), initial: true) { _, ids in
            if let selection, ids.contains(selection) { return }
            selection = ids.first
        }
    }

    private var pager: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(subjects.indices, id: \.self) { index in
                    Button {
                        select(index)
                    } label: {
                        Capsule()
                            .fill(index == selectedIndex ? Color.brandPink : Color.primary.opacity(0.16))
                            .frame(width: index == selectedIndex ? 16 : 6, height: 6)
                            .frame(width: 16, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("第 \(index + 1) 部，共 \(subjects.count) 部")
                    .accessibilityAddTraits(index == selectedIndex ? .isSelected : [])
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("热播作品分页")

            Spacer(minLength: 12)

            Text("\(selectedIndex + 1) / \(subjects.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("第 \(selectedIndex + 1) 部，共 \(subjects.count) 部")

            arrowButton(systemName: "chevron.left", delta: -1, label: "上一部")
                .accessibilityIdentifier("home-hot-prev")
            arrowButton(systemName: "chevron.right", delta: 1, label: "下一部")
                .accessibilityIdentifier("home-hot-next")
        }
        .padding(.horizontal, 20)
        #if os(iOS)
        .frame(height: 44)
        #else
        .frame(height: 34)
        #endif
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: selectedIndex)
    }

    private func arrowButton(systemName: String, delta: Int, label: String) -> some View {
        let target = selectedIndex + delta
        let isDisabled = !subjects.indices.contains(target)
        return Button {
            select(target)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold))
                .frame(width: arrowSize, height: arrowSize)
                .background(Color.primary.opacity(0.065), in: Circle())
                .frame(width: arrowHitSize, height: arrowHitSize)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
        .accessibilityLabel(label)
        #if os(macOS)
        .help(label)
        #endif
    }

    private var arrowSize: CGFloat {
        #if os(macOS)
        28
        #else
        31
        #endif
    }

    private var arrowHitSize: CGFloat {
        #if os(macOS)
        32
        #else
        43
        #endif
    }

    private func select(_ index: Int) {
        guard subjects.indices.contains(index) else { return }
        let id = subjects[index].id
        if reduceMotion {
            selection = id
        } else {
            withAnimation(.snappy(duration: 0.32)) {
                selection = id
            }
        }
    }

    private func accessibilityLabel(for subject: Subject, index: Int) -> String {
        "\(subject.displayTitle)，第 \(index + 1) 部，共 \(subjects.count) 部"
    }
}

private enum DiscoverHeroMetrics {
    static func height(for size: DynamicTypeSize) -> CGFloat {
        if size.isAccessibilitySize { return 440 }
        #if os(macOS)
        return 306
        #else
        return 318
        #endif
    }
}

private struct HeroSubjectCard: View {
    let subject: Subject
    let index: Int
    let count: Int
    let seasonLabel: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var title: String { subject.displayTitle }
    private var summary: String { subject.summary.trimmed }
    private var score: Double? {
        guard let rating = subject.rating, rating.total > 0 else { return nil }
        return rating.score
    }
    private var doing: Int { subject.collection?.doing ?? 0 }
    private var pageCounter: String { String(format: "%02d / %02d", index + 1, count) }
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
        macOSCard
        #else
        iOSCard
        #endif
    }

    private var macOSCard: some View {
        HStack(alignment: .center, spacing: 30) {
            CachedAsyncImage(url: subject.heroURL, maxPixel: 900, placeholderTint: tint, showsPlaceholderIcon: false)
                .frame(width: 180, height: 254)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.bgmOnArtwork.opacity(0.10), lineWidth: 0.5)
                }
                .shadow(color: Color.bgmArtworkScrim.opacity(0.16), radius: 14, y: 8)

            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 10) {
                    macBadge
                    Text(subjectDateLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Text(pageCounter)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

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

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Text("查看条目")
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.bold))
                    Spacer(minLength: 12)
                    if let rank = subject.rating?.rank, rank > 0 {
                        Text("Bangumi #\(rank)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(Color.brandPink)
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(26)
        .frame(height: DiscoverHeroMetrics.height(for: dynamicTypeSize))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                Color.bgmSurface
                LinearGradient(
                    colors: [tint.opacity(0.16), tint.opacity(0.03), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var iOSCard: some View {
        ZStack(alignment: .topLeading) {
            GeometryReader { proxy in
                CachedAsyncImage(url: subject.heroURL, maxPixel: 1200, placeholderTint: tint, showsPlaceholderIcon: false)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }

            LinearGradient(
                stops: [
                    .init(color: Color.bgmArtworkScrim.opacity(0.26), location: 0),
                    .init(color: Color.bgmArtworkScrim.opacity(0.04), location: 0.22),
                    .init(color: Color.bgmArtworkScrim.opacity(0.38), location: 0.52),
                    .init(color: Color.bgmArtworkScrim.opacity(0.82), location: 0.78),
                    .init(color: Color.bgmArtworkScrim.opacity(0.94), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    iosBadge
                    Spacer(minLength: 8)
                    Text(pageCounter)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.bgmOnArtwork.opacity(0.72))
                }

                Spacer(minLength: 0)

                Text(subjectDateLabel)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.bgmOnArtwork.opacity(0.78))

                Text(title)
                    .font(.system(.title, weight: .bold))
                    .foregroundStyle(Color.bgmOnArtwork)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)

                if !summary.isEmpty, !dynamicTypeSize.isAccessibilitySize {
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(Color.bgmOnArtwork.opacity(0.80))
                        .lineSpacing(3)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }

                metaRow(foreground: Color.bgmOnArtwork.opacity(0.82))
            }
            .padding(20)
        }
        .frame(height: DiscoverHeroMetrics.height(for: dynamicTypeSize))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.bgmOnArtwork.opacity(0.12), lineWidth: 0.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var macBadge: some View {
        Label("近期热门", systemImage: "flame.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.brandPink)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.brandPink.opacity(0.10), in: Capsule())
    }

    private var iosBadge: some View {
        Label("近期热门", systemImage: "flame.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.bgmOnArtwork)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.bgmArtworkScrim.opacity(0.42), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.bgmOnArtwork.opacity(0.16), lineWidth: 0.5))
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
