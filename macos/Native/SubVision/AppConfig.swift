// SPDX-License-Identifier: MIT
// What the shell needs to know about SubVision: names, URLs, the tools of the
// first-launch window, the Dock colours. One place, as `AppShellConfig` asks.

import Foundation
import SVShell

enum AppConfig {
    static let bundleIdentifier = "io.github.interstellar0verdrive.subvision"
    static let repositoryURL = URL(string: "https://github.com/Interstellar0verdrive/SubVision")!
    static let releaseAPIURL = URL(string: "https://api.github.com/repos/Interstellar0verdrive/SubVision/releases/latest")!
    static let releasePageURL = URL(string: "https://github.com/Interstellar0verdrive/SubVision/releases/latest")!
    static let releasesURL = URL(string: "https://github.com/Interstellar0verdrive/SubVision/releases")!
    static let guideURL = URL(string: "https://github.com/Interstellar0verdrive/SubVision#readme")!
    static let issuesURL = URL(string: "https://github.com/Interstellar0verdrive/SubVision/issues/new")!

    /// The versions the tools window names before the engine can say them
    /// (`tools.py` FFMPEG_VERSION, `.python-version`).
    static let ffmpegVersion = "9.0.2"
    static let pythonVersion = "3.13"
    /// Nominal sizes of the downloads (design board T1).
    static let runtimeMB: Int64 = 51
    static let ffmpegMB: Int64 = 28

    /// The keys of the downloads, as `tools.status` names them.
    static let downloadKeys = ["ffmpeg", "ffprobe"]
    static let warmupKey = "warmup"

    /// The four rows of the first-launch window (D12), in the boards' order.
    static func tools(_ t: (String, [String: Any]) -> String) -> [ToolRow] {
        [ToolRow(key: "python", name: t("app.tools.row.python", ["version": pythonVersion]),
                 detail: t("app.tools.row.python_sub", [:]), megabytes: runtimeMB, kind: .runtime),
         // The name apart from the version: the error texts name the tool alone ("FFmpeg could not…").
         ToolRow(key: "ffmpeg", name: t("app.tools.row.ffmpeg", ["version": ""]).trimmingCharacters(in: .whitespaces),
                 version: ffmpegVersion, detail: t("app.tools.row.ffmpeg_sub", [:]), megabytes: ffmpegMB),
         ToolRow(key: "ffprobe", name: t("app.tools.row.ffprobe", ["version": ""]).trimmingCharacters(in: .whitespaces),
                 version: ffmpegVersion, detail: t("app.tools.row.ffprobe_sub", [:]), megabytes: ffmpegMB),
         ToolRow(key: warmupKey, name: t("app.tools.row.warmup", [:]),
                 detail: t("app.tools.row.warmup_sub", [:]), kind: .task)]
    }

    static func shell(localizer: Localizer) -> AppShellConfig {
        AppShellConfig(appName: "SubVision", bundleIdentifier: bundleIdentifier,
                       repositoryURL: repositoryURL, releaseAPIURL: releaseAPIURL, releasePageURL: releasePageURL,
                       guideURL: guideURL, issuesURL: issuesURL,
                       logSubsystem: bundleIdentifier, tools: tools { localizer.t($0, $1) }, fallbackVersion: "2.0.0")
    }
}

/// The keys of `UserDefaults` the app keeps its settings under.
enum DefaultsKey {
    static let language = "language"
    /// `system`, `light`, `dark`: the key `ShellTheme.applySaved` reads.
    static let theme = "theme"
    static let notifications = "notifications"
    static let dockProgress = "dockProgress"
    static let autoCheckUpdates = "autoCheckUpdates"
    static let lastUpdateCheck = "lastUpdateCheck"
    static let lastUpdateResult = "lastUpdateResult"
    static let customFFmpeg = "customFFmpeg"
    /// The macOS build the warm-up last ran on: a different one runs it again (T4).
    static let warmupBuild = "warmupBuild"
    static let closeNoticeOff = "closeNoticeOff"
    static let includeSubfolders = "includeSubfolders"
    static let previewVideo = "previewVideo"
    /// The OCR language of the inspector (`OcrParams.langHint`), also the warm-up's.
    static let ocrLanguage = "langHint"
}
