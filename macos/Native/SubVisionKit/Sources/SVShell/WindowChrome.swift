// SPDX-License-Identifier: MIT
// Copied and adapted from the native macOS app of AnimeUp (AnimeUp/WindowChrome.swift
// and AppModel+Tools.swift `WindowSizer`), by the same author: the measures come
// from `SVChrome` and `AppShellConfig` instead of constants.

import AppKit
import SVDesign
import SwiftUI

/// Gives the main window the design's frame: no title bar of its own, the
/// content under it, and the real traffic lights moved into the
/// `TrafficLightsSlot` the page reports (the sidebar's top row, or the top
/// bar when the sidebar is folded).
public struct WindowChrome: NSViewRepresentable {
    /// The slot in window coordinates, top-left origin.
    public var anchor: CGRect?
    public var minSize: CGSize
    /// `<PREFIX>WINDOW=1000x680`: open at that size, to check the layout at other sizes.
    public var sizeOverride: String?
    /// Called when the window closes (the red button or ⌘W): the app keeps running.
    public var onClose: () -> Void

    public init(anchor: CGRect?, minSize: CGSize = SVChrome.default.minWindow, sizeOverride: String? = nil,
                onClose: @escaping () -> Void = {}) {
        self.anchor = anchor
        self.minSize = minSize
        self.sizeOverride = sizeOverride
        self.onClose = onClose
    }

    public func makeNSView(context: Context) -> ChromeView {
        let view = ChromeView()
        view.minSize = minSize
        view.sizeOverride = sizeOverride
        return view
    }

    public func updateNSView(_ view: ChromeView, context: Context) {
        view.anchor = anchor
        view.minSize = minSize
        view.onClose = onClose
        view.placeLights()
    }

    public final class ChromeView: NSView {
        var anchor: CGRect?
        var minSize = SVChrome.default.minWindow
        var sizeOverride: String?
        var onClose: () -> Void = {}
        private var observers: [NSObjectProtocol] = []

        public override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = false
            window.minSize = minSize
            if let spec = sizeOverride,
               case let parts = spec.split(separator: "x").compactMap({ Double($0) }), parts.count == 2 {
                // After the window's saved frame has been restored.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    window.setContentSize(NSSize(width: parts[0], height: parts[1]))
                }
            }
            // AppKit lays the title bar out again on these: put the buttons back each time.
            let names: [Notification.Name] = [NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification,
                                              NSWindow.didResignKeyNotification, NSWindow.didExitFullScreenNotification,
                                              NSWindow.didChangeScreenNotification]
            for name in names {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.placeLights() }
                })
            }
            observers.append(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onClose() }
            })
            placeLights()
        }

        /// A theme switch (Settings › Appearance, or macOS) lays the title bar
        /// out again: the buttons go back to their slot after it.
        public override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            DispatchQueue.main.async { [weak self] in self?.placeLights() }
        }

        /// Centres the three buttons in the slot, 20 pt apart (12 pt dots, 8 pt gaps).
        func placeLights() {
            guard let window, let anchor, !window.styleMask.contains(.fullScreen) else { return }
            let kinds: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
            let contentHeight = window.contentView?.bounds.height ?? window.frame.height
            growTitleBar(window, toCover: anchor.maxY + 6, contentHeight: contentHeight)
            for (i, kind) in kinds.enumerated() {
                guard let button = window.standardWindowButton(kind), let parent = button.superview else { continue }
                let centre = NSPoint(x: anchor.minX + 10 + CGFloat(i) * 20, y: contentHeight - anchor.midY)
                let local = parent.convert(centre, from: nil)
                button.setFrameOrigin(NSPoint(x: (local.x - button.frame.width / 2).rounded(),
                                              y: (local.y - button.frame.height / 2).rounded()))
            }
        }

        /// The buttons live in the title bar view, about 28 pt tall. Moved lower than
        /// that, half of each button fell outside it: clicks and hover only worked on
        /// its top part. The title bar (and its container) grows to reach the slot.
        private func growTitleBar(_ window: NSWindow, toCover height: CGFloat, contentHeight: CGFloat) {
            guard let titleBar = window.standardWindowButton(.closeButton)?.superview,
                  let container = titleBar.superview else { return }
            let needed = ceil(height)
            guard abs(container.frame.height - needed) > 0.5 || abs(titleBar.frame.height - needed) > 0.5 else { return }
            var frame = container.frame
            frame.origin.y = frame.maxY - needed
            frame.size.height = needed
            container.frame = frame
            titleBar.frame = container.bounds
        }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}

/// Resizes the main window between the tools window and the app, centred
/// on the screen it is on and always inside that screen's visible area.
@MainActor
public enum WindowSizer {
    /// The main window: by its scene identifier, else by the app's name.
    public static func main(_ config: AppShellConfig) -> NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(config.mainWindowID) == true }
            ?? NSApp.windows.first { $0.title == config.appName }
    }

    public static func toTools(_ config: AppShellConfig) {
        place(config, config.toolsWindowSize, min: config.toolsWindowMinSize)
    }

    public static func toMain(_ config: AppShellConfig) {
        place(config, config.windowSize, min: config.chrome.minWindow, save: true)
    }

    /// On the next turn of the run loop: by then the window is on a screen and
    /// AppKit has applied its own first frame, which would otherwise win.
    /// `save`: the frame is written under the window's autosave name once the animation is over.
    /// An animated `setFrame` is not saved by AppKit, so the next launch reopened the window at
    /// the tools window's size (stored when the tools window opened), clamped to the minimum.
    private static func place(_ config: AppShellConfig, _ size: CGSize, min: CGSize, save: Bool = false) {
        DispatchQueue.main.async {
            guard let w = main(config), let screen = w.screen ?? NSScreen.main else { return }
            let area = screen.visibleFrame
            w.minSize = min
            var frame = w.frameRect(forContentRect: NSRect(origin: .zero, size: size))
            frame.size.width = Swift.min(frame.width, area.width)
            frame.size.height = Swift.min(frame.height, area.height)
            frame.origin = NSPoint(x: (area.midX - frame.width / 2).rounded(), y: (area.midY - frame.height / 2).rounded())
            w.setFrame(frame, display: true, animate: w.isVisible)
            if save, !w.frameAutosaveName.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + w.animationResizeTime(frame) + 0.2) {
                    w.saveFrame(usingName: w.frameAutosaveName)
                }
            }
        }
    }
}
