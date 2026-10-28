import SwiftUI

// MARK: - Surfaces & headers

extension View {
    /// Shared surface for the profile dashboard. It stays flat on purpose:
    /// the page already has a tinted hero and colourful data marks.
    func profileCard(cornerRadius: CGFloat = 20) -> some View {
        self
            .background(Color.bgmSurface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.055))
            }
    }
}

struct ProfileSectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 3) {
                        Text(actionTitle)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.brandPink)
                    .frame(minHeight: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Hero

struct ProfileStatTile: View {
    let value: String?
    let title: String
    var tint: Color = .brandPink

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value ?? "—")
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack(spacing: 5) {
                Circle()
                    .fill(tint)
                    .frame(width: 5, height: 5)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)：\(value ?? "未加载")")
    }
}

struct FriendAvatarStack: View {
    let urls: [URL?]
    var size: CGFloat = 24

    var body: some View {
        HStack(spacing: -8) {
            ForEach(Array(urls.prefix(3).enumerated()), id: \.offset) { _, url in
                AvatarView(url: url, size: size)
                    .overlay {
                        Circle().strokeBorder(Color.bgmSurface, lineWidth: 2)
                    }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Dashboard tiles

struct ProfileDestinationRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var tint: Color = .brandPink
    var accessory: AnyView? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 6)
            if let accessory { accessory }
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Rectangle().fill(Color.bgmMuted.opacity(0.18)).frame(height: 0.5) }
    }
}

// MARK: - Ratings

struct RatingDistributionBars: View {
    /// Scores 1...10 in order.
    let counts: [Int]
    var height: CGFloat = 42
    var tint: Color = .brandPink

    private var maxCount: Int { max(counts.max() ?? 0, 1) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<10, id: \.self) { index in
                let count = index < counts.count ? counts[index] : 0
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(tint.opacity(index >= 7 ? 0.82 : 0.26))
                        .frame(height: max(3, CGFloat(count) / CGFloat(maxCount) * height))
                    Text("\(index + 1)")
                        .font(.system(size: 7, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height + 14, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("评分分布")
    }
}
