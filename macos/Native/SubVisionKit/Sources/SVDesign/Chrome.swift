// SPDX-License-Identifier: MIT
// Copied and adapted from the design system of the native macOS app of AnimeUp
// (AnimeUpKit/DesignSystem/Chrome.swift, version 2.1), by the same author.
// The measures were constants there; here they are a configuration the app
// sets, with AnimeUp's values as the defaults.
//
// The window frame: the page on `bg`, a floating sidebar panel inset 8 pt,
// its top row holding the window's own traffic lights and the Settings gear.

import SwiftUI

/// Measures of the window frame. The app puts its own in the environment
/// (`.environment(\.svChrome, …)`); the components read them from there.
public struct SVChrome: Sendable, Equatable {
    /// The sidebar panel: width, inset from the window edge, inner padding, row gap.
    public var sidebarWidth: CGFloat = 236
    public var sidebarInset: CGFloat = 8
    public var sidebarPadding = EdgeInsets(top: 12, leading: 10, bottom: 12, trailing: 10)
    public var sidebarSpacing: CGFloat = 14
    /// The sidebar's top row: traffic lights on the left, gear on the right.
    public var topRowHeight: CGFloat = 24
    public var topRowPadding: CGFloat = 4
    /// The main area: page padding.
    public var page = EdgeInsets(top: 28, leading: 28, bottom: 28, trailing: 28)
    /// Below this window width the sidebar folds away into a top bar.
    public var collapseBelow: CGFloat = 1240
    /// The smallest window: the pages are laid out for it.
    public var minWindow = CGSize(width: 720, height: 640)
    /// Width the traffic lights take in the top row (three 14 pt buttons, 6 pt apart).
    public var lightsWidth: CGFloat = 54

    /// AnimeUp's measures, the starting point.
    public static let `default` = SVChrome()

    public init(sidebarWidth: CGFloat = 236, sidebarInset: CGFloat = 8,
                sidebarPadding: EdgeInsets = EdgeInsets(top: 12, leading: 10, bottom: 12, trailing: 10),
                sidebarSpacing: CGFloat = 14, topRowHeight: CGFloat = 24, topRowPadding: CGFloat = 4,
                page: EdgeInsets = EdgeInsets(top: 28, leading: 28, bottom: 28, trailing: 28),
                collapseBelow: CGFloat = 1240, minWindow: CGSize = CGSize(width: 720, height: 640),
                lightsWidth: CGFloat = 54) {
        self.sidebarWidth = sidebarWidth
        self.sidebarInset = sidebarInset
        self.sidebarPadding = sidebarPadding
        self.sidebarSpacing = sidebarSpacing
        self.topRowHeight = topRowHeight
        self.topRowPadding = topRowPadding
        self.page = page
        self.collapseBelow = collapseBelow
        self.minWindow = minWindow
        self.lightsWidth = lightsWidth
    }
}

extension EnvironmentValues {
    /// The window frame's measures; `SVChrome.default` unless the app sets its own.
    @Entry public var svChrome: SVChrome = .default

    /// The pages' top padding (`page.top`, 28 pt). Under the top bar it is
    /// smaller: the page title's line box puts its capitals 11 pt below its top,
    /// and from the bar's hairline the gap must look like the 28 pt at the sides.
    @Entry public var svPageTop: CGFloat = 28
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

/// The floating sidebar panel. `side` over `bg`, a hairline and a soft shadow.
public struct SidebarPanel<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @Environment(\.svChrome) private var chrome

    public init(@ViewBuilder content: @escaping () -> Content) { self.content = content }

    public var body: some View {
        VStack(alignment: .leading, spacing: chrome.sidebarSpacing) { content() }
            .frame(maxHeight: .infinity, alignment: .top)
            .svBox(RoundedRectangle(cornerRadius: SV.Radius.sidebar), fill: SV.side, line: SV.glassLine,
                   padding: chrome.sidebarPadding)
            .frame(width: chrome.sidebarWidth)
            .background { OuterShadow(cornerRadius: SV.Radius.sidebar, opacity: 0.35, blur: 24, y: 8) }
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

/// The 26 pt round tool button of the sidebar's top row (the Settings gear).
public struct ChromeIconButton: View {
    var symbol: String
    var help: String
    var action: () -> Void
    @State private var hover = false

    public init(_ symbol: String, help: String, action: @escaping () -> Void) {
        self.symbol = symbol
        self.help = help
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .svFont(13)
                .foregroundStyle(SV.text)
                .frame(width: 26, height: 26)
                .background(Circle().fill(hover ? SV.glassHover : SV.glass))
                .overlay(Circle().strokeBorder(SV.glassLine, lineWidth: 1))
                .contentShape(Circle())
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
