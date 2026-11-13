// SPDX-License-Identifier: MIT
// The review report windows (F5.4, D8 a): one `ReportWindowController` per
// report, opened from the row's button, ⌘R, the end-of-batch sheet and
// File › Open a Report…; opening a report already open brings its window
// to the front. The window and the bridge are in ReportWindow.swift and
// ReportBridge.swift.

import AppKit
import SVShell
import UniformTypeIdentifiers

/// The report windows open, by the report's file; `AppModel.report` holds it.
struct ReportState {
    var windows: [URL: ReportWindowController] = [:]

    /// The reports open, front to back (the order of their windows).
    var open: [ReportSession] {
        NSApp.orderedWindows.compactMap { window in windows.values.first { $0.window === window }?.session }
    }

    /// The report whose window is in front of the others, if any.
    var front: ReportWindowController? { open.first.flatMap { windows[$0.url] } }
}

extension VideoItem {
    /// `<stem>.revisione.html` next to the video, as the engine writes it.
    var reportURL: URL { url.deletingPathExtension().appendingPathExtension("revisione.html") }
    var reportExists: Bool { FileManager.default.fileExists(atPath: reportURL.path) }
}

extension AppModel {
    /// Opens a report in its window, or brings that window to the front
    /// (the row's button, ⌘R, Open a Report…, the end-of-batch sheet).
    @discardableResult
    func openReport(_ url: URL) -> ReportWindowController {
        let key = url.standardizedFileURL
        if let existing = report.windows[key] {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return existing
        }
        let session = ReportSession(url: key, model: self)
        let last = report.open.first.flatMap { report.windows[$0.url]?.window }
        let controller = ReportWindowController(session: session, cascadeFrom: last)
        controller.onClose = { [weak self] in self?.report.windows[key] = nil }
        report.windows[key] = controller
        controller.show()
        return controller
    }

    /// File › Open a Report… (⌥⌘O): the open panel, then `openReport`
    /// (also for the reports written by the 1.x).
    func openReportPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.html]
        panel.message = t("app.menu.open_panel_report")
        panel.prompt = t("app.common.open")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { openReport(url) }
    }

    /// The report window's Open in Browser: the default app for HTML.
    func openReportInBrowser(_ url: URL) { NSWorkspace.shared.open(url) }

    func showReportInFinder(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
}
