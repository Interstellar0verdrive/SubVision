// SPDX-License-Identifier: MIT
// Debug only: `SUBVISION_COMMANDS=<file>` drives the app from the shell
// through the same model methods the buttons and menus call (the shell's
// `DebugQA.watchCommands`). One command per line; the reply goes to `<file>.out`.
//
//   tab process|preview|fix · add <path>[,<path>…] · remove-all · select-all
//   sidebar · inspector · lang en|it · theme system|light|dark
//   size <w>x<h> · windowid · capture <path> · settings · quit

#if DEBUG
import AppKit
import SVShell
import SwiftUI

@MainActor
enum DebugQA {
    static func scheduleIfAsked(model: AppModel) {
        SVShell.DebugQA.watchIfAsked(model.config) { line in await run(line, model) }
    }

    static func wait(_ seconds: Double, _ condition: @MainActor () -> Bool) async -> Bool {
        await SVShell.DebugQA.wait(seconds, condition)
    }

    private static func run(_ line: String, _ model: AppModel) async -> String {
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        let command = parts.first ?? "", argument = parts.count > 1 ? parts[1] : ""
        switch command {
        case "tab":
            guard let tab = Tab(rawValue: argument) else { return "unknown tab" }
            model.tab = tab
        case "add":
            model.add(argument.split(separator: ",").map { URL(fileURLWithPath: String($0)) })
            _ = await wait(60) { model.videos.allSatisfy(\.probed) }
        case "remove-all":
            model.removeWithUndo(Set(model.videos.map(\.id)))
        case "select-all":
            model.selectAll()
        case "sidebar":
            model.toggleSidebar()
        case "inspector":
            model.toggleInspector()
        case "lang":
            model.setLanguage(argument)
        case "theme":
            model.theme = argument
        case "size":
            let dims = argument.split(separator: "x").compactMap { Double($0) }
            guard dims.count == 2, let window = WindowSizer.main(model.config) else { return "bad size" }
            window.setContentSize(NSSize(width: dims[0], height: dims[1]))
        case "windowid":
            return WindowSizer.main(model.config).map { "\($0.windowNumber)" } ?? "no window"
        case "settingswindow":
            let main = WindowSizer.main(model.config)
            return NSApp.windows.first { $0.isVisible && $0 !== main && $0.title.count > 0 }.map { "\($0.windowNumber) \($0.title)" } ?? "no window"
        case "capture":
            let written = await SVShell.DebugSnapshot.capture(model.config, schemes: SVShell.DebugSnapshot.schemes(model.config), argument)
            return written.joined(separator: " ")
        case "settings":
            // The app menu's Settings… item (⌘,), as the person would press it.
            guard let item = NSApp.mainMenu?.items.first?.submenu?.items.first(where: { $0.keyEquivalent == "," }) else { return "no menu item" }
            NSApp.sendAction(item.action!, to: item.target, from: item)
        case "quit":
            NSApp.terminate(nil)
        default:
            return "unknown"
        }
        return "ok · tab \(model.tab.rawValue) · \(model.videos.count) videos · status \(model.status)"
    }
}
#endif
