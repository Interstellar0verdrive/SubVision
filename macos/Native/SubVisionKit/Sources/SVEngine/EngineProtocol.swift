// SPDX-License-Identifier: MIT
// The protocol of `subvision serve` (src/subvision/serve.py, batch.py,
// preview.py, tools.py): method and event names, typed replies and events,
// the OCR parameters. Decode with `EngineCoding.decoder` (snake_case keys).

import Foundation

public enum EngineProtocol {
    /// `hello.protocol` this package speaks.
    public static let version = 1
}

/// The methods of `serve.py`.
public enum EngineMethod {
    public static let hello = "hello"
    public static let toolsStatus = "tools.status"
    public static let toolsInstall = "tools.install"
    public static let toolsUse = "tools.use"
    public static let warmup = "warmup"
    public static let listsStatus = "lists.status"
    public static let listsImport = "lists.import"
    public static let videosProbe = "videos.probe"
    public static let batchStart = "batch.start"
    public static let batchStop = "batch.stop"
    public static let previewFrames = "preview.frames"
    public static let previewStop = "preview.stop"
    public static let previewTest = "preview.test"
    public static let srtFix = "srt.fix"
    public static let shutdown = "shutdown"
}

// MARK: - OCR parameters

/// `core.OcrParams` without the lists (the engine adds them from the state
/// folder). The defaults are the engine's: maximum accuracy.
public struct OcrParams: Codable, Sendable, Equatable {
    public var fps: Double = 12
    /// A BCP-47 code from `hello.languages` (the engine also takes "Italian"...).
    public var langHint = "it-IT"
    public var bottomKeepPct = 28
    public var keepWPct = 96
    public var topBand = true
    public var topKeepPct = 22
    public var topKeepWPct = 100
    public var recognitionLevel = "accurate"
    public var minConfidence = 0.30
    public var multiVariant = true
    public var skipHamming = 0
    public var refineTiming = true
    public var minDuration = 0.20
    public var mergeGap = 0.6
    public var wrapWidth = 42
    public var workers = 4
    public var qcReport = true
    public var qcGapWarn = 6.0
    public var qcConfWarn = 0.80
    public var qcAgreeWarn = 0.70

    public init() {}

    /// The fast profile of the tests and the demo clips: fps 6, skip 1, one
    /// variant, no signs band, no refinement.
    public static var fast: OcrParams {
        var p = OcrParams()
        p.fps = 6; p.skipHamming = 1; p.multiVariant = false; p.topBand = false; p.refineTiming = false
        return p
    }

    /// The `params` object of `batch.start`, `preview.*` and `srt.fix`.
    public var dictionary: [String: any Sendable] {
        ["fps": fps, "lang_hint": langHint, "bottom_keep_pct": bottomKeepPct, "keep_w_pct": keepWPct,
         "top_band": topBand, "top_keep_pct": topKeepPct, "top_keep_w_pct": topKeepWPct,
         "recognition_level": recognitionLevel, "min_confidence": minConfidence, "multi_variant": multiVariant,
         "skip_hamming": skipHamming, "refine_timing": refineTiming, "min_duration": minDuration,
         "merge_gap": mergeGap, "wrap_width": wrapWidth, "workers": workers, "qc_report": qcReport,
         "qc_gap_warn": qcGapWarn, "qc_conf_warn": qcConfWarn, "qc_agree_warn": qcAgreeWarn]
    }
}

// MARK: - Replies

/// `{started}` of the jobs that run in the background (`tools.install`,
/// `warmup`, `batch.start`, `preview.frames`): `reason` is `busy` or
/// `already_running` when not started.
public struct StartReply: Decodable, Sendable, Equatable {
    public var started: Bool
    public var reason: String?
    /// `tools.install`: the keys it downloads.
    public var keys: [String]?
    /// `warmup`: the Vision languages it prepares.
    public var languages: [String]?
    public var isBusy: Bool { !started && reason == "busy" }
}

/// `batch.stop`, `preview.stop`: `reason` (`no_batch`, `no_preview`) when nothing ran;
/// `not_running` when `batch.stop` named a file that is not the one in progress.
public struct StopReply: Decodable, Sendable, Equatable {
    public var ok: Bool
    public var reason: String?
}

/// `tools.status`: every tool of the engine, `present` when the downloaded
/// binary answers with the expected version.
public struct ToolsStatusReply: Decodable, Sendable, Equatable {
    public struct Tool: Sendable, Equatable {
        public var key: String
        public var present: Bool
        public var path: String?
        public var version: String?

        public init(key: String, present: Bool, path: String? = nil, version: String? = nil) {
            self.key = key
            self.present = present
            self.path = path
            self.version = version
        }
    }

    /// In key order.
    public var tools: [Tool]
    /// The ffmpeg in use (the user's own or the downloaded one), nil when none.
    public var active: EngineHello.FFmpeg?
    /// "Use my own ffmpeg" (`tools.use`), nil for the downloaded one.
    public var custom: String?

    public init(tools: [Tool], active: EngineHello.FFmpeg? = nil, custom: String? = nil) {
        self.tools = tools
        self.active = active
        self.custom = custom
    }

    private struct Entry: Decodable { var present: Bool; var path: String?; var version: String? }
    private enum CodingKeys: String, CodingKey { case tools, active, custom }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let entries = try c.decode([String: Entry].self, forKey: .tools)
        tools = entries.keys.sorted().map { key in
            let e = entries[key]!
            return Tool(key: key, present: e.present, path: e.path, version: e.version)
        }
        active = try c.decodeIfPresent(EngineHello.FFmpeg.self, forKey: .active)
        custom = try c.decodeIfPresent(String.self, forKey: .custom)
    }

    public var allPresent: Bool { tools.allSatisfy(\.present) }
    public var missingKeys: [String] { tools.filter { !$0.present }.map(\.key) }
}

/// `tools.use`: the ffmpeg now in use.
public struct ToolsUseReply: Decodable, Sendable, Equatable {
    public var ffmpeg: EngineHello.FFmpeg?
    public var custom: String?
}

/// `lists.status` and `lists.import`: `ignore.txt` and `corrections.txt` in the state folder.
public struct ListsStatus: Decodable, Sendable, Equatable {
    public struct List: Decodable, Sendable, Equatable {
        public var path: String
        public var count: Int
    }
    public var ignore: List
    public var corrections: List
}

/// One video of `videos.probe`; `error` (`probe_failed`) and `message` when unreadable.
public struct VideoInfo: Decodable, Sendable, Equatable {
    public var path: String
    public var duration: Double?
    public var fps: Double?
    public var width: Int?
    public var height: Int?
    public var error: String?
    public var message: String?
}

public struct VideosProbeReply: Decodable, Sendable, Equatable {
    public var videos: [VideoInfo]
}

/// `preview.test`: the OCR of one frame, per band (`bottom`, and `top` with the signs band on).
public struct OcrTestReply: Decodable, Sendable, Equatable {
    public struct Band: Decodable, Sendable, Equatable {
        /// The voted raw reading.
        public var text: String
        public var conf: Double
        public var agree: Double
        public var alts: [String]
        /// After corrections, wrap and ignore list; `{\an8}` first for the signs band.
        public var finalText: String
        public var ms: Double
        public var variants: Int?
        public var empty: Bool

        private enum CodingKeys: String, CodingKey {
            case text, conf, agree, alts, finalText = "final", ms, variants, empty
        }
    }
    public var bands: [String: Band]
    public var bottom: Band? { bands["bottom"] }
    public var top: Band? { bands["top"] }
}

/// `srt.fix`: `<stem>-fixed-<date>.srt` next to the source.
public struct SrtFixReply: Decodable, Sendable, Equatable {
    public var outPath: String
    public var count: Int
}

// MARK: - Events

/// `ready`, the engine's first line.
public struct EngineReady: Decodable, Sendable, Equatable {
    public var version: String
    public var `protocol`: Int
    public var pid: Int
}

/// `tools.progress`: `waiting`, then `running` with the bytes, then `done` or
/// `failed` (`error`: checksum, network, interrupted, archive, not_static, version).
public struct ToolProgress: Decodable, Sendable, Equatable {
    public enum State: String, Decodable, Sendable { case waiting, running, done, failed }
    public var key: String
    public var state: State
    public var bytes: Int64?
    public var total: Int64?
    public var error: String?

    public init(key: String, state: State, bytes: Int64? = nil, total: Int64? = nil, error: String? = nil) {
        self.key = key
        self.state = state
        self.bytes = bytes
        self.total = total
        self.error = error
    }
}

/// `tools.done`.
public struct ToolsDone: Decodable, Sendable, Equatable {
    public var ok: Bool
    public var status: ToolsStatusReply
}

/// `warmup.done`: the first Vision call is paid (sent also when it failed: check `hello.vision`).
public struct WarmupDone: Decodable, Sendable, Equatable {
    public var seconds: Double
    public var languages: [String]
}

/// A step of the plan of one file: `key` (extract, group, ocr, refine) on a
/// `band` (bottom, top); `estimate` in seconds from the previous file.
public struct PlannedStep: Decodable, Sendable, Equatable, Identifiable {
    public var key: String
    public var band: String
    public var estimate: Double?
    /// `key:band`, as in `BatchFileDone.times`.
    public var id: String { "\(key):\(band)" }
}

public struct BatchFileStarted: Decodable, Sendable, Equatable {
    public var idx: Int
    public var total: Int
    public var name: String
    public var srt: String
    public var log: String
    public var report: String?
    public var steps: [PlannedStep]
}

public struct BatchStep: Decodable, Sendable, Equatable {
    public var idx: Int
    public var step: String
    public var band: String
    public var ratio: Double
    public var count: Int
    public var total: Int
    /// frames, targets or segments.
    public var unit: String
    public var elapsed: Double
    public var eta: Double?
    public var rate: Double?
    public var id: String { "\(step):\(band)" }
}

public struct BatchFileDone: Decodable, Sendable, Equatable {
    public var idx: Int
    public var segments: Int
    public var dropped: Int
    public var refined: Int
    public var elapsed: Double
    /// Seconds per step, by `key:band`.
    public var times: [String: Double]
    public var srt: String
    public var report: String?
    public var log: String
    /// No subtitles found.
    public var empty: Bool
    /// The long gaps without subtitles the report lists, `[start, end]` in seconds
    /// (nil from an engine before the C2 round).
    public var gaps: [[Double]]? = nil
}

public struct BatchFileFailed: Decodable, Sendable, Equatable {
    public var idx: Int
    /// `code (k=v, ...)` for an engine error, `Type: message` otherwise.
    public var error: String
    /// `key:band` of the step it failed in.
    public var atStep: String?
    /// The stable code (`probe_failed`, `unknown`...), translated by the app.
    public var code: String? = nil
    /// A short text for the row: the exception's own message, no type name, no prefix.
    public var text: String? = nil
    /// The technical detail (`Type: message`, stderr).
    public var detail: String? = nil
    public var tool: String? = nil
    public var path: String? = nil
    public var line: Int? = nil
    /// The per-file log, where the whole story is.
    public var log: String? = nil
    /// A tool that exited with an error (11.3.4): its name, exit status and last complaint,
    /// so the app words "ffmpeg exited with status 69: …" in its own language.
    public var program: String? = nil
    public var status: Int? = nil
    public var reason: String? = nil
}

public struct BatchFileStopped: Decodable, Sendable, Equatable {
    public var idx: Int
}

public struct BatchDone: Decodable, Sendable, Equatable {
    public var done: Int
    public var failed: Int
    public var stopped: Int
    public var skipped: Int
    public var elapsed: Double
    /// The batch thread itself failed (every video counted as skipped).
    public var error: String?
}

public struct PreviewProgress: Decodable, Sendable, Equatable {
    /// Zones searched, of `total` (a resumed search counts the zones it did not search again).
    public var done: Int
    public var total: Int
    /// Frames with text in any band (of the zones this search looked at).
    public var found: Int
    /// Frames with text in the signs band (`found_top`; nil from an engine without it).
    public var foundTop: Int?
    /// The zone just searched, 0-based (nil from an engine before C3).
    public var zone: Int?
    /// Its frame; nil when no timestamp of the zone could be read.
    public var frame: PreviewFrame?

    public init(done: Int, total: Int, found: Int, foundTop: Int? = nil, zone: Int? = nil, frame: PreviewFrame? = nil) {
        self.done = done
        self.total = total
        self.found = found
        self.foundTop = foundTop
        self.zone = zone
        self.frame = frame
    }
}

/// A whole frame in `<state>/tmp/preview/<hash>/`: the app draws the bands.
public struct PreviewFrame: Decodable, Sendable, Equatable {
    /// The zone of the video it comes from, 0-based (nil from an engine before C3).
    public var zone: Int?
    public var path: String
    /// The bands with text, in this order: `bottom`, `top` (empty when none has text;
    /// `top` only with the signs band on). Both when the frame has a line and a sign.
    public var bands: [String]
    public var hasText: Bool
    public var width: Int
    public var height: Int
    public var ts: Double

    public var hasDialogue: Bool { bands.contains("bottom") }
    public var hasSigns: Bool { bands.contains("top") }

    public init(zone: Int? = nil, path: String, bands: [String], width: Int = 1920, height: Int = 1080, ts: Double = 0) {
        self.zone = zone
        self.path = path
        self.bands = bands
        self.hasText = !bands.isEmpty
        self.width = width
        self.height = height
        self.ts = ts
    }
}

public struct PreviewDone: Decodable, Sendable, Equatable {
    public var frames: [PreviewFrame]
}

/// `preview.stopped`: why the search stopped before its end.
public struct PreviewStopped: Decodable, Sendable, Equatable {
    /// "user" (`preview.stop`) or "batch" (a batch started); nil from an engine before C3.
    public var reason: String?

    public init(reason: String? = nil) { self.reason = reason }
}

public struct PreviewFailed: Decodable, Sendable, Equatable {
    /// invalid_duration, probe_failed, internal...
    public var error: String
    public var message: String?
}

/// An `EngineEvent` by name, with its data decoded.
public enum EngineMessage: Sendable, Equatable {
    case ready(EngineReady)
    case toolsProgress(ToolProgress)
    case toolsDone(ToolsDone)
    case warmupDone(WarmupDone)
    case batchFileStarted(BatchFileStarted)
    case batchStep(BatchStep)
    case batchFileDone(BatchFileDone)
    case batchFileFailed(BatchFileFailed)
    case batchFileStopped(BatchFileStopped)
    case batchDone(BatchDone)
    case previewProgress(PreviewProgress)
    case previewDone(PreviewDone)
    case previewStopped(PreviewStopped)
    case previewFailed(PreviewFailed)
    /// The client's own events.
    case engineStarted(pid: Int)
    case engineExited(status: Int)
    case engineGaveUp
    /// A name this package does not know.
    case other(name: String)
}

extension EngineEvent {
    /// The event decoded by name. Throws when a known event has data of the
    /// wrong shape (log it: the engine and the app disagree).
    public func message() throws -> EngineMessage {
        struct Pid: Decodable { var pid: Int }
        struct Status: Decodable { var status: Int }
        switch name {
        case "ready": return .ready(try decode())
        case "tools.progress": return .toolsProgress(try decode())
        case "tools.done": return .toolsDone(try decode())
        case "warmup.done": return .warmupDone(try decode())
        case "batch.file.started": return .batchFileStarted(try decode())
        case "batch.step": return .batchStep(try decode())
        case "batch.file.done": return .batchFileDone(try decode())
        case "batch.file.failed": return .batchFileFailed(try decode())
        case "batch.file.stopped": return .batchFileStopped(try decode())
        case "batch.done": return .batchDone(try decode())
        case "preview.progress": return .previewProgress(try decode())
        case "preview.done": return .previewDone(try decode())
        case "preview.stopped": return .previewStopped(try decode())
        case "preview.failed": return .previewFailed(try decode())
        case "engine.started": return .engineStarted(pid: try decode(as: Pid.self).pid)
        case "engine.exited": return .engineExited(status: try decode(as: Status.self).status)
        case "engine.gave_up": return .engineGaveUp
        default: return .other(name: name)
        }
    }
}

// MARK: - Typed calls

extension EngineClient {
    /// `hello`, with a timeout: on the very first launch the launcher sets up
    /// Python before `serve` reads its first line.
    public func hello(timeout: Duration = EngineHello.timeout) async throws -> EngineHello {
        try await call(EngineMethod.hello, timeout: timeout)
    }

    public func toolsStatus() async throws -> ToolsStatusReply {
        try await call(EngineMethod.toolsStatus)
    }

    /// nil downloads what is missing.
    public func toolsInstall(_ keys: [String]? = nil) async throws -> StartReply {
        try await call(EngineMethod.toolsInstall, params: keys.map { ["keys": $0] } ?? [:])
    }

    /// "Use my own ffmpeg": a path, or nil for the downloaded one. Error `bad_tool` when it does not start.
    public func toolsUse(ffmpeg: String?) async throws -> ToolsUseReply {
        try await call(EngineMethod.toolsUse, params: ffmpeg.map { ["ffmpeg": $0] } ?? [:])
    }

    public func warmup(languages: [String]) async throws -> StartReply {
        try await call(EngineMethod.warmup, params: ["languages": languages])
    }

    public func listsStatus() async throws -> ListsStatus {
        try await call(EngineMethod.listsStatus)
    }

    /// `kind`: ignore or corrections. Replaces the list with the file.
    public func listsImport(kind: String, path: String) async throws -> ListsStatus {
        try await call(EngineMethod.listsImport, params: ["kind": kind, "path": path])
    }

    public func probe(_ paths: [String]) async throws -> [VideoInfo] {
        try await call(EngineMethod.videosProbe, params: ["paths": paths], as: VideosProbeReply.self).videos
    }

    /// `lang` (it, en) is the language of the per-file logs and the reports.
    /// Error `bad_params` before anything starts (an unsupported `langHint` too).
    public func batchStart(videos: [String], params: OcrParams, useIgnore: Bool = true,
                           useCorrections: Bool = true, lang: String) async throws -> StartReply {
        try await call(EngineMethod.batchStart, params: [
            "videos": videos, "params": params.dictionary, "use_ignore": useIgnore,
            "use_corrections": useCorrections, "lang": lang])
    }

    /// `all`: the whole batch; otherwise the file in progress only.
    /// `file` is the batch index (`idx` of `batch.file.started`) the stop is
    /// meant for: when another file is in progress by now the engine answers
    /// `ok: false, reason: "not_running"` and stops nothing.
    public func batchStop(all: Bool, file: Int? = nil) async throws -> StopReply {
        var params: [String: Any] = ["scope": all ? "all" : "file"]
        if let file, !all { params["file"] = file }
        return try await call(EngineMethod.batchStop, params: params)
    }

    /// `zones` resumes a search that stopped: only those zones (0-based) are searched.
    public func previewFrames(video: String, params: OcrParams, n: Int = 20, tries: Int = 3, zones: [Int]? = nil) async throws -> StartReply {
        var args: [String: Any] = ["video": video, "params": params.dictionary, "n": n, "tries": tries]
        if let zones { args["zones"] = zones }
        return try await call(EngineMethod.previewFrames, params: args)
    }

    public func previewStop() async throws -> StopReply {
        try await call(EngineMethod.previewStop)
    }

    public func previewTest(frame: String, params: OcrParams, useIgnore: Bool = true,
                            useCorrections: Bool = true) async throws -> OcrTestReply {
        try await call(EngineMethod.previewTest, params: [
            "frame": frame, "params": params.dictionary, "use_ignore": useIgnore, "use_corrections": useCorrections])
    }

    /// Never busy: works during a batch. Error `no_valid_segments` or `not_found`.
    public func srtFix(path: String, merge: Bool = true, ignore: Bool = true, flash: Bool = true,
                       minDuration: Double = 0.2, params: OcrParams, useIgnore: Bool = true,
                       useCorrections: Bool = true) async throws -> SrtFixReply {
        try await call(EngineMethod.srtFix, params: [
            "path": path, "merge": merge, "ignore": ignore, "flash": flash, "min_dur": minDuration,
            "params": params.dictionary, "use_ignore": useIgnore, "use_corrections": useCorrections])
    }
}
