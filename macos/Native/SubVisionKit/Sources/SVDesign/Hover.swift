// SPDX-License-Identifier: MIT
// Copied and adapted from the design system of the native macOS app of AnimeUp
// (AnimeUpKit/DesignSystem/Hover.swift, version 2.1), by the same author.
//
// Hover states for everything clickable that isn't an SVButton (which has its
// own): menus, cards and rows you click, small links.

import AppKit
import SwiftUI

extension SV {
    /// The veil over a clickable surface under the pointer: half of `glass`.
    public static let hoverVeil = Color(dark: "rgba(255,255,255,.04)", light: "rgba(0,0,0,.03)")
}

extension View {
    /// A light veil over `shape` while the pointer is on it (and `enabled`).
    public func svHover<S: Shape>(_ shape: S, enabled: Bool = true) -> some View {
        modifier(HoverVeil(shape: shape, enabled: enabled))
    }

    /// The pointing hand over a link. AppKit's cursor directly: `.pointerStyle(.link)`
    /// doesn't show in these windows (their content reaches under the title bar).
    public func svPointingHand(_ enabled: Bool = true) -> some View {
        modifier(PointingHand(enabled: enabled))
    }
}

private struct HoverVeil<S: Shape>: ViewModifier {
    var shape: S
    var enabled: Bool
    @State private var hover = false

    func body(content: Content) -> some View {
        content
            .overlay { shape.fill(SV.hoverVeil).opacity(hover && enabled ? 1 : 0).allowsHitTesting(false) }
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.12), value: hover)
    }
}

private struct PointingHand: ViewModifier {
    var enabled: Bool
    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                if inside && enabled && !pushed { NSCursor.pointingHand.push(); pushed = true }
                if !inside && pushed { NSCursor.pop(); pushed = false }
            }
            .onDisappear { if pushed { NSCursor.pop(); pushed = false } }
    }
}

// MARK: - Popup menu

/// One line of a `PopupMenu`.
public struct SVMenuItem {
    var title: String?
    /// Secondary text, in grey on the item's right (a version, a date).
    var detail: String? = nil
    var checked: Bool
    var enabled: Bool
    var action: () -> Void

    public static func item(_ title: String, detail: String? = nil, checked: Bool = false, enabled: Bool = true,
                            action: @escaping () -> Void) -> SVMenuItem {
        SVMenuItem(title: title, detail: detail, checked: checked, enabled: enabled, action: action)
    }

    public static var separator: SVMenuItem { SVMenuItem(title: nil, checked: false, enabled: false, action: {}) }
}

/// The design's popup: a button with any label that opens the native menu
/// under itself. Not SwiftUI's `Menu`, which keeps the pointer to itself:
/// neither it nor what contains it ever sees a hover.
public struct PopupMenu<Label: View>: View {
    var items: () -> [SVMenuItem]
    /// A change of this value opens the menu, as a click on the button does (0 never does).
    var openRequest: Int
    @ViewBuilder var label: Label
    @State private var frame = CGRect.zero
    @Environment(\.isEnabled) private var enabled

    public init(_ items: @escaping () -> [SVMenuItem], openRequest: Int = 0, @ViewBuilder label: () -> Label) {
        self.items = items
        self.openRequest = openRequest
        self.label = label()
    }

    public var body: some View {
        Button { show() } label: { label }
            .buttonStyle(PopupButtonStyle())
            // Disabled reads as disabled, like the design's menus (opacity .45).
            .opacity(enabled ? 1 : 0.45)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
            .onChange(of: openRequest) { _, request in
                if request != 0, enabled, frame != .zero { show() }
            }
    }

    private func show() {
        guard let view = NSApp.keyWindow?.contentView ?? NSApp.mainWindow?.contentView else { return }
        let handler = MenuHandler()
        let menu = NSMenu()
        menu.autoenablesItems = false
        let list = items()
        // Details line up on a right tab stop past the longest title.
        let font = NSFont.menuFont(ofSize: 0)
        let widest = list.compactMap { $0.title }.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        // Details in tabular figures, so times and versions line up digit by digit.
        let detailFont = NSFont.monospacedDigitSystemFont(ofSize: font.pointSize, weight: .regular)
        let detailWidest = list.compactMap { $0.detail }.map { ($0 as NSString).size(withAttributes: [.font: detailFont]).width }.max() ?? 0
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: widest + 28 + detailWidest)]
        for item in list {
            guard let title = item.title else { menu.addItem(.separator()); continue }
            let entry = NSMenuItem(title: title, action: #selector(MenuHandler.fire(_:)), keyEquivalent: "")
            if let detail = item.detail {
                let text = NSMutableAttributedString(string: title + "\t", attributes: [.font: font, .paragraphStyle: paragraph])
                text.append(NSAttributedString(string: detail, attributes: [.font: detailFont, .paragraphStyle: paragraph,
                                                                             .foregroundColor: NSColor.secondaryLabelColor]))
                entry.attributedTitle = text
            }
            entry.target = handler
            entry.tag = handler.actions.count
            entry.state = item.checked ? .on : .off
            entry.isEnabled = item.enabled
            handler.actions.append(item.action)
            menu.addItem(entry)
        }
        // Under the control, its left edge aligned, as a popup button opens.
        let y = view.isFlipped ? frame.maxY + 4 : view.bounds.height - frame.maxY - 4
        PopupMenuTracking.open = menu
        defer { PopupMenuTracking.open = nil }
        _ = withExtendedLifetime(handler) {
            menu.popUp(positioning: nil, at: NSPoint(x: frame.minX, y: y), in: view)
        }
    }
}

/// The popup menu that is open, if any: `popUp` returns only when it closes,
/// so a test (or the app's debug commands) closes it from a timer with `cancel()`.
@MainActor
public enum PopupMenuTracking {
    public internal(set) static var open: NSMenu?

    /// The titles of the open menu's items, and the one checked.
    public static var titles: [String] { open?.items.filter { !$0.isSeparatorItem }.map { ($0.state == .on ? "✓ " : "") + $0.title } ?? [] }

    public static func cancel() { open?.cancelTracking() }
}

private final class MenuHandler: NSObject {
    var actions: [() -> Void] = []
    @objc func fire(_ sender: NSMenuItem) { actions[sender.tag]() }
}

/// The popup's button: the label as it is, the hover veil, a touch darker pressed.
private struct PopupButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .svHover(RoundedRectangle(cornerRadius: SV.Radius.field))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Rectangle())
    }
}
