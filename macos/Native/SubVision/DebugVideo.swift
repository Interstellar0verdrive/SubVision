// SPDX-License-Identifier: MIT
// Debug only: the commands of the Video list of design round C3 (boards
// C3-02–C3-05, E3, E5, E8, E10), reached through `DebugQA`
// (`SUBVISION_COMMANDS=<file>`).
//
//   checks                         the header's box and each row's: "header mixed · a.mp4=on b.mp4=- c.mp4=redo"
//                                  (on/off: a box; "-": no box; "redo": a finished row checked, "will be redone")
//   check <idx>[,<idx>…]           a click on those rows' boxes (a finished row's outcome too); replies as checks
//   header                         a click on the header's box; replies as checks
//   drawer <idx> open|close|toggle the row's drawer, as a click on the row; replies as drawers
//   drawers                        the rows whose drawer is open
//   retry <idx>                    Retry on a failed or stopped row: at once without a batch, queued during one;
//                                  replies "running … · queued … · " and the checks
//   queued                         the rows Retry queued during the batch ("queued b.mp4", "queued -")
//   row-menu <idx>                 opens the row's ⋯ menu, reads its items ("title ⌘key", "(off)", "✓", "—") and closes it
//   row-menu-shot <idx> <path>     the main window with that ⋯ menu open over it (`screencapture`, the scheme in use)
//   screen-shot <path>             the main window as the screen shows it (`screencapture`), the scheme in use
//   video-fake before|drawers|batch|failed|outcomes|stopped|off
//                                  the first three videos of the list in the states of the boards, fed by hand
//                                  (a batch on the demo clips is over too fast to catch); off puts them back
//   strips                         what each to-do drawer's strip shows: "a.mp4=video:5 b.mp4=preview:20 c.mp4=none"
//                                  (none: the empty boxes; extracting: the shimmer; video:<n>: the frames of the
//                                  video taken; preview:<n>: the frames the Preview found)
//   wait-strips <s>                until no strip is extracting any more, then as strips
//   strip-hold <idx>|off           that row's strip shown as extracting whatever it has (a capture of the
//                                  shimmer: the demo clips take 0.3 s); off lets every row go

#if DEBUG
import AppKit
import SVShell
import SwiftUI

@MainActor
enum DebugVideo {
    static func run(_ command: String, _ argument: String, _ model: AppModel) async -> String? {
        let args = argument.split(separator: " ").map(String.init)
        switch command {
        case "checks":
            return checks(model)
        case "check":
            for idx in argument.split(separator: ",").compactMap({ Int($0) }) where model.videos.indices.contains(idx) {
                model.toggleCheck(model.videos[idx].id)
            }
            return checks(model)
        case "header":
            model.toggleHeader()
            return checks(model)
        case "drawer":
            guard args.count == 2, let idx = Int(args[0]), model.videos.indices.contains(idx) else { return "usage: drawer <idx> open|close|toggle" }
            let id = model.videos[idx].id
            switch args[1] {
            case "open": model.setDrawer(id, open: true)
            case "close": model.setDrawer(id, open: false)
            default: model.toggleDrawer(id)
            }
            return drawers(model)
        case "drawers":
            return drawers(model)
        case "retry":
            guard let idx = Int(argument), model.videos.indices.contains(idx) else { return "bad index" }
            let wasRunning = model.batch.running
            model.retry(model.videos[idx].id)
            if !wasRunning { _ = await DebugQA.wait(5) { model.batch.running } }
            return "running \(model.batch.running) · " + queued(model) + " · " + checks(model)
        case "queued":
            return queued(model)
        case "row-menu":
            guard let idx = Int(argument), model.videos.indices.contains(idx) else { return "bad index" }
            return await rowMenu(model, idx, shot: nil)
        case "row-menu-shot":
            guard args.count == 2, let idx = Int(args[0]), model.videos.indices.contains(idx) else { return "usage: row-menu-shot <idx> <path>" }
            return await rowMenu(model, idx, shot: args[1])
        case "video-fake":
            return fake(argument, model)
        case "strips":
            return strips(model)
        case "wait-strips":
            let settled = await DebugQA.wait(Double(argument) ?? 60) {
                model.videos.allSatisfy { if case .extracting = model.drawerStrip($0) { return false } else { return true } }
            }
            return (settled ? "" : "timeout · ") + strips(model)
        case "strip-hold":
            if argument == "off" {
                model.videoFrames.heldExtracting = []
                return strips(model)
            }
            guard let idx = Int(argument), model.videos.indices.contains(idx) else { return "usage: strip-hold <idx>|off" }
            model.videoFrames.heldExtracting.insert(model.videos[idx].id)
            return strips(model)
        case "screen-shot":
            // The main window as the screen shows it (`screencapture`), not drawn again by `capture`.
            guard !argument.isEmpty else { return "usage: screen-shot <path>" }
            NSApp.activate(ignoringOtherApps: true)
            WindowSizer.main(model.config)?.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(400))
            return capture(model, argument)
        default:
            return nil
        }
    }

    /// "header mixed · a.mp4=on b.mp4=- c.mp4=redo".
    static func checks(_ model: AppModel) -> String {
        let rows = model.checkRows
        let header = VideoChecks.headerEnabled(rows) ? "\(VideoChecks.headerState(rows))" : "none"
        let each = model.videos.map { v -> String in
            let row = v.checkRow
            let mark = !row.hasBox ? "-" : v.willRedo ? "redo" : row.checked ? "on" : "off"
            return "\(v.name)=\(mark)"
        }
        return "header \(header) · " + each.joined(separator: " ")
    }

    /// "queued b.mp4": the rows Retry queued during the batch, "queued -" without any.
    static func queued(_ model: AppModel) -> String {
        let names = model.videos.filter { model.retryQueued($0.id) }.map(\.name)
        return "queued " + (names.isEmpty ? "-" : names.joined(separator: " "))
    }

    /// "a.mp4=video:5 b.mp4=preview:20 c.mp4=none".
    static func strips(_ model: AppModel) -> String {
        model.videos.map { "\($0.name)=\(model.drawerStrip($0).debugName)" }.joined(separator: " ")
    }

    static func drawers(_ model: AppModel) -> String {
        let open = model.videos.filter { model.run.expanded.contains($0.id) }.map(\.name)
        return "open " + (open.isEmpty ? "-" : open.joined(separator: " "))
    }

    // MARK: - The ⋯ menu

    /// Opens the row's ⋯ (as its click does), reads the menu or captures the window under it, closes it.
    private static func rowMenu(_ model: AppModel, _ idx: Int, shot: String?) async -> String {
        var reply = "no menu"
        var ticks = 0
        let timer = Timer(timeInterval: 0.1, repeats: true) { t in
            MainActor.assumeIsolated {
                ticks += 1
                if let menu = PopupMenuTracking.open, ticks >= 6 {
                    reply = describe(menu)
                    if let shot { reply += " · " + capture(model, shot) }
                    PopupMenuTracking.cancel()
                    t.invalidate()
                } else if ticks > 60 {
                    t.invalidate()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        NSApp.activate(ignoringOtherApps: true)
        WindowSizer.main(model.config)?.makeKeyAndOrderFront(nil)
        let id = model.videos[idx].id
        model.rowMenuRequest = (id, (model.rowMenuRequest?.count ?? 0) + 1)
        _ = await DebugQA.wait(8) { !timer.isValid }
        timer.invalidate()
        return reply
    }

    private static func describe(_ menu: NSMenu) -> String {
        menu.items.map { item -> String in
            if item.isSeparatorItem { return "—" }
            var key = ""
            if !item.keyEquivalent.isEmpty {
                key = item.keyEquivalentModifierMask.contains(.command) ? "⌘" : ""
                key += item.keyEquivalent == "\u{8}" ? "⌫" : item.keyEquivalent.uppercased()
            }
            return (item.state == .on ? "✓" : "") + item.title + (key.isEmpty ? "" : " " + key) + (item.isEnabled ? "" : " (off)")
        }.joined(separator: " | ")
    }

    /// The main window's rectangle on screen, with the menu over it (E8).
    private static func capture(_ model: AppModel, _ path: String) -> String {
        guard let window = WindowSizer.main(model.config), let screen = window.screen ?? NSScreen.main else { return "no window" }
        let f = window.frame
        // screencapture's -R is in points from the top-left of the main screen.
        let top = (NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY) - f.maxY
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-x", "-R\(Int(f.minX)),\(Int(top)),\(Int(f.width)),\(Int(f.height))", path]
        try? task.run()
        task.waitUntilExit()
        return task.terminationStatus == 0 ? path : "screencapture failed"
    }

    // MARK: - The boards' states, fed by hand

    private static let plan2 = ["extract:bottom", "group:bottom", "ocr:bottom", "refine:bottom",
                                "extract:top", "group:top", "ocr:top", "refine:top"]

    private static func done(_ v: inout VideoItem, lines: Int, refined: Int, elapsed: Double, gaps: [[Double]], when: Date = Date()) {
        v.resetOutcome()
        v.state = .done
        v.segments = lines; v.dropped = 0; v.refined = refined; v.elapsed = elapsed
        v.plan = plan2
        v.times = ["extract:bottom": 1, "group:bottom": 0.4, "ocr:bottom": 34, "refine:bottom": 5,
                   "extract:top": 1, "group:top": 0.3, "ocr:top": 22, "refine:top": 0.6]
        v.gaps = gaps
        v.ocrLang = "it-IT"; v.ocrFPS = 12; v.gapWarn = 3
        v.finished = when
        let stem = v.url.deletingPathExtension()
        v.srtPath = stem.appendingPathExtension("srt").path
        v.reportPath = stem.path + ".review.html"
        v.logPath = stem.appendingPathExtension("log").path
        v.checked = nil
    }

    private static func failed(_ v: inout VideoItem) {
        v.resetOutcome()
        v.state = .failed
        v.error = "unknown (OCRError: Vision request failed (-1) · frame 000984.jpg)"
        v.failCode = "unknown"
        v.failText = "Vision request failed (-1)"
        v.failDetail = "OCRError: Vision request failed (-1) · frame 000984.jpg"
        v.failPath = v.path
        v.logPath = v.url.deletingPathExtension().appendingPathExtension("log").path
        v.atStep = "ocr:bottom"
        v.plan = plan2
        v.times = ["extract:bottom": 1, "group:bottom": 0.4, "ocr:bottom": 12]
        v.finished = Date()
        v.checked = nil
    }

    private static func steps(running: String) -> [StepRun] {
        var out: [StepRun] = []
        var past = true
        for id in plan2 {
            let parts = id.split(separator: ":").map(String.init)
            let estimates: [String: Double] = ["extract": 1, "group": 0.5, "ocr": 23, "refine": 5]
            var s = StepRun(key: parts[0], band: parts[1], estimate: estimates[parts[0]])
            if id == running {
                s.state = .running; s.ratio = 0.54; s.count = 412; s.total = 756; s.eta = 16; s.rate = 24; s.elapsed = 18; past = false
            } else if past {
                s.state = .done; s.ratio = 1; s.count = 660; s.duration = parts[0] == "extract" ? 1 : 0.4; s.elapsed = s.duration ?? 0
            }
            out.append(s)
        }
        return out
    }

    private static func fake(_ scene: String, _ model: AppModel) -> String {
        guard model.videos.count >= 3 else { return "needs three videos" }
        let ids = model.videos.prefix(3).map(\.id)
        model.batch = BatchActivity()
        model.run = BatchRun()
        model.focusedRow = nil
        for i in 0..<3 { model.videos[i].resetOutcome(); model.videos[i].checked = nil }
        switch scene {
        case "before":
            // C3-02: a video to do with its drawer and the ring, a done one, one to do whose SRT is there.
            done(&model.videos[1], lines: 14, refined: 7, elapsed: 79, gaps: [[0, 3], [41, 44], [51, 55]])
            model.run.expanded = [ids[0]]
            model.focusedRow = ids[0]
        case "drawers":
            // C3-03, E10: the done row open, the one to do open.
            done(&model.videos[0], lines: 12, refined: 5, elapsed: 64, gaps: [[0, 3], [41, 44], [51, 55]])
            done(&model.videos[1], lines: 14, refined: 7, elapsed: 79, gaps: [[0, 3], [41, 44], [51, 55]])
            model.run.expanded = [ids[0], ids[2]]
        case "batch":
            // C3-04: the first done in this batch, the second running with its drawer, the third waiting.
            done(&model.videos[0], lines: 12, refined: 5, elapsed: 64, gaps: [[0, 3], [41, 44], [51, 55]])
            model.videos[1].state = .running
            model.videos[2].state = .waiting
            model.run = BatchRun(ids: ids, steps: steps(running: "ocr:bottom"), fileStarted: Date().addingTimeInterval(-27), lastFileElapsed: 64)
            model.run.expanded = [ids[1]]
            model.batch = BatchActivity(running: true, index: 2, total: 3, name: model.videos[1].name, fraction: 0.47,
                                        endsAround: AppModel.clockTime(Date().addingTimeInterval(140)))
        case "failed":
            // C3-05, E8: done, failed with its drawer, done.
            done(&model.videos[0], lines: 12, refined: 5, elapsed: 64, gaps: [[0, 3], [41, 44], [51, 55]])
            failed(&model.videos[1])
            done(&model.videos[2], lines: 14, refined: 7, elapsed: 79, gaps: [[0, 3], [41, 44], [51, 55]])
            model.run.expanded = [ids[1]]
        case "outcomes":
            // E3: done (open), no subtitles, failed, and a stopped one if there is a fourth.
            done(&model.videos[0], lines: 12, refined: 5, elapsed: 64, gaps: [[0, 3], [41, 44], [51, 55], [60, 64]])
            done(&model.videos[1], lines: 0, refined: 0, elapsed: 70, gaps: [])
            model.videos[1].state = .noSubs
            failed(&model.videos[2])
            if model.videos.count > 3 {
                model.videos[3].resetOutcome()
                model.videos[3].state = .stopped
                model.videos[3].atStep = "extract:top"
                model.videos[3].plan = plan2
                model.videos[3].times = ["extract:bottom": 1, "group:bottom": 0.4, "ocr:bottom": 30, "refine:bottom": 4]
                model.videos[3].finished = Date()
            }
            model.run.expanded = [ids[0]]
        case "stopped":
            // E5: done, stopped, the rest not started and still checked; the note over the list.
            done(&model.videos[0], lines: 12, refined: 5, elapsed: 64, gaps: [[0, 3]])
            model.videos[1].state = .stopped
            model.videos[1].atStep = "ocr:bottom"
            model.videos[1].plan = plan2
            model.videos[1].times = ["extract:bottom": 1, "group:bottom": 0.4, "ocr:bottom": 20]
            model.videos[1].finished = Date()
            model.run.readyAgain = Set(model.videos.dropFirst(2).map(\.id))
            model.run.stoppedAt = Date()
            model.run.stoppedByUser = true
        case "off":
            model.run.expanded = []
        default:
            return "usage: video-fake before|drawers|batch|failed|outcomes|stopped|off"
        }
        model.saveVideos()
        return "ok · \(scene) · " + checks(model)
    }
}
#endif
