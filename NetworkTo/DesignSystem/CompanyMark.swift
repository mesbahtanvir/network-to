import SwiftUI
import UIKit

/// Draws a company mark, or the company monogram when no mark can be shown, as a square tile
/// the height of the text line it sits in. Tiles are rasterised once per size and placed
/// inline with text so "Role at [mark] Company" wraps as ordinary text on every surface.
@MainActor
enum CompanyMarkTile {
    struct Metrics {
        let side: CGFloat
        let baselineOffset: CGFloat
    }

    static let cornerProportion: CGFloat = 0.25
    private static let cache = NSCache<NSString, UIImage>()

    static func metrics(for textStyle: Font.TextStyle, dynamicTypeSize: DynamicTypeSize) -> Metrics {
        let traits = UITraitCollection(preferredContentSizeCategory: contentSizeCategory(for: dynamicTypeSize))
        let font = UIFont.preferredFont(forTextStyle: uiTextStyle(for: textStyle), compatibleWith: traits)
        return Metrics(side: ceil(font.lineHeight), baselineOffset: font.descender)
    }

    /// The inline text fragment for a mark or monogram; decorative for assistive technology.
    static func text(
        companyName: String,
        reference: CompanyMarkReference?,
        markData: Data?,
        textStyle: Font.TextStyle,
        dynamicTypeSize: DynamicTypeSize,
        displayScale: CGFloat
    ) -> Text {
        let metrics = metrics(for: textStyle, dynamicTypeSize: dynamicTypeSize)
        let tile = image(
            companyName: companyName,
            reference: reference,
            markData: markData,
            side: metrics.side,
            scale: displayScale
        )
        return Text(Image(uiImage: tile).renderingMode(.original))
            .baselineOffset(metrics.baselineOffset)
    }

    static func image(
        companyName: String,
        reference: CompanyMarkReference?,
        markData: Data?,
        side: CGFloat,
        scale: CGFloat
    ) -> UIImage {
        let monogram = CompanyMonogram.characters(for: companyName)
        let hasMark = reference != nil && markData != nil
        let key = "\(reference?.key ?? "-")|\(reference?.version ?? 0)|\(hasMark)|\(monogram)|\(side)|\(scale)" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let size = CGSize(width: side, height: side)
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let bounds = CGRect(origin: .zero, size: size)
            NTColor.companyMarkBackingUIColor.setFill()
            UIBezierPath(roundedRect: bounds, cornerRadius: side * cornerProportion).fill()
            let content = bounds.insetBy(dx: side / 8, dy: side / 8)
            if hasMark, let data = markData, let mark = UIImage(data: data), mark.size.width > 0, mark.size.height > 0 {
                let ratio = min(content.width / mark.size.width, content.height / mark.size.height)
                let drawSize = CGSize(width: mark.size.width * ratio, height: mark.size.height * ratio)
                let origin = CGPoint(x: content.midX - drawSize.width / 2, y: content.midY - drawSize.height / 2)
                mark.draw(in: CGRect(origin: origin, size: drawSize))
            } else {
                drawMonogram(monogram, in: content)
            }
        }
        cache.setObject(rendered, forKey: key)
        return rendered
    }

    private static func drawMonogram(_ monogram: String, in content: CGRect) {
        guard !monogram.isEmpty else { return }
        var pointSize = content.height * (monogram.count > 1 ? 0.6 : 0.74)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        var attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NTColor.companyMarkGlyphUIColor,
            .paragraphStyle: paragraph,
        ]
        var textSize = CGSize.zero
        repeat {
            attributes[.font] = UIFont.systemFont(ofSize: pointSize, weight: .semibold)
            textSize = (monogram as NSString).size(withAttributes: attributes)
            if textSize.width <= content.width || pointSize <= 4 { break }
            pointSize -= 1
        } while true
        let rect = CGRect(x: content.minX, y: content.midY - textSize.height / 2, width: content.width, height: textSize.height)
        (monogram as NSString).draw(in: rect, withAttributes: attributes)
    }

    private static func uiTextStyle(for style: Font.TextStyle) -> UIFont.TextStyle {
        switch style {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .body: return .body
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        default: return .body
        }
    }

    private static func contentSizeCategory(for size: DynamicTypeSize) -> UIContentSizeCategory {
        switch size {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        @unknown default: return .large
        }
    }
}

/// "Role at [mark] Company" for conversation rows, connection rows, and the conversation header.
struct NTRoleAndCompanyLine: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale
    let role: String
    let company: String
    var mark: CompanyMarkReference? = nil
    var textStyle: Font.TextStyle = .subheadline

    var body: some View {
        (Text("\(role) at ")
            + CompanyMarkTile.text(
                companyName: company,
                reference: mark,
                markData: store.companyMarkData(for: mark),
                textStyle: textStyle,
                dynamicTypeSize: dynamicTypeSize,
                displayScale: displayScale
            )
            + Text(" \(company)"))
            .font(.system(textStyle))
            .accessibilityLabel("\(role) at \(company)")
            .task(id: mark) { await store.ensureCompanyMark(mark) }
    }
}
