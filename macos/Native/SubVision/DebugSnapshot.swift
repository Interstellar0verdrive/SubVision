// SPDX-License-Identifier: MIT
// Debug only: `SUBVISION_SNAPSHOT=/path/shot` writes PNGs of the windows a
// few seconds after launch, in light and dark with
// `SUBVISION_SNAPSHOT_SCHEME=both`, then quits. `SUBVISION_SNAPSHOT_ADD=<paths>`
// (comma-separated files or folders) fills the list first;
// `SUBVISION_SNAPSHOT_SETTINGS=1` renders the four Settings tabs;
// `SUBVISION_SNAPSHOT_FIX=<srt>` runs Sub fix on that file and captures F1–F3;
// `SUBVISION_SNAPSHOT_REPORT=<report.html>` opens that report and captures
// the window of R1–R3 (the export of R2 writes an SRT next to it).
// Adapted from the DebugSnapshot of the native macOS app of AnimeUp (by the
// same author); the renderers are the shell's.

#if DEBUG
import AppKit
import SVShell
import SwiftUI

@MainActor
enum DebugSnapshot {
    static func scheduleIfAsked(model: AppModel) {
        guard let base = SVShell.DebugSnapshot.base(model.config) else { return }
        let env = ProcessInfo.processInfo.environment
        let schemes = SVShell.DebugSnapshot.schemes(model.config)
        Task { @MainActor in
            await toolsWindow(model, base: base, schemes: schemes)
            _ = await DebugQA.wait(600) { model.status == .ready && !model.tools.showsWindow }
            try? await Task.sleep(for: .seconds(1.5))
            model.tab = .process
            await capture(model, "\(base)-process-empty.png", schemes: schemes)
            model.openPreview(nil)
            await capture(model, "\(base)-preview-empty.png", schemes: schemes)
            model.tab = .fix
            await capture(model, "\(base)-fix-empty.png", schemes: schemes)
            if let srt = env["SUBVISION_SNAPSHOT_FIX"], !srt.isEmpty {
                await fixStates(model, srt: srt, base: base, schemes: schemes)
            }
            model.tab = .process
            if let add = env["SUBVISION_SNAPSHOT_ADD"], !add.isEmpty {
                model.add(add.split(separator: ",").map { URL(fileURLWithPath: String($0)) })
                _ = await DebugQA.wait(60) { model.videos.allSatisfy(\.probed) }
                try? await Task.sleep(for: .seconds(1))
                model.selection = []
                await capture(model, "\(base)-process-videos.png", schemes: schemes)
                model.openPreview(nil)
                await capture(model, "\(base)-preview-videos.png", schemes: schemes)
                model.tab = .process
            }
            // The narrow window (760x640, as N1 and N2): the parameters retracted.
            if let window = WindowSizer.main(model.config) {
                let saved = window.frame
                setNarrow(window)
                try? await Task.sleep(for: .seconds(1))
                await capture(model, "\(base)-narrow.png", schemes: schemes)
                window.setFrame(saved, display: true)
                try? await Task.sleep(for: .milliseconds(500))
            }
            if env["SUBVISION_SNAPSHOT_TOOLS"] == "1" {
                renderToolsStates(model, base: base, schemes: schemes)
            }
            if env["SUBVISION_SNAPSHOT_SETTINGS"] == "1" {
                for tab in SettingsTab.allCases {
                    SVShell.DebugSnapshot.render(SettingsPage(tab: tab).environment(model), width: 640, schemes: schemes,
                                                 "\(base)-settings-\(tab.rawValue).png")
                }
                model.batch.running = true
                SVShell.DebugSnapshot.render(SettingsPage(tab: .tools).environment(model), width: 640, schemes: schemes,
                                             "\(base)-settings-tools-locked.png")
                SVShell.DebugSnapshot.render(SettingsPage(tab: .lists).environment(model), width: 640, schemes: schemes,
                                             "\(base)-settings-lists-locked.png")
                model.batch.running = false
            }
            if env["SUBVISION_SNAPSHOT_PROCESS"] == "1" {
                await processStates(model, base: base, schemes: schemes)
            }
            if env["SUBVISION_SNAPSHOT_PREVIEW"] == "1" {
                await previewStates(model, base: base, schemes: schemes)
            }
            if let report = env["SUBVISION_SNAPSHOT_REPORT"], !report.isEmpty {
                await reportWindows(model, report: URL(fileURLWithPath: report), base: base, schemes: schemes)
            }
            AppLog.shared.info("snapshots done")
            NSApp.terminate(nil)
        }
    }

    // MARK: - F5.1: the batch states (E2–E6, I1–I3, N1), fed by hand

    /// The list (three videos from `SUBVISION_SNAPSHOT_ADD`) put in the states of
    /// the boards: a batch is over in seconds on the demo clips, too fast to catch.
    private static func processStates(_ model: AppModel, base: String, schemes: [ColorScheme]) async {
        guard model.videos.count >= 3 else { AppLog.shared.error("process snapshots need three videos"); return }
        let window = WindowSizer.main(model.config)
        func settle() async { try? await Task.sleep(for: .milliseconds(600)) }
        func steps(_ bands: [String], running: String?, failedAt: String? = nil) -> [StepRun] {
            var out: [StepRun] = []
            var past = true
            for band in bands {
                for key in ["extract", "group", "ocr", "refine"] {
                    var s = StepRun(key: key, band: band, estimate: [134, 12, 3820, 468][["extract", "group", "ocr", "refine"].firstIndex(of: key)!])
                    let id = "\(key):\(band)"
                    if id == failedAt { s.state = .aborted; s.ratio = 0.3; past = false }
                    else if !past { s.state = failedAt == nil ? .waiting : .notRun }
                    else if id == running {
                        s.state = .running; s.ratio = 0.62; s.count = 10565; s.total = 17040; s.eta = 1420; s.rate = 4.5; s.elapsed = 2347; past = false
                    } else {
                        s.state = .done; s.ratio = 1; s.count = 17040; s.duration = s.estimate; s.elapsed = s.estimate ?? 0
                    }
                    out.append(s)
                }
            }
            return out
        }
        let ids = model.videos.prefix(3).map(\.id)
        model.resetOcrParams()
        model.defaults.set("read", forKey: "inspector.tab")
        model.selection = []
        // I1: the inspector open with the defaults, the list ready.
        model.inspectorOpen = true
        await settle()
        await capture(model, "\(base)-I1.png", schemes: schemes)
        // I2: the Lines tab, two values changed (one of them in Reading: its tab gets the dot).
        model.defaults.set("lines", forKey: "inspector.tab")
        model.defaults.set(1.0, forKey: OcrKey.mergeGap)
        model.defaults.set(1, forKey: OcrKey.skipHamming)
        await settle()
        await capture(model, "\(base)-I2.png", schemes: schemes)
        model.resetOcrParams()
        model.defaults.set("read", forKey: "inspector.tab")
        // E2 / I3: file 2 of 3 with its steps, the first done, the third waiting; the inspector locked.
        model.videos[0].state = .done
        model.videos[0].segments = 312; model.videos[0].dropped = 9; model.videos[0].refined = 588; model.videos[0].elapsed = 5460
        model.videos[0].plan = ["extract:bottom", "group:bottom", "ocr:bottom", "refine:bottom", "extract:top", "group:top", "ocr:top", "refine:top"]
        model.videos[0].times = ["extract:bottom": 134, "group:bottom": 12, "ocr:bottom": 3820, "refine:bottom": 468,
                                 "extract:top": 121, "group:top": 11, "ocr:top": 842, "refine:top": 52]
        model.videos[0].finished = Date()
        model.videos[1].state = .running
        model.videos[2].state = .waiting
        model.run = BatchRun(ids: ids, steps: steps(["bottom", "top"], running: "ocr:bottom"), fileStarted: Date().addingTimeInterval(-2480), lastFileElapsed: 5460)
        model.batch = BatchActivity(running: true, index: 2, total: 3, name: model.videos[1].name, fraction: 0.52,
                                    endsAround: AppModel.clockTime(Date().addingTimeInterval(3600)))
        await settle()
        await capture(model, "\(base)-E2.png", schemes: schemes)
        // N1: the narrow window with the batch running.
        if let window {
            let saved = window.frame
            model.inspectorOpen = false
            setNarrow(window)
            await settle()
            await capture(model, "\(base)-N1.png", schemes: schemes)
            window.setFrame(saved, display: true)
            await settle()
        }
        // I3 centre: the saved language is not one of this Mac's.
        model.batch = BatchActivity()
        model.run = BatchRun()
        model.videos[1].state = .ready
        model.videos[2].state = .ready
        model.inspectorOpen = true
        model.defaults.set("xx-XX", forKey: OcrKey.langHint)
        await settle()
        await capture(model, "\(base)-I3-language.png", schemes: schemes)
        model.resetOcrParams()
        model.inspectorOpen = false
        // E3: the outcomes, the done row opened; E4 and E5 share the list.
        model.videos[1].state = .noSubs
        model.videos[1].segments = 0; model.videos[1].elapsed = 5520; model.videos[1].finished = Date()
        model.videos[2].state = .failed
        // As the engine sends it since F6: the code, the short text for the row, the detail and the log.
        model.videos[2].error = "unknown (OCRError: Vision request failed (-1) · frame 000412.jpg)"
        model.videos[2].failCode = "unknown"
        model.videos[2].failText = "Vision request failed (-1)"
        model.videos[2].failDetail = "OCRError: Vision request failed (-1) · frame 000412.jpg"
        model.videos[2].failPath = model.videos[2].path
        model.videos[2].logPath = model.videos[2].url.deletingPathExtension().appendingPathExtension("log").path
        model.videos[2].atStep = "ocr:bottom"
        model.videos[2].plan = ["extract:bottom", "group:bottom", "ocr:bottom", "refine:bottom"]
        model.videos[2].times = ["extract:bottom": 1, "group:bottom": 0.4, "ocr:bottom": 3]
        model.videos[2].finished = Date()
        model.run.expanded = [ids[0]]
        await settle()
        await capture(model, "\(base)-E3.png", schemes: schemes)
        model.run.expanded = []
        await settle()
        await capture(model, "\(base)-E4.png", schemes: schemes)
        // E5: a file stopped, the batch going on with the next.
        model.videos[0].state = .stopped
        model.videos[0].atStep = "ocr:bottom"
        model.videos[1].state = .running
        model.videos[2].resetOutcome()
        model.videos[2].state = .waiting
        model.run = BatchRun(ids: ids, steps: steps(["bottom"], running: "extract:bottom"), fileStarted: Date().addingTimeInterval(-4))
        model.run.steps[0].ratio = 0.05; model.run.steps[0].count = 800; model.run.steps[0].eta = nil; model.run.steps[0].rate = nil
        model.batch = BatchActivity(running: true, index: 2, total: 3, name: model.videos[1].name, fraction: 0.35)
        await settle()
        await capture(model, "\(base)-E5.png", schemes: schemes)
        // E6: the sheet, rendered on its own (a sheet is another window).
        model.batch = BatchActivity()
        model.run = BatchRun(ids: ids)
        model.videos[0].state = .done; model.videos[0].atStep = nil
        model.videos[1].state = .noSubs
        model.videos[2].state = .failed; model.videos[2].atStep = "ocr:bottom"; model.videos[2].error = "unknown (OCRError: Vision request failed (-1))"
        model.videos[2].failCode = "unknown"; model.videos[2].failText = "Vision request failed (-1)"
        model.run.summary = BatchSummary(ids: ids, done: 2, failed: 1, stopped: 0, skipped: 0, elapsed: 11040, when: Date(), seen: true)
        SVShell.DebugSnapshot.render(FinishedSheet().environment(model), width: 520, schemes: schemes, "\(base)-E6.png")
        for i in 0..<3 { model.videos[i].resetOutcome() }
        model.run = BatchRun()
        model.saveVideos()
    }

    // MARK: - F5.2 · Preview (A1–A6, N2)

    /// `SUBVISION_SNAPSHOT_PREVIEW=1`, with a video from `SUBVISION_SNAPSHOT_ADD`:
    /// the real search and the real OCR test on the first video; A5 is fed by
    /// hand (the demo clip has text in every zone and its duration reads fine).
    private static func previewStates(_ model: AppModel, base: String, schemes: [ColorScheme]) async {
        guard let video = model.videos.first(where: { $0.state == .ready }) else { return }
        let window = WindowSizer.main(model.config)
        model.inspectorOpen = false
        model.openPreview(nil)
        model.selectPreviewVideo(video.id)
        try? await Task.sleep(for: .milliseconds(500))
        await capture(model, "\(base)-A1.png", schemes: schemes)
        // A2: the search at zone 12, fed by hand (on the demo clip the real one
        // is over in a few seconds, less than the two captures take).
        model.preview.search = .running(done: 12, total: PreviewState.zones, found: 9)
        try? await Task.sleep(for: .milliseconds(400))
        await capture(model, "\(base)-A2.png", schemes: schemes)
        model.preview.search = .idle
        model.findFrames()
        guard await DebugQA.wait(180, { !model.isSearchingFrames }), let result = model.previewResult else { return }
        try? await Task.sleep(for: .seconds(1))
        // A3: the inspector open, the dialogue band's top edge held at 31 %.
        model.inspectorOpen = true
        let savedHeight = BandValues.height(.dialogue)
        BandValues.setHeight(31, .dialogue)
        model.preview.drag = BandDrag(band: .dialogue, height: 31, width: BandValues.width(.dialogue))
        try? await Task.sleep(for: .milliseconds(600))
        await capture(model, "\(base)-A3.png", schemes: schemes)
        model.preview.drag = nil
        BandValues.setHeight(savedHeight, .dialogue)
        model.inspectorOpen = false
        // A4: Try OCR on the frame with text.
        model.tryOCR()
        _ = await DebugQA.wait(120) { !model.isReadingOCR }
        try? await Task.sleep(for: .milliseconds(600))
        await capture(model, "\(base)-A4.png", schemes: schemes)
        // A5, fed by hand: no zone with text, the duration not read, a stale test with an empty dialogue band.
        var silent = result
        silent.frames = result.frames.map { var f = $0; f.bands = []; f.hasText = false; return f }
        silent.index = min(silent.index, silent.frames.count - 1)
        model.preview.results[video.id] = silent
        model.preview.search = .failed(code: "invalid_duration", message: nil)
        let json = #"{"bands":{"bottom":{"text":"","conf":0,"agree":0,"alts":[],"final":"","ms":214,"variants":3,"empty":true},"top":{"text":"IL MERCATO","conf":0.71,"agree":0.67,"alts":["IL MERCAT0","LL MERCATO"],"final":"{\\an8}IL MERCATO","ms":96,"variants":3,"empty":false}}}"#
        if let reply = try? EngineCoding.decoder.decode(OcrTestReply.self, from: Data(json.utf8)), let key = model.previewTestKey {
            var params = model.ocrParams
            params.minConfidence += 0.05  // older than the parameters: stale
            model.preview.tests[key] = .done(reply, params: params)
        }
        try? await Task.sleep(for: .milliseconds(600))
        await capture(model, "\(base)-A5.png", schemes: schemes)
        model.preview.results[video.id] = result
        model.preview.search = .idle
        model.clearTest()
        // A6: during the batch, read-only.
        model.batch.running = true
        try? await Task.sleep(for: .milliseconds(600))
        await capture(model, "\(base)-A6.png", schemes: schemes)
        model.batch.running = false
        // N2: the narrow window with the inspector over the page.
        if let window {
            let saved = window.frame
            setNarrow(window)
            model.inspectorOpen = true
            try? await Task.sleep(for: .seconds(1))
            await capture(model, "\(base)-N2.png", schemes: schemes)
            model.inspectorOpen = false
            window.setFrame(saved, display: true)
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    /// Sub fix (F5.3) in the real window: F1 with the file chosen, F2 after a
    /// real `srt.fix` (flashes kept, so the shortest line is dimmed as on the
    /// board), F3 with the three notes one at a time (no valid segments, an
    /// unreadable SRT, a drop that is not an .srt).
    private static func fixStates(_ model: AppModel, srt: String, base: String, schemes: [ColorScheme]) async {
        let saved = model.fix
        model.fix.merge = true
        model.fix.ignore = true
        model.fix.flash = true
        model.fix.minDuration = 0.2
        model.chooseSRT(URL(fileURLWithPath: srt))
        // The switches draw as inactive (white) unless the app is the active one.
        NSApp.activate(ignoringOtherApps: true)
        try? await Task.sleep(for: .milliseconds(500))
        await capture(model, "\(base)-fix-ready.png", schemes: schemes)
        model.runFix()
        _ = await DebugQA.wait(30) { !model.fix.running && model.fix.outcome != nil }
        try? await Task.sleep(for: .milliseconds(500))
        model.fix.flash = false
        await capture(model, "\(base)-fix-done.png", schemes: schemes)
        model.fix.flash = true
        model.fix.outcome = .noValidSegments
        await capture(model, "\(base)-fix-error.png", schemes: schemes)
        model.fix.outcome = .unreadable(line: 214)
        await capture(model, "\(base)-fix-unreadable.png", schemes: schemes)
        model.fix.outcome = .notSrt
        await capture(model, "\(base)-fix-notsrt.png", schemes: schemes)
        model.fix.outcome = nil
        model.fixPath = nil
        model.fix.merge = saved.merge
        model.fix.ignore = saved.ignore
        model.fix.flash = saved.flash
        model.fix.minDuration = saved.minDuration
    }

    /// The tools window while it downloads and while it prepares the recognition (T1, T2).
    private static func toolsWindow(_ model: AppModel, base: String, schemes: [ColorScheme]) async {
        guard await DebugQA.wait(5, { model.tools.showsWindow }) else { return }
        if await DebugQA.wait(300, { model.tools.rows.contains { $0.state == .running && $0.tool.kind == .download && $0.bytes > 0 } }) {
            try? await Task.sleep(for: .milliseconds(300))
            await capture(model, "\(base)-tools.png", schemes: schemes)
        }
        if await DebugQA.wait(300, { model.tools.runningTask != nil }) {
            try? await Task.sleep(for: .seconds(3))
            await capture(model, "\(base)-tools-warmup.png", schemes: schemes)
        }
    }

    /// The tools window in the states of boards T1–T4, from a state fed by hand
    /// (no engine): the real first launch on a Mac with Vision's cache warm is
    /// over in seconds, too fast to catch every state.
    private static func renderToolsStates(_ model: AppModel, base: String, schemes: [ColorScheme]) {
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("subvision-snap-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        func render(_ state: ToolsSetupState, _ name: String) {
            SVShell.DebugSnapshot.render(ToolsSetupView(state: state, texts: model.texts, appName: model.config.appName, showLog: {}, quit: {}),
                                         width: 600, schemes: schemes, "\(base)-\(name).png")
        }
        let mb = AppConfig.ffmpegMB * 1_000_000
        // T1: the runtime done, FFmpeg at 13 of 28 MB.
        let t1 = ToolsSetupState(tools: model.config.tools, engine: nil)
        t1.prepareIfFirstLaunch(stateFolder: empty)
        t1.runtimeReady()
        t1.progress(ToolProgress(key: "ffmpeg", state: .running, bytes: mb * 13 / 28, total: mb))
        render(t1, "tools-t1")
        // T2: the downloads done, the preparation running.
        let t2 = ToolsSetupState(tools: model.config.tools, engine: nil)
        t2.prepareIfFirstLaunch(stateFolder: empty)
        t2.runtimeReady()
        t2.progress(ToolProgress(key: "ffmpeg", state: .done, bytes: mb, total: mb))
        t2.progress(ToolProgress(key: "ffprobe", state: .done, bytes: mb, total: mb))
        render(t2, "tools-t2")
        // T3 left: FFmpeg's download failed on the connection.
        let t3 = ToolsSetupState(tools: model.config.tools, engine: nil)
        t3.prepareIfFirstLaunch(stateFolder: empty)
        t3.runtimeReady()
        t3.progress(ToolProgress(key: "ffmpeg", state: .failed, error: "network"))
        render(t3, "tools-t3-download")
        // T3 right: Vision did not load.
        let t3b = ToolsSetupState(tools: model.config.tools, engine: nil)
        t3b.prepareIfFirstLaunch(stateFolder: empty)
        t3b.runtimeReady()
        t3b.progress(ToolProgress(key: "ffmpeg", state: .done, bytes: mb, total: mb))
        t3b.progress(ToolProgress(key: "ffprobe", state: .done, bytes: mb, total: mb))
        t3b.progress(ToolProgress(key: AppConfig.warmupKey, state: .failed, error: "vision"))
        render(t3b, "tools-t3-vision")
        // T4 left: a later launch, FFmpeg missing.
        let t4 = ToolsSetupState(tools: model.config.tools, engine: nil)
        t4.decide(ToolsStatusReply(tools: [.init(key: "ffmpeg", present: false), .init(key: "ffprobe", present: true)]), runTasks: false)
        t4.progress(ToolProgress(key: "ffmpeg", state: .running, bytes: mb * 20 / 28, total: mb))
        render(t4, "tools-t4-missing")
        // T4 right: a later launch after a macOS update, the preparation only.
        let t4b = ToolsSetupState(tools: model.config.tools, engine: nil)
        t4b.decide(ToolsStatusReply(tools: [.init(key: "ffmpeg", present: true), .init(key: "ffprobe", present: true)]), runTasks: true)
        render(t4b, "tools-t4-update")
        try? FileManager.default.removeItem(at: empty)
    }

    /// The report window of R1–R3 (F5.4): open, after an export (the toast),
    /// the file gone, the loading spinner, and the alert of a failed save.
    private static func reportWindows(_ model: AppModel, report: URL, base: String, schemes: [ColorScheme]) async {
        let window = model.openReport(report)
        // R3 bottom: the spinner, while the page loads (the capture may come too late).
        if window.session.phase == .loading {
            _ = await captureReport(window, "\(base)-report-r3-loading.png", schemes: schemes, settle: .milliseconds(50))
        }
        _ = await DebugQA.wait(15) { window.session.phase != .loading }
        try? await Task.sleep(for: .milliseconds(600))
        _ = await captureReport(window, "\(base)-report-r1.png", schemes: schemes)
        // R2: the export through the bridge, then the toast.
        if let bridge = window.session.bridge {
            _ = try? await bridge.call("await exportSrt();")
            _ = await DebugQA.wait(5) { window.session.toast != nil }
            try? await Task.sleep(for: .milliseconds(400))
            _ = await captureReport(window, "\(base)-report-r2.png", schemes: schemes)
        }
        window.close()
        // R3 top left: the report is not there.
        let gone = report.deletingLastPathComponent().appendingPathComponent("sintel_ita_hardsub_demo.review.html")
        if !FileManager.default.fileExists(atPath: gone.path) {
            let w = model.openReport(gone)
            try? await Task.sleep(for: .milliseconds(600))
            _ = await captureReport(w, "\(base)-report-r3-gone.png", schemes: schemes)
            w.close()
        }
        // R3 top right: the alert of a save that failed next to the original (the card alone).
        let alert = SVAlert(icon: AlertIconName.error, tone: .red, title: model.t("app.report.save_failed"),
                            text: model.t("app.report.save_failed_text"))
        alert.button(model.t("app.report.save_elsewhere"), role: .primary)
        alert.button(model.t("app.common.cancel"))
        SVShell.DebugSnapshot.render(SVAlertCard(alert: alert).padding(48), width: 376, schemes: schemes, "\(base)-report-r3-savefail.png")
    }

    /// A report window, once per scheme, as `SVShell.DebugSnapshot.capture` does for the main one.
    static func captureReport(_ window: ReportWindowController, _ path: String, schemes: [ColorScheme],
                              settle: Duration = .milliseconds(500)) async -> [String] {
        let saved = NSApp.appearance
        defer { NSApp.appearance = saved }
        var written: [String] = []
        for scheme in schemes {
            NSApp.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            window.window?.displayIfNeeded()
            try? await Task.sleep(for: settle)
            let p = schemes.count > 1 ? SVShell.DebugSnapshot.path(path, scheme) : path
            if await window.capture(to: p) { written.append(p) }
        }
        return written
    }

    /// The narrow boards (N1, N2): the whole window at 760x640 as the boards measure it, its top kept.
    static func setNarrow(_ window: NSWindow) {
        var frame = window.frame
        frame.origin.y += frame.height - 640
        frame.size = NSSize(width: 760, height: 640)
        window.setFrame(frame, display: true)
    }

    /// The real window, in every scheme asked.
    static func capture(_ model: AppModel, _ path: String, schemes: [ColorScheme]) async {
        try? await Task.sleep(for: .milliseconds(400))
        let written = await SVShell.DebugSnapshot.capture(model.config, schemes: schemes, path)
        if written.isEmpty { AppLog.shared.error("snapshot \(path): nothing captured") }
    }
}
#endif
