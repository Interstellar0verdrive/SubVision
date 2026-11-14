// SPDX-License-Identifier: MIT
// ShellDemo: the SVShell frame around a fake engine (fake_engine.py). It shows
// the main window with a top bar of three tabs, the first-launch tools window
// (the state folder is a fresh temporary one, so every run is a first launch)
// and, with SHELLDEMO_ALERT=1, an alert. With SHELLDEMO_SNAPSHOT=<prefix> it
// writes PNGs of the tools window, the main window and an alert in light and
// dark (SUBVISION_SNAPSHOT_SCHEME=both) and quits.
//
//   swift run ShellDemo
//   SHELLDEMO_SNAPSHOT=/tmp/shelldemo/shot SUBVISION_SNAPSHOT_SCHEME=both swift run ShellDemo

import AppKit
import Observation
import SVShell
import SwiftUI

let demoTools = [
    ToolRow(key: "python", name: "uv + Python", version: "3.13", detail: "engine and recognition", megabytes: 51, kind: .runtime),
    ToolRow(key: "ffmpeg", name: "FFmpeg", version: "9.0.2", detail: "reads the frames", megabytes: 28),
    ToolRow(key: "warmup", name: "Preparing text recognition", detail: "Vision's models for this Mac", kind: .task),
]

let config = AppShellConfig(
    appName: "ShellDemo", bundleIdentifier: "io.github.subvision.shelldemo",
    repositoryURL: URL(string: "https://github.com/Interstellar0verdrive/SubVision")!,
    releaseAPIURL: URL(string: "https://api.github.com/repos/Interstellar0verdrive/SubVision/releases/latest")!,
    releasePageURL: URL(string: "https://github.com/Interstellar0verdrive/SubVision/releases/latest")!,
    logSubsystem: "io.github.subvision.shelldemo", tools: demoTools, fallbackVersion: "0.1.0")

/// A code folder with a launcher that runs the bundled fake engine, and a
/// fresh state folder (`SHELLDEMO_STATE` to keep one between runs).
func makeConfiguration() throws -> EngineConfiguration {
    let fm = FileManager.default
    let env = ProcessInfo.processInfo.environment
    let root = env["SHELLDEMO_STATE"].map { URL(fileURLWithPath: $0) }
        ?? fm.temporaryDirectory.appendingPathComponent("shelldemo-\(ProcessInfo.processInfo.processIdentifier)")
    let code = root.appendingPathComponent("code")
    let state = root.appendingPathComponent("state")
    try fm.createDirectory(at: code, withIntermediateDirectories: true)
    try fm.createDirectory(at: state, withIntermediateDirectories: true)
    guard let fake = Bundle.module.url(forResource: "fake_engine", withExtension: "py") else {
        throw EngineError.launcherMissing("fake_engine.py not in the bundle")
    }
    let launcher = code.appendingPathComponent("subvision")
    try "#!/bin/bash\nexec /usr/bin/env python3 -u \"\(fake.path)\" \"$@\"\n".write(to: launcher, atomically: true, encoding: .utf8)
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)
    var extra: [String: String] = [:]
    for key in ["FAKE_TOOLS_FAIL", "FAKE_TOOLS_STEP", "FAKE_TOOLS_VERIFIED"] { if let v = env[key] { extra[key] = v } }
    return EngineConfiguration(codeFolder: code, stateFolder: state, extraEnvironment: extra)
}

@MainActor
@Observable
final class DemoModel {
    let configuration: EngineConfiguration
    let engine: EngineClient
    let tools: ToolsSetupState
    var status: EngineStatus = .starting
    var hello: EngineHello?
    var tab = "process"
    var checkingUpdates = false
    var working = false
    @ObservationIgnored var started = false

    init() {
        configuration = try! makeConfiguration()
        engine = EngineClient(configuration: configuration)
        tools = ToolsSetupState(tools: demoTools, engine: engine)
        AppLog.shared = AppLog(subsystem: config.logSubsystem, file: configuration.stateFolder.appendingPathComponent("records/app.log"))
        AppLog.shared.info("code \(configuration.codeFolder.path), state \(configuration.stateFolder.path)")
        tools.onFinished = { WindowSizer.toMain(config) }
    }

    var tabs: [ShellTab] {
        [ShellTab(id: "process", symbol: "play.rectangle", title: "Process", busy: working),
         ShellTab(id: "preview", symbol: "eye", title: "Preview"),
         ShellTab(id: "fix", symbol: "wrench.and.screwdriver", title: "Sub fix", separatorBefore: true)]
    }

    func start() {
        guard !started else { return }
        started = true
        tools.prepareIfFirstLaunch(stateFolder: configuration.stateFolder)
        Task { for await event in engine.events { tools.apply(event) } }
        Task { await launch() }
    }

    private func launch() async {
        status = .starting
        do {
            try await engine.start()
            let h = try await engine.hello()
            hello = h
            tools.runtimeReady()
            tools.decide(try await engine.toolsStatus())
            status = .ready
        } catch {
            status = .failed(String(describing: error))
        }
    }

    func retry() { Task { await engine.stop(); await launch() } }
    func showLog() { NSWorkspace.shared.open(configuration.logFile) }

    func demoAlert() -> SVAlert {
        let alert = SVAlert(icon: AlertIconName.stopFile, tone: .red, title: "Stop this file?", text: "What is done so far is kept.\nYou can pick it up again later.")
        alert.button("Stop", role: .destructiveSolid)
        alert.button("Cancel")
        return alert
    }
}

struct DemoRoot: View {
    @Environment(DemoModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var model = model
        Group {
            if model.tools.showsWindow {
                ToolsSetupView(state: model.tools, appName: config.appName, showLog: model.showLog)
                    .onAppear { WindowSizer.toTools(config) }
            } else {
                MainSplit(tabs: model.tabs, selection: $model.tab, sizeOverride: config.environment("WINDOW"),
                          openSettings: { openSettings() }, showsBottomBar: model.working,
                          topBarTrailing: { if model.working { TopBarChip("Working", tone: .accent, busy: true) {} } },
                          page: { DemoPage() },
                          bottomBar: { workBar })
            }
        }
    }

    /// The window's bottom bar while the demo works.
    private var workBar: some View {
        HStack(spacing: 12) {
            Spinner()
            Text("episode-01.mp4 · ocr 1 240 / 3 600").svFont(12.5).foregroundStyle(SV.text)
            Spacer(minLength: 8)
            SegmentedProgressBar(weights: [24, 48], fraction: 0.34).frame(width: 220)
            Button { model.working = false } label: { Label("Stop", systemImage: "stop.fill") }.svButton(.destructive, .small)
        }
        .padding(.leading, 25).padding(.trailing, 20)
        .frame(maxHeight: .infinity)
        .background(SV.raised)
        .overlay(alignment: .top) { Rectangle().fill(SV.line).frame(height: 1) }
    }
}

/// The app's page: the engine status until the engine is up, then the demo pages.
struct DemoPage: View {
    @Environment(DemoModel.self) private var model

    var body: some View {
        if model.status != .ready {
            EngineStatusView(status: model.status, retry: model.retry, showLog: model.showLog)
        } else {
            switch model.tab {
            case "preview": PlaceholderPage(title: "Preview", symbol: "eye", text: "The preview page of the app goes here.")
            case "fix": PlaceholderPage(title: "Sub fix", symbol: "wrench.and.screwdriver", text: "The Sub fix page of the app goes here.")
            default:
                VStack(alignment: .leading, spacing: 16) {
                    PageHeader("Process", "A demo page inside the SVShell frame: the top bar, the bottom bar,",
                               "the engine status and the tools window are the shell's; this card is the app's.")
                    Card {
                        CardTitle("Engine", symbol: "gearshape.2")
                        Text("\(model.hello?.engine ?? "—") \(model.hello?.version ?? "") · pid \(String(model.hello?.pid ?? 0))")
                            .svFont(SVFont.numbers).foregroundStyle(SV.textCode)
                        HStack(spacing: 8) {
                            Button(model.working ? "Stop work" : "Start work", systemImage: model.working ? "stop.fill" : "play.fill") {
                                model.working.toggle()
                                DockProgress.update(config, fraction: model.working ? 0.34 : nil, badge: model.working ? "1" : nil)
                            }.svButton(.primary)
                            Button("Show alert") { afterClick { model.demoAlert().runModal() } }.svButton(.secondary)
                        }
                    }
                    .frame(maxHeight: 160)
                    Spacer()
                }
                .padding(.horizontal, 28)
                .padding(.top, 17)
            }
        }
    }
}

/// SHELLDEMO_SNAPSHOT=<prefix>: the tools window while it shows, the main window
/// after, an alert card; light and dark as SUBVISION_SNAPSHOT_SCHEME says. Then quit.
@MainActor
func snapshots(_ model: DemoModel, base: String) async {
    let schemes = DebugSnapshot.schemes(config)
    _ = await DebugQA.wait(20) { model.tools.showsWindow && model.tools.rows.contains { $0.state == .running && $0.tool.kind == .download } }
    if model.tools.showsWindow {
        DebugSnapshot.render(ToolsSetupView(state: model.tools, appName: config.appName, showLog: {}, quit: {}),
                             width: 600, schemes: schemes, "\(base)-tools.png")
    }
    _ = await DebugQA.wait(30) { model.status == .ready && !model.tools.showsWindow }
    try? await Task.sleep(for: .seconds(1))
    model.working = true
    try? await Task.sleep(for: .milliseconds(300))
    await DebugSnapshot.capture(config, schemes: schemes, "\(base)-window-live.png")
    DebugSnapshot.render(EngineStatusView(status: .failed("engine launcher not found: /x/subvision"), retry: {}, showLog: {}),
                         width: 700, height: 300, schemes: schemes, "\(base)-engine-failed.png")
    DebugSnapshot.render(SVAlertCard(alert: model.demoAlert()).padding(48).background(SV.bg), width: 376, schemes: schemes, "\(base)-alert.png")
    AppLog.shared.info("snapshots done")
    model.working = false   // no quit confirmation
    NSApp.terminate(nil)
}

struct ShellDemoApp: App {
    @NSApplicationDelegateAdaptor(ShellAppDelegate.self) private var delegate
    @State private var model = DemoModel()

    var body: some Scene {
        ShellWindow(config: config) {
            DemoRoot()
                .environment(model)
                .onAppear {
                    delegate.willTerminate = { Task { await model.engine.terminateNow() } }
                    delegate.quitBlocker = {
                        guard model.working else { return false }
                        let a = SVAlert(icon: AlertIconName.quit, tone: .yellow, title: "Quit while work is running?",
                                        text: "The work stops now.")
                        a.button("Quit and Stop", role: .destructiveSolid)
                        a.button("Cancel")
                        return a.runModal() != 0
                    }
                    delegate.dockMenu = { [.item("Start work") { model.working = true }, .separator, .item("Stop work") { model.working = false }] }
                    model.start()
                    if let base = ProcessInfo.processInfo.environment["SHELLDEMO_SNAPSHOT"], !base.isEmpty {
                        Task { await snapshots(model, base: base) }
                    } else if ProcessInfo.processInfo.environment["SHELLDEMO_ALERT"] == "1" {
                        Task { _ = await DebugQA.wait(30) { model.status == .ready && !model.tools.showsWindow }; model.demoAlert().runModal() }
                    }
                    DebugQA.watchIfAsked(config) { line in
                        switch line {
                        case "work": model.working = true
                        case "idle": model.working = false
                        default: if ["process", "preview", "fix"].contains(line) { model.tab = line } else { return "unknown" }
                        }
                        return "ok · tab \(model.tab) · working \(model.working)"
                    }
                }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { checkForUpdates(config: config) { model.checkingUpdates = $0 } }
            }
        }
        Settings {
            Text("Demo settings").svBody().padding(40).background(SV.bg)
        }
    }
}

// A bare executable has no Info.plist: make it a regular app before the windows come.
NSApplication.shared.setActivationPolicy(.regular)
ShellDemoApp.main()
