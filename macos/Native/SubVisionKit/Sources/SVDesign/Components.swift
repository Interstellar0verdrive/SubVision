// SPDX-License-Identifier: MIT
// Copied and adapted from the design system of the native macOS app of AnimeUp
// (AnimeUpKit/DesignSystem/Components.swift, version 2.1), by the same author.

import SwiftUI
import UniformTypeIdentifiers

/// The status colours, always used as text + tint + line together.
public enum SVTone: Sendable {
    case neutral, accent, green, yellow, red

    public var text: Color {
        switch self {
        case .neutral: SV.text2
        case .accent: SV.primaryText
        case .green: SV.greenText
        case .yellow: SV.yellowText
        case .red: SV.redText
        }
    }

    /// The note / chip background.
    public var background: Color {
        switch self {
        case .neutral: SV.chipBg
        case .accent: SV.soft
        case .green: SV.greenBg
        case .yellow: SV.yellowBg
        case .red: SV.redBg
        }
    }

    public var line: Color {
        switch self {
        case .neutral: SV.chipLine
        case .accent: SV.softLine
        case .green: SV.greenLine
        case .yellow: SV.yellowLine
        case .red: SV.redLine
        }
    }

    /// Tinted buttons inside a note.
    public var tint: Color {
        switch self {
        case .neutral: SV.glass
        case .accent: SV.sel
        case .green: SV.greenTint
        case .yellow: SV.yellowTint
        case .red: SV.redTint
        }
    }

    /// The solid dot / bar colour.
    public var solid: Color {
        switch self {
        case .neutral: SV.text3
        case .accent: SV.primary
        case .green: SV.green
        case .yellow: SV.yellow
        case .red: SV.red
        }
    }

    /// Notes always use the filled shapes.
    public var noteSymbol: String {
        switch self {
        case .neutral, .accent: "info.circle.fill"
        case .green: "checkmark.circle.fill"
        case .yellow: "exclamationmark.triangle.fill"
        case .red: "exclamationmark.octagon.fill"
        }
    }
}

// MARK: - Status chip

/// Mono, lowercase, capsule. Colour plus a word: never colour alone.
public struct StatusChip: View {
    var text: String
    var tone: SVTone
    var symbol: String?

    public init(_ text: String, tone: SVTone = .neutral, symbol: String? = nil) {
        self.text = text
        self.tone = tone
        self.symbol = symbol
    }

    public var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 10))
            }
            // Measured on pixels: even in its own line box the text's weight sat 0.2–0.5 pt
            // below the centre (lowercase, descenders), the icon dead centre. Half a point up, one
            // pixel on a Retina screen, centres it without moving the chip or the icon.
            Text(text).offset(y: -0.5)
        }
        // The font's own line box, centred in the chip's height: the fixed line box of
        // `svFont` puts its extra space above the text, which sat low.
        .font(SVFont.smallNumbers.font)
        .frame(height: SVFont.smallNumbers.lineHeight)
        .foregroundStyle(tone.text)
        .svBox(Capsule(), fill: tone == .accent ? SV.sel : tone.background, line: tone.line,
               padding: EdgeInsets(vertical: 1, horizontal: 8))
        .fixedSize()
    }
}

// MARK: - Note

/// One shape for every message: tint, 1 pt line, 8 pt corners, 12/14 padding.
/// Icon, title, text and buttons all take the status colour.
public struct NoteView<Actions: View>: View {
    var tone: SVTone
    var title: String?
    var text: String
    /// Lines under the text, each with a bullet: the items the title counts (warnings, skipped files).
    var bullets: [String]
    /// A line in semibold under the text: the question a note asks.
    var strong: String?
    /// A last line, a touch lighter (timings, a hint).
    var footnote: String?
    var centred: Bool
    /// The title on the same line as the text, in semibold (board E7: "2 items skipped: … cover.jpg").
    var inlineTitle: Bool
    @ViewBuilder var actions: () -> Actions

    public init(_ tone: SVTone, title: String? = nil, text: String, strong: String? = nil, bullets: [String] = [], footnote: String? = nil,
                centred: Bool = false, inlineTitle: Bool = false, @ViewBuilder actions: @escaping () -> Actions) {
        self.tone = tone
        self.inlineTitle = inlineTitle
        self.title = title
        self.text = text
        self.bullets = bullets
        self.strong = strong
        self.footnote = footnote
        self.centred = centred
        self.actions = actions
    }

    public var body: some View {
        // The buttons sit in the middle of the note's height; the symbol on the first
        // line of text, centred on its capitals.
        HStack(alignment: .center, spacing: 8) {
        HStack(alignment: centred ? .center : .firstTextBaseline, spacing: 8) {
            Image(systemName: tone.noteSymbol)
                .symbolRenderingMode(.monochrome)
                .svFont(14)
                .frame(width: 18, height: 17)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4.5 }
            VStack(alignment: .leading, spacing: 2) {
                if let title, inlineTitle {
                    Text("\(Text(title).fontWeight(.semibold)) \(text)").lineSpacing(3)
                } else {
                    if let title {
                        Text(title).fontWeight(.semibold)
                    }
                    Text(text).lineSpacing(3)
                }
                if let strong { Text(strong).fontWeight(.semibold) }
                if !bullets.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(bullets, id: \.self) { b in
                            HStack(alignment: .firstTextBaseline, spacing: 7) { Text(verbatim: "•"); Text(b) }
                        }
                    }
                    // A little apart: the items the title counts.
                    .padding(.top, 4)
                }
                // The note's own font, only fainter; after a list, a little apart again.
                if let footnote {
                    Text(verbatim: footnote).opacity(0.7)
                        .padding(.top, bullets.isEmpty ? 0 : 4)
                }
            }
            .svFont(12.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
            actions()
        }
        .foregroundStyle(tone.text)
        .svBox(RoundedRectangle(cornerRadius: SV.Radius.field), fill: tone.background, line: tone.line,
               padding: EdgeInsets(vertical: 12, horizontal: 14))
        // As tall as its text: in a card with room to spare it would otherwise take
        // its share of it (the symbol's column reaches the note's full height).
        .fixedSize(horizontal: false, vertical: true)
    }
}

extension NoteView where Actions == EmptyView {
    public init(_ tone: SVTone, title: String? = nil, text: String) {
        self.init(tone, title: title, text: text, actions: { EmptyView() })
    }
}

// MARK: - Card

/// Rows, cards, panels: 10 pt corners, surface, 1 pt line, 18/20 padding.
public struct Card<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: () -> Content

    public init(spacing: CGFloat = 14, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content() }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .svBox(RoundedRectangle(cornerRadius: SV.Radius.card), fill: SV.surface, line: SV.line,
                   padding: EdgeInsets(vertical: 18, horizontal: 20))
    }
}

/// A card title: 16 pt symbol in secondary, 15 semibold title.
public struct CardTitle<Trailing: View>: View {
    var symbol: String
    var title: String
    @ViewBuilder var trailing: () -> Trailing

    public init(_ title: String, symbol: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.symbol = symbol
        self.trailing = trailing
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).svFont(15).foregroundStyle(SV.text2)
                .frame(width: 20)
            Text(title).svFont(SVFont.sectionTitle).foregroundStyle(SV.text)
            Spacer(minLength: 0)
            trailing()
        }
    }
}

extension CardTitle where Trailing == EmptyView {
    public init(_ title: String, symbol: String) {
        self.init(title, symbol: symbol, trailing: { EmptyView() })
    }
}

// MARK: - Value strip

/// A row of facts in one box, split by hairlines: icon, value, label.
public struct ValueStrip: View {
    public struct Item: Identifiable, Sendable {
        public var symbol: String
        public var value: String
        public var label: String
        public var id: String { symbol + value }

        public init(symbol: String, value: String, label: String) {
            self.symbol = symbol
            self.value = value
            self.label = label
        }
    }

    var items: [Item]

    public init(_ items: [Item]) { self.items = items }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 { Rectangle().fill(SV.line).frame(width: 1) }
                HStack(spacing: 8) {
                    Image(systemName: item.symbol).svFont(16).foregroundStyle(SV.text2)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.value).svFont(13, .semibold).foregroundStyle(SV.text)
                        Text(item.label).svFont(11).foregroundStyle(SV.text3)
                    }
                    .lineLimit(1)
                    .fixedSize()
                }
                .padding(.vertical, 9)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .svBox(RoundedRectangle(cornerRadius: SV.Radius.field), fill: SV.raised, line: SV.chipLine)
    }
}

// MARK: - Numbered steps

/// How something works, in order. A line joins the 32 pt circles; a done
/// step turns green with a check.
public struct NumberedSteps: View {
    public struct Step: Identifiable, Sendable {
        public var title: String
        public var detail: String
        public var done: Bool
        public var id: String { title }

        public init(title: String, detail: String, done: Bool = false) {
            self.title = title
            self.detail = detail
            self.done = done
        }
    }

    var steps: [Step]
    var firstNumber: Int
    /// A drawing for each step, on its line at the right; nil for none.
    var art: ((Int) -> AnyView)?
    /// The steps side by side, each drawing above its step: for a card much wider than tall.
    var inRow: Bool

    public init(_ steps: [Step], firstNumber: Int = 0, inRow: Bool = false, art: ((Int) -> AnyView)? = nil) {
        self.steps = steps
        self.firstNumber = firstNumber
        self.inRow = inRow
        self.art = art
    }

    public var body: some View {
        if inRow { row } else { column }
    }

    /// Side by side: drawing, then number and title, then the text in one paragraph.
    private var row: some View {
        HStack(alignment: .top, spacing: 24) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                VStack(alignment: .leading, spacing: 12) {
                    if let art { art(index) }
                    HStack(spacing: 10) {
                        circle(step, number: firstNumber + index)
                        Text(step.title).svFont(13, .semibold).foregroundStyle(SV.text)
                    }
                    // The texts' line breaks are for the column; here they wrap where they must.
                    BalancedParagraph(step.detail.replacingOccurrences(of: "\n", with: " "), style: SVFont.small)
                        .foregroundStyle(SV.text2)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var column: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                if index > 0 { Spacer(minLength: 8) }
                HStack(alignment: .center, spacing: 12) {
                    circle(step, number: firstNumber + index)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title).svFont(13, .semibold).foregroundStyle(SV.text)
                        // The text's own line breaks only while each line fits whole;
                        // otherwise one paragraph, wrapping where it must.
                        ViewThatFits(in: .horizontal) {
                            Text(step.detail).svSmall().fixedSize()
                            BalancedParagraph(step.detail.replacingOccurrences(of: "\n", with: " "), style: SVFont.small)
                                .foregroundStyle(SV.text2)
                        }
                    }
                    if let art {
                        Spacer(minLength: 16)
                        art(index)
                    }
                }
            }
        }
        .frame(maxHeight: 300)
        .background(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1).fill(SV.line)
                .frame(width: 2)
                .padding(.vertical, 30)
                .padding(.leading, 15)
        }
    }

    @ViewBuilder
    private func circle(_ step: Step, number: Int) -> some View {
        ZStack {
            Circle().fill(SV.surface)
            if step.done {
                Circle().fill(SV.greenBg)
                Circle().strokeBorder(SV.greenLine, lineWidth: 1)
                Image(systemName: "checkmark").svFont(12, .semibold).foregroundStyle(SV.greenText)
            } else {
                Circle().strokeBorder(SV.glassLine, lineWidth: 1)
                Text("\(number)").svFont(13, .semibold, mono: true)
                    .foregroundStyle(SV.text2)
            }
        }
        .frame(width: 32, height: 32)
    }
}

// MARK: - Drop frame

/// The stripes inside a drop area (design note 40): bands at 135°, `width`
/// on and `width` off, in `SV.dropHatch`. A Canvas, so it costs nothing at any size.
public struct DiagonalHatch: View {
    var width: CGFloat
    var color: Color

    public init(width: CGFloat = 14, color: Color = SV.dropHatch) {
        self.width = width
        self.color = color
    }

    public var body: some View {
        Canvas { context, size in
            let step = width * 2
            var x: CGFloat = -size.height
            while x < size.width {
                var band = Path()
                band.move(to: CGPoint(x: x, y: 0))
                band.addLine(to: CGPoint(x: x + width, y: 0))
                band.addLine(to: CGPoint(x: x + width + size.height, y: size.height))
                band.addLine(to: CGPoint(x: x + size.height, y: size.height))
                band.closeSubpath()
                context.fill(band, with: .color(color))
                x += step
            }
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// The frame of a drop area (design notes 38 and 40): 12 pt corners, a 2 pt
    /// dash `[6, 4]` in `SV.dropLine` over the stripes; with a file over it the
    /// dash turns to the accent and the stripes give way to the `soft` fill.
    public func svDropFrame(targeted: Bool, cornerRadius: CGFloat = 12) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        return background {
            ZStack {
                if targeted { shape.fill(SV.soft) } else { DiagonalHatch() }
            }
            .clipShape(shape)
        }
        .overlay(shape.strokeBorder(targeted ? SV.primary : SV.dropLine, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
    }
}

// MARK: - Status circle

/// The 22 pt status ring of a row (design note 38): a symbol that stays clear
/// of the ring, a 16 pt spinner while the row works, the warning triangle
/// drawn inside 68 % of the box. Used by the file rows and the tools window.
public struct StatusCircle: View {
    public enum State: Sendable, Equatable {
        /// Waiting in the batch: a dashed ring, so it does not read as a radio button
        /// (a ready row shows no circle at all).
        case waiting
        /// Work going on: the spinner.
        case running
        /// Green check.
        case done
        /// Yellow triangle (done without subtitles, file missing).
        case warning
        /// Red cross (failed, unreadable).
        case failed
        /// Grey square (stopped by the person).
        case stopped
    }

    var state: State
    public static let size: CGFloat = 22

    public init(_ state: State) { self.state = state }

    public var body: some View {
        ZStack {
            switch state {
            case .waiting:
                Circle().strokeBorder(SV.text3, style: StrokeStyle(lineWidth: 1.2, dash: [2.4, 2.6]))
            case .running:
                Spinner(size: Self.size)
            case .done:
                Circle().fill(SV.greenBg)
                Circle().strokeBorder(SV.greenLine)
                Image(systemName: "checkmark").svFont(11, .bold).foregroundStyle(SV.greenText)
            case .warning:
                Circle().fill(SV.yellowBg)
                Circle().strokeBorder(SV.yellowLine)
                WarningTriangle().foregroundStyle(SV.yellowText)
            case .failed:
                Circle().strokeBorder(SV.redLine)
                Image(systemName: "xmark").svFont(10, .bold).foregroundStyle(SV.redText)
            case .stopped:
                Circle().strokeBorder(SV.glassLine)
                RoundedRectangle(cornerRadius: 1.5).fill(SV.text2).frame(width: 8, height: 8)
            }
        }
        .frame(width: Self.size, height: Self.size)
    }
}

/// The warning triangle of `StatusCircle`: 9.5 × 8.2 pt, its vertices 6.2 pt
/// from the centre, so it never touches the ring.
struct WarningTriangle: View {
    var body: some View {
        ZStack {
            Path { p in
                let w: CGFloat = 9.5, h: CGFloat = 8.2
                p.move(to: CGPoint(x: w / 2, y: 0))
                p.addLine(to: CGPoint(x: w, y: h))
                p.addLine(to: CGPoint(x: 0, y: h))
                p.closeSubpath()
            }
            .strokedPath(StrokeStyle(lineWidth: 1.4, lineJoin: .round))
            .frame(width: 9.5, height: 8.2)
            VStack(spacing: 0.8) {
                RoundedRectangle(cornerRadius: 0.6).frame(width: 1.3, height: 3)
                Circle().frame(width: 1.3, height: 1.3)
            }
            .offset(y: 1.4)
        }
        .frame(width: 14, height: 14)
    }
}

// MARK: - Drop zone

/// Where files can be dropped; the button opens the same thing from the
/// keyboard. The drop frame of the design (2 pt dash over faint stripes) and
/// three fanned video cards that open when the view appears.
public struct DropZone: View {
    var title: String
    var buttonTitle: String
    var shortcut: String
    var primary: Bool
    var onOpen: () -> Void
    var onDrop: ([URL]) -> Void
    /// Horizontal: the cards, then title and `text`, the button on the right.
    var axis: Axis
    var text: String?
    @State private var targeted = false
    @State private var fanned = false

    public init(title: String, buttonTitle: String, shortcut: String = "⌘O", primary: Bool,
                axis: Axis = .vertical, text: String? = nil,
                onOpen: @escaping () -> Void, onDrop: @escaping ([URL]) -> Void) {
        self.axis = axis
        self.text = text
        self.title = title
        self.buttonTitle = buttonTitle
        self.shortcut = shortcut
        self.primary = primary
        self.onOpen = onOpen
        self.onDrop = onDrop
    }

    public var body: some View {
        Group {
            if axis == .vertical {
                vertical
            } else {
                // Too narrow for cards, words and button side by side: the vertical layout, rather
                // than a title one word per line.
                ViewThatFits(in: .horizontal) {
                    horizontal
                    vertical
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .svDropFrame(targeted: targeted)
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            Task { @MainActor in
                var urls: [URL] = []
                for provider in providers {
                    if let url = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? URL {
                        urls.append(url)
                    } else if let data = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil) {
                        urls.append(url)
                    }
                }
                onDrop(urls)
            }
            return true
        }
        .onAppear {
            withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.7).delay(0.25)) { fanned = true }
        }
    }

    private var vertical: some View {
        VStack(spacing: 12) {
            thumbs
            VStack(spacing: 3) {
                Text(title).svFont(13, .medium).foregroundStyle(SV.text).multilineTextAlignment(.center)
                if let text {
                    Text(text).svSmall().multilineTextAlignment(.center)
                        .frame(maxWidth: 420).fixedSize(horizontal: false, vertical: true)
                }
            }
            openButton
        }
        .padding(16)
    }

    private var horizontal: some View {
        HStack(spacing: 14) {
            thumbs
            // The text takes the width the row has, the button stays on the right:
            // with a spacer the text kept only its ideal width and wrapped narrow.
            VStack(alignment: .leading, spacing: 3) {
                // ViewThatFits compares ideal widths: an ideal of 80 pt keeps this layout while the
                // title fits on three short lines, and no narrower.
                Text(title).svFont(13, .medium).foregroundStyle(SV.text).lineLimit(3)
                    .frame(minWidth: 80, idealWidth: 80, alignment: .leading)
                if let text { Text(text).svSmall().fixedSize(horizontal: false, vertical: true) }
            }
            .frame(minWidth: 80, idealWidth: 80, maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 2)
            openButton
        }
        .padding(.vertical, 16).padding(.leading, 18).padding(.trailing, 26)
    }

    private var openButton: some View {
        HStack(spacing: 8) {
            Button(buttonTitle, action: onOpen)
                .svButton(primary ? .primary : .secondary, .regular)
            Text(shortcut).svFont(SVFont.smallNumbers).foregroundStyle(SV.text3)
        }
    }

    private var thumbs: some View {
        ZStack {
            thumb(width: 76, height: 52, front: false)
                .rotationEffect(.degrees(fanned ? -9 : 0))
                .offset(x: fanned ? -48 : -10, y: 9)
            thumb(width: 76, height: 52, front: false)
                .rotationEffect(.degrees(fanned ? 9 : 0))
                .offset(x: fanned ? 48 : 10, y: 9)
            thumb(width: 96, height: 66, front: true)
        }
        .frame(width: 200, height: 96)
    }

    private func thumb(width: CGFloat, height: CGFloat, front: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(LinearGradient(colors: [SV.raised, SV.surface], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(front ? SV.softLine : SV.glassLine, lineWidth: 1))
            .overlay {
                if front {
                    Image(systemName: "play.fill").svFont(9)
                        .foregroundStyle(SV.onPrimary)
                        .offset(x: 1)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(SV.primary))
                }
            }
            .overlay(alignment: .bottom) {
                Capsule().fill(SV.trackSoft).frame(height: 3)
                    .overlay(alignment: .leading) {
                        GeometryReader { g in
                            Capsule().fill(SV.primary).frame(width: front ? g.size.width * 0.6 : 0)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 7)
            }
            .frame(width: width, height: height)
            .shadow(color: SV.shadow.opacity(0.25), radius: 8, y: 6)
    }
}

// MARK: - Progress bar

/// 4 pt (rows) or 6 pt (players, speeds) bar.
public struct SVBar: View {
    var fraction: Double
    var height: CGFloat
    var fill: Color
    var track: Color

    public init(_ fraction: Double, height: CGFloat = 4, fill: Color = SV.primary, track: Color = SV.trackSoft) {
        self.fraction = fraction
        self.height = height
        self.fill = fill
        self.track = track
    }

    public var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(fill).frame(width: max(0, min(1, fraction)) * g.size.width)
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
    }
}

/// The ring spinner: accent arc on a soft ring.
public struct Spinner: View {
    var size: CGFloat
    var tint: Color
    @State private var turning = false

    /// `tint` for a spinner on a coloured fill (the selected top-bar segment).
    public init(size: CGFloat = 14, tint: Color = SV.primary) {
        self.size = size
        self.tint = tint
    }

    public var body: some View {
        ZStack {
            Circle().stroke(tint == SV.primary ? SV.softLine : tint.opacity(0.3), lineWidth: size > 12 ? 2 : 1.6)
            Circle().trim(from: 0, to: 0.25)
                .stroke(tint, style: StrokeStyle(lineWidth: size > 12 ? 2 : 1.6, lineCap: .round))
                .rotationEffect(.degrees(turning ? 360 : 0))
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { turning = true }
        }
    }
}

// MARK: - Underlined link

/// Secondary actions inside text, notes, cards: underlined, in the colour of
/// what surrounds them. Never the main action.
public struct UnderlineLink: View {
    var title: String
    var tone: SVTone
    var symbol: String?
    var action: () -> Void
    @State private var hover = false

    public init(_ title: String, tone: SVTone = .accent, symbol: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.tone = tone
        self.symbol = symbol
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                // The symbol on the middle of the capitals (on the baseline it sat half a point high).
                if let symbol { Image(systemName: symbol).svFont(10, .medium).svOnCapsMiddle(12.5) }
                Text(title)
                    .underline(true, color: tone.text.opacity(hover ? 1 : 0.55))
            }
            .svFont(12.5, .medium)
            .foregroundStyle(tone.text)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .svPointingHand()
    }
}

// MARK: - Top bar segment

/// One page in the top bar's segmented control: 12 pt symbol and 12.5 pt title,
/// 24 pt tall; the current one filled with the accent. Work going on shows a
/// spinner, a count (the files of a batch) a small number.
public struct TopBarSegment: View {
    var symbol: String
    var title: String
    var selected: Bool
    var busy: Bool
    var count: Int?
    var action: () -> Void
    @State private var hover = false

    public init(symbol: String, title: String, selected: Bool, busy: Bool = false, count: Int? = nil,
                action: @escaping () -> Void) {
        self.symbol = symbol
        self.title = title
        self.selected = selected
        self.busy = busy
        self.count = count
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                // While the page works the spinner takes the icon's place, before the word (board N1).
                // Natural line boxes (`svControlFont`), centred: the fixed line box of `svFont` put
                // the word 0.75 pt under the segment's centre and under the symbol (measured at 2x).
                if busy {
                    Spinner(size: 10, tint: selected ? SV.onPrimary : SV.primary).frame(width: 12)
                } else {
                    Image(systemName: symbol).svControlFont(12)
                }
                Text(title).svControlFont(12.5, selected ? .semibold : .regular).lineLimit(1)
                // The number stays while the batch works.
                if let count {
                    // A neutral capsule, glass on the bar, a darker veil on the current segment.
                    Text("\(count)").svFont(10, .semibold, mono: true)
                        .foregroundStyle(selected ? SV.onPrimary : SV.text2)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(Capsule().fill(selected ? SV.chipOnAccent : SV.glass))
                        .overlay(Capsule().strokeBorder(selected ? .clear : SV.glassLine))
                }
            }
            .foregroundStyle(selected ? SV.onPrimary : SV.text2)
            .padding(.leading, 12)
            .padding(.trailing, count != nil ? 8 : 12)
            .frame(height: 24)
            .background(Capsule().fill(selected ? SV.primary : hover ? SV.glassHover : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A small choice between two or three views of the same thing (a
/// player's fit or 1:1): 22 pt segments, 6 pt corners in an 8 pt glass track.
public struct SVMiniSegments: View {
    public struct Option {
        var label: AnyView
        var help: String
        var selected: Bool
        var action: () -> Void
        public init(_ label: some View, help: String, selected: Bool, action: @escaping () -> Void) {
            self.label = AnyView(label)
            self.help = help
            self.selected = selected
            self.action = action
        }
    }

    var options: [Option]
    /// Every segment this wide, when given: an icon and "1:1" side by side look alike.
    var segmentWidth: CGFloat?
    public init(_ options: [Option], segmentWidth: CGFloat? = nil) {
        self.options = options
        self.segmentWidth = segmentWidth
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, o in
                Button(action: o.action) {
                    // The semibold width held in place: choosing doesn't nudge the segments.
                    ZStack {
                        o.label.svFont(12, .semibold).hidden()
                        o.label.svFont(12, o.selected ? .semibold : .regular)
                    }
                        .foregroundStyle(o.selected ? SV.onPrimary : SV.text2)
                        .padding(.horizontal, segmentWidth == nil ? 9 : 0)
                        .frame(width: segmentWidth, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6).fill(o.selected ? SV.primary : .clear))
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                        .svHover(RoundedRectangle(cornerRadius: 6), enabled: !o.selected)
                }
                .buttonStyle(.plain)
                .help(o.help)
                .accessibilityLabel(o.help)
                .accessibilityAddTraits(o.selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8).fill(SV.glass))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(SV.glassLine))
    }
}

/// The track of the top bar's segments (`.tsegs`): a capsule 2 pt around them in glass, glass line.
public struct TopBarSegments<Content: View>: View {
    @ViewBuilder var content: () -> Content
    public init(@ViewBuilder content: @escaping () -> Content) { self.content = content }

    public var body: some View {
        HStack(spacing: 2) { content() }
            .padding(2)
            .background(Capsule().fill(SV.glass))
            .overlay(Capsule().strokeBorder(SV.glassLine))
    }
}

// MARK: - Path field

/// A path in an inset, mono, truncating in the middle.
public struct PathField: View {
    var path: String
    var symbol: String

    var height: CGFloat

    /// 28 pt in cards, 26 pt next to a small button (settings rows).
    public init(_ path: String, symbol: String = "externaldrive", height: CGFloat = 28) {
        self.path = path
        self.symbol = symbol
        self.height = height
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).svFont(11).foregroundStyle(SV.text3)
            Text(path).svFont(SVFont.numbers).foregroundStyle(SV.textCode)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .frame(height: height - 2)
        .frame(maxWidth: .infinity)
        .svBox(RoundedRectangle(cornerRadius: SV.Radius.field), fill: SV.inset, line: SV.line,
               padding: EdgeInsets(vertical: 0, horizontal: 10))
        .help(path)
    }
}

/// A coloured dot, 7 pt, for one-line states ("Not done yet").
/// A status line that opens its details. The dot, the text and a
/// chevron in the tone's text colour; the hover veil and the pointing hand.
public struct StatusLink: View {
    var title: String
    var tone: SVTone
    var help: String?
    /// 12 in a list of statuses (sidebar, Settings); 11 next to a label, at its size (Start).
    var size: CGFloat
    /// Work in progress: a spinner in place of the dot (a check running).
    var busy: Bool
    var action: () -> Void
    @State private var hover = false

    public init(_ title: String, tone: SVTone = .green, size: CGFloat = 12, busy: Bool = false, help: String? = nil,
                action: @escaping () -> Void) {
        self.title = title
        self.tone = tone
        self.size = size
        self.busy = busy
        self.help = help
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if busy { Spinner(size: size - 1) } else { StatusDot(tone) }
                // The font's own line box: centred on the dot and the chevron.
                Text(title).svControlFont(size).lineLimit(1)
                Image(systemName: "chevron.right").svControlFont(8, .semibold)
            }
            .foregroundStyle(tone.text)
            .padding(.horizontal, 4).padding(.vertical, 2)
            // Under the pointer, the tone's tint: the plain veil is too faint on a coloured line.
            .background(RoundedRectangle(cornerRadius: 6).fill(tone.background).opacity(hover ? 1 : 0))
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.12), value: hover)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -4)
        .svPointingHand()
        .help(help ?? "")
    }
}

public struct StatusDot: View {
    var tone: SVTone
    public init(_ tone: SVTone) { self.tone = tone }
    public var body: some View { Circle().fill(tone.solid).frame(width: 7, height: 7) }
}
