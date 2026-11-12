// SPDX-License-Identifier: MIT
// The texts the shell shows. English here; the app fills them from its own
// catalogues (`Localizer`) and passes them in, so the shell never reads a
// catalogue itself.

import Foundation

public struct ShellTexts: Sendable, Equatable {
    // Sidebar and top bar
    public var settings = "Settings"
    public var showSidebar = "Show Sidebar"
    public var hideSidebar = "Hide Sidebar"
    /// `{version}` is filled in.
    public var version = "Version {version}"
    public var engineVersion = "Engine {version}"
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
    public var toolsPreparing = "Preparing…"
    public var toolsInside = "Everything goes into the app's own folder."
    public var toolsStoppedTitle = "The download stopped"
    public var toolsStoppedText = "{tool} could not be downloaded. Check the connection and try again."
    public var toolsStoppedChecksum = "{tool} arrived damaged. Try again; if it happens again, send the log."
    public var toolsStoppedKept = "What was already downloaded is kept."
    public var toolsRuntime = "the engine's own Python"
    public var stopped = "stopped"

    // Updates
    public var updateAvailable = "{app} {version} is available"
    public var updateAvailableText = "Download it from GitHub and replace the app in Applications."
    public var updateDownload = "Download…"
    public var updateLater = "Later"
    public var upToDate = "{app} {version} is up to date"
    public var upToDateText = "This is the latest version."
    public var updateErrorTitle = "Could not check for updates"
    public var updateErrorText = "GitHub did not answer. Check the connection and try again."
    public var ok = "OK"

    // Quit and close
    public var quitTitle = "Quit while work is running?"
    public var quitText = "The work stops now. You can pick it up again next time."
    public var quitAnyway = "Quit"
    public var cancel = "Cancel"
    public var closeTitle = "{app} keeps working"
    public var closeText = "The window is closed, the work goes on. Click the Dock icon to open it again."
    public var dontShowAgain = "Don't show again"

    public init() {}

    public static let english = ShellTexts()

    /// `{name}` fields filled from `values`.
    public static func fill(_ text: String, _ values: [String: Any]) -> String {
        var out = text
        for (k, v) in values { out = out.replacingOccurrences(of: "{\(k)}", with: "\(v)") }
        return out
    }
}
