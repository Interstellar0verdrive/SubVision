// SPDX-License-Identifier: MIT
// Debug only: `SUBVISION_SNAPSHOT=/path/shot` writes PNGs of the windows a
// few seconds after launch, in light and dark with
// `SUBVISION_SNAPSHOT_SCHEME=both`, then quits. `SUBVISION_SNAPSHOT_ADD=<paths>`
// (comma-separated files or folders) fills the list first;
// `SUBVISION_SNAPSHOT_SETTINGS=1` renders the four Settings tabs;
// `SUBVISION_SNAPSHOT_FIX=<srt>` runs Sub fix on that file and captures F1–F3.
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
            AppLog.shared.info("snapshots done")
            NSApp.terminate(nil)
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

    /// The real window, in every scheme asked.
    static func capture(_ model: AppModel, _ path: String, schemes: [ColorScheme]) async {
        try? await Task.sleep(for: .milliseconds(400))
        let written = await SVShell.DebugSnapshot.capture(model.config, schemes: schemes, path)
        if written.isEmpty { AppLog.shared.error("snapshot \(path): nothing captured") }
    }
}
#endif
