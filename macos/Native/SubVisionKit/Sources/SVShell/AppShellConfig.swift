// SPDX-License-Identifier: MIT
// The one place where an app configures the shell. The values that were
// constants scattered through the native macOS app of AnimeUp (by the same
// author) are gathered here, with its measures as the defaults.

import AppKit
import SVDesign
import SVEngine

/// A tool the first-launch window downloads, or a step it waits for.
public struct ToolRow: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        /// A download with a known size: a bar while it runs.
        case download
        /// The Python runtime (uv + Python): a spinner until the engine says `hello`.
        case runtime
        /// A step of unknown length (a warm-up): a spinner while it runs, no size.
        case task
    }

    /// The engine's key (`ffmpeg`), also the key of its `tools.progress` events.
    public var key: String
    public var name: String
    /// Shown after the name ("FFmpeg 9.0.2"); empty when the name has it already.
    public var version: String
    /// What it is for, after the name in secondary text ("reads the frames").
    public var detail: String
    public var megabytes: Int64
    public var kind: Kind

    public var id: String { key }

    public init(key: String, name: String, version: String = "", detail: String = "", megabytes: Int64 = 0,
                kind: Kind = .download) {
        self.key = key
        self.name = name
        self.version = version
        self.detail = detail
        self.megabytes = megabytes
        self.kind = kind
    }
}

/// The engine methods and events the tools window speaks: these defaults are
/// the protocol of `serve.py`. The `.task` rows run through `warmup` and end
/// with `warmup.done`.
public struct ToolsMethods: Sendable, Equatable {
    public var status: String
    public var install: String
    public var progressEvent: String
    public var doneEvent: String
    public var warmup: String
    public var warmupDoneEvent: String

    public init(status: String = EngineMethod.toolsStatus, install: String = EngineMethod.toolsInstall,
                progressEvent: String = "tools.progress", doneEvent: String = "tools.done",
                warmup: String = EngineMethod.warmup, warmupDoneEvent: String = "warmup.done") {
        self.status = status
        self.install = install
        self.progressEvent = progressEvent
        self.doneEvent = doneEvent
        self.warmup = warmup
        self.warmupDoneEvent = warmupDoneEvent
    }

    public static let standard = ToolsMethods()
}

/// Colours of the Dock icon's progress bar: `NSColor` because the Dock tile
/// draws with AppKit, outside any SwiftUI appearance.
public struct DockColors: Sendable {
    public var running: NSColor
    public var track: NSColor

    public init(running: NSColor, track: NSColor = NSColor.black.withAlphaComponent(0.55)) {
        self.running = running
        self.track = track
    }

    /// The accent of the dark tokens: the Dock is drawn once, not per appearance.
    public static let standard = DockColors(running: NSColor(css: "#2AC9DE"))
}

/// What the shell needs to know about the app.
public struct AppShellConfig: Sendable {
    public var appName: String
    public var bundleIdentifier: String
    /// The identifier of the main `Window` scene.
    public var mainWindowID: String
    public var repositoryURL: URL
    /// The GitHub API URL of the latest release (`.../releases/latest`).
    public var releaseAPIURL: URL
    /// The page to open for a new version.
    public var releasePageURL: URL
    public var guideURL: URL?
    public var issuesURL: URL?
    /// The main window's first size: `chrome.window` unless given.
    public var windowSize: CGSize
    public var toolsWindowSize: CGSize
    public var toolsWindowMinSize: CGSize
    public var chrome: SVChrome
    /// Prefix of the debug environment variables (`SUBVISION_SNAPSHOT`, `SUBVISION_WINDOW`...).
    public var environmentPrefix: String
    /// `os.Logger` subsystem of the app log.
    public var logSubsystem: String
    public var tools: [ToolRow]
    public var toolsMethods: ToolsMethods
    public var dockColors: DockColors
    /// `CFBundleShortVersionString`, or this when there is no bundle (the demo).
    public var fallbackVersion: String

    public init(appName: String, bundleIdentifier: String, mainWindowID: String = "main",
                repositoryURL: URL, releaseAPIURL: URL, releasePageURL: URL, guideURL: URL? = nil, issuesURL: URL? = nil,
                windowSize: CGSize? = nil,
                toolsWindowSize: CGSize = CGSize(width: 600, height: 380),
                toolsWindowMinSize: CGSize = CGSize(width: 600, height: 360),
                chrome: SVChrome = .default, environmentPrefix: String = "SUBVISION_",
                logSubsystem: String, tools: [ToolRow] = [], toolsMethods: ToolsMethods = .standard,
                dockColors: DockColors = .standard, fallbackVersion: String = "2.0") {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.mainWindowID = mainWindowID
        self.repositoryURL = repositoryURL
        self.releaseAPIURL = releaseAPIURL
        self.releasePageURL = releasePageURL
        self.guideURL = guideURL
        self.issuesURL = issuesURL
        self.windowSize = windowSize ?? chrome.window
        self.toolsWindowSize = toolsWindowSize
        self.toolsWindowMinSize = toolsWindowMinSize
        self.chrome = chrome
        self.environmentPrefix = environmentPrefix
        self.logSubsystem = logSubsystem
        self.tools = tools
        self.toolsMethods = toolsMethods
        self.dockColors = dockColors
        self.fallbackVersion = fallbackVersion
    }

    /// The app's version from its bundle.
    public var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? fallbackVersion
    }

    /// `<PREFIX><suffix>` in the environment, when set and not empty.
    public func environment(_ suffix: String, _ env: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        guard let v = env[environmentPrefix + suffix], !v.isEmpty else { return nil }
        return v
    }
}
