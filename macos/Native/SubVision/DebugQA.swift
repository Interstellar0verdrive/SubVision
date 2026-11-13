// SPDX-License-Identifier: MIT
// Debug only: `SUBVISION_COMMANDS=<file>` drives the app from the shell
// through the same model methods the buttons and menus call (the shell's
// `DebugQA.watchCommands`). One command per line; the reply goes to `<file>.out`.
//
//   tab process|preview|fix · add <path>[,<path>…] · remove-all · select-all
//   sidebar · inspector · lang en|it · theme system|light|dark
//   size <w>x<h> · windowid · capture <path> · settings · quit
//   report-open <path> · report-js <expression> · report-run <statements>
//   report-export · report-confirm yes|no|ask · report-elsewhere <path>|cancel|ask
//   report-windows · report-capture <path>
//   report-close (the front report window; all with "all")

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
        // F5.4: the report windows (ReportWindow.swift, ReportBridge.swift).
        case "report-open":
            let front = model.openReport(URL(fileURLWithPath: argument))
            _ = await wait(15) { front.session.phase != .loading }
            return "\(front.session.phase) · \(front.session.name) · \(front.session.bridge.map { "\($0.file.kind)" } ?? "-")"
        case "report-js", "report-run":
            guard let front = model.report.front, let bridge = front.session.bridge else { return "no report window" }
            do {
                let body = command == "report-js" ? "return (\(argument));" : argument
                let value = try await bridge.call(body)
                return reportValue(value)
            } catch {
                return "error: \(error)"
            }
        case "report-export":
            guard let front = model.report.front, let bridge = front.session.bridge else { return "no report window" }
            let before = front.session.lastExport
            _ = try? await bridge.call("await exportSrt();")
            _ = await wait(5) { front.session.lastExport != before }
            return front.session.lastExport.map(\.path) ?? "no export"
        case "report-confirm":
            ReportBridge.debugConfirm = argument == "yes" ? true : argument == "no" ? false : nil
        case "report-elsewhere":
            ReportSession.debugElsewhere = argument == "ask" ? nil : argument == "cancel" ? .some(nil) : .some(URL(fileURLWithPath: argument))
        case "report-windows":
            let windows = model.report.open.map { s in
                "\(model.report.windows[s.url]?.window?.windowNumber ?? 0) \(s.phase) \(s.name)"
            }
            let menu = (NSApp.windowsMenu?.items ?? []).filter { !$0.isSeparatorItem && !$0.title.isEmpty }.map(\.title)
            return "\(windows.count) report windows: " + windows.joined(separator: " | ") + " · window menu: " + menu.joined(separator: " | ")
        case "report-capture":
            guard let front = model.report.front else { return "no report window" }
            let written = await DebugSnapshot.captureReport(front, argument, schemes: SVShell.DebugSnapshot.schemes(model.config))
            return written.joined(separator: " ")
        case "report-close":
            let targets = argument == "all" ? Array(model.report.windows.values) : [model.report.front].compactMap { $0 }
            guard !targets.isEmpty else { return "no report window" }
            targets.forEach { $0.close() }
        default:
            return "unknown"
        }
        return "ok · tab \(model.tab.rawValue) · \(model.videos.count) videos · status \(model.status)"
    }

    /// A JavaScript value as one line: strings as they are, the rest as JSON.
    private static func reportValue(_ value: Any?) -> String {
        guard let value else { return "undefined" }
        if let text = value as? String { return text }
        if JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) { return text }
        return "\(value)"
    }
}
#endif
