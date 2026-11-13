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
            if env["SUBVISION_SNAPSHOT_PREVIEW"] == "1" {
                await previewStates(model, base: base, schemes: schemes)
            }
            AppLog.shared.info("snapshots done")
            NSApp.terminate(nil)
        }
    }

    // MARK: - F5.2 · Preview (A1–A6, N2)

    /// `SUBVISION_SNAPSHOT_PREVIEW=1`, with a video from `SUBVISION_SNAPSHOT_ADD`:
    /// the real search and the real OCR test on the first video; A5 is fed by
    /// hand (the demo clip has text in every zone and its duration reads fine).
    private static func previewStates(_ model: AppModel, base: String, schemes: [ColorScheme]) async {
        guard let video = model.videos.first(where: { $0.state == .ready }) else { return }
        let window = WindowSizer.main(model.config)
        model.inspectorOpen = false
        model.tab = .preview
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
        silent.frames = result.frames.map { var f = $0; f.band = nil; f.hasText = false; return f }
        silent.index = min(silent.index, silent.frames.count - 1)
        model.preview.results[video.id] = silent
        model.preview.search = .failed(code: "invalid_duration", message: nil)
        let json = #"{"bands":{"bottom":{"text":"","conf":0,"agree":0,"alts":[],"final":"","ms":214,"variants":3,"empty":true},"top":{"text":"IL MERCATO","conf":0.71,"agree":0.67,"alts":["IL MERCAT0","LL MERCATO"],"final":"{\\an8}IL MERCATO","ms":96,"variants":3,"empty":false}}}"#
        if let reply = try? EngineCoding.decoder.decode(OcrTestReply.self, from: Data(json.utf8)) {
            model.preview.test = .done(reply, params: model.ocrParams, useIgnore: model.useIgnore, useCorrections: model.useCorrections)
            model.preview.testFrame = model.previewFrame?.path
            model.preview.stale = true
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
            window.setContentSize(NSSize(width: 900, height: 760))
            model.inspectorOpen = true
            try? await Task.sleep(for: .seconds(1))
            await capture(model, "\(base)-N2.png", schemes: schemes)
            model.inspectorOpen = false
            window.setFrame(saved, display: true)
            try? await Task.sleep(for: .milliseconds(500))
        }
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
