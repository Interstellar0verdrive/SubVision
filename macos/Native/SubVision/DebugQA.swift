// SPDX-License-Identifier: MIT
// Debug only: `SUBVISION_COMMANDS=<file>` drives the app from the shell
// through the same model methods the buttons and menus call (the shell's
// `DebugQA.watchCommands`). One command per line; the reply goes to `<file>.out`.
//
//   tab process|preview|fix · add <path>[,<path>…] · remove-all · select-all
//   sidebar · inspector · lang en|it · theme system|light|dark
//   size <w>x<h> · windowid · capture <path> · settings · quit
//   Preview (F5.2): preview-select, find-frames, stop-frames, wait-frames, frame, band-set,
//   drag-handle, try-ocr, wait-ocr, preview-state (see the block below)
//   Sub fix (F5.3): fix-open <path> · fix-drop <path>[,<path>…] · fix-option merge|ignore|flash|minDuration <value>
//   fix-run · wait-fix <s> · fix-state · fix-menu (the two ⌘↩ items and which one AppKit fires)
//   report-open <path> · report-js <expression> · report-run <statements>
//   report-export · report-confirm yes|no|ask · report-elsewhere <path>|cancel|ask
//   report-windows · report-capture <path>
//   report-close (the front report window; all with "all")
//   The stop alerts (F6; O1 and O2 are not modal, the commands keep running under them):
//   stop-file-ask · stop-all-ask   what the Stop / Stop All buttons do: the alert opens, the reply does not wait for it
//   alert-state                    "none", or "file <idx> <name> · window <id> · buttons Stop|Continue" / "all · …"
//   alert-press <n>                presses button n of the open alert (0 = Stop / Stop All, 1 = Continue)
//   alert-key return|esc           the key, sent to the alert's panel as a real key event
//   stop-file [<idx>]              batch.stop for one file, no alert: with <idx> (the batch index, 0-based) the
//                                  engine stops it only if it is still the one in progress, else "not_running";
//                                  without it, the file in progress whatever it is. Replies with the engine's answer.

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
            if argument.isEmpty { return "batch.stop file: " + (await model.stop(all: false)) }
            guard let idx = Int(argument) else { return "bad index" }
            return "batch.stop file \(idx): " + (await model.stop(all: false, file: idx)) + " · running \(runningIndex(model).map(String.init) ?? "-")"
        case "stop-all":
            await model.stop(all: true)
        case "stop-file-ask", "stop-all-ask":
            guard model.batch.running else { return "no batch" }
            if command == "stop-file-ask" { model.stopCurrentFile() } else { model.stopAll() }
            _ = await wait(3) { model.stopAlert != nil }
            return alertState(model)
        case "alert-state":
            return alertState(model)
        case "alert-press":
            guard let open = model.stopAlert, open.presentation.isOpen else { return "no alert" }
            guard let n = Int(argument), open.presentation.alert.buttons.indices.contains(n) else { return "bad button" }
            open.presentation.press(n)
            return "pressed \(open.presentation.alert.buttons[n].title) · " + alertState(model)
        case "alert-key":
            guard let open = model.stopAlert, open.presentation.isOpen else { return "no alert" }
            guard let code: UInt16 = ["return": 36, "esc": 53][argument] else { return "unknown key" }
            let characters = argument == "return" ? "\r" : "\u{1b}"
            guard let window = NSApp.window(withWindowNumber: open.presentation.windowNumber),
                  let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                               windowNumber: window.windowNumber, context: nil, characters: characters,
                                               charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)
            else { return "no event" }
            window.makeKey()
            window.sendEvent(event)
            try? await Task.sleep(for: .milliseconds(200))
            return "key \(argument) · " + alertState(model)
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
        // F5.2 · Preview (the commands are in `preview(_:_:_:)` below).
        case "preview-select", "find-frames", "stop-frames", "wait-frames", "frame", "band-set", "drag-handle",
             "try-ocr", "wait-ocr", "preview-state":
            return await preview(command, argument, model)
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

    /// The batch index (0-based) of the file in progress.
    private static func runningIndex(_ model: AppModel) -> Int? {
        model.runningVideo.flatMap { model.run.ids.firstIndex(of: $0.id) }
    }

    /// The stop alert that is up, the file it names and the file in progress now.
    private static func alertState(_ model: AppModel) -> String {
        guard let open = model.stopAlert, open.presentation.isOpen else { return "none" }
        let what: String
        switch open.kind {
        case .file(let idx, let name): what = "file \(idx) \(name)"
        case .all: what = "all"
        }
        return "\(what) · window \(open.presentation.windowNumber) · buttons \(open.presentation.alert.buttons.map(\.title).joined(separator: "|"))"
            + " · running \(runningIndex(model).map(String.init) ?? "-")"
    }

    /// "done 2 failed 0 stopped 0 skipped 0 elapsed 12.3" of the last batch.
    private static func summaryLine(_ model: AppModel) -> String {
        guard let s = model.run.summary else { return "no summary" }
        return "done \(s.done) failed \(s.failed) stopped \(s.stopped) skipped \(s.skipped) elapsed \(s.elapsed)"
    }

    // MARK: - F5.2 · Preview
    //
    //   preview-select <idx>           the list's video (0-based) in Preview
    //   find-frames · stop-frames      Find 20 Frames / Stop
    //   wait-frames <s>                until the search ends (replies with the frames found)
    //   frame <n>                      the frame shown, 1-based
    //   band-set <key> <value>         bottom-height, bottom-width, top-height, top-width (percent), top-band (0/1)
    //   drag-handle <band> <handle> <dx> <dy>   the drag's own function (`BandGeometry.apply`, the one the
    //                                  gesture calls) with the pointer moved by (dx, dy) pt from the handle
    //                                  (band: dialogue|signs; handle: height|left|right). Synthesized
    //                                  NSEvents sent or posted to the window never reach a SwiftUI
    //                                  DragGesture (it reads the real pointer), so there is no mouse command.
    //   try-ocr · wait-ocr <s>         Try OCR / until it answers (replies with the texts)
    //   preview-state                  the page's state and the band values in UserDefaults

    private static func preview(_ command: String, _ argument: String, _ model: AppModel) async -> String {
        let args = argument.split(separator: " ").map(String.init)
        switch command {
        case "preview-select":
            guard let i = Int(argument), model.videos.indices.contains(i) else { return "bad index" }
            model.tab = .preview
            model.selectPreviewVideo(model.videos[i].id)
            return "ok · \(model.videos[i].name)"
        case "find-frames":
            guard model.canFindFrames else { return "cannot find: \(previewState(model))" }
            model.findFrames()
            return "ok · searching"
        case "stop-frames":
            model.stopFrames()
            return "ok"
        case "wait-frames":
            let ended = await wait(Double(argument) ?? 120) { !model.isSearchingFrames }
            guard ended else { return "timeout · \(previewState(model))" }
            if case .failed(let code, let message) = model.preview.search { return "failed \(code) \(message ?? "")" }
            guard let result = model.previewResult else { return "no frames" }
            return "\(result.frames.count) frames · \(result.found) with text · index \(result.index + 1)"
        case "frame":
            guard let n = Int(argument) else { return "bad number" }
            model.selectFrame(n - 1)
            return "ok · frame \(model.previewResult.map { $0.index + 1 } ?? 0)"
        case "band-set":
            guard args.count == 2, let value = Int(args[1]) else { return "bad arguments" }
            switch args[0] {
            case "bottom-height": BandValues.setHeight(value, .dialogue)
            case "bottom-width": BandValues.setWidth(value, .dialogue)
            case "top-height": BandValues.setHeight(value, .signs)
            case "top-width": BandValues.setWidth(value, .signs)
            case "top-band": UserDefaults.standard.set(value != 0, forKey: OcrKey.topBand)
            default: return "unknown key"
            }
            return "ok · \(bandValues())"
        case "drag-handle":
            guard args.count == 4, let band = PreviewBand(rawValue: args[0]), let handle = BandHandle(rawValue: args[1]),
                  let dx = Double(args[2]), let dy = Double(args[3]) else { return "bad arguments" }
            let rect = model.preview.frameRect
            guard rect.width > 0 else { return "no frame on screen" }
            let bandRect = BandGeometry.rect(band, height: BandValues.height(band), width: BandValues.width(band), in: rect.size)
            let start: CGPoint
            switch handle {
            case .height: start = CGPoint(x: bandRect.midX, y: band == .dialogue ? bandRect.minY : bandRect.maxY)
            case .left: start = CGPoint(x: bandRect.minX, y: bandRect.midY)
            case .right: start = CGPoint(x: bandRect.maxX, y: bandRect.midY)
            }
            let end = CGPoint(x: start.x + dx, y: start.y + dy)
            guard model.canDragBands else { return "bands locked" }
            let drag = BandGeometry.apply(band, handle, pointer: end, in: rect.size)
            return "ok · \(drag.band.rawValue) height \(drag.height) width \(drag.width) · \(bandValues())"
        case "try-ocr":
            guard model.canTryOCR else { return "cannot try: \(previewState(model))" }
            model.tryOCR()
            return "ok · reading"
        case "wait-ocr":
            let ended = await wait(Double(argument) ?? 120) { !model.isReadingOCR }
            guard ended else { return "timeout" }
            switch model.preview.test {
            case .done(let reply, _, _, _)?:
                let bottom = reply.bottom.map { "bottom \"\(oneLine($0.text))\" → \"\(oneLine($0.finalText))\" conf \($0.conf) agree \($0.agree) \(Int($0.ms)) ms" } ?? "bottom —"
                let top = reply.top.map { " · top \"\(oneLine($0.text))\" → \"\(oneLine($0.finalText))\"" } ?? ""
                return bottom + top
            case .failed(let code, let message)?: return "failed \(code) \(message ?? "")"
            case .reading?: return "still reading"
            case nil: return "no test"
            }
        case "preview-state":
            return previewState(model)
        default:
            return "unknown"
        }
    }

    private static func oneLine(_ s: String) -> String { s.replacingOccurrences(of: "\n", with: " / ") }

    private static func bandValues() -> String {
        "bottom \(BandValues.height(.dialogue))x\(BandValues.width(.dialogue)) · top \(BandValues.signsOn ? "on" : "off") \(BandValues.height(.signs))x\(BandValues.width(.signs))"
    }

    private static func previewState(_ model: AppModel) -> String {
        var parts = ["video \(model.previewVideo?.name ?? "none")", "search \(model.preview.search)"]
        if let r = model.previewResult { parts.append("frames \(r.frames.count) found \(r.found) index \(r.index + 1) band \(model.previewFrame?.band ?? "none")") }
        parts.append(bandValues())
        parts.append("test \(model.preview.test == nil ? "none" : model.isReadingOCR ? "reading" : "done")" + (model.preview.stale ? " stale" : ""))
        parts.append("batch \(model.batch.running)")
        let r = model.preview.frameRect
        parts.append("frame \(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height))")
        return parts.joined(separator: " · ")
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
