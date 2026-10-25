import SwiftUI

struct CachedAsyncImage: View {
    let url: URL?
    var maxPixel: Int = 400
    var contentMode: ContentMode = .fill
    var placeholderTint: Color = .bgmSecondary

    @State private var image: SendableImage?

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image.cgImage, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                LinearGradient(
                    colors: [placeholderTint.opacity(0.55), placeholderTint.opacity(0.22)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: "photo")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .clipped()
        .task(id: "\(url?.absoluteString ?? "")-\(Int(maxPixel))") {
            image = nil
            guard let url else { return }
            image = await ImageLoader.shared.image(for: url, maxPixel: maxPixel)
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
    var width: CGFloat = 132

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                CachedAsyncImage(url: coverURL, maxPixel: Int(ceil(width * 1.42 * displayScale)), placeholderTint: tint)
                    .frame(width: width, height: width * 1.42)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        if let badge {
                            Text(badge)
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(.black.opacity(0.45), in: Capsule())
                                .foregroundStyle(.white)
                                .padding(8)
                        }
                    }

                if let progress, progress > 0 {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(7)
                }
            }

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
                .frame(width: width, alignment: .leading)

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: width, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
    }
}

struct SubjectCard: View {
    let subject: Subject
    var width: CGFloat = 132

    var body: some View {
        let detail = subject.episodeCountText
        return CoverCard(
            title: subject.displayTitle,
            subtitle: detail.isEmpty || detail == subject.typeName ? subject.typeName : "\(subject.typeName) · \(detail)",
            coverURL: subject.coverURL,
            badge: subject.rating.map { String(format: "%.1f", $0.score) },
            tint: .subjectTint(subject.type),
            width: width
        )
    }
}

struct SubjectSummaryCard: View {
    let subject: SubjectSummary
    var progress: Double? = nil
    var badge: String? = nil
    var width: CGFloat = 132

    var body: some View {
        CoverCard(
            title: subject.displayTitle,
            subtitle: "\(SubjectType.title(for: subject.type)) · \(subject.ratingText)",
            coverURL: subject.coverURL,
            badge: badge,
            progress: progress,
            tint: .subjectTint(subject.type),
            width: width
        )
    }
}

struct AiringCard: View {
    let subject: LegacySubject
    var isWatching = false
    var width: CGFloat = 120

    var body: some View {
        CoverCard(
            title: subject.displayTitle,
            subtitle: isWatching ? "在看" : "今日更新",
            coverURL: subject.coverURL,
            badge: subject.rating.map { String(format: "%.1f", $0.score) },
            tint: .subjectTint(subject.type),
            width: width
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
                    .lineLimit(2)
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
            Text(message)
        } actions: {
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
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
        .glassEffect(.regular, in: Capsule())
        .padding(.horizontal, 20)
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
