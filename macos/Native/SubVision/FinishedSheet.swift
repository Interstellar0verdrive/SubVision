// SPDX-License-Identifier: MIT
// The end-of-batch sheet (design boards E6, C2-V5, C3-12): it comes up over
// whatever page is open (no jump to Video). The outcomes in the title ("2 SRT
// pronti · 1 non riuscito", "Nessun SRT: 1 non riuscito"), one row per file of
// the batch in the batch's order: Review on the ones done, a failed one with a
// red cross, its reason in one line and Open Log. Show SRTs in Finder on the
// left, Close (Esc) and Go to Review (Return) on the right. It stays "unseen"
// until closed: the notification's click and the next launch bring it back
// (`AppModel.loadSummary`). The shape follows the FinishedSheet of the native
// macOS app of AnimeUp (by the same author).

import SVShell
import SwiftUI

struct FinishedSheet: View {
    @Environment(AppModel.self) private var model

    private var rows: [VideoItem] { model.summaryVideos }

    private var title: String { model.summaryTitle }

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
                    model.goToReview(rows)
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
        case .failed: (failedText, SV.redText)
        default: (model.t("app.common.stopped_chip"), SV.text2)
        }
    }

    /// "Non riuscito durante OCR ×3 · dialoghi: Vision non ha risposto." in one line (C3-12).
    private var failedText: String {
        let step = video.atStep.map { model.stepLabel($0) } ?? ""
        let head = step.isEmpty ? model.t("app.process.finished.failed") : model.t("app.process.finished.failed_at", ["step": step])
        let reason = model.failureText(video).trimmingCharacters(in: .whitespacesAndNewlines)
        return reason.isEmpty ? head : model.t("app.process.finished.failed_reason", ["head": head, "reason": reason])
    }

    var body: some View {
        HStack(spacing: 12) {
            StatusCircle(circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(video.name).svFont(12.5, .medium).foregroundStyle(SV.text).lineLimit(1).truncationMode(.middle)
                Text(detail.0).svFont(11.5).foregroundStyle(detail.1).lineLimit(1).truncationMode(.tail)
                    .help(video.state == .failed ? detail.0 : "")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if video.state == .done || video.state == .noSubs {
                Button {
                    // C3-12: the sheet closes and the video opens in Review.
                    model.markSummarySeen()
                    model.review(video)
                } label: {
                    Label(model.t("app.process.row.review"), systemImage: "doc.text.magnifyingglass")
                }
                .svButton(.secondary, .small)
                .disabled(video.outputReport == nil)
                .help(model.t("app.process.row.review_help"))
            } else {
                Button { model.openLog(video) } label: {
                    Label(model.t("app.process.row.open_log"), systemImage: "list.bullet.rectangle")
                }
                .svButton(.secondary, .small)
                .disabled(!video.logExists)
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
    }
}

extension AppModel {
    /// "2 SRT pronti · 1 non riuscito", "Nessun SRT: 1 non riuscito" (C3-12); the files
    /// without subtitles and the stopped ones are counted too.
    var summaryTitle: String {
        let done = summaryVideos.filter { $0.state == .done }.count
        let noSubs = summaryVideos.filter { $0.state == .noSubs }.count
        let failed = summaryVideos.filter { $0.state == .failed }.count
        let stopped = summaryVideos.filter { $0.state == .stopped }.count
        var others: [String] = []
        if noSubs > 0 { others.append(tn("app.process.bar.no_subs", noSubs)) }
        if failed > 0 { others.append(tn("app.process.finished.failed_count", failed)) }
        if stopped > 0 { others.append(tn("app.process.bar.stopped_count", stopped)) }
        if done == 0, !others.isEmpty {
            return t("app.process.finished.title_none", ["rest": join(others)])
        }
        return join([tn("app.process.finished.title", done)] + others)
    }
}
