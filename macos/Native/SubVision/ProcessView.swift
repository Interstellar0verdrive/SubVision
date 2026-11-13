// SPDX-License-Identifier: MIT
// Video, the home (design boards E0–E7, C2-V1–V5, N1): the header, the
// notes, the list of videos (rows in `ProcessRows.swift`), the drop area
// under it that fills the rest of the page (design note 60), the bottom bar
// in its four states (ready, a selection, batch running, finished), the
// parameters panel fixed on the right and the end-of-batch sheet
// (`FinishedSheet.swift`).

import AppKit
import SVShell
import SwiftUI

struct ProcessView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.svPageTop) private var top
    @Environment(\.svChrome) private var chrome
    @Environment(\.svWindowWidth) private var windowWidth
    @State private var dropTargeted = false
    /// The height the list's scroll view shows, and the list's own: the drop area takes the rest.
    @State private var viewport: CGFloat = 0
    @State private var listHeight: CGFloat = 0
    @State private var escMonitor: Any?

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
                // No Open Videos… here (design note 60: the drop area under the list adds), no
                // panel button: the panel is fixed beside a wide page, and a narrow window has
                // its button in the top bar (board N1).
                PageTop(title: model.t("app.process.title"), intro: narrow ? nil : model.t("app.process.intro")) { EmptyView() }
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
        .background { Color.clear.contentShape(Rectangle()).onTapGesture { model.selection = [] } }
        .onAppear { installEscape() }
        .onDisappear { removeEscape() }
        .fileDrop(isTargeted: $dropTargeted) { model.add($0) }
        .sheet(isPresented: Binding(get: { model.run.showSummary }, set: { if !$0 { model.markSummarySeen() } })) {
            FinishedSheet()
        }
    }

    // MARK: - Selection

    /// Esc deselects the rows (design note 58), unless a text field, a sheet or the
    /// inspector laid over a narrow window has a better use for it.
    private func installEscape() {
        guard escMonitor == nil else { return }
        let chrome = chrome
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [model] event in
            guard event.keyCode == 53, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
                  model.tab == .process, !model.selection.isEmpty,
                  let window = event.window, window.isMainWindow, window.attachedSheet == nil,
                  !(window.firstResponder is NSText),
                  !(model.inspectorOpen && chrome.inspectorOverlays(windowWidth: window.frame.width)) else { return event }
            model.selection = []
            return nil
        }
    }

    private func removeEscape() {
        if let escMonitor { NSEvent.removeMonitor(escMonitor) }
        escMonitor = nil
    }

    // MARK: - List

    /// A narrow window (the top bar instead of the sidebar): the title alone (board N1).
    private var narrow: Bool { windowWidth < chrome.collapseBelow }

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
            // The list and the drop area scroll together: the area takes what the list leaves of
            // the page, at least 140 pt; with a long list it waits at the end (boards C2-V1, V4).
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VideoList()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
                    VideoDropArea(targeted: dropTargeted)
                        .frame(height: max(140, viewport - listHeight - 12 - 16))
                        .padding(.top, 12)
                }
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, minHeight: viewport, alignment: .topLeading)
                // A click on the empty space deselects (design note 58); the rows take their own clicks first.
                .contentShape(Rectangle())
                .onTapGesture { model.selection = [] }
            }
            .scrollClipDisabled()
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewport = $0 }
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
            if !model.batch.running, !model.selection.isEmpty {
                selectionBar
            } else if model.batch.running {
                Text(runningText).svFont(13, .semibold).foregroundStyle(SV.text).fixedSize()
                if !ready.isEmpty {
                    StatusChip(model.tn("app.process.bar.next_batch", ready.count))
                }
                Spacer(minLength: 8)
                Button { model.stopAll() } label: { Label(model.t("app.common.stop_all"), systemImage: "stop.fill") }
                    .svButton(.destructive, .regular)
                    .help(model.t("app.process.bar.stop_all_help"))
            } else {
                if !finished.isEmpty {
                    Text(outcomeText(finished, ready: ready.count)).svFont(13, .semibold).foregroundStyle(SV.text).fixedSize()
                } else {
                    Text(model.tn("app.process.bar.ready", ready.count, ["t": model.durationText(model.totalDuration)]))
                        .svFont(13, .semibold).foregroundStyle(SV.text).fixedSize()
                    if !narrow {
                        OutputsNote(text: model.t("app.process.bar.outputs"))
                            .layoutPriority(1)
                    }
                }
                Spacer(minLength: 8)
                if !finished.isEmpty {
                    Button(model.t("app.process.bar.clear_done")) { model.clearFinished() }.svButton(.secondary, .regular)
                }
                Button { model.startBatch() } label: { Label(model.t("app.process.bar.start"), systemImage: "play.fill") }
                    .svButton(.primary, .regular)
                    .disabled(!model.canStart)
                    .help(model.t("app.process.bar.start_help"))
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(SV.bg)
        .overlay(alignment: .top) { Rectangle().fill(SV.line).frame(height: 1) }
    }

    /// A selection (design note 58, board C2-V2): what to do with it, in place of the count;
    /// how to leave it on the right, before Start.
    @ViewBuilder private var selectionBar: some View {
        Text(model.tn("app.process.bar.selected", model.selection.count)).svFont(13, .semibold).foregroundStyle(SV.text).fixedSize()
        Button { model.showInFinder(model.selection) } label: {
            Label(model.t("app.common.show_in_finder"), systemImage: "macwindow")
        }
        .svButton(.secondary, .small)
        .help(model.t("app.process.bar.show_in_finder_help"))
        Button { model.removeSelection() } label: { Label(model.t("app.process.bar.remove"), systemImage: "minus") }
            .svButton(.secondary, .small)
            .disabled(!model.canRemoveSelection)
            .help(model.t("app.process.bar.remove_help"))
        Spacer(minLength: 8)
        if !narrow {
            Text(model.t("app.process.bar.deselect_hint")).svSmall(SV.text3).lineLimit(1)
        }
        Button { model.startBatch() } label: { Label(model.t("app.process.bar.start"), systemImage: "play.fill") }
            .svButton(.primary, .regular)
            .disabled(!model.canStart)
            .help(model.t("app.process.bar.start_help"))
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

/// "SRT, report and log next to each video. If the SRT is already there…": all the room between
/// the count and Start; when it must wrap, each sentence on its own line, never half of the
/// second one on the first (design note 61).
struct OutputsNote: View {
    var text: String

    private var sentences: [String] {
        guard let r = text.range(of: ". ") else { return [text] }
        return [String(text[..<r.lowerBound]) + ".", String(text[r.upperBound...])]
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(text).svSmall().lineLimit(1).fixedSize()
            VStack(alignment: .leading, spacing: 1) {
                ForEach(sentences, id: \.self) { sentence in
                    Text(sentence).svSmall().fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Under the list, the drop area of E0 (design note 60): drop videos or folders, or
/// Choose Videos… (⌘O), which adds them at the end. During a batch it stays: what
/// is added goes to the next batch (board C2-V3).
struct VideoDropArea: View {
    @Environment(AppModel.self) private var model
    var targeted: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "film").svFont(34, .light).foregroundStyle(targeted ? SV.primaryText : SV.text3)
                .frame(height: 40)
            Text(model.t("app.process.list.drop_more")).svFont(14, .semibold).foregroundStyle(targeted ? SV.primaryText : SV.text)
            HStack(spacing: 8) {
                Text(model.t("app.process.empty.or_open")).svFont(13).foregroundStyle(SV.text2)
                Button { model.openVideos() } label: { Label(model.t("app.process.list.choose"), systemImage: "folder") }
                    .svButton(.secondary, .regular)
                    .help(model.t("app.process.list.choose_help"))
            }
            if model.batch.running {
                Text(model.t("app.process.list.next_batch")).svFont(11).foregroundStyle(SV.text3)
            } else {
                Text(model.t("app.process.list.formats")).svFont(11, mono: true).foregroundStyle(SV.text3)
            }
        }
        .multilineTextAlignment(.center)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .svDropFrame(targeted: targeted)
    }
}

/// The list of videos: a header row and one row per video in a surface box.
struct VideoList: View {
    @Environment(AppModel.self) private var model
    /// The list's own width: the size column needs room (design note 59 and the C2 boards).
    @State private var width: CGFloat = 0

    /// From this width of the list on, the size column shows; under it the size goes next to the folder.
    static let sizeColumnFrom: CGFloat = 760

    /// No row has a state yet (a new list): no circle column, the names start at the left (design note 63).
    private var showsStatus: Bool { model.videos.contains { $0.circle != nil } }

    /// Column widths of the boards (`.c-nost`, `.c-st`, `.c-stdim`): duration, fps, size, actions.
    var widths: VideoRow.Widths {
        if width >= Self.sizeColumnFrom { return .init(duration: 74, fps: 62, size: 96, actions: 150) }
        return .init(duration: 66, fps: 62, size: nil, actions: showsStatus ? 136 : 116)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ForEach(model.videos) { video in
                Rectangle().fill(SV.line).frame(height: 1)
                VideoRow(video: video, widths: widths, showsStatus: showsStatus)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .background(RoundedRectangle(cornerRadius: SV.Radius.card).fill(SV.surface))
        .overlay(RoundedRectangle(cornerRadius: SV.Radius.card).strokeBorder(SV.line))
        .clipShape(RoundedRectangle(cornerRadius: SV.Radius.card))
    }

    private var header: some View {
        HStack(spacing: 14) {
            if showsStatus { Color.clear.frame(width: StatusCircle.size) }
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
