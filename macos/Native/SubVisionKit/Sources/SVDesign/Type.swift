// SPDX-License-Identifier: MIT
// Copied and adapted from the design system of the native macOS app of AnimeUp
// (AnimeUpKit/DesignSystem/Type.swift, version 2.1), by the same author.
//
// Text is set the way the design boards set it: SF Pro or SF Mono at a size,
// and a line box as tall as the browser makes it. SwiftUI's own line box is up
// to 1 pt taller per line, which piles up down a column, so every text style
// here fixes the line height too.

import AppKit
import SwiftUI

/// A text style: size, weight, family and line height.
public struct SVTextStyle: Sendable {
    public var size: CGFloat
    public var weight: Font.Weight
    public var mono: Bool
    /// CSS `line-height` as a factor of the size; nil is `normal`.
    public var leading: CGFloat?

    public init(_ size: CGFloat, _ weight: Font.Weight = .regular, mono: Bool = false, leading: CGFloat? = nil) {
        self.size = size
        self.weight = weight
        self.mono = mono
        self.leading = leading
    }

    public var font: Font { .system(size: size, weight: weight, design: mono ? .monospaced : .default) }

    /// The line box in points.
    public var lineHeight: CGFloat { leading.map { size * $0 } ?? SVType.normalLineHeight(size, mono: mono) }
}

public enum SVType {
    /// `line-height: normal` for SF Pro and SF Mono, measured in the browser
    /// the boards are drawn with, every half point from 7 to 28.
    private static let pro: [CGFloat] = [8.5, 9, 9, 10, 10.5, 11, 11.5, 12, 13, 13.5, 14, 14.5, 15, 16, 16.5, 17, 17.5,
                                         18.5, 19, 19.5, 20, 20.5, 21.5, 22, 22.5, 23, 23.5, 24.5, 25, 25.5, 26, 26.5,
                                         27, 27.5, 28, 28.5, 29.5, 30, 30.5, 31, 31.5, 32.5, 33]
    private static let sfMono: [CGFloat] = [8, 9, 9.5, 10, 10.5, 11, 12, 12, 12.5, 13, 14, 14.5, 15, 15.5, 16.5, 17,
                                            17.5, 18, 19, 19.5, 20, 20, 20.5, 21.5, 22, 22.5, 23, 24, 24.5, 25, 25.5,
                                            26.5, 27, 27.5, 28, 28.5, 29, 29.5, 30, 30.5, 31.5, 32, 32.5]

    /// Half the cap height of SF Pro at this size: the middle of the capitals above the baseline.
    public static func capCentre(_ size: CGFloat) -> CGFloat { NSFont.systemFont(ofSize: size).capHeight / 2 }

    public static func normalLineHeight(_ size: CGFloat, mono: Bool) -> CGFloat {
        let table = mono ? sfMono : pro
        let i = Int(((size - 7) * 2).rounded())
        if i >= 0 && i < table.count { return table[i] }
        return (size * (mono ? 1.163 : 1.18)).rounded()
    }
}

extension View {
    /// Sets a text style: font and line box.
    public func svFont(_ style: SVTextStyle) -> some View {
        font(style.font).lineHeight(.exact(points: style.lineHeight))
    }

    /// A text made of runs (`svRun`) in other styles: the base font, and a line
    /// box as tall as the tallest run, so a bigger run is never cut.
    public func svFont(_ style: SVTextStyle, runs: SVTextStyle...) -> some View {
        font(style.font).lineHeight(.exact(points: ([style] + runs).map(\.lineHeight).max() ?? style.lineHeight))
    }

    /// A one-line label inside a control (button, segment): the font with its own
    /// line box. The fixed line box of `svFont` puts its extra space above the text,
    /// which sat half a point low in the middle of a capsule.
    public func svControlFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> some View {
        font(SVTextStyle(size, weight).font)
    }

    /// A smaller text on the line of a bigger one that is centred in its row with its own line
    /// box (`svControlFont`, which puts the capitals in the middle, measured within 0.1 pt):
    /// this one sits on that text's baseline instead of being centred itself. `size` is the
    /// bigger text's.
    public func svBaseline(ofCentred size: CGFloat) -> some View {
        alignmentGuide(VerticalAlignment.center) { $0[.firstTextBaseline] - SVType.capCentre(size) }
    }

    /// A mark beside a text (a dot, a swatch, a checkbox, a chip, a small circle) in an
    /// `HStack(alignment: .firstTextBaseline)`: its middle on the middle of the capitals of
    /// the text of `size`, whatever that text's line box. A plain `.center` stack centres it on
    /// the line box instead, which put the marks up to a point off the capitals.
    public func svOnCapsMiddle(_ size: CGFloat) -> some View {
        alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + SVType.capCentre(size) }
    }

    public func svFont(_ size: CGFloat, _ weight: Font.Weight = .regular, mono: Bool = false, leading: CGFloat? = nil) -> some View {
        svFont(SVTextStyle(size, weight, mono: mono, leading: leading))
    }
}

extension Text {
    /// The font of a text style for a run inside another `Text` (interpolated
    /// or joined with `+`): the line box is the enclosing text's.
    public func svRun(_ size: CGFloat, _ weight: Font.Weight = .regular, mono: Bool = false) -> Text {
        font(SVTextStyle(size, weight, mono: mono).font)
    }
}

/// A paragraph in a column of any width, its lines of similar length (CSS
/// `text-wrap: balance`): at each width it takes the narrowest one that keeps
/// the same number of lines, so no lone word is left on the last one. Left-aligned.
public struct BalancedParagraph: View {
    var text: String
    var style: SVTextStyle

    public init(_ text: String, style: SVTextStyle) {
        self.text = text
        self.style = style
    }

    public var body: some View {
        BalancedLayout(text: text, style: style) {
            Text(text).svFont(style).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct BalancedLayout: Layout {
    var text: String
    var style: SVTextStyle

    private func lineWidth(_ proposal: ProposedViewSize, _ subviews: Subviews) -> CGFloat {
        let ideal = subviews.first?.sizeThatFits(.unspecified).width ?? 0
        guard let w = proposal.width, w.isFinite, w < ideal else { return ideal }
        return min(w, BalancedText.width(text, style: style, maxWidth: w))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = lineWidth(proposal, subviews)
        let h = subviews.first?.sizeThatFits(ProposedViewSize(width: w, height: nil)).height ?? 0
        return CGSize(width: proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? w, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let w = lineWidth(ProposedViewSize(width: bounds.width, height: nil), subviews)
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: w, height: nil))
    }
}

/// Centred text that wraps into lines of similar length, up to `maxWidth`.
public struct BalancedText: View {
    var text: String
    var style: SVTextStyle
    var maxWidth: CGFloat

    public init(_ text: String, style: SVTextStyle, maxWidth: CGFloat) {
        self.text = text
        self.style = style
        self.maxWidth = maxWidth
    }

    public var body: some View {
        Text(text)
            .svFont(style)
            .multilineTextAlignment(.center)
            .frame(width: Self.width(text, style: style, maxWidth: maxWidth))
            .fixedSize(horizontal: false, vertical: true)
    }

    static func width(_ text: String, style: SVTextStyle, maxWidth: CGFloat) -> CGFloat {
        let weight: NSFont.Weight = switch style.weight {
        case .bold: .bold
        case .semibold: .semibold
        case .medium: .medium
        default: .regular
        }
        let font = style.mono ? NSFont.monospacedSystemFont(ofSize: style.size, weight: weight)
                              : NSFont.systemFont(ofSize: style.size, weight: weight)
        // Same height as at full width = same number of lines.
        func height(_ w: CGFloat) -> CGFloat {
            (text as NSString).boundingRect(with: NSSize(width: w, height: .greatestFiniteMagnitude),
                                            options: [.usesLineFragmentOrigin], attributes: [.font: font]).height
        }
        let full = height(maxWidth)
        guard full > font.ascender - font.descender + font.leading + 1 else { return maxWidth }   // one line
        var lo: CGFloat = 1, hi = maxWidth
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if height(mid) > full + 0.5 { lo = mid } else { hi = mid }
        }
        return ceil(hi) + 2
    }
}
