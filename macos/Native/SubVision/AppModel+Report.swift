// SPDX-License-Identifier: MIT
// The review report inside the Review page (C3-06, C3-07, boards RV1, R1–R4):
// the list of the videos processed, a click on one (or Review on Video, ⌘R,
// the end-of-batch sheet, a file's notification, File › Open a Review…) and its
// report comes in from the right in the same page, under a title band; back
// (the round ‹, ⌘[) returns to the list. One report at a time, no window of its
// own. The page and the bridge are in ReportPage.swift and ReportBridge.swift.

import AppKit
import SVShell
import SwiftUI
import UniformTypeIdentifiers

/// The report the Review page shows, if any; `AppModel.report` holds it.
struct ReportState {
    /// The report open in the page, nil while the page shows the list.
    var session: ReportSession?
}

extension VideoItem {
    /// `<stem>.review.html` next to the video, as the engine writes it.
    var reportURL: URL { url.deletingPathExtension().appendingPathExtension("review.html") }
    var reportExists: Bool { FileManager.default.fileExists(atPath: reportURL.path) }

    /// The report the last batch wrote, also when it is no longer on disk (the page says
    /// so, R3); nil when the batch wrote none.
    var reviewReport: URL? {
        if let reportPath { return URL(fileURLWithPath: reportPath) }
        return reportExists ? reportURL : nil
    }
}

extension AppModel {
    /// The time the report comes in from the right and goes back (C3-06).
    static let reportSlide = Animation.easeOut(duration: 0.25)

    /// Review is in front with a report open (not the list).
    var reportShown: Bool { tab == .review && report.session != nil }

    /// Opens `url` in the Review page: the page comes to the front and the report slides in
    /// over the list; the same report open already stays as it is (its edits too).
    func openReport(_ url: URL, video: VideoItem? = nil) {
        let key = url.standardizedFileURL
        let owner = video ?? videos.first { $0.reviewReport?.standardizedFileURL == key }
        if let owner { reviewSelection = owner.id }
        let sameTab = tab == .review
        if tab != .review { tab = .review }
        reopenMainWindow()
        if let open = report.session, open.url == key {
            if open.phase == .gone || open.phase == .unreadable { open.load() }
            return
        }
        let session = ReportSession(url: key, videoID: owner?.id, model: self)
        session.load()
        let previous = report.session
        if sameTab && previous == nil {
            withAnimation(Self.reportSlide) { report.session = session }
        } else {
            report.session = session
        }
        previous?.close()
    }

    /// Review (the row's button and ⋯ on Video, ⌘R, the end-of-batch sheet, the Review list):
    /// the Review page with that video's report open.
    func review(_ video: VideoItem) {
        guard let url = video.reviewReport else { return }
        openReport(url, video: video)
    }

    /// Back to the list (the round ‹, View › Back ⌘[, "Back to the List" of R3): the
    /// report slides out, the list is where it was.
    func closeReport() {
        guard let session = report.session else { return }
        if tab == .review {
            withAnimation(Self.reportSlide) { report.session = nil }
        } else {
            report.session = nil
        }
        // The web view keeps its place until the slide is over.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { session.close() }
    }

    /// "Go to Review" of the end-of-batch sheet: one video to review opens its report,
    /// more open the list.
    func goToReview(_ batch: [VideoItem]) {
        let reviewable = batch.filter { ($0.state == .done || $0.state == .noSubs) && $0.reviewReport != nil }
        if reviewable.count == 1, let only = reviewable.first {
            review(only)
        } else {
            if report.session != nil { closeReport() }
            tab = .review
        }
    }

    /// The name a report goes by: the video of the list it belongs to, else the
    /// report's own name without `_<date>.review.html`.
    func reviewName(for report: URL) -> String {
        let key = report.standardizedFileURL.path
        if let video = videos.first(where: { $0.reviewReport?.standardizedFileURL.path == key }) { return video.name }
        return ReviewData.videoName(ofReport: report.lastPathComponent)
    }

    /// File › Open a Review… (⌥⌘O): the open panel, then the report in the page
    /// (also the reports written by the 1.x).
    func openReportPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.html]
        panel.message = t("app.menu.open_panel_report")
        panel.prompt = t("app.common.open")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openReport(url)
    }

    /// File › Save Reviewed SRT (⌘S): the report's own "Save reviewed SRT".
    var canSaveReview: Bool { reportShown && report.session?.phase == .ready }

    func saveReviewedSRT() {
        guard canSaveReview, let bridge = report.session?.bridge else { return }
        Task { _ = try? await bridge.call("await exportSrt();") }
    }

    /// A file's notification (design note 23): the Review page with its report open.
    func openReviewFromNotification(_ id: UUID) {
        guard let video = videos.first(where: { $0.id == id }) else { return }
        reviewSelection = id
        if video.reviewReport != nil { review(video) } else { tab = .review }
    }

    func openReportInBrowser(_ url: URL) { NSWorkspace.shared.open(url) }

    func showReportInFinder(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
}
