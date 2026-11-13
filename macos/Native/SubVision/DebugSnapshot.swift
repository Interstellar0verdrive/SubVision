// SPDX-License-Identifier: MIT
// Debug only: `SUBVISION_SNAPSHOT=/path/shot` writes PNGs of the windows a
// few seconds after launch, in light and dark with
// `SUBVISION_SNAPSHOT_SCHEME=both`, then quits. `SUBVISION_SNAPSHOT_ADD=<paths>`
// (comma-separated files or folders) fills the list first;
// `SUBVISION_SNAPSHOT_SETTINGS=1` renders the four Settings tabs.
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
            model.tab = .preview
            await capture(model, "\(base)-preview-empty.png", schemes: schemes)
            model.tab = .fix
            await capture(model, "\(base)-fix-empty.png", schemes: schemes)
            model.tab = .process
            if let add = env["SUBVISION_SNAPSHOT_ADD"], !add.isEmpty {
                model.add(add.split(separator: ",").map { URL(fileURLWithPath: String($0)) })
                _ = await DebugQA.wait(60) { model.videos.allSatisfy(\.probed) }
                try? await Task.sleep(for: .seconds(1))
                model.selection = []
                await capture(model, "\(base)-process-videos.png", schemes: schemes)
                model.tab = .preview
                await capture(model, "\(base)-preview-videos.png", schemes: schemes)
                model.tab = .process
            }
            // The narrow window: the top bar instead of the sidebar (N1).
            if let window = WindowSizer.main(model.config) {
                let saved = window.frame
                window.setContentSize(NSSize(width: 900, height: 760))
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
        model.defaults.set(true, forKey: "inspector.group.ocr")
        for g in ["dlg", "sig", "seg", "adv"] { model.defaults.set(true, forKey: "inspector.group.\(g)") }
        model.selection = []
        // I1: the inspector open with the defaults, the list ready.
        model.inspectorOpen = true
        await settle()
        await capture(model, "\(base)-I1.png", schemes: schemes)
        // I2: groups closed but Segments and Advanced, two values changed.
        for g in ["ocr", "dlg", "sig"] { model.defaults.set(false, forKey: "inspector.group.\(g)") }
        model.defaults.set(1.0, forKey: OcrKey.mergeGap)
        model.defaults.set(1, forKey: OcrKey.skipHamming)
        await settle()
        await capture(model, "\(base)-I2.png", schemes: schemes)
        model.resetOcrParams()
        for g in ["ocr", "dlg", "sig"] { model.defaults.set(true, forKey: "inspector.group.\(g)") }
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
            window.setContentSize(NSSize(width: 900, height: 760))
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
        model.videos[2].error = "unknown (OCRError: Vision request failed (-1) · frame 000412.jpg)"
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
        model.run.summary = BatchSummary(ids: ids, done: 2, failed: 1, stopped: 0, skipped: 0, elapsed: 11040, when: Date(), seen: true)
        SVShell.DebugSnapshot.render(FinishedSheet().environment(model), width: 520, schemes: schemes, "\(base)-E6.png")
        for i in 0..<3 { model.videos[i].resetOutcome() }
        model.run = BatchRun()
        model.saveVideos()
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

    /// The real window, in every scheme asked.
    static func capture(_ model: AppModel, _ path: String, schemes: [ColorScheme]) async {
        try? await Task.sleep(for: .milliseconds(400))
        let written = await SVShell.DebugSnapshot.capture(model.config, schemes: schemes, path)
        if written.isEmpty { AppLog.shared.error("snapshot \(path): nothing captured") }
    }
}
#endif
