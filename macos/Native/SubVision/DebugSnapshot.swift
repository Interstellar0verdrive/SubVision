// SPDX-License-Identifier: MIT
// Debug only: `SUBVISION_SNAPSHOT=/path/shot` writes PNGs of the windows a
// few seconds after launch, in light and dark with
// `SUBVISION_SNAPSHOT_SCHEME=both`, then quits. `SUBVISION_SNAPSHOT_ADD=<paths>`
// (comma-separated files or folders) fills the list first;
// `SUBVISION_SNAPSHOT_SETTINGS=1` renders the four Settings tabs;
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
            if let report = env["SUBVISION_SNAPSHOT_REPORT"], !report.isEmpty {
                await reportWindows(model, report: URL(fileURLWithPath: report), base: base, schemes: schemes)
            }
            AppLog.shared.info("snapshots done")
            NSApp.terminate(nil)
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
        let gone = report.deletingLastPathComponent().appendingPathComponent("sintel_ita_hardsub_demo.revisione.html")
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

    /// The real window, in every scheme asked.
    static func capture(_ model: AppModel, _ path: String, schemes: [ColorScheme]) async {
        try? await Task.sleep(for: .milliseconds(400))
        let written = await SVShell.DebugSnapshot.capture(model.config, schemes: schemes, path)
        if written.isEmpty { AppLog.shared.error("snapshot \(path): nothing captured") }
    }
}
#endif
