// SPDX-License-Identifier: MIT
// The review report window (F5.4, D8 a): a WKWebView on `<name>.revisione.html`
// with the `subvision` bridge (export, state). The stubs below keep the app
// building until F5.4 fills them.

import Foundation
import SVShell

/// The report windows open; `AppModel.report` holds it.
struct ReportState {}

extension VideoItem {
    /// `<stem>.revisione.html` next to the video, as the engine writes it.
    var reportURL: URL { url.deletingPathExtension().appendingPathExtension("revisione.html") }
    var reportExists: Bool { FileManager.default.fileExists(atPath: reportURL.path) }
}

extension AppModel {
    /// Opens a report in its window (the row's button, ⌘R, Open a Report…).
    func openReport(_ url: URL) { log.info("report: not yet (\(url.lastPathComponent))") }

    /// File › Open a Report… (⌥⌘O): the open panel, then `openReport`.
    func openReportPanel() { log.info("report panel: not yet") }
}
