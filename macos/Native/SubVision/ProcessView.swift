// SPDX-License-Identifier: MIT
// Process, the home (design boards E0–E7): the header, the notes, the list
// of videos (rows in `ProcessRows.swift`), the drop strip, the bottom bar in
// its three states (ready, batch running, finished) and the end-of-batch
// sheet (`FinishedSheet.swift`).

import AppKit
import SVShell
import SwiftUI

struct ProcessView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.svPageTop) private var top
    @Environment(\.svChrome) private var chrome
    @Environment(\.svWindowWidth) private var windowWidth
    @State private var dropTargeted = false

    var body: some View {
        @Bindable var model = model
        InspectorSplit(isOpen: $model.inspectorOpen) {
            page
        } inspector: {
            InspectorView()
        }
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                PageTop(title: model.t("app.process.title"), intro: compact ? nil : model.t("app.process.intro")) {
                    if !model.videos.isEmpty {
                        Button { model.openVideos() } label: { Label(model.t("app.process.open"), systemImage: "folder") }
                            .svButton(.secondary, .regular)
                    }
                    // In a narrow window the top bar holds the inspector button (board N1);
                    // with the inspector open the button stays, to close it (review note 1).
                    if windowWidth >= chrome.collapseBelow { InspectorButton() }
                }
                .padding(.bottom, 18)
                if model.videos.isEmpty {
                    ProcessEmptyView()
                        .padding(.bottom, 28)
                } else {
                    list
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, top)
            if !model.videos.isEmpty {
                bottomBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .fileDrop(isTargeted: $dropTargeted) { model.add($0) }
        .sheet(isPresented: Binding(get: { model.run.showSummary }, set: { if !$0 { model.markSummarySeen() } })) {
            FinishedSheet()
        }
    }

    // MARK: - List

    /// The columns shrink and lose the size column with the inspector open or a narrow window (design note 26).
    private var compact: Bool { model.inspectorOpen || windowWidth < chrome.collapseBelow }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.hello?.vision == false {
                NoteView(.red, title: model.t("app.process.note.vision_title"), text: model.t("app.process.note.vision_text")) {
                    Button(model.t("app.common.retry")) { model.retry() }.buttonStyle(SVTintedButtonStyle(.red))
                    Button(model.t("app.common.show_log")) { model.showLog() }.buttonStyle(SVTintedButtonStyle(.red))
                }
                .padding(.bottom, 14)
            }
            if !model.skippedItems.isEmpty {
                NoteView(.yellow, title: model.tn("app.process.note.skipped", model.skippedItems.count),
                         text: model.skippedItems.joined(separator: ", ")) {
                    Button { model.skippedItems = [] } label: {
                        Image(systemName: "xmark").svFont(11, .semibold).frame(width: 22, height: 22).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(model.t("app.common.dismiss"))
                }
                .padding(.bottom, 14)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VideoList(compact: compact)
                    DropStrip(targeted: dropTargeted)
                        .padding(.top, 10)
                }
                .padding(.bottom, 16)
            }
            .scrollClipDisabled()
            if let note = diskNote {
                NoteView(.yellow, text: note)
                    .padding(.bottom, 14)
            }
        }
    }

    /// Design note 16: under 10 GB free on the internal disk, a yellow line over the bar.
    private var diskNote: String? {
        #if DEBUG
        // The design snapshots (`DebugCapture`, `disk-free`): the free space fed by hand.
        if let gb = DebugCapture.freeGB {
            return gb < 10 ? model.t("app.process.bar.disk_low", ["free": Int(gb.rounded()), "need": 3]) : nil
        }
        #endif
        let home = URL(fileURLWithPath: NSHomeDirectory())
        guard let free = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage else { return nil }
        let gb = Double(free) / 1_000_000_000
        guard gb < 10 else { return nil }
        return model.t("app.process.bar.disk_low", ["free": Int(gb.rounded()), "need": 3])
    }

    // MARK: - Bottom bar

    /// Ready: the count and the outputs line, Start. Running: "File 2 of 3 · ends
    /// around 14:20", the rows added meanwhile, Stop All. Finished: the outcomes,
    /// Remove Finished, Start for the rows that are ready (E1, E2, E3, E5).
    private var bottomBar: some View {
        HStack(alignment: .center, spacing: 14) {
            let ready = model.readyVideos
            let finished = model.finishedVideos
            if model.batch.running {
                Text(runningText).svFont(13, .semibold).foregroundStyle(SV.text).fixedSize()
                if !ready.isEmpty {
                    StatusChip(model.tn("app.process.bar.next_batch", ready.count))
                }
                Spacer(minLength: 8)
                Button { model.stopAll() } label: {
                    HStack(spacing: 6) {
                        Label(model.t("app.common.stop_all"), systemImage: "stop.fill")
                        Text("⌘.").svFont(10, mono: true).opacity(0.7)
                    }
                }
                .svButton(.destructive, .regular)
            } else {
                if !finished.isEmpty {
                    Text(outcomeText(finished, ready: ready.count)).svFont(13, .semibold).foregroundStyle(SV.text).fixedSize()
                } else {
                    Text(model.tn("app.process.bar.ready", ready.count, ["t": model.durationText(model.totalDuration)]))
                        .svFont(13, .semibold).foregroundStyle(SV.text).fixedSize()
                    Text(model.t("app.process.bar.outputs")).svSmall()
                        .frame(maxWidth: 520, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if !finished.isEmpty {
                    Button(model.t("app.process.bar.clear_done")) { model.clearFinished() }.svButton(.secondary, .regular)
                }
                Button { model.startBatch() } label: {
                    HStack(spacing: 6) {
                        Label(model.t("app.process.bar.start"), systemImage: "play.fill")
                        Text("⌘↩").svFont(10, mono: true).opacity(0.7)
                    }
                }
                .svButton(.primary, .regular)
                .disabled(!model.canStart)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(SV.bg)
        .overlay(alignment: .top) { Rectangle().fill(SV.line).frame(height: 1) }
    }

    /// "File 2 di 3 · fine verso le 14:20" (or without the end, before any estimate).
    private var runningText: String {
        if let ends = model.batch.endsAround {
            return model.t("app.process.bar.running", ["i": model.batch.index, "n": model.batch.total, "time": ends])
        }
        return model.t("app.process.row.file_of", ["i": model.batch.index, "n": model.batch.total])
    }

    /// "Lotto fermato · 1 fatto · 1 senza sottotitoli · 1 fallito · 1 pronto".
    private func outcomeText(_ finished: [VideoItem], ready: Int) -> String {
        var parts: [String] = []
        let stopped = finished.filter { $0.state == .stopped }.count
        let done = finished.filter { $0.state == .done }.count
        let noSubs = finished.filter { $0.state == .noSubs }.count
        let failed = finished.filter { $0.state == .failed }.count
        if model.run.summary?.stopped ?? 0 > 0 || (stopped > 0 && model.run.stoppedByUser) { parts.append(model.t("app.process.bar.stopped")) }
        if done > 0 { parts.append(model.tn("app.process.bar.done", done)) }
        if noSubs > 0 { parts.append(model.tn("app.process.bar.no_subs", noSubs)) }
        if failed > 0 { parts.append(model.tn("app.process.bar.failed", failed)) }
        if stopped > 0 { parts.append(model.tn("app.process.bar.stopped_count", stopped)) }
        if ready > 0 { parts.append(model.tn("app.process.bar.ready_count", ready)) }
        return model.join(parts)
    }
}

/// "+ Drop more videos or folders here" under the list (E1).
struct DropStrip: View {
    @Environment(AppModel.self) private var model
    var targeted: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus").svFont(12, .medium)
            Text(model.t("app.process.list.drop_more")).svFont(12)
        }
        .foregroundStyle(targeted ? SV.primaryText : SV.text2)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .svDropFrame(targeted: targeted)
    }
}

/// The list of videos: a header row and one row per video in a surface box.
struct VideoList: View {
    @Environment(AppModel.self) private var model
    var compact: Bool

    /// Column widths of the boards: duration, fps, size, actions (E1; narrower with the inspector or in a narrow window).
    var widths: (duration: CGFloat, fps: CGFloat, size: CGFloat?, actions: CGFloat) {
        compact ? (66, 56, nil, 200) : (74, 62, 86, 236)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ForEach(model.videos) { video in
                Rectangle().fill(SV.line).frame(height: 1)
                VideoRow(video: video, widths: widths)
            }
        }
        .background(RoundedRectangle(cornerRadius: SV.Radius.card).fill(SV.surface))
        .overlay(RoundedRectangle(cornerRadius: SV.Radius.card).strokeBorder(SV.line))
        .clipShape(RoundedRectangle(cornerRadius: SV.Radius.card))
    }

    private var header: some View {
        HStack(spacing: 14) {
            Color.clear.frame(width: StatusCircle.size)
            label(model.t("app.process.list.name")).frame(maxWidth: .infinity, alignment: .leading)
            label(model.t("app.process.list.duration")).frame(width: widths.duration, alignment: .trailing)
            label(model.t("app.process.list.fps")).frame(width: widths.fps, alignment: .trailing)
            if let size = widths.size {
                label(model.t("app.process.list.size")).frame(width: size, alignment: .trailing)
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
