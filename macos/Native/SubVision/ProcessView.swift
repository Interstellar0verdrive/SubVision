// SPDX-License-Identifier: MIT
// Video, the home (design boards E0–E10, C3-02–C3-05, N1, N2): the header,
// the notes, the list of videos with its header checkbox (rows and drawers
// in `ProcessRows.swift` and `ProcessDrawers.swift`), the drop strip under
// it, the bottom bar that says what Process will do (during a batch it gives
// way to the window's batch bar, C3-04) and the parameters panel fixed on the
// right (C3-03: it retracts only in a narrow window). No selection: the
// keyboard moves a focus ring over the rows (↑ ↓, Space → ← open and close,
// ⌫ removes, Esc lets go).

import AppKit
import SVShell
import SwiftUI

struct ProcessView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.svPageTop) private var top
    @Environment(\.svChrome) private var chrome
    @Environment(\.svWindowWidth) private var windowWidth
    @State private var dropTargeted = false
    @State private var keyMonitor: Any?

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
                // No panel button here: the panel is fixed beside a wide page, and a narrow
                // window has its button in the top bar (board N1).
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
            // During the batch the window's batch bar takes its place (C3-04).
            if !model.videos.isEmpty, !model.batch.running {
                bottomBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { Color.clear.contentShape(Rectangle()).onTapGesture { model.focusedRow = nil } }
        .onAppear { installKeys() }
        .onDisappear { removeKeys() }
        .fileDrop(isTargeted: $dropTargeted) { model.add($0) }
    }

    // MARK: - Keys

    /// The list's keys (C3-02), when the main window is in front with nothing over it and no
    /// text is being edited: ↑ ↓ move the focus, Space opens or closes the focused row's drawer,
    /// → opens it, ← closes it, ⌫ ⌦ remove the row (⌘Z puts it back), Esc lets the focus go.
    /// ⌫ is here as well as in the File menu: the menu item's ⌫ is U+0008 and the Delete key
    /// types U+007F, which that key equivalent does not match (manual tests, 14/11).
    private func installKeys() {
        guard keyMonitor == nil else { return }
        let chrome = chrome
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [model] event in
            let code = event.keyCode
            guard [126, 125, 49, 124, 123, 51, 117, 53].contains(code),
                  event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
                  model.tab == .process, !model.preview.shown, !model.videos.isEmpty,
                  let window = event.window, window.isMainWindow, window.attachedSheet == nil,
                  !(window.firstResponder is NSText) else { return event }
            // The parameters laid over a narrow window keep their own keys.
            if model.inspectorOpen && chrome.inspectorOverlays(windowWidth: window.frame.width) { return event }
            switch code {
            case 126: model.moveFocus(by: -1)
            case 125: model.moveFocus(by: 1)
            case 53:
                guard model.focusedRow != nil else { return event }
                model.focusedRow = nil
            default:
                guard let id = model.focusedRow else { return event }
                switch code {
                case 49: withAnimation(.easeOut(duration: 0.2)) { model.toggleDrawer(id) }
                case 124: withAnimation(.easeOut(duration: 0.2)) { model.setDrawer(id, open: true) }
                case 123: withAnimation(.easeOut(duration: 0.2)) { model.setDrawer(id, open: false) }
                default:
                    guard model.canRemoveFocused else { return event }
                    model.removeFocused()
                }
            }
            return nil
        }
    }

    private func removeKeys() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    // MARK: - List

    /// A narrow window (the parameters retracted): the title alone, Duration the only number (N1).
    private var narrow: Bool { chrome.inspectorOverlays(windowWidth: windowWidth) }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.hello?.vision == false {
                NoteView(.red, title: model.t("app.process.note.vision_title"), text: model.t("app.process.note.vision_text")) {
                    Button(model.t("app.common.retry")) { model.retry() }.buttonStyle(SVTintedButtonStyle(.red))
                    Button(model.t("app.common.show_log")) { model.showLog() }.buttonStyle(SVTintedButtonStyle(.red))
                }
                .padding(.bottom, 12)
            }
            if !model.skippedItems.isEmpty {
                NoteView(.yellow, title: model.tn("app.process.note.skipped", model.skippedItems.count),
                         text: model.skippedItems.joined(separator: ", "), inlineTitle: true) {
                    Button { model.skippedItems = [] } label: {
                        Image(systemName: "xmark").svFont(11, .semibold).frame(width: 22, height: 22).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(model.t("app.common.dismiss"))
                }
                .padding(.bottom, 12)
            }
            if let stopped = model.run.stoppedAt, !model.batch.running {
                // E5: a neutral note, what became of the rows.
                NoteView(.neutral, title: model.t("app.process.note.stopped_title", ["time": AppModel.clockTime(stopped)]),
                         text: stoppedText, inlineTitle: true) { EmptyView() }
                    .padding(.bottom, 12)
            }
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        VideoList(narrow: narrow)
                        VideoDropStrip(targeted: dropTargeted, narrow: narrow)
                            .padding(.top, 12)
                    }
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollClipDisabled()
                .onChange(of: model.focusedRow) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.15)) { scroller.scrollTo(id) }
                }
            }
            if let note = diskNote {
                NoteView(.yellow, text: note)
                    .padding(.bottom, 14)
            }
        }
    }

    private var stoppedText: String {
        let notStarted = model.videos.filter { model.run.readyAgain.contains($0.id) && $0.state == .ready }.count
        return notStarted == 0 ? model.t("app.process.note.stopped_none") : model.tn("app.process.note.stopped_text", notStarted)
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

    /// What Process will do (C3-02, C3-03, C3-05, E3, E5): "2 da elaborare · circa 3 min" and
    /// "Elabora 2 video"; with nothing checked the outcomes and Remove Finished, the button off
    /// as "Nessun video da elaborare". Not during a batch: the window's batch bar is there (C3-04).
    private var bottomBar: some View {
        HStack(alignment: .center, spacing: 14) {
            switch model.bottomSummary {
            case .toProcess(let count, let seconds):
                Text(model.join([model.tn("app.process.bar.to_process", count)]
                                + (seconds.map { [model.t("app.process.row.about", ["t": model.durationText($0)])] } ?? [])))
                    .svFont(12.5, .semibold).foregroundStyle(SV.text).fixedSize()
                if !narrow {
                    let retry = model.videos.contains { $0.state == .stopped && !$0.willRedo }
                    Text(model.t(retry ? "app.process.bar.retry_note" : "app.process.bar.outputs"))
                        .svFont(12).foregroundStyle(SV.text2).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer(minLength: 8)
                }
            case .outcomes:
                Text(model.outcomeText).svFont(12.5, .semibold).foregroundStyle(SV.text).lineLimit(1)
                Spacer(minLength: 8)
                Button(model.t("app.process.bar.clear_done")) { model.clearFinished() }.svButton(.secondary, .regular)
            case .nothingChecked:
                Text(model.t("app.process.bar.none_checked")).svFont(12.5, .semibold).foregroundStyle(SV.text).fixedSize()
                Spacer(minLength: 8)
            }
            let count = model.checkedVideos.count
            Button { model.startBatch() } label: {
                Label(VideoChecks.startButton(checked: count) == .nothing ? model.t("app.process.bar.nothing")
                      : model.tn("app.process.bar.process", count), systemImage: "play.fill")
            }
            .svButton(.primary, .regular)
            .disabled(!model.canStart)
            .help(model.t(count > 0 ? "app.process.bar.process_help" : "app.process.bar.nothing_help"))
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(SV.bg)
        .overlay(alignment: .top) { Rectangle().fill(SV.line).frame(height: 1) }
    }
}

extension AppModel {
    /// The left of the bottom bar (`VideoChecks.summary`).
    var bottomSummary: VideoChecks.Summary {
        let finished = finishedVideos
        return VideoChecks.summary(checked: checkedVideos.count, seconds: checkedEstimate,
                                   done: finished.filter { $0.state == .done }.count,
                                   noSubs: finished.filter { $0.state == .noSubs }.count,
                                   failed: finished.filter { $0.state == .failed }.count,
                                   stopped: finished.filter { $0.state == .stopped }.count)
    }

    /// "1 fatto · 1 senza sottotitoli · 1 non riuscito · 1 fermato" (E3).
    var outcomeText: String {
        guard case let .outcomes(done, noSubs, failed, stopped) = bottomSummary else { return "" }
        var parts: [String] = []
        if done > 0 { parts.append(tn("app.process.bar.done", done)) }
        if noSubs > 0 { parts.append(tn("app.process.bar.no_subs", noSubs)) }
        if failed > 0 { parts.append(tn("app.process.bar.failed", failed)) }
        if stopped > 0 { parts.append(tn("app.process.bar.stopped_count", stopped)) }
        return join(parts)
    }

    /// The bottom bar's button as it reads ("Elabora 2 video", "Nessun video da elaborare").
    var startButtonTitle: String {
        switch VideoChecks.startButton(checked: checkedVideos.count) {
        case .process(let n): tn("app.process.bar.process", n)
        case .nothing: t("app.process.bar.nothing")
        }
    }
}

/// Under the list, the drop strip (`.drop3`, C3-02): drop videos or folders, or Choose Videos…
/// (⌘O), which adds them at the end. During a batch it says they go to the next batch (C3-04).
struct VideoDropStrip: View {
    @Environment(AppModel.self) private var model
    var targeted: Bool
    var narrow: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "film").svFont(13).foregroundStyle(targeted ? SV.primaryText : SV.text2)
            Text(model.t("app.process.list.drop_strip")).svFont(12.5).foregroundStyle(targeted ? SV.primaryText : SV.text2)
                .fixedSize(horizontal: false, vertical: true)
            Button { model.openVideos() } label: { Label(model.t("app.process.list.choose"), systemImage: "folder") }
                .svButton(.secondary, .small)
                .help(model.t("app.process.list.choose_help"))
                .fixedSize()
            Text(model.t(model.batch.running ? "app.process.list.next_batch" : "app.process.list.formats_short"))
                .svFont(11, mono: true).foregroundStyle(SV.text3)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                .opacity(narrow && !model.batch.running ? 0 : 1)
                .frame(maxWidth: narrow && !model.batch.running ? 0 : nil)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 46)
        .svDropFrame(targeted: targeted, cornerRadius: 10)
    }
}

/// The list of videos: a header row with its checkbox and one row per video in a surface box.
struct VideoList: View {
    @Environment(AppModel.self) private var model
    var narrow: Bool
    /// The list's own width: under it the numbers give way to Duration alone (N1).
    @State private var width: CGFloat = 0

    private var columns: ListColumns { ListColumns(narrow: narrow || (width > 0 && width < 640)) }

    var body: some View {
        let columns = columns
        VStack(spacing: 0) {
            header(columns)
            ForEach(model.videos) { video in
                Rectangle().fill(SV.line).frame(height: 1)
                VideoRow(video: video, columns: columns)
                    .id(video.id)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .background(RoundedRectangle(cornerRadius: SV.Radius.card).fill(SV.surface))
        .overlay(RoundedRectangle(cornerRadius: SV.Radius.card).strokeBorder(SV.line))
        .clipShape(RoundedRectangle(cornerRadius: SV.Radius.card))
    }

    private func header(_ c: ListColumns) -> some View {
        HStack(spacing: c.gap) {
            headerBox.frame(width: ListColumns.lead)
            label(model.t("app.process.list.name")).frame(maxWidth: .infinity, alignment: .leading)
            label(model.t("app.process.list.duration")).frame(width: c.duration, alignment: .trailing)
            if let fps = c.fps { label(model.t("app.process.list.fps")).frame(width: fps, alignment: .trailing) }
            if let size = c.size { label(model.t("app.process.list.size")).frame(width: size, alignment: .trailing) }
            Color.clear.frame(width: c.actions + ListColumns.more + ListColumns.chevron + 2 * c.gap)
        }
        .padding(.leading, ListColumns.leading)
        .padding(.trailing, ListColumns.trailing)
        .frame(height: 30)
    }

    /// The header's box (C3-02): over the rows that have a box only; "−" when some are checked.
    @ViewBuilder private var headerBox: some View {
        let rows = model.checkRows
        // During a batch the boxes are the batch's (C3-04): none in the header.
        if VideoChecks.headerEnabled(rows), !model.batch.running {
            let state = VideoChecks.headerState(rows)
            HeaderCheckbox(state, help: model.t(state == .on ? "app.process.list.uncheck_all" : "app.process.list.check_all")) {
                model.toggleHeader()
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased()).svFont(10.5, .semibold).foregroundStyle(SV.text3).tracking(0.3).lineLimit(1)
    }
}
