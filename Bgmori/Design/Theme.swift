import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

extension Color {
    static var brandPink: Color {
        #if os(iOS)
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 1, green: 0.53, blue: 0.64, alpha: 1)
                : UIColor(red: 0.78, green: 0.20, blue: 0.37, alpha: 1)
        })
        #else
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 1, green: 0.53, blue: 0.64, alpha: 1)
                : NSColor(red: 0.78, green: 0.20, blue: 0.37, alpha: 1)
        })
        #endif
    }
    static let brandPinkSoft = Color(red: 0.980, green: 0.741, blue: 0.757)
    static var bgmCanvas: Color {
        #if os(iOS)
        Color(uiColor: .systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }
    static let bgmArtworkScrim = Color.black
    static let bgmOnArtwork = Color.white
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

    /// Grouped page canvas: the surface cards sit on this color.
    static var bgmGroupedBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .underPageBackgroundColor)
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
    static let bgmTitle = Font.system(.largeTitle, weight: .bold)
    static let bgmSection = Font.system(.title2, weight: .bold)
    static let bgmBody = Font.body
    static let bgmCaption = Font.subheadline
    static let bgmNumber = Font.system(.headline, design: .rounded).monospacedDigit()
}

struct GlassSurface<Content: View>: View {
    var shape: AnyShape
    var content: Content
    var interactive: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(shape: AnyShape = AnyShape(RoundedRectangle(cornerRadius: 22, style: .continuous)), interactive: Bool = false, @ViewBuilder content: () -> Content) {
        self.shape = shape
        self.interactive = interactive
        self.content = content()
    }

    var body: some View {
        if reduceTransparency {
            content
                .background(Color.bgmSurface, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 1))
        } else {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        }
    }
}

extension View {
    func bgmShortcutLabel() -> some View {
        self
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 14)
            #if os(macOS)
            .frame(minHeight: 36)
            #else
            .frame(minHeight: 44)
            #endif
            .contentShape(Capsule())
    }

    /// Apply once to the floating control group; its children keep plain button styles.
    func bgmFloatingGlass(cornerRadius: CGFloat = 26, shadowRadius: CGFloat = 14) -> some View {
        GlassSurface(shape: AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)), interactive: true) {
            self
        }
        .shadow(color: .bgmArtworkScrim.opacity(shadowRadius < 14 ? 0.04 : 0.08), radius: shadowRadius, y: 3)
    }

    func bgmFloatingControlMargins(maxWidth: CGFloat = 1120) -> some View {
        self
            .frame(maxWidth: maxWidth)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
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
            VStack(alignment: .leading, spacing: 4) {
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
                Button(action: action) {
                    HStack(spacing: 4) {
                        Text(actionTitle)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                    }
                    .font(.subheadline)
                    #if os(iOS)
                    .frame(minHeight: 44)
                    #endif
                }
                #if os(macOS)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                #endif
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
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            if !message.isEmpty { Text(message) }
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.glassProminent)
                    .foregroundStyle(Color.bgmCanvas)
                    .tint(.brandPink)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
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

// Desktop pages keep a readable measure as the window grows.
extension View {
    @ViewBuilder
    func bgmDesktopContent(maxWidth: CGFloat = 1120) -> some View {
        #if os(macOS)
        self.frame(maxWidth: maxWidth)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .top)
        #else
        self
        #endif
    }
}

#if os(macOS)
struct DesktopPanel<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgmSurface, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.06))
        }
    }
}
#endif
