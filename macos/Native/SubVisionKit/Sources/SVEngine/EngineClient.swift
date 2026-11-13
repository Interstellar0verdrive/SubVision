// SPDX-License-Identifier: MIT
// Adapted from the AnimeUp native app (AnimeUpKit/Sources/Engine/EngineClient.swift),
// by the same author. SubVision does not depend on AnimeUp. Changed here: one
// task consumes the sidecar's lines in order, `call` takes an optional
// timeout, `stop` asks for `shutdown` before closing stdin, and the typed
// helpers of the other app are gone (the app adds its own).

import Foundation

/// Talks to `<launcher> serve`: one long-lived Python sidecar per app run.
///
/// - `start()` spawns it (posix_spawn, own process group).
/// - `call(_:params:timeout:)` sends a request and awaits its reply, by id.
///   Replies may come back in any order; events never overtake the lines
///   written before them.
/// - `events` streams the engine's push messages, in order, to one consumer.
/// - When the engine dies unexpectedly, pending calls fail with
///   `.engineExited` and it's restarted with a growing delay (1, 2, 4... 30 s);
///   after 5 crashes in 2 minutes the client gives up (`engine.gave_up`).
public actor EngineClient {
    public nonisolated let configuration: EngineConfiguration
    public nonisolated let events: AsyncStream<EngineEvent>
    private let eventSink: AsyncStream<EngineEvent>.Continuation

    private struct Pending {
        let method: String
        let continuation: CheckedContinuation<Data, Error>
        var timer: Task<Void, Never>?
    }

    private var sidecar: Sidecar?
    private var nextID = 1
    private var pending: [Int: Pending] = [:]
    private var stopping = false
    private var crashes: [Date] = []
    private var gaveUp = false
    public private(set) var restarts = 0

    public init(configuration: EngineConfiguration) {
        self.configuration = configuration
        (events, eventSink) = AsyncStream<EngineEvent>.makeStream(bufferingPolicy: .unbounded)
    }

    public var isRunning: Bool { sidecar?.isRunning ?? false }
    public var pid: Int32? { sidecar?.pid }

    public func start() throws {
        guard sidecar == nil else { return }
        stopping = false
        gaveUp = false
        crashes = []
        try spawn()
    }

    private func spawn() throws {
        let process = try Sidecar(configuration: configuration)
        sidecar = process
        emit("engine.started", ["pid": Int(process.pid)])
        // The one consumer: lines and the exit arrive in the order the
        // sidecar produced them.
        Task { [weak self] in
            for await message in process.messages {
                guard let self else { return }
                await self.handle(message, from: process)
            }
        }
    }

    /// Stops the engine for good (no restart): asks for `shutdown`, closes
    /// stdin, then SIGTERM and SIGKILL after a grace period. Pending calls fail.
    public func stop() {
        stopping = true
        if let sidecar {
            try? sidecar.send(requestLine(method: "shutdown", params: [:]))
            sidecar.stop()
        }
        failPending(EngineError.engineExited)
    }

    /// For the app quitting: no grace period.
    public func terminateNow() {
        stopping = true
        sidecar?.terminateNow()
        failPending(EngineError.engineExited)
    }

    // MARK: requests

    /// Sends `method` with `params` and decodes the `result`.
    /// With a `timeout`, a late reply fails the call with `.timedOut` (and is
    /// ignored if it ever arrives).
    public func call<R: Decodable & Sendable>(_ method: String, params: [String: any Sendable] = [:],
                                              timeout: Duration? = nil, as type: R.Type = R.self) async throws -> R {
        let data = try await raw(method, params: params, timeout: timeout)
        do {
            return try EngineCoding.decoder.decode(R.self, from: data)
        } catch {
            throw EngineError.badReply("\(method): \(error)")
        }
    }

    /// The raw JSON of `result`.
    public func raw(_ method: String, params: [String: any Sendable] = [:],
                    timeout: Duration? = nil) async throws -> Data {
        if gaveUp { throw EngineError.gaveUp }
        guard let sidecar, sidecar.isRunning else { throw EngineError.notRunning }
        let id = nextID
        nextID += 1
        let line = try requestLine(id: id, method: method, params: params)
        return try await withCheckedThrowingContinuation { continuation in
            var entry = Pending(method: method, continuation: continuation, timer: nil)
            if let timeout {
                entry.timer = Task { [weak self] in
                    try? await Task.sleep(for: timeout)
                    guard !Task.isCancelled else { return }
                    await self?.timedOut(id: id)
                }
            }
            pending[id] = entry
            do {
                try sidecar.send(line)
            } catch {
                pending.removeValue(forKey: id)?.timer?.cancel()
                continuation.resume(throwing: error)
            }
        }
    }

    private func requestLine(id: Int? = nil, method: String, params: [String: any Sendable]) throws -> Data {
        var request: [String: Any] = ["method": method, "params": params]
        request["id"] = id ?? { let n = nextID; nextID += 1; return n }()
        return try JSONSerialization.data(withJSONObject: request)
    }

    private func timedOut(id: Int) {
        guard let entry = pending.removeValue(forKey: id) else { return }
        entry.continuation.resume(throwing: EngineError.timedOut(entry.method))
    }

    // MARK: incoming

    private func handle(_ message: Sidecar.Message, from process: Sidecar) {
        guard sidecar === process else { return }
        switch message {
        case .line(let line): received(line)
        case .exited(let status): exited(status: status)
        }
    }

    private func received(_ line: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            // Not protocol: the engine's fd discipline makes this rare, but
            // never fatal.
            return
        }
        if let name = object["event"] as? String {
            let data = (object["data"]).flatMap { try? JSONSerialization.data(withJSONObject: $0) } ?? Data("{}".utf8)
            eventSink.yield(EngineEvent(name: name, data: data))
            return
        }
        guard let id = object["id"] as? Int, let entry = pending.removeValue(forKey: id) else { return }
        entry.timer?.cancel()
        if let error = object["error"] as? [String: Any] {
            entry.continuation.resume(throwing: EngineError.remote(code: error["code"] as? String ?? "error",
                                                                   message: error["message"] as? String ?? "",
                                                                   info: RemoteErrorInfo(error: error)))
        } else if let result = object["result"] {
            if let data = try? JSONSerialization.data(withJSONObject: result, options: [.fragmentsAllowed]) {
                entry.continuation.resume(returning: data)
            } else {
                entry.continuation.resume(throwing: EngineError.badReply("result"))
            }
        } else {
            entry.continuation.resume(throwing: EngineError.badReply("no result"))
        }
    }

    private func exited(status: Int32) {
        sidecar = nil
        failPending(EngineError.engineExited)
        emit("engine.exited", ["status": Int(status)])
        guard !stopping else { return }
        let now = Date()
        crashes = crashes.filter { now.timeIntervalSince($0) < 120 } + [now]
        if crashes.count > 5 {
            gaveUp = true
            emit("engine.gave_up", [:])
            return
        }
        let delay = min(30.0, pow(2.0, Double(crashes.count - 1)))
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            await self?.restartAfterCrash()
        }
    }

    private func restartAfterCrash() {
        guard !stopping, sidecar == nil, !gaveUp else { return }
        restarts += 1
        do { try spawn() } catch { exited(status: -1) }
    }

    private func failPending(_ error: Error) {
        let waiting = pending
        pending.removeAll()
        for (_, entry) in waiting {
            entry.timer?.cancel()
            entry.continuation.resume(throwing: error)
        }
    }

    private func emit(_ name: String, _ data: [String: Any]) {
        let json = (try? JSONSerialization.data(withJSONObject: data)) ?? Data("{}".utf8)
        eventSink.yield(EngineEvent(name: name, data: json))
    }
}
