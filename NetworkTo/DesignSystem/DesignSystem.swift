import SwiftUI
import UIKit

enum NTColor {
    static let background = dynamic(light: 0xF8F4EE, dark: 0x171815)
    static let surface = dynamic(light: 0xFFFDF9, dark: 0x20211D)
    static let surfaceSecondary = dynamic(light: 0xEEE8DF, dark: 0x292A25)
    static let textPrimary = dynamic(light: 0x292821, dark: 0xF5F0E8)
    static let textSecondary = dynamic(light: 0x66665E, dark: 0xBBB8AF)
    static let separator = dynamic(light: 0xE4DBD0, dark: 0x3A3B35)
    static let accent = dynamic(light: 0x526B57, dark: 0xB7CEB9)
    static let accentStrong = dynamic(light: 0x354C3D, dark: 0xBFD3C1)
    static let meeting = dynamic(light: 0xBD7053, dark: 0xDC967A)
    static let success = dynamic(light: 0x2E7350, dark: 0x6BC18F)
    static let warning = dynamic(light: 0x8A641D, dark: 0xE0B55C)
    static let destructive = dynamic(light: 0xB42332, dark: 0xFF7A88)

    /// Company marks sit on the same opaque light neutral tile in both appearances so icons
    /// drawn for light backgrounds stay visible in dark appearance (glyph on backing 8.1:1).
    static let companyMarkBackingUIColor = UIColor(hex: 0xF3EEE6)
    static let companyMarkGlyphUIColor = UIColor(hex: 0x354C3D)
    static let companyMarkBacking = Color(uiColor: companyMarkBackingUIColor)
    static let companyMarkGlyph = Color(uiColor: companyMarkGlyphUIColor)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum NTSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 40
}

enum NTRadius {
    static let control: CGFloat = 12
    static let field: CGFloat = 16
    static let context: CGFloat = 18
    static let card: CGFloat = 20
    static let hero: CGFloat = 28
}

struct NTPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(NTColor.background)
            .background(isEnabled ? NTColor.accentStrong : NTColor.separator)
            .clipShape(RoundedRectangle(cornerRadius: NTRadius.field, style: .continuous))
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.992 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct NTSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(NTColor.textPrimary)
            .background(NTColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: NTRadius.field, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: NTRadius.field, style: .continuous)
                    .stroke(NTColor.separator.opacity(0.8), lineWidth: 0.75)
            }
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct NTSurfaceModifier: ViewModifier {
    var radius: CGFloat = NTRadius.card

    func body(content: Content) -> some View {
        content
            .background(NTColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(NTColor.separator.opacity(0.8), lineWidth: 0.75)
            }
    }
}

extension View {
    func ntSurface(radius: CGFloat = NTRadius.card) -> some View {
        modifier(NTSurfaceModifier(radius: radius))
    }

    func ntScreenBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(NTColor.background.ignoresSafeArea())
            .foregroundStyle(NTColor.textPrimary)
    }
}

struct NTPillFlow: Layout {
    var spacing: CGFloat = NTSpacing.xs

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? .infinity
        var cursor = CGPoint.zero
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursor.x > 0, cursor.x + size.width > width {
                cursor.x = 0
                cursor.y += lineHeight + spacing
                lineHeight = 0
            }
            cursor.x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: width.isFinite ? width : cursor.x, height: cursor.y + lineHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var cursor = CGPoint(x: bounds.minX, y: bounds.minY)
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursor.x > bounds.minX, cursor.x + size.width > bounds.maxX {
                cursor.x = bounds.minX
                cursor.y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: cursor, proposal: ProposedViewSize(size))
            cursor.x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
