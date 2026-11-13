// SPDX-License-Identifier: MIT
// The end-of-batch sheet (design board E6): the outcomes in the title, one
// row per file of the batch with Open Report or Open Log, Show SRTs in
// Finder, OK. It stays "unseen" until closed: the notification's click and
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
            Text(title).svFont(15, .semibold).foregroundStyle(SV.text)
            Text(model.t("app.process.finished.text") + " "
                 + model.t("app.process.finished.took", ["t": model.durationText(model.run.summary?.elapsed ?? 0)]))
                .svSmall().fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, video in
                    if index > 0 { Rectangle().fill(SV.line).frame(height: 1) }
                    SummaryRow(video: video)
                }
            }
            .svBox(RoundedRectangle(cornerRadius: SV.Radius.card), fill: SV.surface, line: SV.line, padding: EdgeInsets())
            HStack(spacing: 8) {
                Spacer()
                if rows.contains(where: { $0.state == .done }) {
                    Button(model.t("app.process.finished.show_all")) { model.showSummarySRTs() }.svButton(.secondary, .regular)
                }
                Button(model.t("app.common.ok")) { model.markSummarySeen() }
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
        case .done: (model.tn("app.process.finished.lines", video.segments ?? 0), SV.text2)
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
                Button(model.t("app.process.finished.show_report")) { if let r = video.outputReport { model.openReport(r) } }
                    .svButton(.secondary, .small)
                    .disabled(video.outputReport == nil)
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
