// SPDX-License-Identifier: MIT
// Components of the design round C3 (boards C3-01, C3-02, C3-07, C3-09, DS4):
// the title band of a detail page (a report, a preview) with its round back
// button, the list's checkboxes (the header's one has three states) and the
// progress bar split into one segment per file of a batch.

import AppKit
import SwiftUI

// MARK: - Title band

/// The fixed band under the top bar of a detail page (`.tband`, boards R1, A3,
/// C3-07, C3-09): 86 pt, on `bg` with a line under it. On the left a 38 pt
/// round button with a chevron goes back (⌘[; under the pointer it lights up
/// and says `backHelp`), next to it the title, "<prefix> <name>" with the name
/// in 24 pt bold and the prefix regular and secondary, the details on a line
/// under it; the secondary buttons on the right. With `maxContentWidth` the
/// content keeps to a centred column that wide (1180 pt for the report), so it
/// lines up with the column under the band. `shortcut: false` when the app's
/// menu has the ⌘[ item (View › Back) that does the same.
public struct TitleBand<Trailing: View>: View {
    var prefix: String
    var name: String
    var subtitle: String
    var backHelp: String
    var maxContentWidth: CGFloat?
    var shortcut: Bool
    var back: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    public static var height: CGFloat { 86 }
    /// The capitals of the 24 pt bold title.
    static var titleCapHeight: CGFloat { NSFont.systemFont(ofSize: 24, weight: .bold).capHeight }

    public init(prefix: String, name: String, subtitle: String = "", backHelp: String,
                maxContentWidth: CGFloat? = nil, shortcut: Bool = true, back: @escaping () -> Void,
                @ViewBuilder trailing: @escaping () -> Trailing) {
        self.prefix = prefix
        self.name = name
        self.subtitle = subtitle
        self.backHelp = backHelp
        self.maxContentWidth = maxContentWidth
        self.shortcut = shortcut
        self.back = back
        self.trailing = trailing
    }

    public var body: some View {
        // The line the stack aligns on (the circle's middle, the text's) in the band's middle:
        // a frame would centre the stack's bounds, which reach lower than the text.
        CentredOnGuide {
        HStack(alignment: .bandMiddle, spacing: 16) {
            BackCircleButton(help: backHelp, shortcut: shortcut, action: back)
            VStack(alignment: .leading, spacing: 3) {
                title
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(height: 29)
                if !subtitle.isEmpty {
                    Text(subtitle).svFont(12.5).foregroundStyle(SV.text2).lineLimit(1).truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The round button on the middle of the text as it reads, from the top of the
            // title's capitals to the details' baseline (C3-07): the title's line box has the
            // ascenders' room above the capitals, which put the words 2 pt low.
            .alignmentGuide(.bandMiddle) { d in
                (d[.firstTextBaseline] - Self.titleCapHeight + d[.lastTextBaseline]) / 2
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 8) { trailing() }
                .fixedSize()
        }
        }
        .frame(height: Self.height)
        .frame(maxWidth: maxContentWidth ?? .infinity)
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity)
        .background(SV.bg)
        .overlay(alignment: .bottom) { Rectangle().fill(SV.line).frame(height: 1) }
    }

    private var title: Text {
        let lead = Text(verbatim: prefix.isEmpty ? "" : prefix + " ").font(.system(size: 24, weight: .regular)).foregroundStyle(SV.text2)
        let bold = Text(verbatim: name).font(.system(size: 24, weight: .bold)).foregroundStyle(SV.text)
        return Text("\(lead)\(bold)").tracking(-0.24)
    }
}

extension VerticalAlignment {
    /// The title band's line: the middle of the round button and of the text as it reads.
    /// A custom alignment, so a stack hands it on (the built-in `.center` of a stack is its
    /// bounds' middle).
    private enum BandMiddle: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d[VerticalAlignment.center] }
    }

    static let bandMiddle = VerticalAlignment(BandMiddle.self)
}

/// One view, placed so that its `.bandMiddle` line is in the middle of the space, its width
/// the space's.
struct CentredOnGuide: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)) ?? .zero
        return CGSize(width: proposal.width ?? size.width, height: proposal.height ?? size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let view = subviews.first else { return }
        let width = ProposedViewSize(width: bounds.width, height: nil)
        let d = view.dimensions(in: width)
        view.place(at: CGPoint(x: bounds.minX, y: bounds.midY - d[.bandMiddle]), anchor: .topLeading, proposal: width)
    }
}

extension TitleBand where Trailing == EmptyView {
    public init(prefix: String, name: String, subtitle: String = "", backHelp: String,
                maxContentWidth: CGFloat? = nil, shortcut: Bool = true, back: @escaping () -> Void) {
        self.init(prefix: prefix, name: name, subtitle: subtitle, backHelp: backHelp,
                  maxContentWidth: maxContentWidth, shortcut: shortcut, back: back) { EmptyView() }
    }
}

/// The band's back button (`.tband .bk`): a 38 pt glass circle with a chevron;
/// under the pointer the control's fill, an accent ring and chevron, and a small
/// label under it ("Back to the list · ⌘["). With `shortcut`, ⌘[ presses it while
/// it is on screen.
public struct BackCircleButton: View {
    var help: String
    var shortcut: Bool
    var action: () -> Void
    @State private var hover = false

    public init(help: String, shortcut: Bool = true, action: @escaping () -> Void) {
        self.help = help
        self.shortcut = shortcut
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(hover ? SV.primaryText : SV.text)
                .frame(width: 38, height: 38)
                .background(Circle().fill(hover ? SV.control : SV.glass))
                .overlay(Circle().strokeBorder(hover ? SV.primary : SV.glassLine, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcut ? KeyboardShortcut("[", modifiers: .command) : nil)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        // The system's tooltip, not one drawn in the band: a page under the band (the report's
        // web view) is drawn above anything the band draws, and covered it.
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Checkboxes

/// The state of a checkbox; the list header's one can be `mixed` (C3-02, DS4).
public enum CheckState: Sendable, Equatable {
    case off, mixed, on

    /// The state of a header box over `checked` of `total` rows that have a box.
    public static func of(checked: Int, total: Int) -> CheckState {
        checked <= 0 || total <= 0 ? .off : checked >= total ? .on : .mixed
    }
}

/// The 16 pt checkbox of the list rows (`.cbx`): the control's fill under a box
/// line, 4 pt corners; on, the accent with a check; mixed, the accent with a dash.
public struct SVCheckbox: View {
    var state: CheckState
    var help: String
    var action: () -> Void
    @Environment(\.isEnabled) private var enabled
    @State private var hover = false

    public init(_ state: CheckState, help: String = "", action: @escaping () -> Void) {
        self.state = state
        self.help = help
        self.action = action
    }

    public init(isOn: Bool, help: String = "", action: @escaping () -> Void) {
        self.init(isOn ? .on : .off, help: help, action: action)
    }

    public var body: some View {
        Button(action: action) {
            CheckboxMark(state: state, hover: hover && enabled)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .opacity(enabled ? 1 : 0.45)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityValue(state == .on ? "1" : state == .mixed ? "0.5" : "0")
        .accessibilityAddTraits(.isToggle)
    }
}

/// The list header's checkbox (C3-02, DS4): none, some ("−") or all of the rows
/// that have a box. What a click does is the app's (with some, it checks all).
public struct HeaderCheckbox: View {
    var state: CheckState
    var help: String
    var action: () -> Void

    public init(_ state: CheckState, help: String = "", action: @escaping () -> Void) {
        self.state = state
        self.help = help
        self.action = action
    }

    public var body: some View { SVCheckbox(state, help: help, action: action) }
}

/// The box alone, 16 pt.
public struct CheckboxMark: View {
    var state: CheckState
    var hover: Bool

    public init(state: CheckState, hover: Bool = false) {
        self.state = state
        self.hover = hover
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4)
        ZStack {
            switch state {
            case .off:
                shape.fill(SV.control)
                shape.strokeBorder(hover ? SV.primary : SV.boxLine)
            case .on:
                shape.fill(hover ? SV.primaryHover : SV.primary)
                Image(systemName: "checkmark").font(.system(size: 9.5, weight: .bold)).foregroundStyle(SV.onPrimary)
            case .mixed:
                shape.fill(hover ? SV.primaryHover : SV.primary)
                RoundedRectangle(cornerRadius: 1).fill(SV.onPrimary).frame(width: 8, height: 2)
            }
        }
        .frame(width: 16, height: 16)
    }
}

// MARK: - Segmented progress bar

/// A progress bar split into one segment per part (a file of a batch), each as
/// wide as its weight (the file's duration), with a 2 pt gap between two
/// segments (`.sgbar`, C3-01, DS4). The gaps are cut out, so the bar reads on
/// any background. `fraction` is of the whole bar.
public struct SegmentedProgressBar: View {
    var weights: [Double]
    var fraction: Double
    var height: CGFloat
    var gap: CGFloat
    var fill: Color
    var track: Color

    public init(weights: [Double], fraction: Double, height: CGFloat = 6, gap: CGFloat = 2,
                fill: Color = SV.primary, track: Color = SV.trackSoft) {
        self.weights = weights
        self.fraction = fraction
        self.height = height
        self.gap = gap
        self.fill = fill
        self.track = track
    }

    /// Where the gaps fall, as fractions of the width (between two segments).
    public static func cuts(_ weights: [Double]) -> [Double] {
        let clean = weights.map { $0 > 0 && $0.isFinite ? $0 : 0 }
        let total = clean.reduce(0, +)
        guard total > 0, clean.count > 1 else { return [] }
        var out: [Double] = [], run = 0.0
        for w in clean.dropLast() {
            run += w
            out.append(run / total)
        }
        return out
    }

    public var body: some View {
        GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .leading) {
                Rectangle().fill(track)
                Rectangle().fill(fill).frame(width: max(0, min(1, fraction)) * w)
            }
            .clipShape(Capsule())
            .mask {
                ZStack(alignment: .leading) {
                    Rectangle()
                    ForEach(Array(Self.cuts(weights).enumerated()), id: \.offset) { _, cut in
                        Rectangle()
                            .frame(width: gap)
                            .offset(x: (w * cut - gap / 2).rounded())
                            .blendMode(.destinationOut)
                    }
                }
                .compositingGroup()
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue("\(Int((fraction * 100).rounded())) %")
    }
}
