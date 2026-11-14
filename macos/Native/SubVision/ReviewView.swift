// SPDX-License-Identifier: MIT
// Review (C3-06, board RV1): the list of the videos processed, each with its
// lines, its gaps and when it ran, «Apri» and ⋯; the chevron says a row goes
// in. A click on a row (or «Apri») brings its report into the same page
// (C3-07, ReportPage.swift), sliding in from the right over the list, which
// keeps its place for the way back. Under the list the totals and Show SRTs
// in Finder.

import AppKit
import SVShell
import SwiftUI

extension AppModel {
    /// The videos with an outcome to review: done or without subtitles, in the list's
    /// order (also the ones processed in an earlier session, while they stay in the list).
    var reviewVideos: [VideoItem] { videos.filter { $0.state == .done || $0.state == .noSubs } }

    /// The review row last opened (⌘R on the list opens it again), if still there.
    var selectedReview: VideoItem? { reviewVideos.first { $0.id == reviewSelection } }

    /// "oggi 22:43" · "ieri 18:02" · "13/11 22:43" in the app's language.
    func processedWhen(_ date: Date) -> String {
        let time = Self.clockTime(date)
        switch ReviewData.day(of: date) {
        case .today: return t("app.review.today", ["time": time])
        case .yesterday: return t("app.review.yesterday", ["time": time])
        case .earlier: return "\(shortDate(date)) \(time)"
        }
    }

    /// A reviewed SRT the report saved next to the video (`<stem>-reviewed-<date>.srt`): the chip of the row.
    func hasReviewedSRT(_ video: VideoItem) -> Bool {
        let folder = video.url.deletingLastPathComponent()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.contains { ReviewData.isReviewedSRT($0, of: video.name) }
    }

    /// Show SRTs in Finder (the Review page): the SRTs of every row, selected.
    func showReviewSRTs() {
        let urls = reviewVideos.map(\.outputSRT).filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// "3 video elaborati · 38 righe · 9 buchi" (RV1), without what is zero ("2 video elaborati · 24 righe").
    var reviewTotals: String {
        let totals = ReviewData.totals(reviewVideos.map { (lines: $0.segments, gaps: $0.gaps?.count) })
        return join([tn("app.review.sum.videos", totals.videos)]
                    + ReviewData.details(lines: totals.lines, gaps: totals.gaps).map(detailText))
    }

    /// One item of a line of details: "12 righe", "2 da ricontrollare", "3 buchi".
    func detailText(_ detail: ReviewData.Detail) -> String {
        switch detail {
        case .lines(let n): tn("app.review.sum.lines", n)
        case .toCheck(let n): t("app.review.report.to_check", ["n": n])
        case .gaps(let n): tn("app.review.sum.gaps", n)
        }
    }
}

/// The page: the list, and the report over it while one is open.
struct ReviewPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            // The list stays under the report, so the way back finds it where it was.
            ReviewListPage()
                .allowsHitTesting(model.report.session == nil)
                .accessibilityHidden(model.report.session != nil)
            if let session = model.report.session {
                ReportPage(session: session)
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            }
        }
        .clipped()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// RV1: the title, the list (or the empty state), the totals at the bottom.
struct ReviewListPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.svPageTop) private var top
    @Environment(\.svChrome) private var chrome
    @Environment(\.svWindowWidth) private var windowWidth

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                PageTop(title: model.t("app.review.title"), intro: chrome.inspectorOverlays(windowWidth: windowWidth) ? nil : model.t("app.review.intro")) {
                    EmptyView()
                }
                .padding(.bottom, 18)
                if model.reviewVideos.isEmpty {
                    empty
                } else {
                    ScrollView {
                        ReviewList()
                            .padding(.bottom, 16)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .scrollClipDisabled()
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, top)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if !model.reviewVideos.isEmpty { bottomBar }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SV.bg)
    }

    /// Nothing processed yet: what will come here, and the way to Video.
    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: Tab.review.symbol).svFont(40, .light).foregroundStyle(SV.text3)
            Text(model.t("app.review.empty_title")).svFont(14, .semibold).foregroundStyle(SV.text)
            Text(model.t("app.review.empty_text")).svSmall().multilineTextAlignment(.center)
                .frame(maxWidth: 440).fixedSize(horizontal: false, vertical: true)
            Button { model.tab = .process } label: { Label(model.t("app.review.go_video"), systemImage: Tab.process.symbol) }
                .svButton(.secondary, .regular)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 28)
    }

    /// "3 video elaborati · 38 righe · 9 buchi" and Show SRTs in Finder.
    private var bottomBar: some View {
        HStack(spacing: 14) {
            Text(model.reviewTotals).svFont(12.5, .semibold).foregroundStyle(SV.text).lineLimit(1)
            Spacer(minLength: 8)
            Button { model.showReviewSRTs() } label: {
                Label(model.t("app.process.finished.show_all"), systemImage: "macwindow")
            }
            .svButton(.secondary, .regular)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(SV.bg)
        .overlay(alignment: .top) { Rectangle().fill(SV.line).frame(height: 1) }
    }
}

/// The list of the Review page (`.c3r` of RV1): the circle, the video, lines, gaps,
/// when, «Apri», ⋯ and the chevron.
struct ReviewList: View {
    @Environment(AppModel.self) private var model
    @State private var width: CGFloat = 0

    /// Under this width of the list the "processed" column goes into the row's second line.
    static let whenColumnFrom: CGFloat = 760

    var widths: ReviewRow.Widths {
        .init(lines: 56, gaps: 52, when: width >= Self.whenColumnFrom || width == 0 ? 104 : nil, open: 64)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ForEach(model.reviewVideos) { video in
                Rectangle().fill(SV.line).frame(height: 1)
                ReviewRow(video: video, widths: widths)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .background(RoundedRectangle(cornerRadius: SV.Radius.card).fill(SV.surface))
        .overlay(RoundedRectangle(cornerRadius: SV.Radius.card).strokeBorder(SV.line))
        .clipShape(RoundedRectangle(cornerRadius: SV.Radius.card))
    }

    private var header: some View {
        HStack(spacing: ReviewRow.gap) {
            Color.clear.frame(width: StatusCircle.size)
            label(model.t("app.process.list.name")).frame(maxWidth: .infinity, alignment: .leading)
            label(model.t("app.review.col.lines")).frame(width: widths.lines, alignment: .trailing)
            label(model.t("app.review.col.gaps")).frame(width: widths.gaps, alignment: .trailing)
            if let when = widths.when {
                label(model.t("app.review.col.when")).frame(width: when, alignment: .trailing)
            }
            Color.clear.frame(width: widths.open)
            Color.clear.frame(width: ReviewRow.moreWidth)
            Color.clear.frame(width: ReviewRow.chevronWidth)
        }
        .padding(.leading, 13 + 3)
        .padding(.trailing, 16)
        .frame(height: 30)
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased()).svFont(10.5, .semibold).foregroundStyle(SV.text3).tracking(0.4).lineLimit(1)
    }
}

/// One processed video. A click anywhere but on its buttons opens the report in the page;
/// the chevron says so (no drawer here: the times and files are on Video).
struct ReviewRow: View {
    struct Widths: Equatable {
        var lines: CGFloat
        var gaps: CGFloat
        var when: CGFloat?
        var open: CGFloat
    }

    static let gap: CGFloat = 12
    static let moreWidth: CGFloat = 22
    static let chevronWidth: CGFloat = 16

    @Environment(AppModel.self) private var model
    var video: VideoItem
    var widths: Widths
    @State private var hover = false

    private var hasReport: Bool { video.reviewReport != nil }
    /// The batch wrote a report that is no longer on disk: the chip, and a click shows R3.
    private var reportMissing: Bool { hasReport && video.outputReport == nil }

    var body: some View {
        HStack(alignment: .center, spacing: Self.gap) {
            StatusCircle(video.state == .noSubs ? .warning : .done)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .center, spacing: 8) {
                    Text(video.name).svFont(12.5, .medium).foregroundStyle(SV.text).lineLimit(1).truncationMode(.middle)
                    if model.hasReviewedSRT(video) {
                        StatusChip(model.t("app.review.reviewed"), tone: .green)
                            .help(model.t("app.review.reviewed_help"))
                    }
                    if reportMissing {
                        StatusChip(model.t("app.review.report_missing"), tone: .neutral)
                            .help(model.t("app.review.report_missing_help"))
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(video.folder).svFont(11, mono: true).foregroundStyle(SV.text3).lineLimit(1).truncationMode(.middle)
                    ForEach(secondLine, id: \.self) { piece in
                        Text("· \(piece)").svFont(11, mono: true).foregroundStyle(SV.text3).lineLimit(1).fixedSize()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            number(video.segments.map(String.init)).frame(width: widths.lines, alignment: .trailing)
            number(video.gaps.map { String($0.count) }, tint: (video.gaps?.count ?? 0) > 0 ? SV.yellowText : nil)
                .frame(width: widths.gaps, alignment: .trailing)
            if let when = widths.when {
                number(video.finished.map(model.processedWhen)).frame(width: when, alignment: .trailing)
            }
            Button { model.review(video) } label: { Text(model.t("app.review.open")) }
                .svButton(.primary, .small)
                .disabled(!hasReport)
                .help(model.t(hasReport ? "app.review.open_help" : "app.review.no_report"))
                .frame(width: widths.open, alignment: .trailing)
            PopupMenu({ menuItems }) {
                Image(systemName: "ellipsis").svFont(13, .semibold).foregroundStyle(SV.text2)
                    .frame(width: Self.moreWidth, height: 22).contentShape(Rectangle())
            }
            .frame(width: Self.moreWidth)
            .help(model.t("app.process.row.more"))
            .accessibilityLabel(model.t("app.process.row.more"))
            Image(systemName: "chevron.right").svFont(13, .medium).foregroundStyle(SV.text3)
                .frame(width: Self.chevronWidth)
                .opacity(hasReport ? 1 : 0.4)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 8)
        .frame(minHeight: 52)
        .padding(.leading, 13)
        .padding(.trailing, 16)
        .background(hover && hasReport ? SV.hoverVeil : .clear)
        .overlay(alignment: .leading) { Rectangle().fill(video.state == .noSubs ? SV.yellow : SV.green).frame(width: 3) }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { if hasReport { model.review(video) } }
        .contextMenu { menuButtons }
        .help(video.path)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.review(video) }
    }

    /// "1280×544", and the time processed when its column does not fit (narrow window).
    private var secondLine: [String] {
        var pieces: [String] = []
        if let size = video.size { pieces.append(size) }
        if widths.when == nil, let finished = video.finished { pieces.append(model.processedWhen(finished)) }
        return pieces
    }

    private func number(_ text: String?, tint: Color? = nil) -> some View {
        Text(text ?? "—").svFont(12, mono: true).foregroundStyle(tint ?? SV.textCode).lineLimit(1)
    }

    /// The ⋯ menu (C3-06): where the files are, the report in the browser, the file's log.
    private var menuItems: [SVMenuItem] {
        [.item(model.t("app.common.show_in_finder")) { model.showInFinder([video.id]) },
         .item(model.t("app.report.open_browser"), enabled: video.outputReport != nil) {
             if let url = video.outputReport { model.openReportInBrowser(url) }
         },
         .item(model.t("app.process.row.open_log"), enabled: video.logExists) { model.openLog(video) }]
    }

    @ViewBuilder private var menuButtons: some View {
        Button(model.t("app.review.open")) { model.review(video) }.disabled(!hasReport)
        Divider()
        Button(model.t("app.common.show_in_finder")) { model.showInFinder([video.id]) }
        Button(model.t("app.report.open_browser")) {
            if let url = video.outputReport { model.openReportInBrowser(url) }
        }
        .disabled(video.outputReport == nil)
        Button(model.t("app.process.row.open_log")) { model.openLog(video) }.disabled(!video.logExists)
    }
}
