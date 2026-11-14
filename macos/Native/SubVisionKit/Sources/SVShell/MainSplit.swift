// SPDX-License-Identifier: MIT
// Copied and adapted from the native macOS app of AnimeUp (AnimeUp/MainView.swift
// and TopBar.swift), by the same author: the tabs, the page and the bars come
// from the app; the measures from `SVChrome`. Design round C3 took the sidebar
// away (navigation N-A): the top bar is there at every width.

import AppKit
import SVDesign
import SwiftUI

/// One page of the app, as a segment of the top bar shows it.
public struct ShellTab: Identifiable, Hashable, Sendable {
    public var id: String
    public var symbol: String
    public var title: String
    /// Work going on in that page: a spinner in place of the icon (C3-01).
    public var busy: Bool
    /// A small number on the segment.
    public var count: Int?
    /// A thin line before this tab: it starts the group of the tools (Sub fix after the pages).
    public var separatorBefore: Bool

    public init(id: String, symbol: String, title: String, busy: Bool = false, count: Int? = nil,
                separatorBefore: Bool = false) {
        self.id = id
        self.symbol = symbol
        self.title = title
        self.busy = busy
        self.count = count
        self.separatorBefore = separatorBefore
    }
}

/// The frame (navigation N-A, design round C3): the top bar with the pages as
/// segments at every width, the page under it, and at the bottom of the window
/// the app's `bottomBar` while `showsBottomBar` (the batch bar: it slides up in
/// 0.2 s and down again when it goes).
public struct MainSplit<TopBarTrailing: View, Page: View, BottomBar: View>: View {
    var tabs: [ShellTab]
    @Binding var selection: String
    var texts: ShellTexts
    var openSettings: () -> Void
    var onClose: () -> Void
    var sizeOverride: String?
    var showsBottomBar: Bool
    @ViewBuilder var topBarTrailing: () -> TopBarTrailing
    @ViewBuilder var page: () -> Page
    @ViewBuilder var bottomBar: () -> BottomBar
    @Environment(\.svChrome) private var chrome
    @State private var lightsAnchor: CGRect?

    public init(tabs: [ShellTab], selection: Binding<String>, texts: ShellTexts = .english, sizeOverride: String? = nil,
                openSettings: @escaping () -> Void, onClose: @escaping () -> Void = {},
                showsBottomBar: Bool = false,
                @ViewBuilder topBarTrailing: @escaping () -> TopBarTrailing,
                @ViewBuilder page: @escaping () -> Page,
                @ViewBuilder bottomBar: @escaping () -> BottomBar) {
        self.tabs = tabs
        self._selection = selection
        self.texts = texts
        self.sizeOverride = sizeOverride
        self.openSettings = openSettings
        self.onClose = onClose
        self.showsBottomBar = showsBottomBar
        self.topBarTrailing = topBarTrailing
        self.page = page
        self.bottomBar = bottomBar
    }

    public var body: some View {
        GeometryReader { g in
            VStack(spacing: 0) {
                ShellTopBar(tabs: tabs, selection: $selection, texts: texts, openSettings: openSettings, trailing: topBarTrailing)
                pageBody
                    .environment(\.svPageTop, 17)
                    .environment(\.svWindowWidth, g.size.width)
                    .overlay(alignment: .top) {
                        // What scrolls under the top bar fades into it. At rest the page's
                        // own top padding is under the fade, so nothing shows.
                        LinearGradient(colors: [SV.bg, SV.bg.opacity(0)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 18)
                            .allowsHitTesting(false)
                    }
                if showsBottomBar {
                    bottomBar()
                        .frame(height: chrome.batchBarHeight)
                        .frame(maxWidth: .infinity)
                        .environment(\.svWindowWidth, g.size.width)
                        .transition(.move(edge: .bottom))
                }
            }
            .clipped()
        }
        // The minimum is the whole window's (the narrow board is 760x640, top bar included), but
        // SwiftUI adds the hidden title bar's height to the content's minimum: take it off here.
        .frame(minWidth: chrome.minWindow.width, minHeight: chrome.minWindow.height - Self.titleBarHeight)
        .background(SV.bg)
        .ignoresSafeArea()
        .background(WindowChrome(anchor: lightsAnchor, minSize: chrome.minWindow, generous: chrome,
                                 sizeOverride: sizeOverride, onClose: onClose))
        .onPreferenceChange(TrafficLightsAnchor.self) { lightsAnchor = $0 }
        .animation(.easeOut(duration: 0.2), value: showsBottomBar)
    }

    /// The height of a standard title bar, which the window adds to the content's minimum.
    private static var titleBarHeight: CGFloat {
        let content = NSRect(x: 0, y: 0, width: 100, height: 100)
        return max(0, NSWindow.frameRect(forContentRect: content, styleMask: [.titled]).height - content.height)
    }

    private var pageBody: some View {
        page()
            // The page never sets the window's height: a wrapped text measured at
            // a narrow width would otherwise make the frame taller than the window.
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            // A scrolled page must not slide under the top bar.
            .clipped()
    }
}

extension MainSplit where BottomBar == EmptyView {
    public init(tabs: [ShellTab], selection: Binding<String>, texts: ShellTexts = .english, sizeOverride: String? = nil,
                openSettings: @escaping () -> Void, onClose: @escaping () -> Void = {},
                @ViewBuilder topBarTrailing: @escaping () -> TopBarTrailing,
                @ViewBuilder page: @escaping () -> Page) {
        self.init(tabs: tabs, selection: selection, texts: texts, sizeOverride: sizeOverride, openSettings: openSettings,
                  onClose: onClose, showsBottomBar: false, topBarTrailing: topBarTrailing, page: page) { EmptyView() }
    }
}

/// The window's 52 pt top bar (`.topbar`, boards C3-01, DS4). Traffic lights on
/// the left, the pages as a segmented control in the middle (⌘1 ⌘2 ⌘3 are the
/// app's menu items), on the right the app's `trailing` and the Settings gear.
public struct ShellTopBar<Trailing: View>: View {
    var tabs: [ShellTab]
    @Binding var selection: String
    var texts: ShellTexts
    var openSettings: () -> Void
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.svChrome) private var chrome

    public init(tabs: [ShellTab], selection: Binding<String>, texts: ShellTexts = .english,
                openSettings: @escaping () -> Void, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.tabs = tabs
        self._selection = selection
        self.texts = texts
        self.openSettings = openSettings
        self.trailing = trailing
    }

    public var body: some View {
        HStack(spacing: 8) {
            TrafficLightsSlot()
                .frame(maxWidth: .infinity, alignment: .leading)
            TopBarSegments {
                ForEach(tabs) { tab in
                    if tab.separatorBefore {
                        // `.tsegs .vsep`: a hairline between the pages and the tools.
                        Rectangle().fill(SV.glassLine).frame(width: 1, height: 16).padding(.horizontal, 3)
                    }
                    TopBarSegment(symbol: tab.symbol, title: tab.title, selected: tab.id == selection,
                                  busy: tab.busy, count: tab.count) { selection = tab.id }
                }
            }
            .fixedSize()
            HStack(spacing: 8) {
                trailing()
                ChromeIconButton("gearshape", help: texts.settings, action: openSettings)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        // The lights' left edge and the gear's right edge on the page's 28 pt margins.
        .padding(.leading, 25)
        .padding(.trailing, 28)
        .frame(height: chrome.topBarHeight)
        .background(SV.bg)
        // Where the bar ends and the page that scrolls under it begins.
        .overlay(alignment: .bottom) { Rectangle().fill(SV.line).frame(height: 1) }
    }
}

/// A small status capsule for the top bar's right side: a tone with its dot (a spinner while
/// busy), or `outline`, a neutral capsule with a thin border and the text in the outline's
/// tone, no dot (the update available, beside the gear).
public struct TopBarChip: View {
    var title: String
    var tone: SVTone
    var outline: Bool
    var busy: Bool
    var action: () -> Void
    @State private var hover = false

    public init(_ title: String, tone: SVTone, busy: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.tone = tone
        self.outline = false
        self.busy = busy
        self.action = action
    }

    public init(_ title: String, outline tone: SVTone, action: @escaping () -> Void) {
        self.title = title
        self.tone = tone
        self.outline = true
        self.busy = false
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if !outline {
                    if busy { Spinner(size: 10) } else { StatusDot(tone) }
                }
                // The font's own line box: `svFont` set the words half a point low in the capsule.
                Text(title).svControlFont(11.5, outline ? .medium : .regular).lineLimit(1)
            }
            .foregroundStyle(tone.text)
            .padding(.horizontal, outline ? 10 : 9)
            .frame(height: 24)
            .background(Capsule().fill(outline ? (hover ? SV.glassHover : SV.bg) : tone.background))
            .overlay(Capsule().strokeBorder(outline ? tone.solid : tone.line, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .fixedSize()
    }
}

/// A page with only a title and a line of text (a placeholder while a page is built).
public struct PlaceholderPage: View {
    var title: String
    var symbol: String
    var text: String
    @Environment(\.svPageTop) private var top

    public init(title: String, symbol: String, text: String) {
        self.title = title
        self.symbol = symbol
        self.text = text
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).svPageTitle()
            Text(text).svBody()
            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.top, top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay {
            Image(systemName: symbol).svFont(64, .ultraLight).foregroundStyle(SV.line)
        }
    }
}
