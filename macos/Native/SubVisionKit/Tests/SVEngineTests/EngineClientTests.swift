// SPDX-License-Identifier: MIT
// Adapted from the AnimeUp native app (AnimeUpKit/Tests/EngineTests/EngineClientTests.swift),
// by the same author. SubVision does not depend on AnimeUp.

import Foundation
import Testing
@testable import SVEngine

/// A throwaway code folder (launcher `subvision` → the fake engine) and
/// state folder; `cleanUp()` removes both.
struct Sandbox {
    let code: URL
    let state: URL

    static func make() throws -> Sandbox {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("subvisionkit-test-\(UUID().uuidString)")
        let code = root.appendingPathComponent("code")
        let state = root.appendingPathComponent("state")
        try fm.createDirectory(at: code, withIntermediateDirectories: true)
        guard let fake = Bundle.module.url(forResource: "fake_engine", withExtension: "py", subdirectory: "Fixtures") else {
            throw EngineError.badReply("fake_engine.py missing from the test bundle")
        }
        let launcher = code.appendingPathComponent("subvision")
        try """
        #!/bin/bash
        exec /usr/bin/env python3 -u "\(fake.path)" "$@"
        """.write(to: launcher, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)
        return Sandbox(code: code, state: state)
    }

    var configuration: EngineConfiguration {
        EngineConfiguration(codeFolder: code, stateFolder: state)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: code.deletingLastPathComponent())
    }
}

struct Pid: Decodable, Sendable { var pid: Int }

@Suite(.serialized) struct EngineClientTests {
    @Test func helloDecodesAndTheEnvironmentIsSet() async throws {
        let box = try Sandbox.make()
        defer { box.cleanUp() }
        let client = EngineClient(configuration: box.configuration)
        try await client.start()
        let hello = try await client.call("hello", timeout: .seconds(10), as: EngineHello.self)
        #expect(hello.engine == "fake" && hello.protocol == 1 && hello.vision && !hello.livetext)
        #expect(hello.ffmpeg == nil && hello.languages == ["it-IT", "en-US"])
        #expect(hello.stateFolder == box.state.path)
        #expect(await client.isRunning)
        #expect(await client.pid == Int32(hello.pid ?? 0))
        struct Folders: Decodable { var codeFolder: String; var cwd: String }
        let f = try await client.call("hello", as: Folders.self)
        #expect(f.codeFolder == box.code.path)
        #expect(URL(fileURLWithPath: f.cwd).standardizedFileURL.path == box.state.standardizedFileURL.path
                || f.cwd.hasSuffix("/state"))
        #expect(FileManager.default.fileExists(atPath: box.state.appendingPathComponent("records/engine.log").path))
        await client.stop()
    }

    @Test func unknownMethodIsARemoteError() async throws {
        let box = try Sandbox.make()
        defer { box.cleanUp() }
        let client = EngineClient(configuration: box.configuration)
        try await client.start()
        do {
            _ = try await client.raw("no.such.method")
            Issue.record("an unknown method answered")
        } catch let EngineError.remote(code, _) {
            #expect(code == "unknown_method")
        }
        await client.stop()
    }

    @Test func nonJSONLinesAreIgnored() async throws {
        let box = try Sandbox.make()
        defer { box.cleanUp() }
        let client = EngineClient(configuration: box.configuration)
        try await client.start()
        struct R: Decodable { var ok: Bool }
        #expect(try await client.call("noise", as: R.self).ok)
        await client.stop()
    }

    /// A crash fails the pending call and the client starts a new engine.
    @Test func restartsAfterACrash() async throws {
        let box = try Sandbox.make()
        defer { box.cleanUp() }
        let client = EngineClient(configuration: box.configuration)
        try await client.start()
        let first = try await client.call("hello", as: Pid.self)
        do {
            _ = try await client.raw("crash")
            Issue.record("the crash call answered")
        } catch {
            #expect(error as? EngineError == .engineExited)
        }
        // Back within the first restart delay (1 s).
        var second: Pid?
        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(100))
            if let p = try? await client.call("hello", as: Pid.self) { second = p; break }
        }
        #expect(second != nil && second?.pid != first.pid)
        #expect(await client.restarts == 1)
        await client.stop()
    }

    /// The exit status travels with `engine.exited`; a clean stop restarts nothing.
    @Test func exitStatusAndNoRestartAfterStop() async throws {
        let box = try Sandbox.make()
        defer { box.cleanUp() }
        let client = EngineClient(configuration: box.configuration)
        try await client.start()
        _ = try await client.call("hello", as: Pid.self)
        await client.stop()
        var status: Int?
        for await event in client.events where event.name == "engine.exited" {
            status = try event.dictionary()["status"] as? Int
            break
        }
        #expect(status == 0)
        try await Task.sleep(for: .milliseconds(1500))
        #expect(await client.restarts == 0)
        #expect(await !client.isRunning)
        await #expect(throws: EngineError.notRunning) { try await client.raw("hello") }
    }

    @Test func missingLauncherIsAnError() async throws {
        let box = try Sandbox.make()
        defer { box.cleanUp() }
        let client = EngineClient(configuration: EngineConfiguration(
            codeFolder: URL(fileURLWithPath: "/nonexistent"), stateFolder: box.state))
        await #expect(throws: EngineError.launcherMissing("/nonexistent/subvision")) { try await client.start() }
    }

    @Test func callTimesOut() async throws {
        let box = try Sandbox.make()
        defer { box.cleanUp() }
        let client = EngineClient(configuration: box.configuration)
        try await client.start()
        let started = ContinuousClock.now
        await #expect(throws: EngineError.timedOut("sleep")) {
            try await client.raw("sleep", params: ["seconds": 3], timeout: .milliseconds(300))
        }
        #expect(ContinuousClock.now - started < .seconds(2))
        // The engine is fine and the late reply is ignored.
        struct Echo: Decodable { var x: Int }
        #expect(try await client.call("echo", params: ["x": 7], timeout: .seconds(5), as: Echo.self).x == 7)
        await client.stop()
    }

    @Test func repliesMayComeOutOfOrder() async throws {
        let box = try Sandbox.make()
        defer { box.cleanUp() }
        let client = EngineClient(configuration: box.configuration)
        try await client.start()
        struct Slept: Decodable { var slept: Double }
        struct Echo: Decodable { var x: Int }
        async let slow = client.call("sleep", params: ["seconds": 0.5], as: Slept.self)
        async let fast = client.call("echo", params: ["x": 1], as: Echo.self)
        let (s, f) = try await (slow, fast)
        #expect(s.slept == 0.5 && f.x == 1)
        await client.stop()
    }

    @Test func eventsArriveInOrder() async throws {
        let box = try Sandbox.make()
        defer { box.cleanUp() }
        let client = EngineClient(configuration: box.configuration)
        try await client.start()
        struct Tick: Decodable { var i: Int }
        struct Sent: Decodable { var sent: Int }
        let ticks = Task { () -> [Int] in
            var seen: [Int] = []
            for await event in client.events where event.name == "tick" {
                seen.append(try event.decode(as: Tick.self).i)
                if seen.count == 100 { break }
            }
            return seen
        }
        #expect(try await client.call("events", params: ["n": 100], as: Sent.self).sent == 100)
        #expect(try await ticks.value == Array(0..<100))
        await client.stop()
    }

    @Test func pendingCallsFailOnEOF() async throws {
        let box = try Sandbox.make()
        defer { box.cleanUp() }
        let client = EngineClient(configuration: box.configuration)
        try await client.start()
        let waiting = Task { try await client.raw("sleep", params: ["seconds": 30]) }
        let gone = Task { try await client.raw("quit") }
        var failures = 0
        for call in [waiting, gone] {
            do { _ = try await call.value } catch { if error as? EngineError == .engineExited { failures += 1 } }
        }
        #expect(failures == 2)
        await client.stop()
    }

    @Test func environmentIsolation() {
        let cfg = EngineConfiguration(codeFolder: URL(fileURLWithPath: "/code"),
                                      stateFolder: URL(fileURLWithPath: "/state"),
                                      extraEnvironment: ["SUBVISION_LANG": "it"])
        let env = cfg.environment(base: ["SUBVISION_STATO": "/somebody/else", "SUBVISION_CODE": "/old",
                                         "PYTHONPATH": "/x", "VIRTUAL_ENV": "/v", "PATH": "/opt/x"])
        #expect(env["SUBVISION_STATO"] == "/state" && env["SUBVISION_CODE"] == "/code")
        #expect(env["PYTHONPATH"] == nil && env["VIRTUAL_ENV"] == nil)
        #expect(env["SUBVISION_LANG"] == "it")
        #expect(env["PYTHONUNBUFFERED"] == "1")
        #expect(env["PATH"]!.hasPrefix("/opt/x:") && env["PATH"]!.contains("/usr/bin"))
    }

    @Test func standardFolders() {
        let dev = EngineConfiguration.standard(debug: true, environment: [:])
        #expect(dev.stateFolder.lastPathComponent == "SubVision-dev")
        #expect(dev.logFile.path.hasSuffix("SubVision-dev/records/engine.log"))
        let release = EngineConfiguration.standard(debug: false, environment: [:])
        #expect(release.stateFolder.lastPathComponent == "SubVision")
        #expect(release.codeFolder.lastPathComponent == "SubVision")
        #expect(release.launcher.lastPathComponent == "subvision")
        let env = EngineConfiguration.standard(debug: true, environment: [
            "SUBVISION_CODE": "/c", "SUBVISION_STATO": "/s", "SUBVISION_LANG": "it"])
        #expect(env.codeFolder.path == "/c" && env.stateFolder.path == "/s")
        #expect(env.extraEnvironment == ["SUBVISION_LANG": "it"])
    }

    @Test func helloToleratesMissingFields() throws {
        let json = #"{"engine":"subvision","version":"2.0.0","protocol":1}"#
        let h = try EngineCoding.decoder.decode(EngineHello.self, from: Data(json.utf8))
        #expect(h.engine == "subvision" && !h.vision && h.languages.isEmpty && h.ffmpeg == nil)
        let full = #"{"engine":"subvision","version":"2.0.0","protocol":1,"pid":4,"python":"3.13.12","vision":true,"livetext":true,"ffmpeg":{"path":"/f","version":"9.0.2"},"languages":["it-IT"],"state_folder":"/s"}"#
        let g = try EngineCoding.decoder.decode(EngineHello.self, from: Data(full.utf8))
        #expect(g.ffmpeg == EngineHello.FFmpeg(path: "/f", version: "9.0.2") && g.stateFolder == "/s" && g.livetext)
    }
}

@Suite struct LogRotationTests {
    @Test func rotatesAboveTheLimit() throws {
        let box = try Sandbox.make()
        defer { box.cleanUp() }
        try FileManager.default.createDirectory(at: box.state, withIntermediateDirectories: true)
        let log = box.state.appendingPathComponent("engine.log")
        try Data(repeating: 65, count: 2000).write(to: log)
        Sidecar.rotate(log, limit: 5000)
        #expect(FileManager.default.fileExists(atPath: log.path))
        Sidecar.rotate(log, limit: 1000)
        #expect(!FileManager.default.fileExists(atPath: log.path))
        #expect(FileManager.default.fileExists(atPath: box.state.appendingPathComponent("engine.1.log").path))
    }
}

@Suite struct SignalMaskTests {
    /// Helpers started by the engine must be stoppable: nothing blocked in the mask.
    @Test func sidecarStartsWithNoBlockedSignals() async throws {
        let box = try Sandbox.make()
        defer { box.cleanUp() }
        // Block SIGTERM and SIGUSR1 on this thread, as a GUI thread might.
        var set = sigset_t()
        sigemptyset(&set)
        sigaddset(&set, SIGTERM)
        sigaddset(&set, SIGUSR1)
        var old = sigset_t()
        pthread_sigmask(SIG_BLOCK, &set, &old)
        defer { pthread_sigmask(SIG_SETMASK, &old, nil) }
        let client = EngineClient(configuration: box.configuration)
        try await client.start()
        struct R: Decodable, Sendable { var blocked: [Int] }
        let r = try await client.call("signals", as: R.self)
        #expect(r.blocked.isEmpty, "blocked signals in the engine: \(r.blocked)")
        await client.stop()
    }
}
