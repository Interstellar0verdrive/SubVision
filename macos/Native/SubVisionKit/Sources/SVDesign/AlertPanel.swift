// SPDX-License-Identifier: MIT
// Copied and adapted from the design system of the native macOS app of AnimeUp
// (AnimeUpKit/DesignSystem/AlertPanel.swift, version 2.1), by the same author.
// There the icons came from the app's asset catalog through `Bundle.main`; here
// the app hands in an `AlertIconSource`, with a default that still looks in
// `Bundle.main` and falls back to an SF symbol.
//
// The app's own alert, chosen over the native one: a 280 pt card, symbol at
// 40 pt in the status colour, centred title and text, buttons stacked at full
// width. `runModal()` is synchronous like NSAlert's, so it works inside
// applicationShouldTerminate too. `present(over:completion:)` shows the same
// card without a modal loop: the main actor keeps running under it (the
// engine's events, the timers), and the alert can be closed from code.

import AppKit
import SwiftUI

/// Where an alert's 40 pt icon comes from, by name.
public struct AlertIconSource: Sendable {
    /// The image for an icon name, or nil when the source has none.
    public var image: @Sendable (String) -> Image?

    public init(_ image: @escaping @Sendable (String) -> Image?) {
        self.image = image
    }

    /// A template image named `AlertIcons/<name>` in the app's asset catalog; when
    /// the catalog has none, the SF symbol of `symbols[name]`, or `fallbackSymbol`.
    public static let `default` = AlertIconSource.bundle(.main)

    /// Like `default`, from another bundle (tests, a package's resources).
    public static func bundle(_ bundle: Bundle, prefix: String = "AlertIcons/") -> AlertIconSource {
        let bundle = UncheckedBundle(bundle)
        return AlertIconSource { name in
            if bundle.value.image(forResource: prefix + name) != nil {
                return Image(prefix + name, bundle: bundle.value).renderingMode(.template)
            }
            return symbols.image(name)
        }
    }

    /// SF symbols only, no catalog.
    public static let symbols = AlertIconSource { name in
        Image(systemName: symbolNames[name] ?? fallbackSymbol)
    }

    /// The symbol in place of a missing icon, by icon name (`AlertIconName`).
    public static let symbolNames: [String: String] = [
        AlertIconName.stopFile: "stop.circle", AlertIconName.stopAll: "stop.circle",
        AlertIconName.quit: "power", AlertIconName.windowClose: "xmark.circle",
        AlertIconName.folderEmpty: "folder", AlertIconName.error: "exclamationmark.triangle",
        AlertIconName.info: "info.circle", AlertIconName.update: "arrow.down.circle",
        AlertIconName.toolMissing: "wrench.and.screwdriver", AlertIconName.vision: "text.viewfinder",
        AlertIconName.language: "globe",
    ]
    public static let fallbackSymbol = "exclamationmark.circle"
}

/// The icons of SubVision's alerts (design inventory, §8): the names of the
/// template images `AlertIcons/<name>` in the app's asset catalog.
public enum AlertIconName {
    /// O1 Stop this file.
    public static let stopFile = "stop-file"
    /// O2 Stop all.
    public static let stopAll = "stop-all"
    /// O3 Quit with a batch running.
    public static let quit = "quit"
    /// O4 Close the window with a batch running.
    public static let windowClose = "window-close"
    /// O8a A folder with no videos.
    public static let folderEmpty = "folder-empty"
    /// The revised SRT could not be saved (R3), and other errors.
    public static let error = "error"
    /// O8b, O8c.
    public static let info = "info"
    /// O8d, in its three tones.
    public static let update = "update"
    /// O5a, O5b: ffmpeg gone or not answering.
    public static let toolMissing = "tool-missing"
    /// O6: Vision does not load.
    public static let vision = "vision"
    /// O7: the OCR language is not one of this Mac's.
    public static let language = "language"

    public static let all = [stopFile, stopAll, quit, windowClose, folderEmpty, error, info, update,
                             toolMissing, vision, language]
}

/// `Bundle` is not `Sendable`; it is immutable for our use.
private struct UncheckedBundle: @unchecked Sendable {
    let value: Bundle
    init(_ value: Bundle) { self.value = value }
}

/// What a button of the alert does.
public struct SVAlertButton {
    public var title: String
    public var role: SVButtonRole
    /// Esc presses it; the last button is the cancel button unless one says so.
    public var cancel: Bool

    public init(_ title: String, role: SVButtonRole = .secondary, cancel: Bool = false) {
        self.title = title
        self.role = role
        self.cancel = cancel
    }
}

@MainActor
public final class SVAlert {
    /// The icon source every alert uses unless given its own: the app sets it once at launch.
    public static var iconSource: AlertIconSource = .default

    /// The icon's name in the source ("stop-file", "error", …).
    public var icon: String
    public var tone: SVTone
    public var title: String
    public var texts: [String]
    public private(set) var buttons: [SVAlertButton] = []
    /// An optional "Don't show again" box under the buttons, and whether it was ticked.
    public var checkbox: String?
    public fileprivate(set) var checked = false
    public var iconSource: AlertIconSource

    public init(icon: String, tone: SVTone, title: String, text: String, iconSource: AlertIconSource? = nil) {
        self.icon = icon
        self.tone = tone
        self.title = title
        // One paragraph per line of the text.
        self.texts = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        self.iconSource = iconSource ?? Self.iconSource
    }

    /// The first button added is the default one (Return).
    public func button(_ title: String, role: SVButtonRole = .secondary, cancel: Bool = false) {
        buttons.append(SVAlertButton(title, role: role, cancel: cancel))
    }

    var image: Image {
        iconSource.image(icon) ?? AlertIconSource.symbols.image(icon) ?? Image(systemName: AlertIconSource.fallbackSymbol)
    }

    /// Shows the alert over the main window and returns the index of the button pressed.
    @discardableResult
    public func runModal() -> Int {
        let cancelIndex = buttons.lastIndex(where: \.cancel) ?? (buttons.count > 1 ? buttons.count - 1 : 0)
        let panel = AlertWindow(cancelIndex: cancelIndex)
        let card = SVAlertCard(alert: self) { index in NSApp.stopModal(withCode: .init(rawValue: 1000 + index)) }
        let host = NSHostingView(rootView: card.padding(AlertWindow.margin))
        host.frame.size = host.fittingSize
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
        panel.place(over: NSApp.mainWindow ?? NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible })
        panel.makeKeyAndOrderFront(nil)
        let response = NSApp.runModal(for: panel)
        panel.orderOut(nil)
        return max(0, response.rawValue - 1000)
    }

    /// Shows the alert over `window` (the main window when nil) and returns at
    /// once: no modal loop, so whatever runs on the main actor keeps running
    /// while the alert is up. `completion` gets the index of the button pressed
    /// (Return presses the first, Esc the cancel one, as in `runModal()`); it is
    /// not called when the alert is closed from code with `close()`.
    @discardableResult
    public func present(over window: NSWindow? = nil, completion: @escaping @MainActor (Int) -> Void) -> SVAlertPresentation {
        let cancelIndex = buttons.lastIndex(where: \.cancel) ?? (buttons.count > 1 ? buttons.count - 1 : 0)
        let panel = AlertWindow(cancelIndex: cancelIndex)
        let parent = window ?? NSApp.mainWindow ?? NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible && !($0 is AlertWindow) }
        let presentation = SVAlertPresentation(alert: self, panel: panel, parent: parent, completion: completion)
        // The panel keeps the presentation alive while it is up; `close()` breaks the cycle.
        panel.onPress = { index in presentation.press(index) }
        let card = SVAlertCard(alert: self) { [weak presentation] index in presentation?.press(index) }
        let host = NSHostingView(rootView: card.padding(AlertWindow.margin))
        host.frame.size = host.fittingSize
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
        // A panel hides when the app is not the active one: this one stays, as a sheet would.
        panel.hidesOnDeactivate = false
        panel.level = parent == nil ? .floating : .normal
        panel.place(over: parent)
        // A child of the window: above it, and it follows the window around.
        parent?.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        presentation.watchParent()
        return presentation
    }
}

/// An alert shown with `SVAlert.present`: open until a button is pressed, the
/// window under it closes, or `close()`.
@MainActor
public final class SVAlertPresentation {
    public let alert: SVAlert
    private let panel: AlertWindow
    private weak var parent: NSWindow?
    private var completion: (@MainActor (Int) -> Void)?
    private var observer: NSObjectProtocol?
    public private(set) var isOpen = true

    init(alert: SVAlert, panel: AlertWindow, parent: NSWindow?, completion: @escaping @MainActor (Int) -> Void) {
        self.alert = alert
        self.panel = panel
        self.parent = parent
        self.completion = completion
    }

    /// The panel's window number, for a capture of the alert alone.
    public var windowNumber: Int { panel.windowNumber }

    /// The window under the alert closed: that is a cancel.
    func watchParent() {
        guard let parent else { return }
        observer = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: parent, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.press(self?.panel.cancelIndex ?? 0) }
        }
    }

    /// As if the button at `index` had been pressed: closes the alert and calls the completion.
    public func press(_ index: Int) {
        guard isOpen, alert.buttons.indices.contains(index) else { return }
        let done = completion
        close()
        done?(index)
    }

    /// Brings the alert back in front, with the keyboard.
    public func focus() {
        guard isOpen else { return }
        panel.makeKeyAndOrderFront(nil)
    }

    /// Closes the alert without an answer: the completion is not called.
    public func close() {
        guard isOpen else { return }
        isOpen = false
        completion = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        panel.onPress = nil
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        // The keyboard goes back to the window the alert was over.
        if let parent, parent.isVisible, NSApp.keyWindow == nil || NSApp.keyWindow === panel { parent.makeKey() }
    }
}

/// A borderless, see-through panel: the card draws its own shape and shadow.
final class AlertWindow: NSPanel {
    /// Room around the card for its shadow (blur 60, 24 down): with less, the panel's edge cuts it
    /// into a hard grey rectangle, visible in light.
    static let margin: CGFloat = 84
    let cancelIndex: Int
    /// Set by `present`: a press (Esc here, the buttons through the card) without a modal loop.
    var onPress: ((Int) -> Void)?

    init(cancelIndex: Int) {
        self.cancelIndex = cancelIndex
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .modalPanel
        // Not movable by its background: a SwiftUI host lets AppKit start a window
        // drag on mouse-down, and the buttons never got the click.
        isMovableByWindowBackground = false
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        if let onPress { onPress(cancelIndex) } else { NSApp.stopModal(withCode: .init(rawValue: 1000 + cancelIndex)) }
    }

    /// Esc reaches a borderless panel as a plain key: it is the cancel button.
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancelOperation(nil) } else { super.keyDown(with: event) }
    }

    /// Centred on the window, its top a third of the way down, as macOS places alerts.
    func place(over window: NSWindow?) {
        guard let window else { center(); return }
        let w = window.frame, s = frame.size
        setFrameOrigin(NSPoint(x: (w.midX - s.width / 2).rounded(), y: (w.maxY - w.height / 3 - s.height / 2).rounded()))
    }
}

/// The alert's card on its own, without the modal panel: what `runModal()`
/// shows, also usable in a preview, a design board or a gallery.
public struct SVAlertCard: View {
    let alert: SVAlert
    let press: (Int) -> Void
    @State private var checked = false
    /// 280 pt card, 1 pt line, 16 pt padding each side.
    static let textWidth: CGFloat = 280 - 2 - 32

    public init(alert: SVAlert, press: @escaping (Int) -> Void = { _ in }) {
        self.alert = alert
        self.press = press
    }

    public var body: some View {
        VStack(spacing: 8) {
            alert.image
                .renderingMode(.template)
                .resizable().scaledToFit()
                .frame(width: 40, height: 40)
                .foregroundStyle(alert.tone.text)
                .padding(.bottom, 4)
            // Lines of similar length (text-wrap: balance), never a short last line.
            BalancedText(alert.title, style: SVTextStyle(14, .bold), maxWidth: Self.textWidth)
                .foregroundStyle(SV.text)
            ForEach(Array(alert.texts.enumerated()), id: \.offset) { _, text in
                BalancedText(text, style: SVTextStyle(12, leading: 1.45), maxWidth: Self.textWidth)
                    .foregroundStyle(SV.textCode)
            }
            VStack(spacing: 8) {
                ForEach(Array(alert.buttons.enumerated()), id: \.offset) { index, b in
                    let button = Button(b.title) { press(index) }
                        .buttonStyle(SVButtonStyle(b.role, size: .large, fullWidth: true))
                    if index == 0 { button.keyboardShortcut(.defaultAction) } else { button }
                }
            }
            .padding(.top, 6)
            if let title = alert.checkbox {
                AlertCheckbox(title: title, isOn: Binding(get: { checked }, set: { checked = $0; alert.checked = $0 }))
                    .padding(.top, 4)
            }
        }
        .frame(width: Self.textWidth)
        .svBox(RoundedRectangle(cornerRadius: 24), fill: SV.alert, line: SV.glassLine,
               padding: EdgeInsets(top: 20, leading: 16, bottom: 16, trailing: 16))
        .background { OuterShadow(cornerRadius: 24, opacity: 0.6, blur: 60, y: 24) }
    }
}

/// The suppression box under an alert's buttons ("Don't ask again").
struct AlertCheckbox: View {
    var title: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 8) {
                ZStack {
                    if isOn {
                        RoundedRectangle(cornerRadius: 4).fill(SV.primary)
                        Image(systemName: "checkmark").svFont(9, .bold).foregroundStyle(SV.onPrimary)
                    } else {
                        RoundedRectangle(cornerRadius: 4).fill(SV.control)
                        RoundedRectangle(cornerRadius: 4).strokeBorder(SV.boxLine)
                    }
                }
                .frame(width: 15, height: 15)
                Text(title).svFont(12).foregroundStyle(SV.text2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
