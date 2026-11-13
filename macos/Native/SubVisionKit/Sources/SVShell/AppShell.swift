// SPDX-License-Identifier: MIT
// Copied and adapted from the native macOS app of AnimeUp (AnimeUp/AnimeUpApp.swift
// and AppModel.swift), by the same author: the delegate's decisions are closures
// the app sets, and the theme is read from the app's own defaults.

import AppKit
import SwiftUI

/// The app delegate of the frame. The red button closes the window and the app
/// keeps running; ⌘Q quits, unless `quitBlocker` says the person changed their
/// mind; the Dock icon reopens the window and shows `dockMenu`.
@MainActor
public final class ShellAppDelegate: NSObject, NSApplicationDelegate {
    /// Asked on ⌘Q. Return true to cancel the quit (after a confirmation, say).
    public var quitBlocker: @MainActor () -> Bool = { false }
    /// The Dock icon's menu, built fresh each time it opens; nil for none.
    public var dockMenu: @MainActor () -> [DockMenuEntry] = { [] }
    /// Set by the main window, so the Dock icon can reopen it.
    public var reopenMainWindow: @MainActor () -> Void = {}
    /// Last thing before the process ends: the engine goes with the app.
    public var willTerminate: @MainActor () -> Void = {}
    /// Before any window: the saved appearance, so nothing flashes the other one.
    public var willFinishLaunching: @MainActor () -> Void = {}

    public override init() {}

    public func applicationWillFinishLaunching(_ notification: Notification) {
        willFinishLaunching()
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        quitBlocker() ? .terminateCancel : .terminateNow
    }

    public func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let entries = dockMenu()
        guard !entries.isEmpty else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        for entry in entries {
            switch entry {
            case .separator: menu.addItem(.separator())
            case .item(let title, let run): menu.addItem(DockAction(title, run))
            case .label(let title):
                // Text only, dimmed like a disabled item (board O10).
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }
        return menu
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { reopenMainWindow() }
        return true
    }

    public func applicationWillTerminate(_ notification: Notification) {
        willTerminate()
    }
}

public enum DockMenuEntry {
    case item(String, @MainActor () -> Void)
    /// A line that only says something (the file in progress): dimmed, not clickable.
    case label(String)
    case separator
}

/// A menu item that runs a closure.
final class DockAction: NSMenuItem {
    private let run: @MainActor () -> Void

    init(_ title: String, _ run: @escaping @MainActor () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { MainActor.assumeIsolated { run() } }
}

/// Settings › General › Appearance: System follows macOS, Light and Dark pin it.
@MainActor
public enum ShellTheme {
    public static func apply(_ theme: String?) {
        switch theme {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    /// The theme saved in the app's defaults (`system`, `light`, `dark`; the
    /// `@AppStorage` of Settings › General), applied before the window opens.
    public static func applySaved(defaults: UserDefaults = .standard, key: String = "theme") {
        apply(defaults.string(forKey: key))
    }

    /// The appearance in force now, as a colour scheme.
    public static var scheme: ColorScheme {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }
}

/// The main window scene of the frame: hidden title bar, the app's size,
/// resizable down to the content's minimum.
public struct ShellWindow<Content: View>: Scene {
    var config: AppShellConfig
    var content: () -> Content

    public init(config: AppShellConfig, @ViewBuilder content: @escaping () -> Content) {
        self.config = config
        self.content = content
    }

    public var body: some Scene {
        Window(config.appName, id: config.mainWindowID) {
            content().environment(\.svChrome, config.chrome)
        }
        .defaultSize(width: config.windowSize.width, height: config.windowSize.height)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
    }
}

/// The standard About panel: a line about the app (`app.menu.about_credits`),
/// then a link to the project, under the version.
@MainActor
public func showAboutPanel(repositoryURL: URL, credits line: String? = nil) {
    let small = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    let text = repositoryURL.absoluteString.replacingOccurrences(of: "https://", with: "")
    let credits = NSMutableAttributedString()
    if let line, !line.isEmpty {
        credits.append(NSAttributedString(string: line + "\n", attributes: [.font: small, .foregroundColor: NSColor.labelColor]))
    }
    credits.append(NSAttributedString(string: text, attributes: [.link: repositoryURL, .font: small]))
    let centred = NSMutableParagraphStyle(); centred.alignment = .center
    credits.addAttribute(.paragraphStyle, value: centred, range: NSRange(location: 0, length: credits.length))
    NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    NSApp.activate()
}

/// Alerts opened by a button wait for the click to finish: a modal loop started
/// inside the button's own gesture leaves AppKit tracking that click, and the
/// alert's buttons never get theirs.
@MainActor
public func afterClick(_ show: @escaping @MainActor () -> Void) {
    DispatchQueue.main.async { show() }
}
