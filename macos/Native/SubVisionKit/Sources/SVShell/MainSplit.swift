// SPDX-License-Identifier: MIT
// Copied and adapted from the native macOS app of AnimeUp (AnimeUp/MainView.swift,
// TopBar.swift and SidebarView.swift), by the same author: the tabs, the page
// and the sidebar's extra content come from the app; the measures from `SVChrome`.

import AppKit
import SVDesign
import SwiftUI

/// One page of the app, as the sidebar and the top bar show it.
public struct ShellTab: Identifiable, Hashable, Sendable {
    public var id: String
    public var symbol: String
    public var title: String
    public var subtitle: String
    /// Work going on in that page: a spinner.
    public var busy: Bool
    /// A check on the sidebar tab (something finished there).
    public var done: Bool
    /// A small number on the top bar segment (files waiting).
    public var count: Int?

    public init(id: String, symbol: String, title: String, subtitle: String = "",
                busy: Bool = false, done: Bool = false, count: Int? = nil) {
        self.id = id
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.busy = busy
        self.done = done
        self.count = count
    }
}

/// The sidebar's footer: version, Check for Updates, the project on GitHub.
public struct ShellFooter {
    public var appVersion: String
    /// `hello.version` and `hello.python`, for the tooltip.
    public var engineVersion: String?
    public var pythonVersion: String?
    public var checkingUpdates: Bool
    public var repositoryURL: URL
    public var checkUpdates: @MainActor () -> Void

    public init(appVersion: String, engineVersion: String? = nil, pythonVersion: String? = nil, checkingUpdates: Bool = false,
                repositoryURL: URL, checkUpdates: @escaping @MainActor () -> Void) {
        self.appVersion = appVersion
        self.engineVersion = engineVersion
        self.pythonVersion = pythonVersion
        self.checkingUpdates = checkingUpdates
        self.repositoryURL = repositoryURL
        self.checkUpdates = checkUpdates
    }
}

/// The frame: the sidebar panel and the page on `bg`. Below
/// `SVChrome.collapseBelow` the sidebar folds away and the top bar takes its
/// place; in a wide window it can also be hidden from View (`sidebarChoice`).
public struct MainSplit<SidebarExtra: View, TopBarTrailing: View, Page: View>: View {
    var tabs: [ShellTab]
    @Binding var selection: String
    /// The sidebar as the person set it from View, in a wide window; nil keeps it shown.
    @Binding var sidebarChoice: Bool?
    var texts: ShellTexts
    var footer: ShellFooter
    var openSettings: () -> Void
    var onClose: () -> Void
    var sizeOverride: String?
    /// Told whether the window is narrow (no sidebar possible) and whether the sidebar shows.
    var layoutChanged: (_ narrow: Bool, _ sidebarShown: Bool) -> Void
    @ViewBuilder var sidebarExtra: () -> SidebarExtra
    @ViewBuilder var topBarTrailing: () -> TopBarTrailing
    @ViewBuilder var page: () -> Page
    @Environment(\.svChrome) private var chrome
    @State private var lightsAnchor: CGRect?

    public init(tabs: [ShellTab], selection: Binding<String>, sidebarChoice: Binding<Bool?>,
                texts: ShellTexts = .english, footer: ShellFooter, sizeOverride: String? = nil,
                openSettings: @escaping () -> Void, onClose: @escaping () -> Void = {},
                layoutChanged: @escaping (_ narrow: Bool, _ sidebarShown: Bool) -> Void = { _, _ in },
                @ViewBuilder sidebarExtra: @escaping () -> SidebarExtra,
                @ViewBuilder topBarTrailing: @escaping () -> TopBarTrailing,
                @ViewBuilder page: @escaping () -> Page) {
        self.tabs = tabs
        self._selection = selection
        self._sidebarChoice = sidebarChoice
        self.texts = texts
        self.footer = footer
        self.sizeOverride = sizeOverride
        self.openSettings = openSettings
        self.onClose = onClose
        self.layoutChanged = layoutChanged
        self.sidebarExtra = sidebarExtra
        self.topBarTrailing = topBarTrailing
        self.page = page
    }

    public var body: some View {
        GeometryReader { g in
            let narrow = g.size.width < chrome.collapseBelow
            let inline = !narrow && (sidebarChoice ?? true)
            HStack(spacing: 0) {
                if inline {
                    ShellSidebar(tabs: tabs, selection: $selection, texts: texts, footer: footer,
                                 openSettings: openSettings, extra: sidebarExtra)
                        .padding([.leading, .top, .bottom], chrome.sidebarInset)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                VStack(spacing: 0) {
                    if !inline {
                        ShellTopBar(tabs: tabs, selection: $selection, texts: texts, canShowSidebar: !narrow,
                                    showSidebar: { sidebarChoice = true }, openSettings: openSettings, trailing: topBarTrailing)
                    }
                    pageBody
                        .environment(\.svPageTop, inline ? chrome.page.top : 17)
                        .environment(\.svWindowWidth, g.size.width)
                        .overlay(alignment: .top) {
                        // What scrolls under the top bar fades into it. At rest the page's
                        // own top padding is under the fade, so nothing shows.
                        if !inline {
                            LinearGradient(colors: [SV.bg, SV.bg.opacity(0)], startPoint: .top, endPoint: .bottom)
                                .frame(height: 18)
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
            .onChange(of: narrow, initial: true) { _, now in layoutChanged(now, inline) }
            .onChange(of: inline, initial: true) { _, now in layoutChanged(narrow, now) }
        }
        .background(SV.bg)
        .ignoresSafeArea()
        .background(WindowChrome(anchor: lightsAnchor, minSize: chrome.minWindow, sizeOverride: sizeOverride, onClose: onClose))
        .onPreferenceChange(TrafficLightsAnchor.self) { lightsAnchor = $0 }
        .animation(.easeOut(duration: 0.2), value: sidebarChoice)
        .frame(minWidth: chrome.minWindow.width, minHeight: chrome.minWindow.height)
    }

    private var pageBody: some View {
        page()
            // The page never sets the window's height: a wrapped text measured at
            // a narrow width would otherwise make the frame taller than the window.
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            // Pages reach up under the title bar; with the sidebar folded, the top bar
            // sits there instead, and a scrolled page must not slide under it.
            .clipped()
    }
}

/// The glass sidebar: traffic lights and the Settings gear on the top row,
/// the tabs, the app's extra content (status lines, an activity card) and the footer.
public struct ShellSidebar<Extra: View>: View {
    var tabs: [ShellTab]
    @Binding var selection: String
    var texts: ShellTexts
    var footer: ShellFooter
    var openSettings: () -> Void
    @ViewBuilder var extra: () -> Extra
    @Environment(\.svChrome) private var chrome

    public init(tabs: [ShellTab], selection: Binding<String>, texts: ShellTexts = .english, footer: ShellFooter,
                openSettings: @escaping () -> Void, @ViewBuilder extra: @escaping () -> Extra) {
        self.tabs = tabs
        self._selection = selection
        self.texts = texts
        self.footer = footer
        self.openSettings = openSettings
        self.extra = extra
    }

    public var body: some View {
        SidebarPanel {
            HStack(spacing: 8) {
                TrafficLightsSlot()
                Spacer(minLength: 0)
                ChromeIconButton("gearshape", help: texts.settings, action: openSettings)
            }
            .frame(height: chrome.topRowHeight)
            .padding(.horizontal, chrome.topRowPadding)
            VStack(spacing: 2) {
                ForEach(tabs) { tab in
                    SidebarTab(symbol: tab.symbol, title: tab.title, subtitle: tab.subtitle, selected: tab.id == selection,
                               trailing: tab.busy ? .busy : tab.done && tab.id != selection ? .done : .none) {
                        selection = tab.id
                    }
                }
            }
            extra()
            Spacer(minLength: 12)
            ShellFooterView(footer: footer, texts: texts)
        }
    }
}

/// The sidebar footer: version (the engine's in the tooltip), Check for Updates, GitHub.
struct ShellFooterView: View {
    var footer: ShellFooter
    var texts: ShellTexts

    var body: some View {
        HStack(spacing: 8) {
            Text(ShellTexts.fill(texts.version, ["version": footer.appVersion]))
                .svFont(SVFont.smallNumbers).foregroundStyle(SV.text3)
                .help(ShellTexts.fill(texts.engineVersion, ["version": footer.engineVersion ?? "…", "python": footer.pythonVersion ?? "…"]))
            FooterLink(help: texts.checkUpdates, action: footer.checkUpdates) {
                if footer.checkingUpdates {
                    Spinner(size: 10)
                } else {
                    Image(systemName: "arrow.clockwise").svFont(10, .medium)
                }
            }
            .disabled(footer.checkingUpdates)
            Spacer(minLength: 0)
            FooterLink(help: footer.repositoryURL.absoluteString.replacingOccurrences(of: "https://", with: ""),
                       action: { NSWorkspace.shared.open(footer.repositoryURL) }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right").svFont(10, .medium)
                    Text(texts.github).svFont(11)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 2)
    }
}

/// The sidebar footer's small links: tertiary text, brighter under the pointer,
/// which becomes the pointing hand.
public struct FooterLink<Label: View>: View {
    var help: String
    var action: @MainActor () -> Void
    @ViewBuilder var label: Label
    @State private var hover = false

    public init(help: String, action: @escaping @MainActor () -> Void, @ViewBuilder label: () -> Label) {
        self.help = help
        self.action = action
        self.label = label()
    }

    public var body: some View {
        Button(action: action) {
            label
                .foregroundStyle(hover ? SV.text : SV.text3)
                .padding(3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(-3)
        .onHover { hover = $0 }
        .svPointingHand()
        .help(help)
    }
}

/// With the sidebar folded (a narrow window, or hidden from View), a 52 pt row
/// takes its place. Traffic lights on the left, the pages as a segmented
/// control in the middle, on the right the app's `trailing` and the Settings gear.
public struct ShellTopBar<Trailing: View>: View {
    var tabs: [ShellTab]
    @Binding var selection: String
    var texts: ShellTexts
    /// The window is wide enough for the sidebar: offer the button that brings it back.
    var canShowSidebar: Bool
    var showSidebar: () -> Void
    var openSettings: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    public init(tabs: [ShellTab], selection: Binding<String>, texts: ShellTexts = .english, canShowSidebar: Bool,
                showSidebar: @escaping () -> Void, openSettings: @escaping () -> Void,
                @ViewBuilder trailing: @escaping () -> Trailing) {
        self.tabs = tabs
        self._selection = selection
        self.texts = texts
        self.canShowSidebar = canShowSidebar
        self.showSidebar = showSidebar
        self.openSettings = openSettings
        self.trailing = trailing
    }

    public var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 16) {
                TrafficLightsSlot()
                if canShowSidebar {
                    ChromeIconButton("sidebar.left", help: texts.showSidebar, action: showSidebar)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            TopBarSegments {
                ForEach(tabs) { tab in
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
        .frame(height: 52)
        // Where the bar ends and the page that scrolls under it begins.
        .overlay(alignment: .bottom) { Rectangle().fill(SV.line).frame(height: 1) }
    }
}

/// A small status capsule for the top bar's right side (a tone, a word, a spinner while busy).
public struct TopBarChip: View {
    var title: String
    var tone: SVTone
    var busy: Bool
    var action: () -> Void

    public init(_ title: String, tone: SVTone, busy: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.tone = tone
        self.busy = busy
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if busy { Spinner(size: 10) } else { StatusDot(tone) }
                Text(title).svFont(11.5).lineLimit(1)
            }
            .foregroundStyle(tone.text)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Capsule().fill(tone.background))
            .overlay(Capsule().strokeBorder(tone.line))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
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
