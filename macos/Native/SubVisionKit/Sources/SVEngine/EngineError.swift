// SPDX-License-Identifier: MIT
// Adapted from the AnimeUp native app (AnimeUpKit/Sources/Engine/Sidecar.swift),
// by the same author. SubVision does not depend on AnimeUp.

import Foundation

/// What can go wrong between the app and the sidecar.
public enum EngineError: Error, Equatable, CustomStringConvertible {
    /// The launcher is not there (or not executable).
    case launcherMissing(String)
    /// `posix_spawn` failed; the payload is the errno.
    case spawnFailed(Int32)
    /// No sidecar is running (never started, or stopped for good).
    case notRunning
    /// The sidecar went away (crash, EOF, stop) before answering.
    case engineExited
    /// Too many crashes in a short time: no more restarts.
    case gaveUp
    /// The reply did not come within the timeout given to `call`.
    case timedOut(String)
    /// The reply could not be read or decoded.
    case badReply(String)
    /// The engine answered with `{"error": {"code", "message"}}`.
    case remote(code: String, message: String)

    public var description: String {
        switch self {
        case .launcherMissing(let p): return "engine launcher not found: \(p)"
        case .spawnFailed(let e): return "could not start the engine: \(String(cString: strerror(e)))"
        case .notRunning: return "the engine is not running"
        case .engineExited: return "the engine stopped before answering"
        case .gaveUp: return "the engine keeps crashing; restart the app"
        case .timedOut(let m): return "the engine did not answer \(m) in time"
        case .badReply(let s): return "unreadable reply from the engine: \(s)"
        case .remote(let code, let message): return "\(code): \(message)"
        }
    }
}
