// SPDX-License-Identifier: MIT
// The menu bar's keyboard shortcuts with the app's state of now.
//
// SwiftUI sets a menu item's action (and so whether it is on) when its menu
// is updated, which happens when the menu opens. An item that was off the last
// time its menu opened stays off for its shortcut too: ⌘. during a batch, ⌘R
// and ⌫ on a selected row, ⌘← ⌘→ ⌘T in the Preview window did nothing until
// the menu had been opened once (manual tests, 14/11). Before AppKit looks for
// a key equivalent, every menu of the bar is brought up to date, as on opening.

import AppKit

@MainActor
enum MenuShortcuts {
    private static var monitor: Any?

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if isShortcut(event), let menu = NSApp.mainMenu { refresh(menu) }
            return event
        }
    }

    /// Keys a menu item can own: with ⌘ or ⌃, or ⌫ / ⌦ (Remove from List) when no
    /// text is being edited (there they delete characters, never rows).
    private static func isShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) || flags.contains(.control) { return true }
        guard event.keyCode == 51 || event.keyCode == 117 else { return false }
        return !(event.window?.firstResponder is NSText)
    }

    private static func refresh(_ menu: NSMenu) {
        menu.delegate?.menuNeedsUpdate?(menu)
        menu.update()
        for item in menu.items {
            if let submenu = item.submenu { refresh(submenu) }
        }
    }
}
