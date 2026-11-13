// SPDX-License-Identifier: MIT
// The end-of-batch sheet (design boards E6, C2-V5): the outcomes in the title,
// one row per file of the batch with Review or Open Log; Show SRTs in Finder
// on the left, Close and Go to Review (the default) on the right. It stays "unseen" until closed: the notification's click and
// the next launch bring it back (`AppModel.loadSummary`). The shape follows
// the FinishedSheet of the native macOS app of AnimeUp (by the same author).

import SVShell
import SwiftUI

struct FinishedSheet: View {
    @Environment(AppModel.self) private var model

    private var rows: [VideoItem] { model.summaryVideos }

    /// "1 SRT pronto · 1 senza sottotitoli · 1 fallito" (the stopped ones too).
    private var title: String {
        let done = rows.filter { $0.state == .done }.count
        let noSubs = rows.filter { $0.state == .noSubs }.count
        let failed = rows.filter { $0.state == .failed }.count
        let stopped = rows.filter { $0.state == .stopped }.count
        var parts: [String] = []
        if done > 0 || (noSubs + failed + stopped == 0) { parts.append(model.tn("app.process.finished.title", done)) }
        if noSubs > 0 { parts.append(model.tn("app.process.bar.no_subs", noSubs)) }
        if failed > 0 { parts.append(model.tn("app.process.bar.failed", failed)) }
        if stopped > 0 { parts.append(model.tn("app.process.bar.stopped_count", stopped)) }
        return model.join(parts)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).svFont(16, .bold).foregroundStyle(SV.text)
            // No "the batch took 2 min" (design note 69): each row says how long its file took.
            Text(model.t("app.process.finished.text"))
                .svSmall().fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, video in
                    if index > 0 { Rectangle().fill(SV.line).frame(height: 1) }
                    SummaryRow(video: video)
                }
            }
            .svBox(RoundedRectangle(cornerRadius: SV.Radius.card), fill: SV.surface, line: SV.line, padding: EdgeInsets())
            HStack(spacing: 8) {
                if rows.contains(where: { $0.state == .done }) {
                    Button { model.showSummarySRTs() } label: {
                        Label(model.t("app.process.finished.show_all"), systemImage: "macwindow")
                    }
                    .svButton(.secondary, .regular)
                }
                Spacer()
                Button(model.t("app.common.close")) { model.markSummarySeen() }
                    .svButton(.secondary, .regular)
                    .keyboardShortcut(.cancelAction)
                Button {
                    model.markSummarySeen()
                    model.tab = .review
                } label: { Label(model.t("app.process.finished.go_review"), systemImage: "doc.text.magnifyingglass") }
                    .svButton(.primary, .regular)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 520)
        .background(SV.bg)
    }
}

/// One file of the sheet: ring, name and the outcome in a word, the button.
struct SummaryRow: View {
    @Environment(AppModel.self) private var model
    var video: VideoItem

    private var circle: StatusCircle.State {
        switch video.state {
        case .done: .done
        case .noSubs: .warning
        case .failed: .failed
        default: .stopped
        }
    }

    private var detail: (String, Color) {
        switch video.state {
        case .done:
            // "16 righe · elaborato in 01:54"
            (model.join([model.tn("app.process.finished.lines", video.segments ?? 0)]
                        + (video.elapsed.map { [model.t("app.process.finished.took_file", ["t": Localizer.clock($0)])] } ?? [])), SV.text2)
        case .noSubs: (model.t("app.process.finished.no_subs"), SV.yellowText)
        case .failed: (model.t("app.process.finished.failed_at", ["step": model.stepLabel(video.atStep)]), SV.redText)
        default: (model.t("app.common.stopped_chip"), SV.text2)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            StatusCircle(circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(video.name).svFont(12.5, .medium).foregroundStyle(SV.text).lineLimit(1).truncationMode(.middle)
                Text(detail.0).svFont(11.5).foregroundStyle(detail.1).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if video.state == .done || video.state == .noSubs {
                Button { model.review(video) } label: {
                    Label(model.t("app.process.row.review"), systemImage: "doc.text.magnifyingglass")
                }
                .svButton(.secondary, .small)
                .disabled(video.outputReport == nil)
                .help(model.t("app.process.row.review_help"))
            } else {
                Button(model.t("app.process.row.open_log")) { model.openLog(video) }
                    .svButton(.secondary, .small)
                    .disabled(!video.logExists)
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
    }
}
