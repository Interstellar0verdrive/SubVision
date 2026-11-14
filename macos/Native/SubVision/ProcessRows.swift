// SPDX-License-Identifier: MIT
// The rows of the Video list (design round C3, boards C3-02–C3-05, E1–E9,
// N1, DS3). No selection: on the left a checkbox, "process it", where the
// batch's circles show later (waiting, running, done, no subtitles, failed,
// stopped); the name, the folder and a line of state; the numbers; one action
// as a primary button (Preview, Review, Retry, or Stop on the running row);
// the ⋯ menu, the same as the context menu; and the chevron. A click anywhere
// outside the buttons opens the row's drawer: what is known of a video to do,
// the steps of the running one, the times, result and files of a finished one,
// where and why a failed one stopped. One border per row: the state's bar on
// the left, a thin ring on the other sides when the keyboard's focus is there.

import AppKit
import SVShell
import SwiftUI

/// The blue of the signs band on the frame and in the step headers (design note 4).
let signsBlue = Color(dark: "#4F8EF7", light: "#2F6FD6")

extension VideoItem {
    /// The row's outcome circle (22 pt, C3-04): a dashed ring while it waits in the batch,
    /// the spinner, then the outcome, which stays after the batch. None for a video to do
    /// (its checkbox is there).
    var circle: StatusCircle.State? {
        switch state {
        case .unreadable: return .failed
        case .running: return .running
        case .done: return .done
        case .noSubs: return .warning
        case .failed: return .failed
        case .stopped: return .stopped
        case .waiting: return exists ? .waiting : .warning
        case .ready: return exists ? nil : .warning
        }
    }
}

/// The columns of the list (`.c3l` of C3-02; `.c3n1`, Duration only, in a narrow window, N1).
struct ListColumns: Equatable {
    var narrow: Bool

    var gap: CGFloat { narrow ? 10 : 12 }
    // «DURATION» in English needs 60 pt at the header's size (it was cut to «DURATI…»).
    var duration: CGFloat { narrow ? 56 : 60 }
    var fps: CGFloat? { narrow ? nil : 48 }
    var size: CGFloat? { narrow ? nil : 78 }
    var actions: CGFloat { narrow ? 96 : 104 }
    static let lead: CGFloat = 22
    static let more: CGFloat = 22
    static let chevron: CGFloat = 16
    /// The bar and the padding before the checkbox column.
    static let leading: CGFloat = 16
    static let trailing: CGFloat = 16
    /// Where the name starts, and the drawers with it.
    var textInset: CGFloat { Self.leading + Self.lead + gap }
}

/// One video of the list (C3-02).
struct VideoRow: View {
    @Environment(AppModel.self) private var model
    var video: VideoItem
    var columns: ListColumns
    @State private var hover = false

    private var open: Bool { model.run.expanded.contains(video.id) }
    private var focused: Bool { model.focusedRow == video.id }
    private var unreadable: Bool { video.state == .unreadable }
    private var missing: Bool { !video.exists }
    /// Retry queued it during the batch (C3-05): it starts when the batch ends.
    private var queued: Bool { model.retryQueued(video.id) }
    /// A batch runs and this row is not in it (C3-04): dimmed, its box can't change.
    /// A row Retry queued is not dimmed: it is the next to go.
    private var outOfBatch: Bool { model.batch.running && !model.run.ids.contains(video.id) && !queued }
    private var dim: Double { unreadable || (missing && !video.state.isFinished) ? 0.55 : outOfBatch ? 0.6 : 1 }

    /// The bar on the left: the state's colour, solid (C3-02, one border per row).
    private var edge: Color {
        if unreadable { return SV.red }
        if queued { return SV.primary }
        switch video.state {
        case .running: return SV.primary
        case .done: return video.willRedo ? SV.primary : SV.green
        case .noSubs: return video.willRedo ? SV.primary : SV.yellow
        case .failed: return video.willRedo ? SV.primary : SV.red
        case .stopped: return video.willRedo ? SV.primary : SV.stopped
        case .ready:
            if missing { return SV.yellow }
            return video.isChecked ? SV.primary : SV.track
        default: return SV.track
        }
    }

    private var background: Color {
        if video.state == .running { return SV.soft }
        if hover { return SV.hoverVeil }
        return open ? SV.openVeil : .clear
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The row's head takes the click; inside the drawer a click does nothing (text, buttons).
            head
                .contentShape(Rectangle())
                .onTapGesture { click() }
                // Opaque, above the drawer: while the drawer slides in or out it passes under the
                // head and must not show through it (the owner's note).
                .background { ZStack { SV.surface; background } }
                .zIndex(1)
            if open {
                VideoDrawer(video: video, columns: columns)
                    .padding(.leading, columns.textInset)
                    .padding(.trailing, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 14)
                    .overlay(alignment: .top) {
                        Rectangle().fill(SV.detailLine).frame(height: 1).padding(.leading, columns.textInset)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipped()
        .background(background)
        // 3 pt inside the list's 1 pt border, which is drawn over the rows (as on the boards).
        .overlay(alignment: .leading) { Rectangle().fill(edge).frame(width: 3).padding(.leading, 1) }
        // The keyboard's ring in a neutral grey: only the thick left bar is coloured (the owner's note).
        .overlay { if focused && model.focusRingVisible { FocusRing().stroke(SV.rowFocus, lineWidth: 1).allowsHitTesting(false) } }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .contextMenu { RowMenuButtons(video: video) }
        .help(video.path)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(focused ? .isSelected : [])
        // The drawer opens with a click on the row; VoiceOver gets it as the row's action.
        .accessibilityAction(named: model.t(open ? "app.process.row.close_drawer" : "app.process.row.open_drawer")) {
            withAnimation(.easeOut(duration: 0.2)) { model.toggleDrawer(video.id) }
        }
    }

    private var head: some View {
        HStack(alignment: .center, spacing: columns.gap) {
            RowLead(video: video)
            VStack(alignment: .leading, spacing: 3) {
                // The chips on the middle of the name's capitals.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(video.name).svFont(12.5, .medium).foregroundStyle(SV.text).lineLimit(2).truncationMode(.middle)
                    chips.svOnCapsMiddle(12.5)
                }
                Text(video.folder).svFont(11, mono: true).foregroundStyle(SV.text3).lineLimit(1).truncationMode(.middle)
                RowStatusLine(video: video, outOfBatch: outOfBatch)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(dim)
            Group {
                number(video.duration.map(Localizer.clock)).frame(width: columns.duration, alignment: .trailing)
                if let fps = columns.fps {
                    number(video.fps.map(model.previewFPSText)).frame(width: fps, alignment: .trailing)
                }
                if let size = columns.size {
                    number(video.size).frame(width: size, alignment: .trailing)
                }
            }
            .opacity(dim)
            RowAction(video: video)
                .frame(width: columns.actions, alignment: .trailing)
            RowMoreButton(video: video)
                .frame(width: ListColumns.more)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                // The symbol's ink sits 0.75 pt right of its box: turned down (an open drawer)
                // it fell a point under the row's buttons (measured at 2x).
                .offset(x: -0.75)
                .frame(width: 18, height: 18)
                .foregroundStyle(SV.text3)
                .rotationEffect(.degrees(open ? 90 : 0))
                .frame(width: ListColumns.chevron)
                .accessibilityHidden(true)
        }
        .padding(.leading, ListColumns.leading)
        .padding(.trailing, ListColumns.trailing)
        .padding(.vertical, 8)
        .frame(minHeight: 52)
    }

    @ViewBuilder private var chips: some View {
        if video.willRedo {
            StatusChip(model.t("app.process.row.redo_chip"), tone: .accent)
                .help(model.t("app.process.row.redo_chip_help"))
        } else if video.state == .ready, video.srtExists {
            // A warning, not an error: the new SRT gets the date in its name (C3-03).
            StatusChip(model.t("app.process.row.srt_exists"), tone: .yellow)
                .help(model.t("app.process.row.srt_exists_help"))
        }
    }

    /// Numbers in mono, "—" where the probe has nothing (unreadable), "…" until it answers.
    private func number(_ text: String?) -> some View {
        Text(text ?? (video.probed ? "—" : "…")).svFont(SVFont.numbers).foregroundStyle(SV.textCode).lineLimit(1)
    }

    /// A click anywhere outside the buttons opens or closes the drawer, and the focus comes
    /// here. The second click of a double click does nothing more: a double click opens too.
    private func click() {
        model.focusedRow = video.id
        model.focusRingVisible = false
        guard (NSApp.currentEvent?.clickCount ?? 1) < 2 else { return }
        withAnimation(.easeOut(duration: 0.2)) { model.toggleDrawer(video.id) }
    }
}

extension SV {
    /// An open row, a touch lighter than the list (`.fr.open`).
    static let openVeil = Color(dark: "rgba(255,255,255,.025)", light: "rgba(0,0,0,.015)")
}

/// The focus ring of a row (C3-02): a thin line on the top, right and bottom sides;
/// the left one is the row's bar.
struct FocusRing: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = rect.insetBy(dx: 0.5, dy: 0.5)
        p.move(to: CGPoint(x: rect.minX + 3, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: rect.minX + 3, y: r.maxY))
        return p
    }
}

// MARK: - The left column

/// The 22 pt column on the left (C3-02, C3-04): the checkbox of a video to do; the outcome
/// of a finished one, which turns into an empty box under the pointer (a click checks it:
/// "will be redone"); the batch's circles while it runs, which no click changes.
struct RowLead: View {
    @Environment(AppModel.self) private var model
    var video: VideoItem
    @State private var hover = false

    private var batchRunning: Bool { model.batch.running }

    var body: some View {
        ZStack {
            content
                .transition(.opacity)
        }
        .frame(width: ListColumns.lead, height: ListColumns.lead)
        .animation(.easeInOut(duration: 0.15), value: batchRunning)
        .animation(.easeInOut(duration: 0.15), value: video.state)
    }

    @ViewBuilder private var content: some View {
        switch video.checkKind {
        case .excluded:
            if let circle = video.circle { StatusCircle(circle) } else { Color.clear }
        case .todo:
            SVCheckbox(isOn: video.isChecked, help: model.t("app.process.row.check_help")) { model.toggleCheck(video.id) }
                .accessibilityLabel("\(model.t("app.process.row.check_help")): \(video.name)")
                .disabled(batchRunning)
                .id("box")
        case .finished:
            if video.isChecked {
                SVCheckbox(isOn: true, help: model.t("app.process.row.check_help")) { model.toggleCheck(video.id) }
                    .accessibilityLabel("\(model.t("app.process.row.check_help")): \(video.name)")
                    .disabled(batchRunning)
                    .id("box")
            } else if batchRunning {
                // A row Retry queued waits as the batch's rows wait: the dashed ring (C3-05).
                (model.retryQueued(video.id) ? .waiting : video.circle).map { StatusCircle($0) }
            } else {
                // The outcome; under the pointer the empty box that brings it back to the batch.
                Button { model.toggleCheck(video.id) } label: {
                    ZStack {
                        if hover {
                            CheckboxMark(state: .off, hover: true)
                        } else if let circle = video.circle {
                            StatusCircle(circle)
                        }
                    }
                    .frame(width: ListColumns.lead, height: ListColumns.lead)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hover = $0 }
                .help(model.t("app.process.row.redo_help"))
                .accessibilityLabel("\(model.t("app.process.row.redo_help")): \(video.name)")
            }
        }
    }
}

// MARK: - The line of state

/// The third line of a row (C3-02–C3-05, E3, E5, E7, E9).
struct RowStatusLine: View {
    @Environment(AppModel.self) private var model
    var video: VideoItem
    var outOfBatch: Bool

    var body: some View {
        if video.state == .unreadable {
            line(model.t("app.process.row.unreadable"), SV.redText).help(video.problem ?? "")
        } else if model.retryQueued(video.id) {
            line(model.t("app.process.row.retry_queued"), SV.text2)
        } else if !video.exists, !video.state.isFinished {
            line(model.t("app.process.row.not_found"), SV.yellowText).help(model.t("app.process.row.file_missing_help"))
        } else {
            switch video.state {
            case .waiting:
                line(waitingText, SV.text2)
            case .running:
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    line(runningText(at: context.date), SV.text2)
                }
            case .ready:
                line(readyText, SV.text2)
            case .done:
                line(outOfBatchPrefix(doneText), SV.text2)
            case .noSubs:
                line(outOfBatchPrefix(model.t("app.process.row.no_subs")), SV.yellowText)
            case .failed:
                line(outOfBatchPrefix(model.rowFailedText(video)), SV.redText).help(video.errorDetail ?? "")
            case .stopped:
                line(outOfBatchPrefix(model.rowStoppedText(video)), SV.stopped)
            case .unreadable:
                EmptyView()
            }
        }
    }

    private func line(_ text: String, _ color: Color) -> some View {
        Text(text).svFont(11.5).foregroundStyle(color).lineLimit(2)
    }

    private func outOfBatchPrefix(_ text: String) -> String {
        outOfBatch ? model.join([model.t("app.process.row.not_in_batch"), text]) : text
    }

    /// "Da elaborare · circa 01:16", "Non spuntato: resta fuori dal lotto", "Da elaborare · nel prossimo lotto".
    private var readyText: String {
        let todo = model.t("app.process.row.todo")
        if model.batch.running {
            return video.isChecked ? model.join([todo, model.t("app.process.row.next_batch")]) : model.t("app.process.row.not_in_batch")
        }
        guard video.isChecked else { return model.t("app.process.row.unchecked") }
        if model.run.readyAgain.contains(video.id) { return model.join([todo, model.t("app.process.row.not_started")]) }
        guard let estimate = model.estimate(video) else { return todo }
        return model.join([todo, model.t("app.process.row.about", ["t": Localizer.clock(estimate)])])
    }

    private var waitingText: String {
        if let estimate = model.waitingEstimate(video) {
            return model.t("app.process.row.waiting_est", ["t": Localizer.clock(estimate)])
        }
        return model.t("app.process.row.waiting")
    }

    /// "trascorso 00:27 · finisce verso le 08:44" (C3-04).
    private func runningText(at date: Date) -> String {
        let elapsed = Localizer.clock(model.run.fileStarted.map { date.timeIntervalSince($0) } ?? 0)
        if let ends = model.runningFileEnds(at: date) {
            return model.t("app.process.row.ends", ["t": elapsed, "time": AppModel.clockTime(ends)])
        }
        return model.t("app.process.row.elapsed", ["t": elapsed])
    }

    /// "12 righe · 5 confini raffinati · elaborato in 01:04 · 3 buchi"; out of a running batch,
    /// when rather than how long ("14 righe · elaborato ieri alle 22:10", C3-04).
    private var doneText: String {
        var parts = [model.tn("app.process.row.lines", video.segments ?? 0)]
        if outOfBatch {
            if let finished = video.finished {
                parts.append(model.t("app.process.row.finished_when", ["when": model.whenText(finished)]))
            }
            return model.join(parts)
        }
        if let dropped = video.dropped, dropped > 0 { parts.append(model.tn("app.process.row.dropped", dropped)) }
        if let refined = video.refined, refined > 0 { parts.append(model.tn("app.process.row.refined", refined)) }
        if let elapsed = video.elapsed { parts.append(model.t("app.process.finished.took_file", ["t": Localizer.clock(elapsed)])) }
        if let gaps = video.gaps, !gaps.isEmpty { parts.append(model.tn("app.process.row.gaps", gaps.count)) }
        return model.join(parts)
    }
}

extension AppModel {
    /// "l'estrazione dei fotogrammi", "la lettura OCR": a step inside a sentence.
    func stepPhrase(_ id: String?) -> String {
        guard let key = id?.split(separator: ":").first.map(String.init) else { return "—" }
        return localizer.has("app.process.step_in.\(key)") ? t("app.process.step_in.\(key)") : stepName(key)
    }

    func bandPhrase(_ id: String?) -> String {
        guard let id, let band = id.split(separator: ":").dropFirst().first else { return "" }
        return bandName(String(band), lower: true)
    }

    /// "Non riuscito durante la lettura OCR · dialoghi: Vision non ha risposto" (C3-05): the step,
    /// then the sentence of a known code or the engine's short text (`failureText`).
    func rowFailedText(_ video: VideoItem) -> String {
        let error = failureText(video)
        guard video.atStep != nil else { return t("app.process.row.failed_plain", ["error": error]) }
        let text = t("app.process.row.failed", ["step": stepPhrase(video.atStep), "band": bandPhrase(video.atStep), "error": error])
        // A sentence of the catalogue ends with its own full stop; a bare text does not get one.
        return text.hasSuffix(": ") ? String(text.dropLast(2)) : text
    }

    /// "Fermato durante la lettura OCR · dialoghi, dopo 41:12. Nessun SRT a metà" (E5).
    func rowStoppedText(_ video: VideoItem) -> String {
        let values: [String: Any] = ["step": stepPhrase(video.atStep), "band": bandPhrase(video.atStep)]
        let spent = video.times?.values.reduce(0, +) ?? 0
        guard spent >= 1 else { return t("app.process.row.stopped", values) }
        return t("app.process.row.stopped_after", values.merging(["t": Localizer.clock(spent)]) { a, _ in a })
    }

    /// "oggi alle 22:10", "ieri alle 22:10", "il 12/11 alle 22:10".
    func whenText(_ date: Date) -> String {
        let time = Self.clockTime(date)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return t("app.process.row.when_today", ["time": time]) }
        if calendar.isDateInYesterday(date) { return t("app.process.row.when_yesterday", ["time": time]) }
        let f = DateFormatter()
        f.locale = Locale(identifier: language)
        f.setLocalizedDateFormatFromTemplate("dM")
        return t("app.process.row.when_date", ["date": f.string(from: date), "time": time])
    }
}

// MARK: - The action, ⋯ and the context menu

/// One action per row, as a primary button (C3-02, C3-05): Preview for a video to do (and for
/// one without subtitles, whose bands are to be checked, E3), Review for a done one, Retry for
/// a failed or stopped one; Stop stays the stop button of the running row.
struct RowAction: View {
    @Environment(AppModel.self) private var model
    var video: VideoItem

    var body: some View {
        switch video.state {
        case .ready, .noSubs:
            Button { model.openInPreview(video.id) } label: { Label(model.t("app.process.row.preview"), systemImage: "viewfinder") }
                .svButton(.primary, .small)
                .disabled(!model.canPreview(video))
                .help(model.t("app.process.row.preview_help"))
        case .running:
            Button { model.stopCurrentFile() } label: { Label(model.t("app.common.stop"), systemImage: "stop.fill") }
                .svButton(.secondary, .small)
                .help(model.t("app.process.row.stop_help"))
        case .done:
            Button { model.review(video) } label: { Label(model.t("app.process.row.review"), systemImage: "doc.text.magnifyingglass") }
                .svButton(.primary, .small)
                .disabled(video.outputReport == nil)
                .help(model.t(video.outputReport == nil ? "app.process.row.review_none" : "app.process.row.review_help"))
        case .failed, .stopped:
            let now = VideoChecks.retry(batchRunning: model.batch.running) == .startNow
            let queued = model.retryQueued(video.id)
            Button { model.retry(video.id) } label: { Label(model.t("app.process.row.retry"), systemImage: "arrow.clockwise") }
                .svButton(.primary, .small)
                .disabled(!video.exists || video.willRedo || queued || (now && !model.canRun))
                .help(model.t(queued ? "app.process.row.retry_queued_help" : now ? "app.process.row.retry_help" : "app.process.row.retry_queue_help"))
        case .waiting, .unreadable:
            // The column keeps its width: the numbers stay in line with the other rows.
            Color.clear.frame(height: 1)
        }
    }
}

extension AppModel {
    /// The items of a row's ⋯ and context menus, in the same order (C3-05): Preview ⌘Y · Review ⌘R ·
    /// — · Process Again · — · Show in Finder · Open Log · — · Remove from List ⌫. What does not
    /// apply is there, off.
    func rowMenu(_ video: VideoItem) -> [SVMenuItem] {
        let id = video.id
        return [
            .item(t("app.process.row.preview"), enabled: canPreview(video), key: "y") { [self] in openInPreview(id) },
            .item(t("app.process.row.review"), enabled: video.outputReport != nil, key: "r") { [self] in
                if let v = videos.first(where: { $0.id == id }) { review(v) }
            },
            .separator,
            .item(t("app.process.row.process_again"), checked: video.willRedo,
                  enabled: video.checkKind == .finished && !video.willRedo && !batch.running) { [self] in processAgain([id]) },
            .separator,
            .item(t("app.common.show_in_finder"), enabled: video.exists) { [self] in showInFinder([id]) },
            .item(t("app.process.row.open_log"), enabled: video.logExists) { [self] in
                if let v = videos.first(where: { $0.id == id }) { openLog(v) }
            },
            .separator,
            .item(t("app.process.row.remove"), enabled: !video.state.inBatch, key: "\u{8}", modifiers: []) { [self] in removeWithUndo([id]) },
        ]
    }
}

/// ⋯, always there (C3-02, C3-05).
struct RowMoreButton: View {
    @Environment(AppModel.self) private var model
    var video: VideoItem

    var body: some View {
        PopupMenu({ model.rowMenu(video) }, openRequest: model.rowMenuRequest?.id == video.id ? model.rowMenuRequest?.count ?? 0 : 0) {
            Image(systemName: "ellipsis").svFont(13, .semibold).foregroundStyle(SV.text2)
                .frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .help(model.t("app.process.row.more"))
        .accessibilityLabel(model.t("app.process.row.more"))
    }
}

/// The context menu: the ⋯ menu's items as buttons, with their shortcuts shown.
struct RowMenuButtons: View {
    @Environment(AppModel.self) private var model
    var video: VideoItem

    var body: some View {
        let id = video.id
        Button(model.t("app.process.row.preview")) { model.openInPreview(id) }
            .keyboardShortcut("y", modifiers: .command)
            .disabled(!model.canPreview(video))
        Button(model.t("app.process.row.review")) { model.review(video) }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(video.outputReport == nil)
        Divider()
        Button(model.t("app.process.row.process_again")) { model.processAgain([id]) }
            .disabled(video.checkKind != .finished || video.willRedo || model.batch.running)
        Divider()
        Button(model.t("app.common.show_in_finder")) { model.showInFinder([id]) }.disabled(!video.exists)
        Button(model.t("app.process.row.open_log")) { model.openLog(video) }.disabled(!video.logExists)
        Divider()
        Button(model.t("app.process.row.remove")) { model.removeWithUndo([id]) }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(video.state.inBatch)
    }
}
