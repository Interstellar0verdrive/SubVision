// SPDX-License-Identifier: MIT
// Review (design note 80, board C2-R1): the videos of the list that were
// processed (done, or without subtitles), with what is left to check: lines,
// lines dropped into the report, long gaps without subtitles, when it ran.
// Review opens the file's review report ("Revisione · <video>"); a click on a
// row opens its times and files (the detail of E3) with the gaps in a note.

import AppKit
import SVShell
import SwiftUI

extension AppModel {
    /// The videos with an outcome to review: done or without subtitles, in the list's
    /// order (also the ones processed in an earlier session, while they stay in the list).
    var reviewVideos: [VideoItem] { videos.filter { $0.state == .done || $0.state == .noSubs } }

    /// The review row selected (⌘R opens it), if still there.
    var selectedReview: VideoItem? { reviewVideos.first { $0.id == reviewSelection } }

    /// "oggi 22:43" · "ieri 18:02" · "13/11 22:43" in the app's language.
    func processedWhen(_ date: Date) -> String {
        let time = Self.clockTime(date)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return t("app.review.today", ["time": time]) }
        if calendar.isDateInYesterday(date) { return t("app.review.yesterday", ["time": time]) }
        let f = DateFormatter()
        f.locale = Locale(identifier: language)
        f.setLocalizedDateFormatFromTemplate("dM")
        return "\(f.string(from: date)) \(time)"
    }

    /// "00:00:41 → 00:00:49".
    func gapText(_ gap: [Double]) -> String {
        func hms(_ s: Double) -> String {
            let t = max(0, Int(s.rounded(.down)))
            return String(format: "%02d:%02d:%02d", t / 3600, t / 60 % 60, t % 60)
        }
        guard gap.count == 2 else { return "" }
        return "\(hms(gap[0])) → \(hms(gap[1]))"
    }

    /// The reviewed SRT the report exported next to the video (`<stem>-reviewed-<date>.srt`): the chip of the row.
    func hasReviewedSRT(_ video: VideoItem) -> Bool {
        let folder = video.url.deletingLastPathComponent()
        let stem = video.url.deletingPathExtension().lastPathComponent + "-reviewed-"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.contains { $0.hasPrefix(stem) && $0.hasSuffix(".srt") }
    }

    /// Show SRTs in Finder (the Review page): the SRTs of every row, selected.
    func showReviewSRTs() {
        let urls = reviewVideos.map(\.outputSRT).filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}

struct ReviewPage: View {
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

    /// "2 video elaborati · 37 righe · 2 scartate · 1 buco" and Show SRTs in Finder.
    private var bottomBar: some View {
        let rows = model.reviewVideos
        let lines = rows.compactMap(\.segments).reduce(0, +)
        let dropped = rows.compactMap(\.dropped).reduce(0, +)
        let gaps = rows.compactMap { $0.gaps?.count }.reduce(0, +)
        var parts = [model.tn("app.review.sum.videos", rows.count), model.tn("app.process.finished.lines", lines),
                     model.tn("app.review.sum.dropped", dropped)]
        if rows.contains(where: { $0.gaps != nil }) { parts.append(model.tn("app.review.sum.gaps", gaps)) }
        return HStack(spacing: 14) {
            Text(model.join(parts)).svFont(13, .semibold).foregroundStyle(SV.text).lineLimit(1)
            Spacer(minLength: 8)
            Button { model.showReviewSRTs() } label: {
                Label(model.t("app.process.finished.show_all"), systemImage: "macwindow")
            }
            .svButton(.secondary, .regular)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(SV.bg)
        .overlay(alignment: .top) { Rectangle().fill(SV.line).frame(height: 1) }
    }
}

/// The list of the Review page (`.c-rev`): the circle, the video, lines, dropped, gaps,
/// when, and Review with ⋯.
struct ReviewList: View {
    @Environment(AppModel.self) private var model
    @State private var width: CGFloat = 0

    /// Under this width of the list the "processed" column goes into the row's third line.
    static let whenColumnFrom: CGFloat = 760

    var widths: ReviewRow.Widths {
        .init(lines: 62, dropped: 72, gaps: 56, when: width >= Self.whenColumnFrom ? 110 : nil, actions: 150)
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
        HStack(spacing: 14) {
            Color.clear.frame(width: StatusCircle.size)
            label(model.t("app.process.list.name")).frame(maxWidth: .infinity, alignment: .leading)
            label(model.t("app.review.col.lines")).frame(width: widths.lines, alignment: .trailing)
            label(model.t("app.review.col.dropped")).frame(width: widths.dropped, alignment: .trailing)
            label(model.t("app.review.col.gaps")).frame(width: widths.gaps, alignment: .trailing)
            if let when = widths.when {
                label(model.t("app.review.col.when")).frame(width: when, alignment: .trailing)
            }
            Color.clear.frame(width: widths.actions)
        }
        .padding(.leading, 13 + 3)
        .padding(.trailing, 16)
        .frame(height: 30)
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased()).svFont(10.5, .semibold).foregroundStyle(SV.text3).tracking(0.3).lineLimit(1)
    }
}

/// One processed video: a click selects it and opens its times and files (E3), with the gaps.
struct ReviewRow: View {
    struct Widths: Equatable {
        var lines: CGFloat
        var dropped: CGFloat
        var gaps: CGFloat
        var when: CGFloat?
        var actions: CGFloat
    }

    @Environment(AppModel.self) private var model
    var video: VideoItem
    var widths: Widths
    @State private var hover = false

    private var selected: Bool { model.reviewSelection == video.id }
    private var expanded: Bool { model.run.expanded.contains(video.id) }
    private var textInset: CGFloat { StatusCircle.size + 14 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                StatusCircle(video.state == .noSubs ? .warning : .done)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(video.name).svFont(12.5, .medium).foregroundStyle(SV.text).lineLimit(1).truncationMode(.middle)
                        if model.hasReviewedSRT(video) {
                            StatusChip(model.t("app.review.reviewed"), tone: .green)
                                .help(model.t("app.review.reviewed_help"))
                        }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(video.folder).svFont(11, mono: true).foregroundStyle(SV.text3).lineLimit(1).truncationMode(.middle)
                        if let size = video.size {
                            Text("· \(size)").svFont(11, mono: true).foregroundStyle(SV.text3).lineLimit(1).fixedSize()
                        }
                    }
                    Text(meta).svFont(11.5).foregroundStyle(video.state == .noSubs ? SV.yellowText : SV.text2).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                number(video.segments.map(String.init)).frame(width: widths.lines, alignment: .trailing)
                number(video.dropped.map(String.init)).frame(width: widths.dropped, alignment: .trailing)
                number(video.gaps.map { String($0.count) }, tint: (video.gaps?.count ?? 0) > 0 ? SV.yellowText : nil)
                    .frame(width: widths.gaps, alignment: .trailing)
                if let when = widths.when {
                    number(video.finished.map(model.processedWhen)).frame(width: when, alignment: .trailing)
                }
                actions.frame(width: widths.actions, alignment: .trailing)
            }
            .padding(.vertical, 8)
            .frame(minHeight: 52)
            if expanded { detail }
        }
        .padding(.leading, 13)
        .padding(.trailing, 16)
        .background(selected ? SV.selSoft : hover ? SV.hoverVeil : .clear)
        .overlay(alignment: .leading) { Rectangle().fill(video.state == .noSubs ? SV.yellow : SV.green).frame(width: 3) }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { toggle() }
        .contextMenu { menuButtons }
        .help(video.path)
    }

    /// "elaborato in 01:54 · Italiano · 12 fps" (and the date when its column is not shown).
    private var meta: String {
        if video.state == .noSubs { return model.t("app.process.row.no_subs") }
        var parts: [String] = []
        if let elapsed = video.elapsed { parts.append(model.t("app.process.finished.took_file", ["t": Localizer.clock(elapsed)])) }
        if let lang = video.ocrLang { parts.append(model.languageName(lang)) }
        if let fps = video.ocrFPS { parts.append(model.t("app.review.fps", ["fps": model.localizer.number(fps)])) }
        if widths.when == nil, let finished = video.finished { parts.append(model.processedWhen(finished)) }
        return model.join(parts)
    }

    private func number(_ text: String?, tint: Color? = nil) -> some View {
        Text(text ?? "—").svFont(SVFont.numbers).foregroundStyle(tint ?? SV.textCode).lineLimit(1)
    }

    private var actions: some View {
        HStack(spacing: 6) {
            Button { model.review(video) } label: { Label(model.t("app.process.row.review"), systemImage: "doc.text.magnifyingglass") }
                .svButton(.secondary, .small)
                .disabled(video.outputReport == nil)
                .help(model.t(video.outputReport == nil ? "app.process.row.review_none" : "app.process.row.review_help"))
            PopupMenu({ menuItems }) {
                Image(systemName: "ellipsis").svFont(13, .semibold).foregroundStyle(SV.text2)
                    .frame(width: 22, height: 22).contentShape(Rectangle())
            }
            .help(model.t("app.process.row.more"))
            .accessibilityLabel(model.t("app.process.row.more"))
        }
    }

    private var menuItems: [SVMenuItem] {
        [.item(model.t("app.common.show_in_finder")) { model.showInFinder([video.id]) },
         .item(model.t("app.process.row.open_srt"), enabled: FileManager.default.fileExists(atPath: video.outputSRT.path)) { model.openSRT(video) },
         .item(model.t("app.process.row.open_log"), enabled: video.logExists) { model.openLog(video) },
         .item(model.t("app.process.row.open_in_preview"), enabled: model.canPreview(video)) { model.openInPreview(video.id) },
         .separator,
         .item(model.t("app.process.row.remove"), enabled: !video.state.inBatch) { model.removeWithUndo([video.id]) }]
    }

    @ViewBuilder private var menuButtons: some View {
        Button(model.t("app.process.row.review")) { model.review(video) }.disabled(video.outputReport == nil)
        Button(model.t("app.common.show_in_finder")) { model.showInFinder([video.id]) }
        Button(model.t("app.process.row.open_srt")) { model.openSRT(video) }
            .disabled(!FileManager.default.fileExists(atPath: video.outputSRT.path))
        Button(model.t("app.process.row.open_log")) { model.openLog(video) }.disabled(!video.logExists)
        Button(model.t("app.process.row.open_in_preview")) { model.openInPreview(video.id) }.disabled(!model.canPreview(video))
        Divider()
        Button(model.t("app.process.row.remove")) { model.removeWithUndo([video.id]) }
    }

    /// The times and the files (E3), then the gaps the report lists, in a yellow note.
    private var detail: some View {
        VStack(alignment: .leading, spacing: 12) {
            FinishedDetail(video: video)
            if let gaps = video.gaps, !gaps.isEmpty {
                NoteView(.yellow, text: gapNote(gaps))
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 12)
        .overlay(alignment: .top) { Rectangle().fill(SV.detailLine).frame(height: 1).padding(.trailing, -16) }
        .padding(.leading, textInset)
    }

    /// "1 buco senza sottotitoli oltre 6 s (00:00:41 → 00:00:49): controllalo con Rivedi."
    private func gapNote(_ gaps: [[Double]]) -> String {
        var ranges = gaps.prefix(3).map(model.gapText).joined(separator: ", ")
        if gaps.count > 3 { ranges += ", …" }
        let seconds = model.localizer.number(video.gapWarn ?? model.ocrParams.qcGapWarn)
        return model.tn("app.review.gap_note", gaps.count, ["s": seconds, "ranges": ranges])
    }

    private func toggle() {
        model.reviewSelection = video.id
        if expanded { model.run.expanded.remove(video.id) } else { model.run.expanded.insert(video.id) }
    }
}
