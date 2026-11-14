// SPDX-License-Identifier: MIT
// Copied and adapted from the design system of the native macOS app of AnimeUp
// (AnimeUpKit/DesignSystem/Chrome.swift, version 2.1), by the same author.
// The measures were constants there; here they are a configuration the app
// sets, with the values of SubVision's design boards as the defaults.
//
// The window frame (design round C3, navigation N-A): the page on `bg` under
// a 52 pt top bar that holds the window's own traffic lights, the pages as
// segments and the Settings gear; no sidebar at any width.

import SwiftUI

/// Measures of the window frame. The app puts its own in the environment
/// (`.environment(\.svChrome, …)`); the components read them from there.
public struct SVChrome: Sendable, Equatable {
    /// The slot of the traffic lights: its height (the lights are centred in it).
    public var topRowHeight: CGFloat = 24
    /// The top bar: traffic lights, the pages' segments, the trailing buttons.
    public var topBarHeight: CGFloat = 52
    /// The batch bar at the bottom of the window while a batch runs (C3-01).
    public var batchBarHeight: CGFloat = 44
    /// The main area: page padding.
    public var page = EdgeInsets(top: 28, leading: 28, bottom: 28, trailing: 28)
    /// The window the boards are drawn at, its first size and the least it opens at
    /// (C3-03: at least this, or almost the whole screen when that is smaller).
    public var window = CGSize(width: 1360, height: 860)
    /// The smallest window: the pages are laid out for it.
    public var minWindow = CGSize(width: 720, height: 640)
    /// Width the traffic lights take in the top row (three 14 pt buttons, 6 pt apart).
    public var lightsWidth: CGFloat = 54
    /// The parameters panel of Video and Preview (design boards C2-P1–P3, C2-V1).
    public var inspectorWidth: CGFloat = 340
    /// Below this window width the panel retracts and opens over the page, from the
    /// right, with the top bar's button (N1, N2); at this width or more it is always
    /// beside the page and never closes (C3-03).
    public var inspectorOverlayBelow: CGFloat = 1100

    /// SubVision's measures (design boards DS4, E1, N1, N2).
    public static let `default` = SVChrome()

    public init(topRowHeight: CGFloat = 24, topBarHeight: CGFloat = 52, batchBarHeight: CGFloat = 44,
                page: EdgeInsets = EdgeInsets(top: 28, leading: 28, bottom: 28, trailing: 28),
                window: CGSize = CGSize(width: 1360, height: 860),
                minWindow: CGSize = CGSize(width: 720, height: 640), lightsWidth: CGFloat = 54,
                inspectorWidth: CGFloat = 340, inspectorOverlayBelow: CGFloat = 1100) {
        self.topRowHeight = topRowHeight
        self.topBarHeight = topBarHeight
        self.batchBarHeight = batchBarHeight
        self.page = page
        self.window = window
        self.minWindow = minWindow
        self.lightsWidth = lightsWidth
        self.inspectorWidth = inspectorWidth
        self.inspectorOverlayBelow = inspectorOverlayBelow
    }

    /// In a window this wide, the inspector covers the page instead of sitting beside it.
    public func inspectorOverlays(windowWidth: CGFloat) -> Bool { windowWidth < inspectorOverlayBelow }

    /// The size the main window opens at on a screen whose visible area is `area`:
    /// `current` grown to at least `window`, or to almost the whole area (96 %)
    /// when the area is smaller; never larger than the area.
    public func generousSize(current: CGSize, area: CGSize) -> CGSize {
        let w = min(max(current.width, min(window.width, (area.width * 0.96).rounded())), area.width)
        let h = min(max(current.height, min(window.height, (area.height * 0.96).rounded())), area.height)
        return CGSize(width: w, height: h)
    }
}

extension EnvironmentValues {
    /// The window frame's measures; `SVChrome.default` unless the app sets its own.
    @Entry public var svChrome: SVChrome = .default

    /// The pages' top padding under the top bar: the page title's line box puts its
    /// capitals 11 pt below its top, and from the bar's hairline the gap must look
    /// like the 28 pt at the sides.
    @Entry public var svPageTop: CGFloat = 17

    /// The window's width, set by the shell's frame (for the inspector, which
    /// overlays the page below `SVChrome.inspectorOverlayBelow`).
    @Entry public var svWindowWidth: CGFloat = SVChrome.default.window.width
}

/// Where the traffic lights go, in window coordinates (top-left origin).
public struct TrafficLightsAnchor: PreferenceKey {
    public static let defaultValue: CGRect? = nil
    public static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) { value = nextValue() ?? value }
}

/// A gap for the window's traffic lights, which report its place so the
/// window can move its real buttons there.
public struct TrafficLightsSlot: View {
    @Environment(\.svChrome) private var chrome

    public init() {}

    public var body: some View {
        Color.clear
            .frame(width: chrome.lightsWidth, height: chrome.topRowHeight)
            .background(GeometryReader { g in
                Color.clear.preference(key: TrafficLightsAnchor.self, value: g.frame(in: .global))
            })
    }
}

/// A CSS `box-shadow`: drawn only outside the shape, so a see-through fill
/// on top doesn't let it darken the panel (SwiftUI's shadow sits under it).
/// The colour is `SV.shadow` (black in dark, a softer cool ink in light).
public struct OuterShadow: View {
    var cornerRadius: CGFloat
    var opacity: Double
    /// CSS blur radius; SwiftUI's shadow radius is half of it.
    var blur: CGFloat
    var y: CGFloat

    public init(cornerRadius: CGFloat, opacity: Double, blur: CGFloat, y: CGFloat) {
        self.cornerRadius = cornerRadius
        self.opacity = opacity
        self.blur = blur
        self.y = y
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        // The fill is masked out: only its shadow is left, so its colour never shows.
        shape.fill(.black)
            .shadow(color: SV.shadow.opacity(opacity), radius: blur / 2, y: y)
            .mask {
                Rectangle().padding(-(blur + abs(y)) * 2)
                    .overlay(shape.blendMode(.destinationOut))
                    .compositingGroup()
            }
    }
}

/// A 26 pt tool button of the top bar (`.iconbtn`: the Settings gear, the
/// parameters panel of a narrow window): secondary ink, a glass tile under the
/// pointer and while `on`.
public struct ChromeIconButton: View {
    var symbol: String
    var help: String
    var on: Bool
    var action: () -> Void
    @State private var hover = false

    public init(_ symbol: String, help: String, on: Bool = false, action: @escaping () -> Void) {
        self.symbol = symbol
        self.help = help
        self.on = on
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .svFont(15)
                .foregroundStyle(on || hover ? SV.text : SV.text2)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(on ? SV.glass : hover ? SV.glassHover : .clear))
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// A page's title and its intro: the intro's two lines (of similar length, the
/// second slightly longer) while each fits whole, otherwise one paragraph.
public struct PageHeader<Trailing: View>: View {
    var title: String
    var line1: String
    var line2: String
    @ViewBuilder var trailing: () -> Trailing

    public init(_ title: String, _ line1: String, _ line2: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.line1 = line1
        self.line2 = line2
        self.trailing = trailing
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).svPageTitle()
                ViewThatFits(in: .horizontal) {
                    Text(line1 + "\n" + line2).svBody().fixedSize()
                    Text(line1 + " " + line2).svBody().fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    public init(_ title: String, _ line1: String, _ line2: String) {
        self.init(title, line1, line2) { EmptyView() }
    }
}
