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
    /// The engine answered with `{"error": {"code", "message", ...}}`; `info`
    /// carries the optional details of the error object.
    case remote(code: String, message: String, info: RemoteErrorInfo = RemoteErrorInfo())

    /// The engine's error code (`busy`, `bad_params`, `not_found`...) of a `.remote` error.
    public var remoteCode: String? {
        if case .remote(let code, _, _) = self { return code }
        return nil
    }

    /// The details of a `.remote` error (`detail`, `tool`, `path`, `line`, and
    /// `field`/`reason` of a `bad_params`); nil for the other cases.
    public var remoteInfo: RemoteErrorInfo? {
        if case .remote(_, _, let info) = self { return info }
        return nil
    }

    public var description: String {
        switch self {
        case .launcherMissing(let p): return "engine launcher not found: \(p)"
        case .spawnFailed(let e): return "could not start the engine: \(String(cString: strerror(e)))"
        case .notRunning: return "the engine is not running"
        case .engineExited: return "the engine stopped before answering"
        case .gaveUp: return "the engine keeps crashing; restart the app"
        case .timedOut(let m): return "the engine did not answer \(m) in time"
        case .badReply(let s): return "unreadable reply from the engine: \(s)"
        case .remote(let code, let message, _): return "\(code): \(message)"
        }
    }
}

/// The optional fields of the engine's error object: `detail` (technical
/// text), `tool` (ffmpeg | ffprobe | vision | uv), `path`, `line` (parse
/// errors), and for `bad_params` the `data {field, reason}` pair.
public struct RemoteErrorInfo: Sendable, Equatable {
    public var detail: String?
    public var tool: String?
    public var path: String?
    public var line: Int?
    /// `bad_params`: the parameter refused (`lang_hint`, `fps`, ...).
    public var field: String?
    /// `bad_params`: why, in the engine's words.
    public var reason: String?

    public init(detail: String? = nil, tool: String? = nil, path: String? = nil, line: Int? = nil,
                field: String? = nil, reason: String? = nil) {
        self.detail = detail; self.tool = tool; self.path = path; self.line = line
        self.field = field; self.reason = reason
    }

    /// From the `error` object of a reply.
    public init(error: [String: Any]) {
        let data = error["data"] as? [String: Any]
        self.init(detail: error["detail"] as? String, tool: error["tool"] as? String,
                  path: error["path"] as? String, line: error["line"] as? Int,
                  field: data?["field"] as? String, reason: data?["reason"] as? String)
    }
}
