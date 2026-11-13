// SPDX-License-Identifier: MIT
// Debug only: `SUBVISION_COMMANDS=<file>` drives the app from the shell
// through the same model methods the buttons and menus call (the shell's
// `DebugQA.watchCommands`). One command per line; the reply goes to `<file>.out`.
//
//   tab process|preview|fix · add <path>[,<path>…] · remove-all · select-all
//   sidebar · inspector · lang en|it · theme system|light|dark
//   size <w>x<h> · windowid · capture <path> · settings · quit
//   Sub fix (F5.3): fix-open <path> · fix-drop <path>[,<path>…] · fix-option merge|ignore|flash|minDuration <value>
//   fix-run · wait-fix <s> · fix-state · fix-menu (the two ⌘↩ items and which one AppKit fires)

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
        // Sub fix (F5.3)
        case "fix-open":
            model.chooseSRT(URL(fileURLWithPath: argument))
        case "fix-drop":
            model.receiveFixDrop(argument.split(separator: ",").map { URL(fileURLWithPath: String($0)) })
        case "fix-option":
            let pair = argument.split(separator: " ", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { return "usage: fix-option <name> <value>" }
            switch pair[0] {
            case "merge": model.fix.merge = pair[1] == "true"
            case "ignore": model.fix.ignore = pair[1] == "true"
            case "flash": model.fix.flash = pair[1] == "true"
            case "minDuration":
                guard let v = Double(pair[1]) else { return "bad value" }
                model.fix.minDuration = v
            default: return "unknown option"
            }
        case "fix-run":
            model.runFix()
        case "wait-fix":
            let ok = await wait(Double(argument) ?? 30) { !model.fix.running && model.fix.outcome != nil }
            return ok ? fixState(model) : "timeout · " + fixState(model)
        case "fix-state":
            return fixState(model)
        case "fix-menu":
            return await fixMenu(model)
        case "quit":
            NSApp.terminate(nil)
        default:
            return "unknown"
        }
        return "ok · tab \(model.tab.rawValue) · \(model.videos.count) videos · status \(model.status)"
    }

    /// Everything Sub fix shows and sends, one line: path, options, the shared parameters, the outcome.
    private static func fixState(_ model: AppModel) -> String {
        let f = model.fix, p = model.ocrParams
        let outcome: String
        switch f.outcome {
        case nil: outcome = "none"
        case .created(let path, let count): outcome = "created \(count) \(path)"
        case .noValidSegments: outcome = "no_valid_segments"
        case .unreadable(let line): outcome = "bad_srt line \(line)"
        case .notFound(let path): outcome = "not_found \(path)"
        case .notSrt: outcome = "not_srt"
        case .failed(let message): outcome = "failed \(message)"
        }
        return "path \(model.fixPath?.path ?? "none") · lines \(f.lines ?? 0) · duration \(f.duration ?? 0)"
            + " · merge \(f.merge) · ignore \(f.ignore) · flash \(f.flash) · minDuration \(f.minDuration)"
            + " · gap \(p.mergeGap) · wrap \(p.wrapWidth) · lang \(p.langHint) · useIgnore \(model.useIgnore) · useCorrections \(model.useCorrections)"
            + " · running \(f.running) · canRun \(model.canRunFix) · outcome \(outcome)"
    }

    /// Design note 15: Start and Run Sub fix share ⌘↩. Lists both items with
    /// their state, then sends a real ⌘↩ through the menu bar and says whether
    /// a menu item took it (the model shows which one ran).
    private static func fixMenu(_ model: AppModel) async -> String {
        // SwiftUI rebuilds the menu on the next turn of the run loop: give it one.
        try? await Task.sleep(for: .milliseconds(500))
        func walk(_ menu: NSMenu, _ out: inout [String]) {
            // SwiftUI enables its items when the menu is validated, as on opening it.
            menu.delegate?.menuNeedsUpdate?(menu)
            menu.update()
            for item in menu.items {
                if item.keyEquivalent == "\r", item.keyEquivalentModifierMask.contains(.command) {
                    out.append("\(item.title)=\(item.isEnabled ? "on" : "off")")
                }
                if let sub = item.submenu { walk(sub, &out) }
            }
        }
        var items: [String] = []
        if let main = NSApp.mainMenu { walk(main, &items) }
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                           windowNumber: WindowSizer.main(model.config)?.windowNumber ?? 0, context: nil,
                                           characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)
        else { return items.joined(separator: " · ") + " · no event" }
        let before = model.fix.outcome
        // The key goes the way a real press goes: the app active, the window key, `sendEvent`.
        NSApp.activate(ignoringOtherApps: true)
        let window = WindowSizer.main(model.config)
        window?.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(500))
        let key = window?.isKeyWindow ?? false
        NSApp.sendEvent(event)
        try? await Task.sleep(for: .milliseconds(300))
        let ran = model.fix.running || model.fix.outcome != before
        return items.joined(separator: " · ") + " · key window \(key) · fix ran \(ran)"
    }
}
#endif
