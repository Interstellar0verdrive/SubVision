// SPDX-License-Identifier: MIT
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import SVShell

/// A throwaway code folder (launcher `subvision` → the fake engine) and
/// state folder; `cleanUp()` removes both.
struct ShellSandbox {
    let root: URL
    let code: URL
    let state: URL

    static func make() throws -> ShellSandbox {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("svshell-test-\(UUID().uuidString)")
        let code = root.appendingPathComponent("code")
        let state = root.appendingPathComponent("state")
        try fm.createDirectory(at: code, withIntermediateDirectories: true)
        try fm.createDirectory(at: state, withIntermediateDirectories: true)
        guard let fake = Bundle.module.url(forResource: "fake_engine", withExtension: "py", subdirectory: "Fixtures") else {
            throw EngineError.badReply("fake_engine.py missing from the test bundle")
        }
        let launcher = code.appendingPathComponent("subvision")
        try """
        #!/bin/bash
        exec /usr/bin/env python3 -u "\(fake.path)" "$@"
        """.write(to: launcher, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)
        return ShellSandbox(root: root, code: code, state: state)
    }

    func configuration(_ extra: [String: String] = [:]) -> EngineConfiguration {
        EngineConfiguration(codeFolder: code, stateFolder: state, extraEnvironment: extra)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }
}

let demoTools = [
    ToolRow(key: "python", name: "uv + Python", version: "3.13", detail: "engine and recognition", megabytes: 42, kind: .runtime),
    ToolRow(key: "ffmpeg", name: "FFmpeg", version: "9.0.2", detail: "reads the frames", megabytes: 38),
    ToolRow(key: "warmup", name: "Preparing text recognition", detail: "Vision's models for this Mac", kind: .task),
]

let demoConfig = AppShellConfig(
    appName: "ShellDemo", bundleIdentifier: "io.github.subvision.shelldemo",
    repositoryURL: URL(string: "https://github.com/Interstellar0verdrive/SubVision")!,
    releaseAPIURL: URL(string: "https://api.github.com/repos/Interstellar0verdrive/SubVision/releases/latest")!,
    releasePageURL: URL(string: "https://github.com/Interstellar0verdrive/SubVision/releases/latest")!,
    logSubsystem: "io.github.subvision.shelldemo", tools: demoTools, fallbackVersion: "2.0.0")

/// Polls `condition` every 50 ms for up to `seconds`.
@MainActor
func until(_ seconds: Double, _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return condition()
}

@Suite(.serialized) struct ToolsSetupTests {
    @MainActor
    @Test func firstLaunchRowsFollowTheEvents() async throws {
        let box = try ShellSandbox.make()
        defer { box.cleanUp() }
        let engine = EngineClient(configuration: box.configuration())
        let state = ToolsSetupState(tools: demoTools, engine: engine)
        var finished = false
        state.onFinished = { finished = true }
        // No .venv yet: the window opens straight away, the runtime spinning.
        state.prepareIfFirstLaunch(stateFolder: box.state)
        #expect(state.showsWindow && state.runtimePending)
        #expect(state.rows.map(\.id) == ["python", "ffmpeg", "warmup"])
        #expect(state.rows[0].state == .running)
        // The events reach the state through one consumer, in order.
        let listener = Task { @MainActor in
            for await event in engine.events { state.apply(event) }
        }
        try await engine.start()
        _ = try await engine.hello(timeout: .seconds(10))
        let status = try await engine.toolsStatus()
        #expect(status.missingKeys == ["ffmpeg"])
        state.decide(status)
        #expect(state.phase == .installing)
        #expect(state.rows.map(\.id) == ["python", "ffmpeg", "warmup"])
        #expect(state.rows[0].state == .done)
        // ffmpeg downloads: running with a growing bar, then done.
        #expect(await until(10) { state.rows[1].state == .running && state.rows[1].bytes > 0 })
        #expect(state.rows[1].total == 38_000_000)
        #expect(state.totals.count == 2 && state.totals.total == 80_000_000)
        #expect(await until(10) { state.rows[1].state == .done })
        // Then the warm-up (`warmup`, `warmup.done`), then the window goes.
        #expect(await until(10) { state.rows[2].state == .running || state.rows[2].state == .done })
        #expect(await until(10) { finished })
        #expect(state.rows[2].seconds == 31)
        #expect(state.phase == .notNeeded)
        #expect(!state.showsWindow)
        listener.cancel()
        await engine.stop()
    }

    @MainActor
    @Test func aFailedDownloadWaitsForTryAgain() async throws {
        let box = try ShellSandbox.make()
        defer { box.cleanUp() }
        let engine = EngineClient(configuration: box.configuration(["FAKE_TOOLS_FAIL": "ffmpeg"]))
        let state = ToolsSetupState(tools: demoTools, engine: engine)
        let listener = Task { @MainActor in
            for await event in engine.events { state.apply(event) }
        }
        try await engine.start()
        _ = try await engine.hello(timeout: .seconds(10))
        // A later launch with a tool gone missing: only that row (T4).
        state.decide(ToolsStatusReply(tools: [.init(key: "ffmpeg", present: false)]))
        #expect(state.rows.map(\.id) == ["ffmpeg"])
        #expect(await until(10) { state.failure != nil })
        #expect(state.failure?.key == "ffmpeg")
        #expect(state.failure?.error == "checksum")
        #expect(state.rows[0].state == .failed && state.showsWindow)
        state.retry()
        #expect(state.phase == .installing && state.rows[0].state == .waiting)
        #expect(await until(10) { state.phase == .notNeeded })
        listener.cancel()
        await engine.stop()
    }

    @MainActor
    @Test func nothingMissingMeansNoWindow() async throws {
        let state = ToolsSetupState(tools: [demoTools[0], demoTools[1]], engine: nil)
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("svshell-venv-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: marker.appendingPathComponent(".venv"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: marker) }
        state.prepareIfFirstLaunch(stateFolder: marker)
        #expect(state.phase == .unknown && !state.showsWindow)
        state.decide(ToolsStatusReply(tools: [.init(key: "ffmpeg", present: true, version: "9.0.2")]))
        #expect(state.phase == .notNeeded && state.rows.isEmpty)
    }

    @MainActor
    @Test func afterAMacOSUpdateOnlyTheWarmupRuns() async throws {
        let box = try ShellSandbox.make()
        defer { box.cleanUp() }
        let engine = EngineClient(configuration: box.configuration(["FAKE_TOOLS_VERIFIED": "1"]))
        let state = ToolsSetupState(tools: demoTools, engine: engine)
        state.warmupLanguages = ["en-US"]
        var finished = false
        state.onFinished = { finished = true }
        let listener = Task { @MainActor in
            for await event in engine.events { state.apply(event) }
        }
        try await engine.start()
        _ = try await engine.hello(timeout: .seconds(10))
        let status = try await engine.toolsStatus()
        #expect(status.allPresent && status.active?.version == "9.0.2")
        state.decide(status, runTasks: true)
        #expect(state.rows.map(\.id) == ["warmup"] && state.rows[0].state == .running)
        #expect(state.runningTask?.id == "warmup")
        #expect(await until(10) { finished })
        #expect(state.rows[0].seconds == 31 && !state.showsWindow)
        // A task that cannot run (no Vision) is reported by the app as failed.
        state.decide(status, runTasks: true)
        state.progress(ToolProgress(key: "warmup", state: .failed, error: "vision"))
        #expect(state.failure?.key == "warmup" && state.showsWindow)
        listener.cancel()
        await engine.stop()
    }
}

@Suite struct VideoDropTests {
    @Test func scansFilesAndFoldersRecursively() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("svshell-drop-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let season = root.appendingPathComponent("Season 1")
        let extras = season.appendingPathComponent("extras")
        try fm.createDirectory(at: extras, withIntermediateDirectories: true)
        for name in ["Season 1/ep02.mkv", "Season 1/ep01.MP4", "Season 1/notes.txt", "Season 1/extras/trailer.mov",
                     "Season 1/.hidden.mp4", "loose.mp4", "image.png"] {
            try Data().write(to: root.appendingPathComponent(name))
        }
        let all = VideoScan.videos(in: [root.appendingPathComponent("loose.mp4"), season,
                                        root.appendingPathComponent("image.png"), root.appendingPathComponent("missing.mp4")])
        #expect(all.map(\.lastPathComponent) == ["loose.mp4", "ep01.MP4", "ep02.mkv", "trailer.mov"])
        let shallow = VideoScan.videos(in: [season], recursive: false)
        #expect(shallow.map(\.lastPathComponent) == ["ep01.MP4", "ep02.mkv"])
        let onlyMkv = VideoScan.videos(in: [season], extensions: ["mkv"])
        #expect(onlyMkv.map(\.lastPathComponent) == ["ep02.mkv"])
        // The same file twice (once loose, once in its folder) is one.
        let twice = VideoScan.videos(in: [season.appendingPathComponent("ep02.mkv"), season])
        #expect(twice.count == 3)
    }
}

@Suite struct AppLogTests {
    @Test func writesOneLinePerEntry() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("svshell-log-\(UUID().uuidString)/records/app.log")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent().deletingLastPathComponent()) }
        let log = AppLog(subsystem: "io.github.subvision.tests", file: file)
        log.info("first")
        log.error("second")
        log.debug("not on file")
        let text = try String(contentsOf: file, encoding: .utf8)
        let lines = text.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].hasSuffix(" INFO first") && lines[1].hasSuffix(" ERROR second"))
    }
}

@Suite struct ShellTextsTests {
    @Test func fillsFields() {
        #expect(ShellTexts.fill("Version {version} of {app}", ["version": "2.0", "app": "X"]) == "Version 2.0 of X")
        #expect(ShellTexts.fill("plain", [:]) == "plain")
    }

    @Test func comeFromTheCatalogue() {
        let l = Localizer(catalogs: ["en": ["app.common.retry": "Try Again", "app.tools.minutes_left.altri": "about {n} minutes left"],
                                     "it": ["app.common.retry": "Riprova", "app.tools.minutes_left.altri": "mancano circa {n} minuti"]],
                          languages: ["en", "it"], language: "it")
        let texts = ShellTexts(l)
        #expect(texts.retry == "Riprova" && texts.toolsMinutesLeft == "mancano circa {n} minuti")
        // Not in this catalogue: the English text, but no second line in the update alerts.
        #expect(texts.showLog == ShellTexts.english.showLog && texts.upToDateText.isEmpty)
        let keys = ShellTexts.catalogue.map(\.1)
        #expect(Set(keys).count == keys.count && keys.allSatisfy { $0.hasPrefix("app.") })
    }

    @Test func configReadsPrefixedEnvironment() {
        let env = ["SUBVISION_SNAPSHOT": "/tmp/shot", "SUBVISION_EMPTY": ""]
        #expect(demoConfig.environment("SNAPSHOT", env) == "/tmp/shot")
        #expect(demoConfig.environment("EMPTY", env) == nil)
        #expect(demoConfig.environment("OTHER", env) == nil)
        #expect(demoConfig.appVersion == "2.0.0")
    }
}

// MARK: - Updates with a fake GitHub

final class FakeGitHub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var reply: (status: Int, body: String) = (200, "{}")

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.reply.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized) struct UpdateTests {
    static var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FakeGitHub.self]
        return URLSession(configuration: config)
    }

    @Test func versionsCompareNumberByNumber() {
        #expect(UpdateCheck.isNewer("2.0.10", than: "2.0.9"))
        #expect(UpdateCheck.isNewer("2.1", than: "2.0.9"))
        #expect(!UpdateCheck.isNewer("2.0", than: "2.0.0"))
        #expect(!UpdateCheck.isNewer("1.9.9", than: "2.0"))
        #expect(UpdateCheck.isNewer("2.0.1-rc1", than: "2.0.0"))
        #expect(UpdateCheck.normalise("v2.1.0") == "2.1.0")
    }

    @Test func newerReleaseIsAvailable() async {
        FakeGitHub.reply = (200, #"{"tag_name": "v2.1.0", "html_url": "https://example.com/r/2.1.0"}"#)
        let result = await UpdateCheck.check(releaseAPIURL: demoConfig.releaseAPIURL, currentVersion: "2.0.0",
                                             fallbackPage: demoConfig.releasePageURL, session: Self.session)
        #expect(result == .available(version: "2.1.0", url: URL(string: "https://example.com/r/2.1.0")!))
    }

    @Test func sameReleaseIsUpToDate() async {
        FakeGitHub.reply = (200, #"{"tag_name": "v2.0.0"}"#)
        let result = await UpdateCheck.check(releaseAPIURL: demoConfig.releaseAPIURL, currentVersion: "2.0.0",
                                             fallbackPage: demoConfig.releasePageURL, session: Self.session)
        #expect(result == .upToDate)
    }

    @Test func badAnswersAreErrors() async {
        FakeGitHub.reply = (503, "")
        let down = await UpdateCheck.check(releaseAPIURL: demoConfig.releaseAPIURL, currentVersion: "2.0.0",
                                           fallbackPage: demoConfig.releasePageURL, session: Self.session)
        #expect(down == .error("HTTP 503"))
        FakeGitHub.reply = (200, #"{"message": "rate limited"}"#)
        let odd = await UpdateCheck.check(releaseAPIURL: demoConfig.releaseAPIURL, currentVersion: "2.0.0",
                                          fallbackPage: demoConfig.releasePageURL, session: Self.session)
        if case .error = odd {} else { Issue.record("expected an error, got \(odd)") }
    }
}

// MARK: - Snapshots in both appearances

@Suite struct SnapshotTests {
    @MainActor
    @Test func rendersAViewInBothSchemes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("svshell-snap-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let state = ToolsSetupState(tools: demoTools, engine: nil)
        state.prepareIfFirstLaunch(stateFolder: dir)   // no .venv there: the window's rows
        let view = ToolsSetupView(state: state, appName: "ShellDemo", appIcon: NSImage(size: NSSize(width: 64, height: 64)),
                                  showLog: {}, quit: {})
        let paths = DebugSnapshot.render(view, width: 600, schemes: [.light, .dark], dir.appendingPathComponent("tools.png").path)
        #expect(paths.count == 2)
        #expect(paths[0].hasSuffix("tools-light.png") && paths[1].hasSuffix("tools-dark.png"))
        for (path, dark) in zip(paths, [false, true]) {
            let rep = try #require(NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: path))))
            #expect(rep.pixelsWide == 1200)
            #expect(rep.pixelsHigh > 400)
            let pixel = try #require(rep.colorAt(x: 4, y: 4)?.usingColorSpace(.sRGB))
            let luminance = 0.2126 * pixel.redComponent + 0.7152 * pixel.greenComponent + 0.0722 * pixel.blueComponent
            #expect(dark ? luminance < 0.15 : luminance > 0.85, "\(path): \(pixel)")
        }
        let env = ["SUBVISION_SNAPSHOT_SCHEME": "both", "SUBVISION_SNAPSHOT": "/tmp/x"]
        #expect(DebugSnapshot.schemes(demoConfig, env: env) == [.light, .dark])
        #expect(DebugSnapshot.base(demoConfig, env: env) == "/tmp/x")
        #expect(DebugSnapshot.path("/a/b/shot.png", .dark) == "/a/b/shot-dark.png")
    }
}

@Suite struct QATests {
    @MainActor
    @Test func commandsFileIsRunAndEmptied() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("svshell-qa-\(UUID().uuidString).txt")
        defer {
            try? FileManager.default.removeItem(at: file)
            try? FileManager.default.removeItem(at: file.appendingPathExtension("out"))
        }
        try "tab preview\nstate\n".write(to: file, atomically: true, encoding: .utf8)
        var seen: [String] = []
        let watcher = DebugQA.watchCommands(file, interval: .milliseconds(20)) { line in
            seen.append(line)
            return "ok \(line)"
        }
        #expect(await until(5) { seen.count == 2 })
        watcher.cancel()
        #expect(seen == ["tab preview", "state"])
        #expect(try String(contentsOf: file, encoding: .utf8).isEmpty)
        let out = try String(contentsOf: file.appendingPathExtension("out"), encoding: .utf8)
        #expect(out == "tab preview\tok tab preview\nstate\tok state\n")
    }
}

// MARK: - The first-launch window in another language

@Suite struct ToolsRelabelTests {
    @MainActor
    @Test func relabelKeepsEachRowsProgress() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("svshell-relabel-\(UUID().uuidString)")
        let state = ToolsSetupState(tools: demoTools, engine: nil)
        state.prepareIfFirstLaunch(stateFolder: dir)   // no .venv there: the runtime row is running
        let before = state.rows.map(\.state)
        #expect(state.rows.first?.tool.detail == "engine and recognition")
        let italian = [
            ToolRow(key: "python", name: "uv + Python", version: "3.13", detail: "motore e riconoscimento", megabytes: 42, kind: .runtime),
            ToolRow(key: "ffmpeg", name: "FFmpeg", version: "9.0.2", detail: "legge i fotogrammi", megabytes: 38),
            ToolRow(key: "warmup", name: "Preparazione del riconoscimento", detail: "i modelli di Vision per questo Mac", kind: .task),
        ]
        state.relabel(italian)
        #expect(state.rows.map(\.tool.detail) == ["motore e riconoscimento", "legge i fotogrammi", "i modelli di Vision per questo Mac"])
        #expect(state.rows.map(\.state) == before)
        #expect(state.tools.last?.name == "Preparazione del riconoscimento")
    }
}
