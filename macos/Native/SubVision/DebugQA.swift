// SPDX-License-Identifier: MIT
// Debug only: `SUBVISION_COMMANDS=<file>` drives the app from the shell
// through the same model methods the buttons and menus call (the shell's
// `DebugQA.watchCommands`). One command per line; the reply goes to `<file>.out`.
//
//   tab process|review|fix · add <path>[,<path>…] · remove-all · check-all
//   inspector [open|close] · lang en|it · theme system|light|dark
//   size <w>x<h> · windowid · capture <path> · settings · quit
//   key <combo> [main|front|<window>]   a key press posted to the app's event queue, e.g. key cmd+return, key esc
//   mouse click|double|right <x>,<y> [main|front|<window>] [pick <title>]   real mouse events sent to a window
//   deactivate · notifications · notification-click <n>|file <idx>   the app behind; its delivered notifications; a click on one
//   mouse drag <x>,<y> <x2>,<y2> [main|front|<window>] · mouse scroll <x>,<y> <dy> [main|front|<window>]
//   Preview (F5.2, a page inside Video since C3): preview-open, preview-close, preview-layout, preview-select,
//   preview-video, preview-nav, retry-frames, stop-frames, wait-frames, frame, frames, frame-bands, band-set,
//   drag-handle, try-ocr, wait-ocr, preview-state (see the block below)
//   Sub fix (F5.3): fix-open <path> · fix-drop <path>[,<path>…] · fix-option merge|ignore|flash|minDuration <value>
//   fix-run · wait-fix <s> · fix-state · fix-menu (the two ⌘↩ items and which one AppKit fires)
//   The report in the Review page (C3-07; `capture` draws its web view in too):
//   report-open <path> (File › Open a Review…) · report-js <expression> · report-run <statements>
//   report-page                    "list · …", or "Revisione di <video> · <details> · <phase> · back on · save on"
//   report-back · report-close     the band's round ‹ (View › Back, ⌘[) / back to the list from code
//   report-key-back                ⌘[ pressed (the key View › Back has on this keyboard), then report-page
//   report-export · report-save    the report bar's "Save reviewed SRT" / File › Save Reviewed SRT (⌘S)
//   report-confirm yes|no|ask      answers "Reset all…" (the confirm message), confirm() and the overwrite question
//   report-elsewhere <path>|cancel|ask
//   report-windows · report-capture <path>   the app's windows and the Window menu (no report window) / a capture
//   report-lock on|off             the report's folder read-only (chmod 555) or writable again (755):
//                                  with it locked, a change in the report cannot be saved (the yellow notice)
//                                  and an export asks where else to save
//   report-state                   whether the "changes are not being saved" notice is up, and the last state write
//   report-alert                   the alert of the report that is up ("Reset all…", the overwrite question, a confirm()):
//                                  title, window, buttons
//   report-alert-press <n>         presses its button n (0 = Replace / OK / Cancel of "Reset all…", 1 = the other)
//   report-alert-key return|esc    the key, sent to that alert's panel as a real key event
//   engine-event <name> <json>     an engine event fed by hand to the batch's own handler, e.g.
//                                  engine-event batch.file.failed {"idx":0,"error":"unknown (X: y)","at_step":"ocr:bottom","code":"unknown","text":"y","detail":"X: y","log":"/path/name.log"}
//   The stop alerts (F6; O1 and O2 are not modal, the commands keep running under them):
//   stop-file-ask · stop-all-ask   what the Stop / Stop All buttons do: the alert opens, the reply does not wait for it
//   alert-state                    "none", or "file <idx> <name> · window <id> · buttons Stop|Continue" / "all · …"
//   alert-press <n>                presses button n of the open alert (0 = Stop / Stop All, 1 = Continue)
//   alert-key return|esc           the key, sent to the alert's panel as a real key event
//   stop-file [<idx>]              batch.stop for one file, no alert: with <idx> (the batch index, 0-based) the
//                                  engine stops it only if it is still the one in progress, else "not_running";
//                                  without it, the file in progress whatever it is. Replies with the engine's answer.
//   C2 · Video, Review and the panel: inspector-tab read|bands|lines · params-reset (undoable) ·
//   focus <idx> (the keyboard's ring on a row of Video; empty lets it go) · focused · bottom-bar · remove-focused ·
//   review-state · review-select <idx> (the Review list, that row last opened) · review <idx> (its report in the page)
//   C3 · the frame: batch-bar (the window's batch bar: hidden, or its line, segments and percentage) ·
//   summary-sheet (the end-of-batch sheet: its title, the page under it and each row's outcome)
//   C3 · the list of Video: checks, check, header, drawer, drawers, retry, row-menu, row-menu-shot,
//   video-fake, strips, wait-strips, strip-hold (see DebugVideo.swift)
//   F6 · the QA scenarios (macos/Native/QA):
//   status                         engine status, Vision, tools phase and rows, window, language, tab
//   wait-ready <s>                 until the engine is ready and the tools window is gone (first launch: downloads)
//   text <key>                     the catalogue's text for the app's language now
//   menu                           the main menu's titles and the File menu's first items
//   menu-dump <index>              one menu's items with their keys, dimmed and checked ones marked
//   window-size                    the main window's size (the whole window, as `size` sets it), "760x640"
//   row-text <idx>                 what the row of video idx says after its step (a failed row: the error text)
//   batch-progress                 the batch's weights (durations), fraction, rate and ends around, as the
//                                  batch bar, the Dock and O3 show them
//   alert-other · alert-other-press <n>   the non-modal alert that is not O1/O2 (O7, an error): title and buttons; press n
//   lang-menu                      waits for the inspector's language menu to open, reads its items and closes it
//   The F6 design snapshots: engine-status, vision, disk-free, batch-fake, capture-all, capture-window,
//   windows, settings-tab, settings-feed, alert-show, alerts-close, menu-shot, dock-tile, compose, gallery
//   (see DebugCapture.swift)

#if DEBUG
import AppKit
import SVShell
import SwiftUI
import UserNotifications

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
        case "check-all":
            model.checkAll()
        case "inspector":
            switch argument {
            case "open": model.inspectorOpen = true
            case "close": model.inspectorOpen = false
            default: model.toggleInspector()
            }
            return "inspector \(model.inspectorOpen ? "open" : "closed")"
        case "lang":
            model.setLanguage(argument)
        case "theme":
            model.theme = argument
        case "size":
            let dims = argument.split(separator: "x").compactMap { Double($0) }
            guard dims.count == 2, let window = WindowSizer.main(model.config) else { return "bad size" }
            // The whole window, as the boards measure it and as the app sizes it (`WindowSizer`):
            // the top bar is inside the content (full-size content view).
            var frame = window.frame
            frame.origin.y += frame.height - dims[1]
            frame.size = NSSize(width: dims[0], height: dims[1])
            window.setFrame(frame, display: true)
        case "key":
            return await sendKey(argument, model)
        case "deactivate":
            // The app no longer in front (another app's turn), as when the person works elsewhere.
            NSApp.deactivate()
            try? await Task.sleep(for: .milliseconds(300))
            return "active \(NSApp.isActive)"
        case "notifications":
            // The app's notifications in Notification Center: "title — body {userInfo}" per line, " ¦ " between.
            let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            let lines = delivered.map { n in
                "\(n.request.content.title) — \(n.request.content.body) \(n.request.content.userInfo.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ","))"
            }
            return "authorization \(settings.authorizationStatus.rawValue) · \(lines.count) delivered" + (lines.isEmpty ? "" : ": " + lines.joined(separator: " ¦ "))
        case "notification-click":
            // The click on the delivered notification n (0 = the newest), as macOS hands it to the app;
            // "file <idx>": the one a finished file of the list sends (when macOS does not let the app post).
            var info: [String: String] = [:]
            if argument.hasPrefix("file "), let i = Int(argument.dropFirst(5)), model.videos.indices.contains(i) {
                info = ["page": Tab.review.rawValue, "video": model.videos[i].id.uuidString]
            } else {
                let delivered = await UNUserNotificationCenter.current().deliveredNotifications().sorted { $0.date > $1.date }
                guard let n = Int(argument), delivered.indices.contains(n) else { return "no notification \(argument)" }
                for (k, v) in delivered[n].request.content.userInfo { if let k = k as? String, let v = v as? String { info[k] = v } }
            }
            ShellNotifications.shared.onClick(info)
            try? await Task.sleep(for: .milliseconds(400))
        case "mouse":
            return await sendMouse(argument, model)
        case "windowid":
            return WindowSizer.main(model.config).map { "\($0.windowNumber)" } ?? "no window"
        case "settingswindow":
            let main = WindowSizer.main(model.config)
            return NSApp.windows.first { $0.isVisible && $0 !== main && $0.title.count > 0 }.map { "\($0.windowNumber) \($0.title)" } ?? "no window"
        case "capture":
            // With a report in front its web view (drawn out of process) is drawn in by hand.
            let schemes = SVShell.DebugSnapshot.schemes(model.config)
            let written = model.reportShown ? await DebugSnapshot.captureMain(model, argument, schemes: schemes)
                : await SVShell.DebugSnapshot.capture(model.config, schemes: schemes, argument)
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
        // `inspector-tab read|bands|lines`).
        case "params":
            switch argument {
            case "fast": model.applyOcrParams(.fast)
            case "default": model.resetOcrParams()
            default: return "unknown profile"
            }
        case "start":
            guard model.canStart else { return "cannot start (\(model.checkedVideos.count) checked, status \(model.status), vision \(model.hello?.vision ?? false))" }
            model.startBatch()
            _ = await wait(10) { model.batch.running && model.runningVideo != nil }
        case "stop-file":
            if argument.isEmpty { return "batch.stop file: " + (await model.stop(all: false)) }
            guard let idx = Int(argument) else { return "bad index" }
            return "batch.stop file \(idx): " + (await model.stop(all: false, file: idx)) + " · running \(runningIndex(model).map(String.init) ?? "-")"
        case "stop-all":
            await model.stop(all: true)
        case "engine-event":
            let p = argument.split(separator: " ", maxSplits: 1).map(String.init)
            guard p.count == 2 else { return "usage: engine-event <name> <json>" }
            do {
                let message = try EngineEvent(name: p[0], data: Data(p[1].utf8)).message()
                model.handleBatch(message, name: p[0])
            } catch {
                return "bad event: \(error)"
            }
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
        case "batch-progress":
            guard model.batch.running else { return "no batch" }
            let weights = model.batchWeights.map { String(format: "%.1f", $0) }.joined(separator: "+")
            let rate = model.batchRate.map { String(format: "%.2f", $0) } ?? "-"
            return "file \(model.batch.index)/\(model.batch.total) · weights \(weights) · fraction "
                + String(format: "%.3f", model.batch.fraction ?? -1) + " · rate \(rate) · ends \(model.batch.endsAround ?? "-")"
        case "states":
            return model.videos.map { "\($0.name)=\($0.state.rawValue)\($0.segments.map { ":\($0)" } ?? "")\($0.atStep.map { "@\($0)" } ?? "")" }.joined(separator: " ")
        case "expand":
            guard let idx = Int(argument), model.videos.indices.contains(idx) else { return "bad index" }
            model.run.expanded.insert(model.videos[idx].id)
        case "process-again":
            // The rows given ("0,1"), or every finished one: checked, "will be redone" (C3-02).
            let picked = argument.split(separator: ",").compactMap { Int($0) }.filter { model.videos.indices.contains($0) }
            model.processAgain(Set(picked.isEmpty ? model.videos.map(\.id) : picked.map { model.videos[$0].id }))
        case "clear-done":
            model.clearFinished()
        case "summary-seen":
            model.markSummarySeen()
        case "batch-bar":
            // C3-01: the window's batch bar, as it reads: its line, the segments and the percentage.
            guard model.batch.running else { return "hidden" }
            let text = model.batchBarText
            let pct = model.t("app.process.batchbar.percent", ["n": Int(((model.batch.fraction ?? 0) * 100).rounded())])
            return "shown · \(text.head)\(text.tail) · segments \(model.batchWeights.count) · \(pct)"
        case "summary-sheet":
            // C3-12: the end-of-batch sheet, over the page in front: its title and one outcome per row.
            guard model.run.showSummary else { return "no sheet · tab \(model.tab.rawValue)" }
            let rows = model.summaryVideos.map { "\($0.name)=\($0.state.rawValue)" }.joined(separator: " ")
            return "sheet · \(model.summaryTitle) · tab \(model.tab.rawValue) · \(rows)"
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
        case "inspector-tab":
            // The parameters panel's tab (C2): read, bands or lines.
            guard ["read", "bands", "lines"].contains(argument) else { return "bad tab" }
            model.defaults.set(argument, forKey: "inspector.tab")
        case "params-reset":
            // "Ripristina" of the panel and View › Restore All Defaults (undoable).
            model.resetAllParameters()
            return model.ocrParams == OcrParams() ? "ok · defaults" : "not reset"
        case "focus":
            // The keyboard's ring on a row of Video (C3-02), as a click or ↑ ↓ put it; empty lets it go.
            if let idx = Int(argument), model.videos.indices.contains(idx) { model.focusedRow = model.videos[idx].id; model.focusRingVisible = true } else { model.focusedRow = nil }
            return "focus \(model.focusedVideo?.name ?? "-") · " + bottomBar(model)
        case "bottom-bar":
            return bottomBar(model)
        case "focused":
            // The row with the keyboard's ring, without moving it.
            return "focus \(model.focusedVideo?.name ?? "-")"
        case "remove-focused":
            guard model.canRemoveFocused else { return "cannot remove" }
            model.removeFocused()
            return "ok · \(model.videos.count) left · focus \(model.focusedVideo?.name ?? "-")"
        case "review-state":
            return reviewState(model)
        case "review-select":
            // The Review list with that row as the one last opened (⌘R), the report closed.
            guard let idx = Int(argument), model.reviewVideos.indices.contains(idx) else { return "bad index" }
            let video = model.reviewVideos[idx]
            model.tab = .review
            model.reviewSelection = video.id
            if model.report.session != nil { model.closeReport() }
            try? await Task.sleep(for: .milliseconds(450))
            return "ok · \(video.name)"
        case "review":
            // The row's «Apri» on Review (as Review on Video, ⌘R, the sheet): the report in the page.
            guard let idx = Int(argument), model.reviewVideos.indices.contains(idx) else { return "bad index" }
            let video = model.reviewVideos[idx]
            guard video.reviewReport != nil else { return "no report" }
            model.review(video)
            _ = await wait(20) { model.report.session?.phase != .loading }
            try? await Task.sleep(for: .milliseconds(400))
            return reportPage(model)
        // F5.2 · Preview (the commands are in `preview(_:_:_:)` below).
        case "preview-open", "preview-close", "preview-layout", "preview-select", "preview-video", "preview-nav",
             "frames", "frame-bands", "retry-frames", "stop-frames", "frames-progress", "wait-frames", "frame", "band-set", "drag-handle",
             "try-ocr", "wait-ocr", "preview-state":
            return await preview(command, argument, model)
        // F5.4, C3-07: the report in the Review page (ReportPage.swift, ReportBridge.swift).
        case "report-open":
            // File › Open a Review… without the panel.
            model.openReport(URL(fileURLWithPath: argument))
            guard let session = model.report.session else { return "no report" }
            _ = await wait(15) { session.phase != .loading }
            return "\(session.phase) · \(session.name) · \(session.bridge.map { "\($0.file.kind)" } ?? "-")"
        case "report-page":
            return reportPage(model)
        case "report-back":
            // The band's round ‹ (View › Back and ⌘[ run the same `backAction`).
            guard let back = model.backAction else { return "no back" }
            back()
            try? await Task.sleep(for: .milliseconds(450))
            return reportPage(model)
        case "report-js", "report-run":
            guard let bridge = model.report.session?.bridge else { return "no report" }
            do {
                let body = command == "report-js" ? "return (\(argument));" : argument
                let value = try await bridge.call(body)
                return reportValue(value)
            } catch {
                return "error: \(error)"
            }
        case "report-export", "report-save":
            // report-export: the report bar's "Save reviewed SRT"; report-save: File › Save Reviewed SRT (⌘S).
            guard let session = model.report.session, let bridge = session.bridge else { return "no report" }
            let before = session.lastExport
            if command == "report-save" {
                guard model.canSaveReview else { return "menu item off" }
                model.saveReviewedSRT()
            } else {
                // Not awaited: with the overwrite question up (`report-confirm ask`) the export waits for its answer.
                Task { _ = try? await bridge.call("await exportSrt();") }
            }
            _ = await wait(5) { session.lastExport != before || bridge.pageAlert?.isOpen == true }
            if bridge.pageAlert?.isOpen == true { return "asking: \(bridge.pageAlert?.alert.title ?? "")" }
            return session.lastExport.map(\.path) ?? "no export"
        case "report-lock":
            guard let session = model.report.session else { return "no report" }
            let folder = session.url.deletingLastPathComponent()
            do {
                try FileManager.default.setAttributes([.posixPermissions: argument == "on" ? 0o555 : 0o755], ofItemAtPath: folder.path)
            } catch {
                return "error: \(error)"
            }
            return "\(argument == "on" ? "read-only" : "writable") · \(folder.path)"
        case "report-state":
            guard let session = model.report.session else { return "no report" }
            let written = session.bridge?.lastStateWritten.map { "\(Int(Date().timeIntervalSince($0))) s ago" } ?? "never"
            return "state warning \(session.stateWarning ? "shown" : "none") · last write \(written) · last export \(session.lastExport?.lastPathComponent ?? "none")"
        case "report-alert", "report-alert-press":
            guard let bridge = model.report.session?.bridge else { return "no report" }
            // The report asks through a message: its alert may come a moment after the command before.
            if command == "report-alert" { _ = await wait(2) { bridge.pageAlert?.isOpen == true } }
            guard let open = bridge.pageAlert, open.isOpen else { return "none" }
            let state = "\(open.alert.title) · \(open.alert.texts.joined(separator: " ")) · window \(open.windowNumber) · buttons \(open.alert.buttons.map(\.title).joined(separator: "|"))"
            guard command == "report-alert-press" else { return state }
            guard let n = Int(argument), open.alert.buttons.indices.contains(n) else { return "bad button" }
            open.press(n)
            return "pressed \(open.alert.buttons[n].title)"
        case "report-key-back":
            // ⌘[ as the person presses it: the key of View › Back as the menu has it (SwiftUI adapts
            // "[" to the keyboard: "ò" on an Italian one), posted to the main window's event queue.
            let items = NSApp.mainMenu?.items.compactMap(\.submenu).flatMap(\.items) ?? []
            guard let item = items.first(where: { $0.title == model.t("app.menu.back") }), let window = WindowSizer.main(model.config)
            else { return "no menu item" }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(300))
            let key = item.keyEquivalent
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: item.keyEquivalentModifierMask,
                                                   timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                                   context: nil, characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: 33)
                else { return "no event" }
                NSApp.postEvent(event, atStart: false)
            }
            try? await Task.sleep(for: .milliseconds(700))
            return "key ⌘\(key) · " + reportPage(model)
        case "report-alert-key":
            // Return or Esc sent to the report's alert as a real key ("Reset all…": both are Cancel).
            guard let open = model.report.session?.bridge?.pageAlert, open.isOpen else { return "no alert" }
            guard let code: UInt16 = ["return": 36, "esc": 53][argument] else { return "unknown key" }
            let characters = argument == "return" ? "\r" : "\u{1b}"
            guard let window = NSApp.window(withWindowNumber: open.windowNumber),
                  let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                               windowNumber: window.windowNumber, context: nil, characters: characters,
                                               charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)
            else { return "no event" }
            window.makeKey()
            window.sendEvent(event)
            try? await Task.sleep(for: .milliseconds(300))
            return open.isOpen ? "still open" : "closed"
        case "report-confirm":
            ReportBridge.debugConfirm = argument == "yes" ? true : argument == "no" ? false : nil
        case "report-elsewhere":
            ReportSession.debugElsewhere = argument == "ask" ? nil : argument == "cancel" ? .some(nil) : .some(URL(fileURLWithPath: argument))
        case "report-windows":
            // No window of its own any more (C3-06): the app's windows and the Window menu.
            let windows = NSApp.windows.filter { $0.isVisible && $0.level == .normal }.map { $0.identifier?.rawValue ?? $0.title }
            let menu = (NSApp.windowsMenu?.items ?? []).filter { !$0.isSeparatorItem && !$0.title.isEmpty }.map(\.title)
            return "\(windows.count) windows: " + windows.joined(separator: " | ") + " · window menu: " + menu.joined(separator: " | ")
        case "report-capture":
            // The main window with the report's web view and the alert over it drawn in (`capture` does the same).
            let written = await DebugSnapshot.captureMain(model, argument, schemes: SVShell.DebugSnapshot.schemes(model.config))
            return written.joined(separator: " ")
        case "status":
            return statusLine(model)
        case "wait-ready":
            let ok = await wait(Double(argument) ?? 900) { model.status == .ready && !model.tools.showsWindow && model.tools.phase == .notNeeded }
            return (ok ? "ready · " : "timeout · ") + statusLine(model)
        case "text":
            return model.t(argument)
        case "menu":
            let items = NSApp.mainMenu?.items ?? []
            // SwiftUI refreshes a menu's items when it opens: as if it were opened.
            for item in items { if let m = item.submenu { m.delegate?.menuNeedsUpdate?(m); m.update() } }
            let file = items.count > 1 ? (items[1].submenu?.items.prefix(4).map(\.title) ?? []) : []
            return items.dropFirst().map(\.title).joined(separator: "|") + " · " + file.joined(separator: "|")
        case "menu-dump":
            // One menu of the bar (0 = the app's), as the person sees it when it opens:
            // "title ⌘key" per item, "(off)" when dimmed, "✓" when checked, "—" for a separator.
            let items = NSApp.mainMenu?.items ?? []
            guard let i = Int(argument), items.indices.contains(i), let m = items[i].submenu else { return "bad menu" }
            m.delegate?.menuNeedsUpdate?(m); m.update()
            let lines = m.items.filter { !$0.isHidden }.map { item -> String in
                if item.isSeparatorItem { return "—" }
                var key = ""
                if !item.keyEquivalent.isEmpty {
                    let f = item.keyEquivalentModifierMask
                    key = (f.contains(.control) ? "⌃" : "") + (f.contains(.option) ? "⌥" : "") + (f.contains(.shift) ? "⇧" : "")
                        + (f.contains(.command) ? "⌘" : "")
                    let k = item.keyEquivalent
                    key += k == "\r" ? "↩" : k == "\u{8}" || k == "\u{7f}" ? "⌫" : k.uppercased()
                }
                return (item.state == .on ? "✓" : "") + item.title + (key.isEmpty ? "" : " " + key) + (item.isEnabled ? "" : " (off)")
            }
            return items[i].title + ": " + lines.joined(separator: " | ")
        case "window-size":
            guard let w = WindowSizer.main(model.config) else { return "no window" }
            let size = w.frame.size
            return "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
                + " · min \(Int(w.minSize.width))x\(Int(w.minSize.height)) · content min \(Int(w.contentMinSize.width))x\(Int(w.contentMinSize.height))"
        case "row-text":
            guard let idx = Int(argument), model.videos.indices.contains(idx) else { return "bad index" }
            let v = model.videos[idx]
            return "\(v.state.rawValue) · \(model.failureText(v)) · detail \(v.errorDetail ?? "-")"
        case "alert-other":
            guard let a = Alerts.shown, a.isOpen else { return "none" }
            return "\(a.alert.title) · buttons \(a.alert.buttons.map(\.title).joined(separator: "|"))"
        case "alert-other-press":
            guard let a = Alerts.shown, a.isOpen else { return "no alert" }
            guard let n = Int(argument), a.alert.buttons.indices.contains(n) else { return "bad button" }
            a.press(n)
            return "pressed \(a.alert.buttons[n].title)"
        case "lang-menu":
            return await languageMenu(model)
        case "report-close":
            // Back to the list, as the round ‹ does.
            guard model.report.session != nil else { return "no report" }
            model.closeReport()
            try? await Task.sleep(for: .milliseconds(450))
        default:
            // The F6 design snapshots (DebugCapture.swift).
            if let reply = await DebugCapture.run(command, argument, model) { return reply }
            return await DebugVideo.run(command, argument, model) ?? "unknown"
        }
        return "ok · tab \(model.tab.rawValue) · \(model.videos.count) videos · status \(model.status)"
    }

    /// "status ready · vision true · tools notNeeded · rows - · window 1360x840 · lang it · tab process".
    /// The bottom bar of Video as it reads (C3-02): "checked 2 · finished 0 · Elabora 2 video on",
    /// or "running …" while the batch bar is there.
    static func bottomBar(_ model: AppModel) -> String {
        if model.batch.running { return "running \(model.batch.index) of \(model.batch.total)" }
        return "checked \(model.checkedVideos.count) · finished \(model.finishedVideos.count) · \(model.startButtonTitle) \(model.canStart ? "on" : "off")"
    }

    /// The report in the Review page: "Revisione di a.mp4 · 12 righe · … · ready · back on · save on",
    /// or "list" when the page shows the list.
    private static func reportPage(_ model: AppModel) -> String {
        guard let session = model.report.session else {
            return "list · tab \(model.tab.rawValue) · back \(model.canGoBack ? "on" : "off")"
        }
        return "\(model.t("app.review.report.of")) \(session.title) · \(model.reportDetails(session)) · \(session.phase)"
            + " · tab \(model.tab.rawValue) · back \(model.canGoBack ? "on" : "off") · save \(model.canSaveReview ? "on" : "off")"
    }

    /// The Review page: "review 2 · a.mp4 lines 12 dropped 0 gaps 1 lang it-IT fps 6 reviewed no · …".
    private static func reviewState(_ model: AppModel) -> String {
        let rows = model.reviewVideos.map { v in
            "\(v.name) lines \(v.segments.map(String.init) ?? "-") dropped \(v.dropped.map(String.init) ?? "-")"
                + " gaps \(v.gaps.map { String($0.count) } ?? "-") lang \(v.ocrLang ?? "-") fps \(v.ocrFPS.map { String(Int($0)) } ?? "-")"
                + " report \(v.outputReport != nil ? "yes" : v.reviewReport != nil ? "missing" : "no")"
                + " reviewed \(model.hasReviewedSRT(v) ? "yes" : "no")"
        }
        let totals = rows.isEmpty ? [] : ["totals " + model.reviewTotals]
        return (["review \(rows.count)"] + rows + totals).joined(separator: " · ")
    }

    private static func statusLine(_ model: AppModel) -> String {
        let rows = model.tools.rows.map { "\($0.tool.key)=\($0.state)" }.joined(separator: ",")
        return "status \(model.status) · vision \(model.hello?.vision.description ?? "-") · tools \(model.tools.phase)"
            + " · rows \(rows.isEmpty ? "-" : rows) · lang \(model.language) · tab \(model.tab.rawValue)"
    }

    /// The inspector's language menu (O7's "Choose the Language"): `popUp` runs its own
    /// tracking loop, so a timer in the common modes reads the items and closes it.
    private static func languageMenu(_ model: AppModel) async -> String {
        var titles: [String]?
        var ticks = 0
        let timer = Timer(timeInterval: 0.1, repeats: true) { t in
            MainActor.assumeIsolated {
                ticks += 1
                if PopupMenuTracking.open != nil {
                    titles = PopupMenuTracking.titles
                    PopupMenuTracking.cancel()
                    t.invalidate()
                } else if ticks > 50 {
                    t.invalidate()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        _ = await wait(6) { titles != nil || !timer.isValid }
        guard let titles else { return "no menu" }
        let checked = titles.first { $0.hasPrefix("✓ ") } ?? "-"
        return "\(titles.count) items · checked \(checked) · first \(titles.prefix(3).joined(separator: "|"))"
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
            + " · running \(runningIndex(model).map(String.init) ?? "-")" + " · text \(open.presentation.alert.texts.joined(separator: " "))"
    }

    /// "done 2 failed 0 stopped 0 skipped 0 elapsed 12.3" of the last batch.
    private static func summaryLine(_ model: AppModel) -> String {
        guard let s = model.run.summary else { return "no summary" }
        return "done \(s.done) failed \(s.failed) stopped \(s.stopped) skipped \(s.skipped) elapsed \(s.elapsed)"
    }

    // MARK: - F5.2 · Preview (a page inside Video, C3-09)
    //
    //   preview-open [idx]             the Preview page, on the list's video idx (0-based) or on the one shown
    //                                  last, as the row's Preview button opens it; a video never searched
    //                                  starts its search by itself ("ok · <name> · searching")
    //   preview-close                  the title band's ‹ (View › Back): the page slides out, the list is back
    //   preview-layout                 one line: the window's size, the content area, the frame, the thumbnail
    //                                  rows and their width, the summary, the two panels' heights, then
    //                                  "fits" or "overflows" (from where the pieces were really drawn)
    //   preview-select <idx>           the list's video (0-based) on the page (refused for one it cannot show)
    //   preview-video up|down          the title band's arrows (⌘↑ ⌘↓): the video above / below
    //   preview-nav                    "video 2 di 3 · up <name>|off · down <name>|off", as the band shows it
    //   retry-frames · stop-frames     «Riprova» (the zones left) / Stop
    //   wait-frames <s>                until the search ends (replies with the frames found)
    //   frames-progress <done> <found>|off   board A0 for a capture: the video shown as if its search were at
    //                                  zone <done> (the real one on the demo clips is over before a capture ends)
    //   frame <n>|silent               the frame shown, 1-based; "silent": the first one without text
    //   frames                         every frame with its bands: "1:bottom 2:bottom+top 3:none …"
    //   frame-bands <bottom|top|bottom+top|none>   the shown frame's bands set by hand, as a quick probe
    //                                  of the search could have read them (design note 77: Try OCR corrects them)
    //   band-set <key> <value>         bottom-height, bottom-width, top-height, top-width (percent), top-band (0/1)
    //   drag-handle <band> <handle> <dx> <dy>   the drag's own function (`BandGeometry.apply`, the one the
    //                                  gesture calls) with the pointer moved by (dx, dy) pt from the handle
    //                                  (band: dialogue|signs; handle: height|left|right). Synthesized
    //                                  NSEvents sent or posted to the window never reach a SwiftUI
    //                                  DragGesture (it reads the real pointer), so there is no mouse command.
    //   try-ocr · wait-ocr <s>         Try OCR (or the stale panel's «Riprova OCR…») / until it answers
    //   preview-state                  the page, the video, the search (and why it stopped), the frame, the band
    //                                  values in UserDefaults, the test of the frame on screen ("test done stale
    //                                  signs": the panels with the grey note of C3-11), the panel's tab, Back

    private static func preview(_ command: String, _ argument: String, _ model: AppModel) async -> String {
        let args = argument.split(separator: " ").map(String.init)
        switch command {
        case "preview-open":
            var id: UUID?
            if !argument.isEmpty {
                guard let i = Int(argument), model.videos.indices.contains(i) else { return "bad index" }
                guard model.canPreview(model.videos[i]) else { return "cannot preview · \(model.videos[i].name)" }
                id = model.videos[i].id
            }
            model.openPreview(id)
            // The slide (0.25 s) and the band's Back set after it.
            try? await Task.sleep(for: .milliseconds(700))
            guard model.previewShown else { return "no preview page" }
            return "ok · \(model.previewVideo?.name ?? "none")" + (model.isSearchingPreviewVideo ? " · searching" : "")
        case "preview-close":
            guard model.previewShown else { return "no preview page" }
            model.backAction?()
            _ = await wait(3) { !model.preview.shown }
            try? await Task.sleep(for: .milliseconds(300))
            return model.preview.shown ? "still shown" : "ok · tab \(model.tab.rawValue) · back \(model.canGoBack ? "on" : "off")"
        case "preview-layout":
            return previewLayout(model)
        case "preview-select":
            guard let i = Int(argument), model.videos.indices.contains(i) else { return "bad index" }
            guard model.canPreview(model.videos[i]) else { return "cannot preview · \(model.videos[i].name)" }
            model.showPreviewVideo(model.videos[i].id)
            try? await Task.sleep(for: .milliseconds(300))
            return "ok · \(model.previewVideo?.name ?? "none")"
        case "preview-video":
            let step = argument == "up" ? -1 : 1
            guard model.previewNeighbour(step) != nil else { return "off" }
            model.showNeighbourVideo(step)
            try? await Task.sleep(for: .milliseconds(300))
            return "ok · \(model.previewVideo?.name ?? "none")" + (model.isSearchingPreviewVideo ? " · searching" : "")
        case "preview-nav":
            return previewNav(model)
        case "retry-frames":
            guard model.canFindFrames else { return "cannot search: \(previewState(model))" }
            model.findFrames()
            return "ok · searching"
        case "stop-frames":
            model.stopFrames()
            _ = await wait(15) { !model.isSearchingFrames }
            return "ok · \(previewState(model))"
        case "frames-progress":
            guard let id = model.previewVideo?.id else { return "no video" }
            if argument == "off" {
                guard model.preview.searching == id else { return "not held" }
                model.preview.search = .idle
                model.preview.searching = nil
                return "ok · \(previewState(model))"
            }
            guard args.count == 2, let done = Int(args[0]), let found = Int(args[1]), !model.isSearchingFrames else { return "bad arguments or searching" }
            model.preview.searching = id
            model.preview.search = .running(done: done, total: PreviewState.zones, found: found)
            try? await Task.sleep(for: .milliseconds(300))
            return "ok · \(previewState(model))"
        case "wait-frames":
            let ended = await wait(Double(argument) ?? 120) { !model.isSearchingFrames }
            guard ended else { return "timeout · \(previewState(model))" }
            if case .failed(let code, let message) = model.preview.search { return "failed \(code) \(message ?? "")" }
            guard let result = model.previewResult else { return "no frames" }
            let stop = result.search.stop.map { " · stopped \($0.rawValue)" } ?? ""
            return "\(result.frames.count) frames · \(result.found) with text · \(result.foundSigns) with signs · index \(result.index.map { "\($0 + 1)" } ?? "none")" + stop
        case "frame":
            if argument == "silent" {
                guard let i = model.previewFrames.firstIndex(where: { !$0.hasText }) else { return "no frame without text" }
                model.selectFrame(i)
                return "ok · frame \(i + 1)"
            }
            guard let n = Int(argument) else { return "bad number" }
            model.selectFrame(n - 1)
            return "ok · frame \(model.previewResult?.index.map { $0 + 1 } ?? 0)"
        case "frames":
            return model.previewFrames.enumerated().map { i, f in
                "\(i + 1):\(f.bands.isEmpty ? "none" : f.bands.joined(separator: "+"))"
            }.joined(separator: " ")
        case "frame-bands":
            guard let video = model.previewVideo, var result = model.preview.results[video.id],
                  let frame = model.previewFrame else { return "no frame" }
            let bands = argument == "none" ? [] : argument.split(separator: "+").map(String.init)
            var f = frame
            f.bands = bands
            f.hasText = !bands.isEmpty
            result.search.add(f, zone: frame.zone ?? 0)
            model.preview.results[video.id] = result
            return "ok · \(previewState(model))"
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
            guard rect.width > 0, model.previewShown else { return "no frame on screen" }
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
            switch model.previewTest {
            case .done(let reply, _)?:
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
        var parts = ["page \(model.previewShown ? "shown" : "hidden")", "video \(model.previewVideo?.name ?? "none")",
                     "search \(model.preview.search)"]
        if let r = model.previewResult {
            let stop = r.search.complete ? "complete" : (model.isSearchingPreviewVideo ? "running" : "stopped \(r.search.stop?.rawValue ?? "-") \(r.frames.count)/\(r.search.total)")
            parts.append("frames \(r.frames.count) found \(r.found) \(stop) index \(r.index.map { "\($0 + 1)" } ?? "none") bands \(model.previewFrame.map { $0.bands.isEmpty ? "none" : $0.bands.joined(separator: "+") } ?? "none")")
        }
        parts.append(bandValues())
        let stale = PreviewBand.allCases.filter { model.previewStale($0) }.map(\.rawValue)
        let test: String
        switch model.previewTest {
        case nil: test = "none"
        case .reading?: test = "reading"
        case .done?: test = "done"
        case .failed?: test = "failed"
        }
        parts.append("test \(test)" + (stale.isEmpty ? "" : " stale " + stale.joined(separator: "+")))
        parts.append("tests \(model.preview.tests.count)")
        parts.append("batch \(model.batch.running)")
        parts.append("panel \(UserDefaults.standard.string(forKey: InspectorTab.key) ?? "-")")
        parts.append("back \(model.canGoBack ? "on" : "off")")
        let r = model.preview.frameRect
        parts.append("frame \(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height))")
        return parts.joined(separator: " · ")
    }

    /// `preview-nav`: the right of the title band, as drawn.
    private static func previewNav(_ model: AppModel) -> String {
        guard model.previewShown else { return "no preview page" }
        let position = model.previewVideoIndex.map { model.t("app.preview.video_of", ["i": $0 + 1, "n": model.videos.count]) } ?? "-"
        let up = model.previewNeighbour(-1)?.name ?? "off", down = model.previewNeighbour(1)?.name ?? "off"
        return "\(position) · up \(up) · down \(down)"
    }

    /// `preview-layout`: what was really drawn, and whether it all fits the content area
    /// (the block inside it, the arrows too, the thumbnail rows as wide as the frame, the
    /// two panels as tall as each other and at least `PreviewLayout.panelsMin`).
    private static func previewLayout(_ model: AppModel) -> String {
        guard model.previewShown, let window = WindowSizer.main(model.config) else { return "no preview page" }
        let rects = PreviewMetrics.rects
        guard let content = rects["content"], let frame = rects["frame"] else { return "nothing drawn" }
        func size(_ r: CGRect) -> String { "\(fmt(r.width))x\(fmt(r.height))" }
        func inside(_ r: CGRect) -> Bool {
            r.minX >= content.minX - 0.5 && r.maxX <= content.maxX + 0.5 && r.minY >= content.minY - 0.5 && r.maxY <= content.maxY + 0.5
        }
        var parts = ["window \(Int(window.frame.width))x\(Int(window.frame.height))", "content \(size(content))"]
        var fits = inside(frame)
        let framesShown = model.previewFrame != nil && !model.isSearchingPreviewVideo
        if framesShown, let thumbs = rects["thumbs"], let summary = rects["summary"],
           let dialogue = rects["panel.dialogue"], let signs = rects["panel.signs"] {
            let layout = PreviewMetrics.layout
            parts.append("frame \(size(frame))")
            parts.append("thumbs \(PreviewLayout.rows)x\(PreviewLayout.columns) \(fmt(layout?.thumbWidth ?? 0))x\(fmt(layout?.thumbHeight ?? 0)) rows \(fmt(thumbs.width))")
            parts.append("summary \(fmt(summary.width))")
            parts.append("panels \(fmt(dialogue.height))/\(fmt(signs.height))")
            let arrows = frame.minX - PreviewLayout.arrow >= content.minX - 0.5 && frame.maxX + PreviewLayout.arrow <= content.maxX + 0.5
            let bottomGap = content.maxY - max(dialogue.maxY, signs.maxY)
            parts.append("bottom \(fmt(bottomGap))")
            let checks: [(String, Bool)] = [
                ("frame", fits), ("arrows", arrows), ("inside", [thumbs, summary, dialogue, signs].allSatisfy(inside)),
                ("thumbs", abs(thumbs.width - frame.width) < 0.5), ("panels", abs(dialogue.height - signs.height) < 0.5),
                ("min", dialogue.height >= PreviewLayout.panelsMin - 1), ("bottom", bottomGap >= PreviewLayout.bottom - 1),
                ("edges", abs(dialogue.minX - frame.minX) < 0.5 && abs(signs.maxX - frame.maxX) < 0.5),
                ("width", frame.width <= PreviewLayout.maxFrameWidth + 0.5), ("centre", abs(frame.midX - content.midX) < 1)]
            fits = checks.allSatisfy(\.1)
            if !fits { parts.append("failing " + checks.filter { !$0.1 }.map(\.0).joined(separator: ",")) }
        } else {
            parts.append("placeholder \(size(frame))")
        }
        parts.append(PreviewMetrics.scrolls ? "scrolls" : fits ? "fits" : "overflows")
        return parts.joined(separator: " · ")
    }

    private static func fmt(_ v: CGFloat) -> String {
        v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v)
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

    /// `key <combo> [main|front|<window number>]`: a key press as a real one goes, the app
    /// active, the window key and `NSApp.sendEvent` (menus' key equivalents, the focused
    /// field, the window's own handlers). The combo is modifiers and one key joined by "+":
    /// cmd, shift, opt, ctrl; a letter, a digit, ".", ",", return, esc, tab, space, delete,
    /// left, right, up, down. With no window, the key window (else the main one).
    private static func sendKey(_ argument: String, _ model: AppModel) async -> String {
        let parts = argument.split(separator: " ").map(String.init)
        guard let combo = parts.first else { return "usage: key <combo> [main|front|<window>]" }
        var flags: NSEvent.ModifierFlags = []
        var key = ""
        for token in combo.lowercased().split(separator: "+").map(String.init) {
            switch token {
            case "cmd": flags.insert(.command)
            case "shift": flags.insert(.shift)
            case "opt", "alt": flags.insert(.option)
            case "ctrl": flags.insert(.control)
            default: key = token
            }
        }
        let named: [String: (UInt16, String)] = [
            "return": (36, "\r"), "esc": (53, "\u{1b}"), "tab": (48, "\t"), "space": (49, " "), "delete": (51, "\u{7f}"), "backspace": (51, "\u{8}"),
            "left": (123, String(UnicodeScalar(NSLeftArrowFunctionKey)!)), "right": (124, String(UnicodeScalar(NSRightArrowFunctionKey)!)),
            "down": (125, String(UnicodeScalar(NSDownArrowFunctionKey)!)), "up": (126, String(UnicodeScalar(NSUpArrowFunctionKey)!)),
            ".": (47, "."), ",": (43, ","), "[": (33, "["),
        ]
        let letters: [Character: UInt16] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13,
            "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26,
            "8": 28, "0": 29, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
        ]
        let code: UInt16, chars: String
        if let n = named[key] { (code, chars) = n }
        else if key.count == 1, let c = letters[key.first!] { code = c; chars = key }
        else { return "unknown key \(key)" }
        NSApp.activate(ignoringOtherApps: true)
        let target: NSWindow?
        switch parts.count > 1 ? parts[1] : "" {
        case "main": target = WindowSizer.main(model.config)
        case "front", "": target = NSApp.keyWindow ?? WindowSizer.main(model.config)
        case let number: target = Int(number).flatMap { NSApp.window(withWindowNumber: $0) }
        }
        guard let window = target else { return "no window" }
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(300))
        // A real arrow key carries the function and numeric pad flags too (menus match on them).
        if (123...126).contains(code) { flags.formUnion([.function, .numericPad]) }
        let shown = flags.contains(.shift) && chars.count == 1 ? chars.uppercased() : chars
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: window.windowNumber, context: nil, characters: shown,
                                               charactersIgnoringModifiers: shown, isARepeat: false, keyCode: code)
            else { return "no event" }
            // Into the event queue, as the window server delivers a press: AppKit takes it from
            // there, not from inside this command (a modal alert it opens does not hold the command).
            NSApp.postEvent(event, atStart: false)
        }
        try? await Task.sleep(for: .milliseconds(400))
        let responder = NSApp.keyWindow?.firstResponder.map { String(describing: type(of: $0)) } ?? "none"
        return "key \(combo) · window \(window.windowNumber) · key window \(NSApp.keyWindow?.windowNumber ?? 0) · responder \(responder)"
    }

    /// `mouse click|double|right <x>,<y> [main|front|<window>] [pick <item title>]`: a click sent to
    /// the window as real mouse events (x, y in points from the window's top-left corner, as its
    /// captures). Taps, double taps and context menus see them; a DragGesture does not (see
    /// drag-handle). A right click replies with the context menu's items (read while it tracks) and
    /// closes it, or presses the item named after "pick".
    private static func sendMouse(_ argument: String, _ model: AppModel) async -> String {
        var parts = argument.split(separator: " ").map(String.init)
        var pick: String?
        if let p = parts.firstIndex(of: "pick") {
            pick = parts[(p + 1)...].joined(separator: " ")
            parts = Array(parts[..<p])
        }
        guard parts.count >= 2 else { return "usage: mouse click|double|right <x>,<y> [main|front|<window>] [pick <title>]" }
        let xy = parts[1].split(separator: ",").compactMap { Double($0) }
        guard xy.count == 2 else { return "bad point" }
        let target: NSWindow?
        let windowArgument = parts[0] == "drag" || parts[0] == "scroll" ? 3 : 2
        switch parts.count > windowArgument ? parts[windowArgument] : "" {
        case "main": target = WindowSizer.main(model.config)
        case "front", "": target = NSApp.keyWindow ?? WindowSizer.main(model.config)
        case let number: target = Int(number).flatMap { NSApp.window(withWindowNumber: $0) }
        }
        guard let window = target else { return "no window" }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(300))
        let point = NSPoint(x: xy[0], y: window.frame.height - xy[1])
        func event(_ type: NSEvent.EventType, _ clicks: Int) -> NSEvent? {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)
        }
        if parts[0] == "scroll" {
            // `mouse scroll <x>,<y> <dy> [window]`: wheel events of 10 pt each (positive: down the content).
            guard parts.count > 2, let dy = Double(parts[2]) else { return "usage: mouse scroll <x>,<y> <dy> [window]" }
            let steps = max(1, Int(abs(dy) / 10))
            for _ in 0..<steps {
                guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                       wheel1: Int32(dy > 0 ? -10 : 10), wheel2: 0, wheel3: 0) else { return "no event" }
                cg.location = CGPoint(x: window.frame.minX + xy[0], y: (NSScreen.screens.first?.frame.height ?? 0) - window.frame.maxY + xy[1])
                guard let wheel = NSEvent(cgEvent: cg) else { return "no event" }
                window.sendEvent(wheel)
                try? await Task.sleep(for: .milliseconds(15))
            }
            try? await Task.sleep(for: .milliseconds(400))
            return "scroll \(Int(dy)) at \(Int(xy[0])),\(Int(xy[1])) · window \(window.windowNumber)"
        }
        if parts[0] == "drag" {
            // `mouse drag <x>,<y> <x2>,<y2> [window]`: down, ten moves, up, each sent to the window.
            let to = parts.count > 2 ? parts[2].split(separator: ",").compactMap { Double($0) } : []
            guard to.count == 2 else { return "usage: mouse drag <x>,<y> <x2>,<y2> [window]" }
            func at(_ type: NSEvent.EventType, _ x: Double, _ y: Double) -> NSEvent? {
                NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: window.frame.height - y), modifierFlags: [],
                                   timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                   context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
            }
            guard let down = at(.leftMouseDown, xy[0], xy[1]) else { return "no event" }
            window.sendEvent(down)
            for i in 1...10 {
                try? await Task.sleep(for: .milliseconds(30))
                let f = Double(i) / 10
                if let move = at(.leftMouseDragged, xy[0] + (to[0] - xy[0]) * f, xy[1] + (to[1] - xy[1]) * f) { window.sendEvent(move) }
            }
            if let up = at(.leftMouseUp, to[0], to[1]) { window.sendEvent(up) }
            try? await Task.sleep(for: .milliseconds(400))
            return "drag \(Int(xy[0])),\(Int(xy[1])) → \(Int(to[0])),\(Int(to[1])) · window \(window.windowNumber)"
        }
        guard ["click", "double", "right"].contains(parts[0]) else { return "unknown mouse action" }
        // A menu that opens (a context menu, a ⋯ or pop-up button) runs its own tracking loop:
        // its items are read when it starts and it is closed on the next turn, pressing "pick".
        var titles: [String]?
        var pressed = "-"
        let observer = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { note in
            guard let opened = note.object as? NSMenu else { return }
            nonisolated(unsafe) let menu = opened
            MainActor.assumeIsolated {
                menu.update()
                titles = menu.items.filter { !$0.isHidden }.map { item in
                    item.isSeparatorItem ? "—" : (item.state == .on ? "✓ " : "") + item.title + (item.isEnabled ? "" : " (off)")
                }
                let timer = Timer(timeInterval: 0.15, repeats: false) { _ in
                    MainActor.assumeIsolated {
                        if let pick, let i = menu.items.firstIndex(where: { $0.title == pick }) {
                            pressed = pick
                            menu.performActionForItem(at: i)
                        }
                        menu.cancelTracking()
                    }
                }
                RunLoop.main.add(timer, forMode: .common)
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        if parts[0] == "right" {
            guard let down = event(.rightMouseDown, 1), let up = event(.rightMouseUp, 1) else { return "no event" }
            window.sendEvent(down)
            window.sendEvent(up)
        } else {
            let times = parts[0] == "double" ? 2 : 1
            for n in 1...times {
                guard let down = event(.leftMouseDown, n), let up = event(.leftMouseUp, n) else { return "no event" }
                window.sendEvent(down)
                window.sendEvent(up)
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
        _ = await wait(parts[0] == "right" ? 3 : 0.8) { titles != nil }
        try? await Task.sleep(for: .milliseconds(300))
        let head = "\(parts[0]) \(Int(xy[0])),\(Int(xy[1])) · window \(window.windowNumber)"
        guard let titles else { return head + (parts[0] == "right" ? " · no menu" : "") }
        return head + " · menu \(titles.joined(separator: " | ")) · pressed \(pressed)"
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
