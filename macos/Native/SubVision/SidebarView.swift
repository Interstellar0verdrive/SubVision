// SPDX-License-Identifier: MIT
// What the app puts in the shell's sidebar: the three tabs with their status
// lines (design board DS4, inventory §0), the activity card of a running
// batch and the update card.

import AppKit
import SVShell
import SwiftUI

extension AppModel {
    var tabs: [ShellTab] {
        [ShellTab(id: Tab.process.rawValue, symbol: Tab.process.symbol, title: t("app.sidebar.tab.process"),
                  subtitle: processSubtitle, busy: batch.running, count: countedVideos == 0 ? nil : countedVideos),
         ShellTab(id: Tab.review.rawValue, symbol: Tab.review.symbol, title: t("app.sidebar.tab.review"),
                  subtitle: reviewSubtitle),
         ShellTab(id: Tab.fix.rawValue, symbol: Tab.fix.symbol, title: t("app.sidebar.tab.fix"),
                  subtitle: fixSubtitle, done: fixDone, separatorBefore: true)]
    }

    /// The videos the sidebar counts: the unreadable ones are left out (board E1).
    var countedVideos: Int { videos.filter { $0.state != .unreadable }.count }

    /// "Nessun video" · "3 video" · "3 video · 1 in corso" · "4 video · 1 fallito" (E2–E5).
    var processSubtitle: String {
        guard countedVideos > 0 else { return t("app.sidebar.no_videos") }
        var parts = [tn("app.sidebar.videos", countedVideos)]
        if batch.running { parts.append(t("app.sidebar.running")); return join(parts) }
        let done = videos.filter { $0.state == .done || $0.state == .noSubs }.count
        let failed = videos.filter { $0.state == .failed }.count
        let stopped = videos.filter { $0.state == .stopped }.count
        if done > 0 { parts.append(tn("app.sidebar.done", done)) }
        if failed > 0 { parts.append(tn("app.sidebar.failed", failed)) }
        if stopped > 0 { parts.append(tn("app.sidebar.stopped", stopped)) }
        return join(parts)
    }

    /// "Nessun video elaborato" · "2 elaborati" (boards C2-V1, C2-R1).
    var reviewSubtitle: String {
        let n = reviewVideos.count
        return n == 0 ? t("app.sidebar.no_reviews") : tn("app.sidebar.reviews", n)
    }
}

/// Under the tabs: one card at a time, the batch first, else an update.
struct SidebarExtra: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.batch.running {
            ActivityCard(kind: model.t("app.sidebar.batch"),
                         line: Text(model.t("app.sidebar.batch_line", ["i": model.batch.index, "n": model.batch.total, "name": model.batch.name])),
                         fraction: model.batch.fraction,
                         footnote: model.batch.endsAround.map { model.t("app.sidebar.batch_ends", ["time": $0]) }) {
                Button { model.stopAll() } label: { Label(model.t("app.common.stop_all"), systemImage: "stop.fill") }
                    .svButton(.secondary, .small, fullWidth: true)
            }
            .onTapGesture { model.tab = .process }
        } else if let update = model.updateAvailable {
            UpdateCard(version: update.version, url: update.url)
        }
    }
}

/// "SubVision v2.0.1 is available": What's new, Download… (yellow).
struct UpdateCard: View {
    @Environment(AppModel.self) private var model
    var version: String
    var url: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle").svFont(11)
                Text(model.t("app.sidebar.update", ["version": version])).svFont(11.5, .semibold)
            }
            .foregroundStyle(SV.yellowText)
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                UnderlineLink(model.t("app.sidebar.whats_new"), tone: .yellow) { NSWorkspace.shared.open(url) }
                Spacer(minLength: 0)
                Button(model.t("app.common.download")) { NSWorkspace.shared.open(url) }.svButton(.notice, .small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .svBox(RoundedRectangle(cornerRadius: SV.Radius.card), fill: SV.yellowBg, line: SV.yellowLine,
               padding: EdgeInsets(vertical: 12, horizontal: 12))
    }
}
