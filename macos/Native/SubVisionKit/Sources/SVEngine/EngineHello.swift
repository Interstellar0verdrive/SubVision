// SPDX-License-Identifier: MIT
// Adapted from the AnimeUp native app (AnimeUpKit/Sources/Models/EngineReplies.swift),
// by the same author. SubVision does not depend on AnimeUp.

import Foundation

/// `hello`: who answered and what it can do, as `serve.py` sends it. Every
/// field but `engine`, `version` and `protocol` is optional in the JSON, so
/// an older or stripped-down engine still decodes.
public struct EngineHello: Codable, Sendable, Equatable {
    public struct FFmpeg: Codable, Sendable, Equatable {
        public var path: String
        public var version: String?

        public init(path: String, version: String? = nil) {
            self.path = path
            self.version = version
        }
    }

    public var engine: String
    public var version: String
    public var `protocol`: Int
    public var pid: Int?
    public var python: String?
    /// Apple Vision is available in the engine's Python.
    public var vision: Bool
    /// LiveText (ocrmac) is available.
    public var livetext: Bool
    /// nil when ffmpeg is not installed yet.
    public var ffmpeg: FFmpeg?
    /// BCP-47 codes Vision supports on this Mac.
    public var languages: [String]
    public var stateFolder: String?

    /// How long `hello` may take: the first answer comes after the launcher
    /// has checked (or set up) uv, Python and the virtual environment.
    public static let timeout: Duration = .seconds(90)

    /// The engine speaks `EngineProtocol.version`.
    public var isCompatible: Bool { self.protocol == EngineProtocol.version }

    public init(engine: String, version: String, protocol: Int, pid: Int? = nil, python: String? = nil,
                vision: Bool = false, livetext: Bool = false, ffmpeg: FFmpeg? = nil,
                languages: [String] = [], stateFolder: String? = nil) {
        self.engine = engine
        self.version = version
        self.protocol = `protocol`
        self.pid = pid
        self.python = python
        self.vision = vision
        self.livetext = livetext
        self.ffmpeg = ffmpeg
        self.languages = languages
        self.stateFolder = stateFolder
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        engine = try c.decode(String.self, forKey: .engine)
        version = try c.decode(String.self, forKey: .version)
        `protocol` = try c.decode(Int.self, forKey: .protocol)
        pid = try c.decodeIfPresent(Int.self, forKey: .pid)
        python = try c.decodeIfPresent(String.self, forKey: .python)
        vision = try c.decodeIfPresent(Bool.self, forKey: .vision) ?? false
        livetext = try c.decodeIfPresent(Bool.self, forKey: .livetext) ?? false
        ffmpeg = try c.decodeIfPresent(FFmpeg.self, forKey: .ffmpeg)
        languages = try c.decodeIfPresent([String].self, forKey: .languages) ?? []
        stateFolder = try c.decodeIfPresent(String.self, forKey: .stateFolder)
    }
}
