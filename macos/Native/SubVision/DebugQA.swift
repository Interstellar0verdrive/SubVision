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
            model.quitApp()
        // F5.1: the batch (`params fast|default`, `start`, `stop-file`, `stop-all`,
        // `wait-batch <s>`, `wait-file <idx> <s>` (idx in the list, 0-based),
        // `wait-step <idx> <key> <s>` (the step reported progress), `states`,
        // `expand <idx>`, `process-again`, `clear-done`, `summary`, `summary-seen`,
        // `inspector-set <key> <value>` (an OcrKey with a number, true/false or text),
        // `inspector-groups open|closed`).
        case "params":
            switch argument {
            case "fast": model.applyOcrParams(.fast)
            case "default": model.resetOcrParams()
            default: return "unknown profile"
            }
        case "start":
            guard model.canStart else { return "cannot start (\(model.readyVideos.count) ready, status \(model.status), vision \(model.hello?.vision ?? false))" }
            model.startBatch()
            _ = await wait(10) { model.batch.running && model.runningVideo != nil }
        case "stop-file":
            await model.stop(all: false)
        case "stop-all":
            await model.stop(all: true)
        case "wait-batch":
            let ok = await wait(Double(argument) ?? 600) { !model.batch.running && model.videos.allSatisfy { !$0.state.inBatch } }
            return ok ? "batch done · \(summaryLine(model))" : "timeout"
        case "wait-file":
            let p = argument.split(separator: " ").map(String.init)
            guard p.count == 2, let idx = Int(p[0]), let s = Double(p[1]), model.videos.indices.contains(idx) else { return "bad args" }
            let ok = await wait(s) { model.videos[idx].state.isFinished || (model.videos[idx].state == .ready && !model.batch.running) }
            return "\(ok ? "ok" : "timeout") · \(model.videos[idx].name) \(model.videos[idx].state.rawValue)"
        case "wait-step":
            let p = argument.split(separator: " ").map(String.init)
            guard p.count == 3, let idx = Int(p[0]), let s = Double(p[2]), model.videos.indices.contains(idx) else { return "bad args" }
            let ok = await wait(s) {
                model.videos[idx].state == .running && model.run.steps.contains { $0.key == p[1] && ($0.state == .running || $0.state == .done) && $0.count > 0 }
            }
            return "\(ok ? "ok" : "timeout") · \(model.run.currentStep?.id ?? "-")"
        case "states":
            return model.videos.map { "\($0.name)=\($0.state.rawValue)\($0.segments.map { ":\($0)" } ?? "")\($0.atStep.map { "@\($0)" } ?? "")" }.joined(separator: " ")
        case "expand":
            guard let idx = Int(argument), model.videos.indices.contains(idx) else { return "bad index" }
            model.run.expanded.insert(model.videos[idx].id)
        case "process-again":
            model.processAgain(Set(model.videos.map(\.id)))
        case "clear-done":
            model.clearFinished()
        case "summary-seen":
            model.markSummarySeen()
        case "summary":
            model.run.showSummary = model.run.summary != nil
            return model.run.summary.map { _ in "shown · \(summaryLine(model))" } ?? "no summary"
        case "inspector-set":
            let p = argument.split(separator: " ", maxSplits: 1).map(String.init)
            guard p.count == 2 else { return "bad args" }
            let key = p[0].hasPrefix("ocr.") || p[0] == OcrKey.langHint ? p[0] : "ocr.\(p[0])"
            if p[1] == "true" || p[1] == "false" { model.defaults.set(p[1] == "true", forKey: key) }
            else if let i = Int(p[1]) { model.defaults.set(i, forKey: key) }
            else if let d = Double(p[1]) { model.defaults.set(d, forKey: key) }
            else { model.defaults.set(p[1], forKey: key) }
        case "inspector-groups":
            for g in ["ocr", "dlg", "sig", "seg", "adv"] { model.defaults.set(argument == "open", forKey: "inspector.group.\(g)") }
        default:
            return "unknown"
        }
        return "ok · tab \(model.tab.rawValue) · \(model.videos.count) videos · status \(model.status)"
    }

    /// "done 2 failed 0 stopped 0 skipped 0 elapsed 12.3" of the last batch.
    private static func summaryLine(_ model: AppModel) -> String {
        guard let s = model.run.summary else { return "no summary" }
        return "done \(s.done) failed \(s.failed) stopped \(s.stopped) skipped \(s.skipped) elapsed \(s.elapsed)"
    }
}
#endif
