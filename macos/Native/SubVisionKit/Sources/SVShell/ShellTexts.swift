// SPDX-License-Identifier: MIT
// The texts the shell shows. English here; `ShellTexts(localizer)` takes them
// from the app's catalogues (`locales/<lang>/app.json`, keys `app.*`), so the
// shell's own views speak the app's language.

import Foundation
import SVLocalization

public struct ShellTexts: Sendable, Equatable {
    // Sidebar and top bar
    public var settings = "Settings"
    public var showSidebar = "Show Sidebar"
    /// `{version}` is filled in.
    public var version = "Version {version}"
    /// `{version}` and `{python}`: the sidebar footer's tooltip.
    public var engineVersion = "Engine {version} · Python {python}"
    public var checkUpdates = "Check for Updates…"
    public var github = "GitHub"

    // Engine status
    public var engineStarting = "Starting the engine…"
    public var engineFirst = "The first start takes a moment."
    public var engineFailed = "The engine did not start"
    public var engineGaveUp = "The engine keeps stopping. Quit and open the app again; if it goes on, send the log."
    public var retry = "Try Again"
    public var showLog = "Show Log"
    public var quit = "Quit"

    // Tools window
    public var welcome = "Welcome to {app}"
    /// `{mb}` is filled in.
    public var toolsIntro1 = "{app} needs a few tools, about {mb} MB, downloaded once."
    public var toolsIntro2 = "They stay inside the app's own folder; nothing else on the Mac changes."
    public var toolsDownloading = "Downloading {i} of {n}"
    public var toolsProgress = "{done} of {total} MB"
    public var toolsMinuteLeft = "about a minute left"
    public var toolsMinutesLeft = "about {n} minutes left"
    /// The status line while a task (the warm-up) runs, and its time.
    public var toolsPreparing = "Preparing…"
    public var toolsPreparingTime = ""
    public var toolsInside = "Everything goes into the app's own folder."
    public var toolsStoppedTitle = "The download stopped"
    public var toolsStoppedText = "{tool} could not be downloaded. Check the connection and try again."
    public var toolsStoppedChecksum = "{tool} arrived damaged. Try again; if it happens again, send the log."
    public var toolsStoppedKept = "What was already downloaded is kept."
    /// A task row failed (the warm-up: Vision did not load).
    public var toolsTaskFailedTitle = "The preparation did not start."
    public var toolsTaskFailedText = "The log says why."
    public var toolsRuntime = "the engine's own Python"
    public var toolsMegabytes = "{n} MB"
    public var toolsSeconds = "{n} s"
    public var stopped = "stopped"

    // Updates
    public var updateAvailable = "{app} {version} is available"
    /// `{current}`: the version installed.
    public var updateAvailableText = "Download it from GitHub and replace the app in Applications."
    public var updateDownload = "Download…"
    public var updateLater = "Later"
    public var upToDate = "{app} {version} is up to date"
    public var upToDateText = "This is the latest version."
    public var updateErrorTitle = "Could not check for updates"
    public var updateErrorText = "GitHub did not answer. Check the connection and try again."
    public var ok = "OK"

    public init() {}

    public static let english = ShellTexts()

    /// Every field from the app's catalogues; a key the catalogue lacks keeps
    /// the English text, except the alert texts the design leaves out.
    public init(_ localizer: Localizer) {
        self.init()
        // The boards have no second line in these two alerts.
        upToDateText = ""
        updateErrorText = ""
        for (path, key) in Self.catalogue where localizer.has(key) {
            self[keyPath: path] = localizer.t(key)
        }
    }

    /// Field ↔ catalogue key (the plural fields use their `.altri` form).
    /// The app's catalogue test checks that every key is there.
    nonisolated(unsafe) public static let catalogue: [(WritableKeyPath<ShellTexts, String>, String)] = [
        (\.settings, "app.sidebar.settings"),
        (\.showSidebar, "app.sidebar.show_sidebar"),
        (\.version, "app.sidebar.version"),
        (\.engineVersion, "app.sidebar.engine_version"),
        (\.checkUpdates, "app.sidebar.check_updates"),
        (\.github, "app.sidebar.github_short"),
        (\.engineStarting, "app.tools.engine.starting"),
        (\.engineFirst, "app.tools.engine.first"),
        (\.engineFailed, "app.tools.engine.failed"),
        (\.engineGaveUp, "app.tools.engine.gave_up"),
        (\.retry, "app.common.retry"),
        (\.showLog, "app.common.show_log"),
        (\.quit, "app.common.quit"),
        (\.welcome, "app.tools.welcome"),
        (\.toolsIntro1, "app.tools.intro1"),
        (\.toolsIntro2, "app.tools.intro2"),
        (\.toolsDownloading, "app.tools.downloading"),
        (\.toolsProgress, "app.tools.progress"),
        (\.toolsMinuteLeft, "app.tools.minute_left"),
        (\.toolsMinutesLeft, "app.tools.minutes_left.altri"),
        (\.toolsPreparing, "app.tools.preparing"),
        (\.toolsPreparingTime, "app.tools.preparing_time"),
        (\.toolsInside, "app.tools.inside"),
        (\.toolsStoppedTitle, "app.tools.stopped_title"),
        (\.toolsStoppedText, "app.tools.stopped_text"),
        (\.toolsStoppedChecksum, "app.tools.stopped_checksum"),
        (\.toolsStoppedKept, "app.tools.stopped_kept"),
        (\.toolsTaskFailedTitle, "app.tools.vision_failed"),
        (\.toolsTaskFailedText, "app.tools.vision_failed_text"),
        (\.toolsRuntime, "app.tools.row.python_sub"),
        (\.toolsMegabytes, "app.tools.mb"),
        (\.toolsSeconds, "app.tools.seconds"),
        (\.stopped, "app.common.stopped_chip"),
        (\.updateAvailable, "app.alerts.update_title"),
        (\.updateAvailableText, "app.alerts.update_text"),
        (\.updateDownload, "app.common.download"),
        (\.updateLater, "app.alerts.later"),
        (\.upToDate, "app.settings.up_to_date"),
        (\.updateErrorTitle, "app.settings.update_error"),
        (\.updateErrorText, "app.alerts.update_error_text"),
        (\.ok, "app.common.ok"),
    ]

    /// `{name}` fields filled from `values` (the `Localizer` rules: `{{` `}}`
    /// are braces, an unknown field stays as it is).
    public static func fill(_ text: String, _ values: [String: Any]) -> String {
        Localizer.format(text, values)
    }
}
