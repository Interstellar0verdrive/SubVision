// SPDX-License-Identifier: MIT
// The review report inside the Review page (C3-07, boards R1–R4): the title
// band ("Revisione di <video>", its details, Show in Finder and Open in
// Browser, the round ‹ back to the list), and under it the report in a
// WKWebView, which draws the summary box with the report bar that sticks to
// the top when the page scrolls and the legend fixed at the bottom. While it
// loads, a spinner; a report no longer on disk, a red note (R3). The session
// and its bridge live in `AppModel.report` while the report is open.

import AppKit
import SVShell
import SwiftUI
import WebKit

/// The report the page shows, and the bridge behind it.
@MainActor
@Observable
final class ReportSession {
    enum Phase: Equatable {
        case loading
        case ready
        /// The file is not there (any more).
        case gone
        /// The file is there but is not a readable review report.
        case unreadable
    }

    let url: URL
    /// The video of the list the report belongs to (nil for a report opened from File).
    let videoID: UUID?
    private(set) var phase: Phase = .loading
    private(set) var bridge: ReportBridge?
    /// Lines, lines to re-check and gaps, read from the report's data (the title band's details).
    private(set) var counts: ReviewData.Counts?
    /// The review state (`<name>.review.json`) could not be written: the
    /// yellow notice at the bottom, once per run of failures (closing it keeps
    /// it closed until a write goes through and another fails).
    private(set) var stateWarning = false
    @ObservationIgnored private var stateFailing = false
    /// The last export, for the debug commands (the report bar shows it itself, R2).
    private(set) var lastExport: URL?
    unowned let model: AppModel
    #if DEBUG
    /// Debug: the answer to "Choose where to save…" without the alert and the panel
    /// (`report-elsewhere <path>|cancel`); `.some(nil)` cancels.
    static var debugElsewhere: URL??
    #endif

    var name: String { url.lastPathComponent }
    /// The video's name: the bold part of "Revisione di <video>".
    var title: String { model.reviewName(for: url) }
    var video: VideoItem? { videoID.flatMap { id in model.videos.first { $0.id == id } } }

    init(url: URL, videoID: UUID?, model: AppModel) {
        self.url = url
        self.videoID = videoID
        self.model = model
    }

    /// Reads the file and starts the load; the phase says what the page shows.
    func load() {
        bridge?.detach()
        bridge = nil
        phase = .loading
        guard FileManager.default.fileExists(atPath: url.path) else {
            phase = .gone
            return
        }
        guard let file = ReportFile(url: url) else {
            phase = .unreadable
            return
        }
        counts = file.counts
        let bridge = ReportBridge(file: file, language: model.language, t: { [model] key, values in model.t(key, values) })
        bridge.onNavigationFinished = { [weak self] in self?.phase = .ready }
        bridge.onNavigationFailed = { [weak self] error in
            AppLog.shared.error("report load \(file.url.lastPathComponent): \(error)")
            self?.phase = FileManager.default.fileExists(atPath: file.url.path) ? .unreadable : .gone
        }
        bridge.onExport = { [weak self] outcome in
            if case .saved(let url) = outcome { self?.lastExport = url }
        }
        bridge.askWhereToSave = { [weak self] name in self?.askWhereToSave(name) }
        bridge.onStateWrite = { [weak self] ok in self?.stateWritten(ok) }
        self.bridge = bridge
        model.log.info("report open \(file.url.lastPathComponent) (\(file.kind == .bridged ? "2.0" : "1.x"))")
        bridge.load()
    }

    /// The page went back to the list: the bridge lets the web view go.
    func close() {
        bridge?.detach()
    }

    /// A write of the review state went through or not (the notice of `stateWarning`).
    private func stateWritten(_ ok: Bool) {
        if ok {
            stateFailing = false
            stateWarning = false
        } else if !stateFailing {
            stateFailing = true
            stateWarning = true
        }
    }

    func hideStateWarning() { stateWarning = false }

    /// R3: the export could not be written next to the original.
    private func askWhereToSave(_ name: String) -> URL? {
        #if DEBUG
        if let answer = Self.debugElsewhere { return answer }
        #endif
        let a = SVAlert(icon: AlertIconName.error, tone: .red, title: model.t("app.report.save_failed"),
                        text: model.t("app.report.save_failed_text"))
        a.button(model.t("app.report.save_elsewhere"), role: .primary)
        a.button(model.t("app.common.cancel"))
        guard a.runModal() == 0 else { return nil }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [.init(filenameExtension: "srt") ?? .plainText]
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    func showInFinder() { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    func openInBrowser() { NSWorkspace.shared.open(url) }
}

extension AppModel {
    /// The title band's details: "12 righe · 2 da ricontrollare · 3 buchi · elaborato oggi alle 08:57"
    /// (R1), without what is zero ("12 righe · elaborato oggi alle 08:57"); a report no longer
    /// there says only when it was processed (R3).
    func reportDetails(_ session: ReportSession) -> String {
        var parts: [String] = []
        if session.phase != .gone, session.phase != .unreadable {
            let video = session.video
            parts = ReviewData.details(lines: session.counts?.lines ?? video?.segments, toCheck: session.counts?.toCheck,
                                       gaps: session.counts?.gaps ?? video?.gaps?.count).map(detailText)
        }
        if let when = session.video?.finished ?? Self.modified(session.url) { parts.append(processedOn(when)) }
        return join(parts)
    }

    /// "elaborato oggi alle 08:57", "elaborato ieri alle 18:02", "elaborato il 13/11 alle 22:43".
    func processedOn(_ date: Date) -> String {
        let time = Self.clockTime(date)
        switch ReviewData.day(of: date) {
        case .today: return t("app.review.report.when_today", ["time": time])
        case .yesterday: return t("app.review.report.when_yesterday", ["time": time])
        case .earlier: return t("app.review.report.when_date", ["date": shortDate(date), "time": time])
        }
    }

    /// "13/11" in the app's language.
    func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: language)
        f.setLocalizedDateFormatFromTemplate("dM")
        return f.string(from: date)
    }

    private static func modified(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}

/// The report in the page: the title band, then the web view or the state of R3.
struct ReportPage: View {
    let session: ReportSession
    @Environment(AppModel.self) private var model

    /// The column of the report (`.wrap` of the report, 1180 px): the band keeps to it too.
    static let column: CGFloat = 1180

    var body: some View {
        VStack(spacing: 0) {
            TitleBand(prefix: model.t("app.review.report.of"), name: session.title, subtitle: model.reportDetails(session),
                      backHelp: model.t("app.common.back_to_list"), maxContentWidth: Self.column, shortcut: false,
                      back: { model.closeReport() }) {
                if session.phase != .gone, session.phase != .unreadable {
                    Button { session.showInFinder() } label: {
                        Label(model.t("app.common.show_in_finder"), systemImage: "macwindow")
                    }
                    .svButton(.secondary, .small)
                    Button { session.openInBrowser() } label: {
                        Label(model.t("app.report.open_browser"), systemImage: "arrow.up.right.square")
                    }
                    .svButton(.secondary, .small)
                }
            }
            content
        }
        .background(SV.bg)
        // The band's ‹ and View › Back (⌘[) go back to the list.
        .onAppear { model.backAction = { [weak model] in model?.closeReport() } }
        // Gone with the report, or with the page; not when a report opened again at once (the
        // band of the new one appeared before this one finished sliding out).
        .onDisappear { if model.report.session == nil || model.tab != .review { model.backAction = nil } }
    }

    private var content: some View {
        ZStack(alignment: .top) {
            switch session.phase {
            case .loading, .ready:
                if let bridge = session.bridge {
                    WebViewHost(webView: bridge.webView)
                        .opacity(session.phase == .ready ? 1 : 0)
                }
                if session.phase == .loading {
                    HStack(spacing: 10) {
                        Spinner(size: 16)
                        Text(model.t("app.report.loading")).svFont(12.5).foregroundStyle(SV.text2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .gone:
                note(title: model.t("app.report.gone", ["name": session.name]), text: model.t("app.report.gone_text"))
            case .unreadable:
                note(title: model.t("app.report.unreadable", ["name": session.name]), text: model.t("app.report.unreadable_text"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if session.stateWarning {
                StateWarning(text: model.t("app.report.state_failed"), closeHelp: model.t("app.common.dismiss")) {
                    session.hideStateWarning()
                }
                .help(model.t("app.report.state_failed_help", ["name": session.bridge?.file.stateURL.lastPathComponent ?? ""]))
                // Over the report's legend, fixed at the bottom of the page.
                .padding(.bottom, 52)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: session.stateWarning)
    }

    /// R3: the red note, 640 pt, a little under the band, with the way back to the list.
    private func note(title: String, text: String) -> some View {
        NoteView(.red, title: title, text: text) {
            Button(model.t("app.review.report.back")) { model.closeReport() }.svButton(.destructive, .small)
        }
        .frame(width: 640)
        .padding(.top, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// The pill at the bottom of the report, in yellow with a close button: the
/// review state is not being saved.
struct StateWarning: View {
    var text: String
    var closeHelp: String
    var close: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle").svFont(14).foregroundStyle(SVTone.yellow.text)
            Text(verbatim: text).svFont(12.5).foregroundStyle(SV.text).lineLimit(1)
            Button(action: close) {
                Image(systemName: "xmark").svFont(10, .semibold).foregroundStyle(SV.text2)
                    .frame(width: 22, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(closeHelp)
            .accessibilityLabel(closeHelp)
        }
        .padding(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 8))
        .background(Capsule().fill(SV.alert))
        .overlay(Capsule().strokeBorder(SVTone.yellow.line, lineWidth: 1))
        .shadow(color: SV.shadow.opacity(0.4), radius: 16, y: 12)
    }
}

/// The bridge's WKWebView, owned by the bridge, in the view tree.
struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
