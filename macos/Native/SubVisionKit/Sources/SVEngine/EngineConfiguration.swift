// SPDX-License-Identifier: MIT
// Adapted from the AnimeUp native app (AnimeUpKit/Sources/Engine/EngineConfiguration.swift),
// by the same author. SubVision does not depend on AnimeUp.

import Foundation

/// Where the engine lives and what it runs with.
///
/// - `codeFolder`: the program (the launcher, `src/`...). In the app bundle
///   it's `Contents/Resources/<spec.bundleFolderName>`; in Debug the scheme
///   sets `<PREFIX>CODE` to the worktree, so Python changes need no rebuild.
/// - `stateFolder`: what the app downloads and records (Python, bin/,
///   records/): `~/Library/Application Support/<spec.releaseStateFolderName>`,
///   or `<spec.debugStateFolderName>` in Debug.
public struct EngineConfiguration: Sendable, Equatable {
    /// The names that tie a configuration to one app: launcher, environment
    /// variables, folders. SubVision's own values are `Spec.subvision`.
    public struct Spec: Sendable, Equatable {
        /// The executable inside `codeFolder` (a bash script that execs Python).
        public var launcherName: String
        /// Prefix of the environment variables the engine reads
        /// (`<PREFIX>CODE`, `<PREFIX>STATO`...), with the trailing underscore.
        public var environmentPrefix: String
        /// Folder of the engine inside `Contents/Resources` of the bundle.
        public var bundleFolderName: String
        /// State folder names under `~/Library/Application Support`.
        public var releaseStateFolderName: String
        public var debugStateFolderName: String
        /// The engine's stderr, relative to the state folder.
        public var logRelativePath: String
        /// Variables (without the prefix) passed through to the engine when
        /// the app's own environment sets them, e.g. the Debug scheme.
        public var passThroughSuffixes: [String]

        public init(launcherName: String, environmentPrefix: String, bundleFolderName: String,
                    releaseStateFolderName: String, debugStateFolderName: String,
                    logRelativePath: String = "records/engine.log", passThroughSuffixes: [String] = []) {
            self.launcherName = launcherName
            self.environmentPrefix = environmentPrefix
            self.bundleFolderName = bundleFolderName
            self.releaseStateFolderName = releaseStateFolderName
            self.debugStateFolderName = debugStateFolderName
            self.logRelativePath = logRelativePath
            self.passThroughSuffixes = passThroughSuffixes
        }

        /// SubVision 2.0: `subvision serve`, `SUBVISION_*`, state in
        /// `SubVision` (`SubVision-dev` in Debug), log in `records/engine.log`;
        /// `SUBVISION_FFMPEG` (an ffmpeg of one's own, read by the engine at
        /// startup) passes through from the Debug scheme.
        public static let subvision = Spec(
            launcherName: "subvision", environmentPrefix: "SUBVISION_", bundleFolderName: "SubVision",
            releaseStateFolderName: "SubVision", debugStateFolderName: "SubVision-dev",
            passThroughSuffixes: ["FFMPEG"])

        public var codeKey: String { environmentPrefix + "CODE" }
        public var stateKey: String { environmentPrefix + "STATO" }
    }

    public var spec: Spec
    public var codeFolder: URL
    public var stateFolder: URL
    public var extraEnvironment: [String: String]
    public var logFile: URL

    public init(spec: Spec = .subvision, codeFolder: URL, stateFolder: URL,
                extraEnvironment: [String: String] = [:], logFile: URL? = nil) {
        self.spec = spec
        self.codeFolder = codeFolder
        self.stateFolder = stateFolder
        self.extraEnvironment = extraEnvironment
        self.logFile = logFile ?? stateFolder.appendingPathComponent(spec.logRelativePath)
    }

    public var launcher: URL { codeFolder.appendingPathComponent(spec.launcherName) }

    /// The default for this build. `<PREFIX>CODE` and `<PREFIX>STATO` in the
    /// app's own environment win (the Debug scheme sets them).
    public static func standard(spec: Spec = .subvision, debug: Bool, bundle: Bundle = .main,
                                environment: [String: String] = ProcessInfo.processInfo.environment) -> EngineConfiguration {
        let code: URL
        if let env = environment[spec.codeKey], !env.isEmpty {
            code = URL(fileURLWithPath: (env as NSString).expandingTildeInPath)
        } else {
            code = (bundle.resourceURL ?? bundle.bundleURL).appendingPathComponent(spec.bundleFolderName)
        }
        let state: URL
        if let env = environment[spec.stateKey], !env.isEmpty {
            state = URL(fileURLWithPath: (env as NSString).expandingTildeInPath)
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            state = support.appendingPathComponent(debug ? spec.debugStateFolderName : spec.releaseStateFolderName)
        }
        var extra: [String: String] = [:]
        for suffix in spec.passThroughSuffixes {
            let key = spec.environmentPrefix + suffix
            if let v = environment[key], !v.isEmpty { extra[key] = v }
        }
        return EngineConfiguration(spec: spec, codeFolder: code, stateFolder: state, extraEnvironment: extra)
    }

    /// The environment the sidecar starts with.
    func environment(base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var env = base
        // Never inherit these from a terminal that launched the app: they
        // would point the engine at somebody else's folders or Python.
        for key in env.keys where key.hasPrefix(spec.environmentPrefix) {
            env.removeValue(forKey: key)
        }
        for key in ["PYTHONPATH", "PYTHONHOME", "VIRTUAL_ENV", "UV_PROJECT_ENVIRONMENT"] {
            env.removeValue(forKey: key)
        }
        env[spec.codeKey] = codeFolder.path
        // Nothing is ever written next to the program (the bundle is read-only).
        env[spec.stateKey] = stateFolder.path
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTHONIOENCODING"] = "utf-8"
        let path = env["PATH"] ?? ""
        let essentials = "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = path.isEmpty ? essentials : "\(path):\(essentials)"
        for (k, v) in extraEnvironment { env[k] = v }
        return env
    }
}
