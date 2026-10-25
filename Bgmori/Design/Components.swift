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
    let title: String
    var subtitle: String? = nil
    let coverURL: URL?
    var badge: String? = nil
    var progress: Double? = nil
    var tint: Color = .brandPink
    var width: CGFloat = 132

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                CachedAsyncImage(url: coverURL, maxPixel: Int(width * 2.6), placeholderTint: tint)
                    .frame(width: width, height: width * 1.36)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        if let badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .bold))
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
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: width, alignment: .leading)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
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
                .frame(width: 52, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
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
        Button {
            action?()
        } label: {
            HStack(spacing: 4) {
                Text(name)
                    .font(.system(size: 12, weight: .medium))
                if let count {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(isSelected ? Color.brandPink : Color.bgmSecondary.opacity(0.8), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
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
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.brandPink)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(actionTitle, action: action)
                .buttonStyle(.glassProminent)
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
        CachedAsyncImage(url: url, maxPixel: Int(size * 3), placeholderTint: .brandPink)
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 1))
    }
}

extension View {
    func bgmCardBackground(cornerRadius: CGFloat = 18) -> some View {
        background(Color.bgmSurface.opacity(0.75), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
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
