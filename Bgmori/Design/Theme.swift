import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

extension Color {
    static let brandPink = Color(red: 0.941, green: 0.569, blue: 0.600)
    static let brandPinkSoft = Color(red: 0.980, green: 0.741, blue: 0.757)
    static var bgmBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    static var bgmSurface: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    static var bgmSecondary: Color {
        Color.primary.opacity(0.07)
    }

    static var bgmInk: Color { .primary }
    static var bgmMuted: Color { .secondary }

    static func subjectTint(_ type: Int) -> Color {
        switch type {
        case 1: Color(red: 0.77, green: 0.55, blue: 0.29)
        case 2: Color(red: 0.89, green: 0.42, blue: 0.54)
        case 3: Color(red: 0.42, green: 0.48, blue: 0.85)
        case 4: Color(red: 0.31, green: 0.68, blue: 0.49)
        case 6: Color(red: 0.48, green: 0.54, blue: 0.60)
        default: .brandPink
        }
    }

    static func collectionTint(_ type: Int) -> Color {
        switch type {
        case 1: Color(red: 0.36, green: 0.55, blue: 0.94)
        case 2: Color(red: 0.20, green: 0.66, blue: 0.33)
        case 3: .brandPink
        case 4: Color(red: 0.96, green: 0.65, blue: 0.14)
        case 5: Color(red: 0.60, green: 0.63, blue: 0.65)
        default: .brandPink
        }
    }
}

extension Font {
    static let bgmTitle = Font.system(size: 28, weight: .bold, design: .default)
    static let bgmSection = Font.system(size: 20, weight: .bold, design: .default)
    static let bgmBody = Font.system(size: 16, weight: .regular, design: .default)
    static let bgmCaption = Font.system(size: 12, weight: .medium, design: .default)
    static let bgmNumber = Font.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit()
}

struct GlassSurface<Content: View>: View {
    var shape: AnyShape
    var content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(shape: AnyShape = AnyShape(RoundedRectangle(cornerRadius: 22, style: .continuous)), @ViewBuilder content: () -> Content) {
        self.shape = shape
        self.content = content()
    }

    var body: some View {
        if reduceTransparency {
            content
                .background(Color.bgmSurface, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 1))
        } else {
            content.glassEffect(.regular, in: shape)
        }
    }
}

struct GlassPill: View {
    let title: String
    let icon: String
    var tint: Color = .brandPink
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
        }
        .buttonStyle(.glass)
        .tint(tint)
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.bgmSection)
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.bgmCaption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 14, weight: .medium))
            }
        }
        .padding(.horizontal, 20)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.glassProminent)
                    .tint(.brandPink)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
    }
}

struct RatingStars: View {
    let score: Double
    var size: CGFloat = 12

    var body: some View {
        let value = score / 2
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: starName(index: index, value: value))
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(Color(red: 0.96, green: 0.70, blue: 0.16))
            }
        }
    }

    private func starName(index: Int, value: Double) -> String {
        let filled = value - Double(index)
        if filled >= 0.75 { return "star.fill" }
        if filled >= 0.25 { return "star.leadinghalf.filled" }
        return "star"
    }
}

struct ScoreBadge: View {
    let score: Double?
    var total: Int? = nil

    var body: some View {
        VStack(spacing: 2) {
            Text(score.map { String(format: "%.1f", $0) } ?? "—")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(total.map { "\($0) 人" } ?? "评分")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(width: 54, height: 54)
        .background(Color.bgmSecondary.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
