// SPDX-License-Identifier: MIT
// The rows of the Process list in their seven states (design boards E1–E5,
// DS3): the status ring and edge, name, folder and outcome line, the numbers,
// the actions column (Stop, Open Report, ⋯), and under the row the steps of
// the file in progress (bars per band with count, ETA and rate), the failed
// step with its error, or the times and files of a finished row.

import AppKit
import SVShell
import SwiftUI

/// The blue of the signs band on the frame and in the step headers (design note 4).
let signsBlue = Color(dark: "#4F8EF7", light: "#2F6FD6")

extension VideoItem {
    /// The row's circle (design note 63): none for a ready row, a dashed ring while it
    /// waits in the batch, the spinner, then the outcome, which stays after the batch.
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

/// One video (E1–E5). Click selects, ⌘-click adds, double-click opens a
/// finished row, the context menu and ⌫ act on the selection.
struct VideoRow: View {
    @Environment(AppModel.self) private var model
    /// The widths of the number and action columns (`VideoList.widths`).
    struct Widths: Equatable {
        var duration: CGFloat
        var fps: CGFloat
        var size: CGFloat?
        var actions: CGFloat
    }

    var video: VideoItem
    var widths: Widths
    /// Some row of the list has a state: every row keeps the circle's column (design note 63).
    var showsStatus = true
    @State private var hover = false

    /// Where the text starts: after the circle's column, or at the left edge without it.
    private var textInset: CGFloat { showsStatus ? StatusCircle.size + 14 : 0 }

    private var selected: Bool { model.selection.contains(video.id) }
    private var missing: Bool { !video.exists }
    private var unreadable: Bool { video.state == .unreadable }
    private var dim: Bool { unreadable || (missing && !video.state.isFinished) }
    private var running: Bool { video.state == .running }
    private var expanded: Bool { model.run.expanded.contains(video.id) }

    private var edge: Color {
        if unreadable { return SV.red }
        switch video.state {
        case .running: return SV.primary
        case .done: return SV.green
        case .noSubs: return SV.yellow
        case .failed: return SV.red
        case .stopped: return SV.text3
        default: return missing ? SV.yellow : SV.track
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                if showsStatus {
                    if let circle = video.circle {
                        StatusCircle(circle)
                    } else {
                        Color.clear.frame(width: StatusCircle.size, height: StatusCircle.size)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(video.name).svFont(12.5, .medium).foregroundStyle(SV.text).lineLimit(1).truncationMode(.middle)
                        if video.state == .ready, video.srtExists {
                            StatusChip(model.t("app.process.row.srt_exists"))
                                .help(model.t("app.process.row.srt_exists_help", ["name": renamedSRT]))
                        }
                    }
                    // Without the size column (a narrow list) the resolution follows the folder (`.fline`, design note 59).
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(video.folder).svFont(11, mono: true).foregroundStyle(SV.text3).lineLimit(1).truncationMode(.middle)
                        if widths.size == nil, let size = video.size {
                            Text("· \(size)").svFont(11, mono: true).foregroundStyle(SV.text3).lineLimit(1).fixedSize()
                        }
                    }
                    statusLine
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(dim ? 0.55 : 1)
                Group {
                    number(video.duration.map(Localizer.clock)).frame(width: widths.duration, alignment: .trailing)
                    number(video.fps.map(fpsText)).frame(width: widths.fps, alignment: .trailing)
                    if let size = widths.size {
                        number(video.size).frame(width: size, alignment: .trailing)
                    }
                }
                .opacity(dim ? 0.55 : 1)
                RowActions(video: video)
                    .frame(width: widths.actions, alignment: .trailing)
            }
            .padding(.vertical, 8)
            .frame(minHeight: 52)
            if running || video.state == .failed {
                if running {
                    // A light line between the row's head and its steps, from the text to the right edge (design note 65).
                    Rectangle().fill(SV.detailLine).frame(height: 1)
                        .padding(.leading, textInset)
                        .padding(.trailing, -16)
                        .padding(.top, 2)
                        .padding(.bottom, 8)
                }
                StepsPanel(video: video)
                    .padding(.leading, textInset)
                    .padding(.top, running ? 0 : 4)
                    .padding(.bottom, 12)
            } else if video.state.isFinished, expanded {
                FinishedDetail(video: video)
                    .padding(.leading, textInset)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
            }
        }
        .padding(.leading, 13)
        .padding(.trailing, 16)
        // The selection a step softer than the sidebar's (design note 58, `.fr.selr`).
        .background(selected ? SV.selSoft : running ? SV.soft : hover ? SV.hoverVeil : .clear)
        .overlay(alignment: .leading) { Rectangle().fill(edge).frame(width: 3) }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .gesture(TapGesture(count: 2).onEnded { toggleExpanded() })
        .simultaneousGesture(TapGesture().onEnded { select() })
        .contextMenu { RowMenu(video: video, selected: selected) }
        .help(video.size.map { "\($0) · \(video.path)" } ?? video.path)
    }

    /// The third line: the outcome of the row (E1–E5).
    @ViewBuilder private var statusLine: some View {
        if unreadable {
            Text(model.t("app.process.row.unreadable")).svFont(11.5).foregroundStyle(SV.redText)
                .help(video.problem ?? "")
        } else if missing, !video.state.isFinished {
            Text(model.t("app.process.row.not_found")).svFont(11.5).foregroundStyle(SV.yellowText)
                .help(model.t("app.process.row.file_missing_help"))
        } else {
            switch video.state {
            case .waiting:
                Text(waitingText).svFont(11.5).foregroundStyle(SV.text2)
            case .running:
                // Only the time: the place in the batch is in the sidebar's card and the bottom bar (design note 66).
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(model.t("app.process.row.elapsed", ["t": Localizer.clock(elapsed(at: context.date))]))
                        .svFont(11.5).foregroundStyle(SV.text2)
                }
            case .done:
                Text(doneText).svFont(11.5).foregroundStyle(SV.text2).lineLimit(2)
            case .noSubs:
                Text(model.t("app.process.row.no_subs")).svFont(11.5).foregroundStyle(SV.yellowText).lineLimit(2)
            case .failed:
                Text(failedText).svFont(11.5).foregroundStyle(SV.redText).lineLimit(2)
                    .help(video.errorDetail ?? "")
            case .stopped:
                Text(model.t("app.process.row.stopped", ["step": stepOnly, "band": bandOnly])).svFont(11.5).foregroundStyle(SV.text2)
            case .ready:
                // Back to ready after Stop All (E5); a row that never was in a batch says nothing (E1).
                if model.run.readyAgain.contains(video.id) {
                    Text(model.t("app.process.row.ready")).svFont(11.5).foregroundStyle(SV.text2)
                }
            case .unreadable:
                EmptyView()
            }
        }
    }

    private func elapsed(at date: Date) -> Double {
        model.run.fileStarted.map { date.timeIntervalSince($0) } ?? 0
    }

    private var waitingText: String {
        if let estimate = model.waitingEstimate(video) {
            return model.t("app.process.row.waiting_est", ["t": model.durationText(estimate)])
        }
        return model.t("app.process.row.waiting")
    }

    /// "312 righe · 9 scartate (nel report) · 588 confini raffinati · elaborato in 01:31:00".
    private var doneText: String {
        var parts = [model.tn("app.process.row.lines", video.segments ?? 0)]
        if let dropped = video.dropped, dropped > 0 { parts.append(model.tn("app.process.row.dropped", dropped)) }
        if let refined = video.refined, refined > 0 { parts.append(model.tn("app.process.row.refined", refined)) }
        if let elapsed = video.elapsed { parts.append(model.t("app.process.finished.took_file", ["t": Localizer.clock(elapsed)])) }
        return model.join(parts)
    }

    private var stepOnly: String {
        video.atStep.flatMap { $0.split(separator: ":").first }.map { model.stepName(String($0)) } ?? "—"
    }

    private var bandOnly: String {
        guard let at = video.atStep, let band = at.split(separator: ":").dropFirst().first else { return "" }
        return model.bandName(String(band), lower: true)
    }

    /// "Fallito durante OCR ×3 · dialoghi: Vision request failed (-1)": the step, then the
    /// sentence of a known code or the engine's short text (`AppModel.failureText`).
    private var failedText: String {
        let error = model.failureText(video)
        // Before any step (the file went away, the probe failed): no step to name.
        guard video.atStep != nil else { return model.t("app.process.row.failed_plain", ["error": error]) }
        let text = model.t("app.process.row.failed", ["step": stepOnly, "band": bandOnly, "error": error])
        // A sentence of the catalogue ends with its own full stop; a bare text does not get one.
        return text.hasSuffix(": ") ? String(text.dropLast(2)) : text
    }

    /// Numbers in mono, "—" where the probe has nothing (unreadable, not yet probed).
    private func number(_ text: String?) -> some View {
        Text(text ?? (video.probed ? "—" : "…")).svFont(SVFont.numbers).foregroundStyle(SV.textCode).lineLimit(1)
    }

    /// "23,976" or "24": the language's separators, no trailing zeros.
    private func fpsText(_ fps: Double) -> String {
        let rounded = (fps * 1000).rounded() / 1000
        return model.localizer.number(rounded, decimals: rounded == rounded.rounded() ? 0 : 3)
    }

    /// The name a new SRT would get when one is there already (`<stem>_<yyyyMMdd_HHmmss>.srt`).
    private var renamedSRT: String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return video.url.deletingPathExtension().lastPathComponent + "_" + f.string(from: Date()) + ".srt"
    }

    private func toggleExpanded() {
        guard video.state.isFinished, video.state != .failed else { return }
        if expanded { model.run.expanded.remove(video.id) } else { model.run.expanded.insert(video.id) }
    }

    private func select() {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        if flags.contains(.command) {
            if selected { model.selection.remove(video.id) } else { model.selection.insert(video.id) }
        } else if flags.contains(.shift), let anchor = model.selection.first,
                  let a = model.videos.firstIndex(where: { $0.id == anchor }),
                  let b = model.videos.firstIndex(where: { $0.id == video.id }) {
            model.selection = Set(model.videos[min(a, b)...max(a, b)].map(\.id))
        } else {
            model.selection = [video.id]
        }
    }
}

/// The context menu of a row: Finder, Preview, the outputs of a finished row, Process Again, Remove.
struct RowMenu: View {
    @Environment(AppModel.self) private var model
    var video: VideoItem
    var selected: Bool

    var body: some View {
        let missing = !video.exists
        Button(model.t("app.menu.show_in_finder")) { model.showInFinder([video.id]) }.disabled(missing)
        Button(model.t("app.process.row.open_in_preview")) { model.openInPreview(video.id) }
            .disabled(missing || video.state == .unreadable)
        if video.state.isFinished {
            Divider()
            if video.state != .failed, video.state != .stopped {
                Button(model.t("app.process.row.review")) { model.review(video) }
                    .disabled(video.outputReport == nil)
                Button(model.t("app.process.row.open_srt")) { model.openSRT(video) }
                    .disabled(!FileManager.default.fileExists(atPath: video.outputSRT.path))
            }
            Button(model.t("app.process.row.open_log")) { model.openLog(video) }.disabled(!video.logExists)
            Button(model.t("app.process.row.process_again")) { model.processAgain([video.id]) }
        }
        Divider()
        Button(model.t("app.menu.remove")) { model.removeWithUndo(selected ? model.selection : [video.id]) }
            .disabled(video.state.inBatch)
    }
}

/// The actions column (`.acts` of the C2 boards): Preview on a row ready for the batch,
/// Stop on the running one, Review and ⋯ on a finished one, Open Log and ⋯ on a failed
/// one, Process Again on a stopped one; nothing while a row waits in the batch.
struct RowActions: View {
    @Environment(AppModel.self) private var model
    var video: VideoItem

    var body: some View {
        HStack(spacing: 6) {
            switch video.state {
            case .ready:
                Button { model.openInPreview(video.id) } label: { Label(model.t("app.process.row.preview"), systemImage: "viewfinder") }
                    .svButton(.secondary, .small)
                    .disabled(!model.canPreview(video))
                    .help(model.t("app.process.row.preview_help"))
            case .running:
                Button { model.stopCurrentFile() } label: { Label(model.t("app.common.stop"), systemImage: "stop.fill") }
                    .svButton(.secondary, .small)
                    .help(model.t("app.process.row.stop_help"))
            case .done, .noSubs:
                Button { model.review(video) } label: { Label(model.t("app.process.row.review"), systemImage: "doc.text.magnifyingglass") }
                    .svButton(.secondary, .small)
                    .disabled(video.outputReport == nil)
                    .help(model.t(video.outputReport == nil ? "app.process.row.review_none" : "app.process.row.review_help"))
                more
            case .failed:
                Button(model.t("app.process.row.open_log")) { model.openLog(video) }.svButton(.secondary, .small)
                    .disabled(!video.logExists)
                more
            case .stopped:
                Button(model.t("app.process.row.process_again")) { model.processAgain([video.id]) }.svButton(.secondary, .small)
            default:
                EmptyView()
            }
        }
    }

    private var more: some View {
        PopupMenu({ moreItems }) {
            Image(systemName: "ellipsis").svFont(13, .semibold).foregroundStyle(SV.text2)
                .frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .help(model.t("app.process.row.more"))
        .accessibilityLabel(model.t("app.process.row.more"))
    }

    private var moreItems: [SVMenuItem] {
        var items: [SVMenuItem] = [.item(model.t("app.common.show_in_finder")) { model.showInFinder([video.id]) }]
        if video.state != .failed {
            items.append(.item(model.t("app.process.row.open_srt"), enabled: FileManager.default.fileExists(atPath: video.outputSRT.path)) { model.openSRT(video) })
            items.append(.item(model.t("app.process.row.open_log"), enabled: video.logExists) { model.openLog(video) })
        }
        items.append(.item(model.t("app.process.row.open_in_preview"), enabled: model.canPreview(video)) { model.openInPreview(video.id) })
        items += [.separator,
                  .item(model.t("app.process.row.process_again")) { model.processAgain([video.id]) },
                  .item(model.t("app.process.row.remove")) { model.removeWithUndo([video.id]) }]
        return items
    }
}

// MARK: - Steps (E2, E4, DS3)

/// The steps of the file in progress, or of the one that failed, by band.
struct StepsPanel: View {
    @Environment(AppModel.self) private var model
    var video: VideoItem

    private var steps: [StepRun] {
        if video.state == .running { return model.run.steps }
        // A failed row keeps its plan and times; the aborted step and the rest are drawn from `atStep`.
        return failedSteps
    }

    private var failedSteps: [StepRun] {
        guard let plan = video.plan else { return [] }
        var seen = false
        return plan.map { id in
            let parts = id.split(separator: ":").map(String.init)
            var s = StepRun(key: parts.first ?? id, band: parts.count > 1 ? parts[1] : "bottom")
            if id == video.atStep { s.state = .aborted; seen = true }
            else if seen { s.state = .notRun }
            else { s.state = .done; s.ratio = 1 }
            if let t = video.times?[id] { s.duration = t; s.elapsed = t }
            return s
        }
    }

    /// The column of the numbers, shared by every step of both bands (design note 64): as wide as
    /// the longest text expected, wider for all of them together when one text needs more.
    @State private var numbersWidth: CGFloat = 0

    /// The longest text a running step is expected to show: "17.040 / 17.040 · ETA 23:40 · 127 fps".
    private var widestExpected: String {
        let l = model.localizer, n = l.number(17_040)
        return model.t("app.steps.running", ["done": n, "total": n, "eta": Localizer.clock(23 * 60 + 40),
                                             "rate": l.number(127), "unit_s": model.t("app.steps.unit.fps")])
    }

    var body: some View {
        let bands = Array(NSOrderedSet(array: steps.map(\.band))) as? [String] ?? []
        VStack(alignment: .leading, spacing: 10) {
            ForEach(bands, id: \.self) { band in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).fill(band == "top" ? signsBlue : SV.green).frame(width: 9, height: 9)
                        Text(model.bandName(band).uppercased()).svFont(10.5, .semibold).foregroundStyle(SV.text3).tracking(0.3)
                    }
                    ForEach(steps.filter { $0.band == band }) { step in
                        StepLine(step: step, failedRow: video.state == .failed, numbersWidth: numbersWidth)
                    }
                }
            }
            if video.state == .failed, let detail = video.errorDetail {
                // The technical detail and where the whole story is (board E4).
                VStack(alignment: .leading, spacing: 2) {
                    Text(detail).svFont(11.5, mono: true).foregroundStyle(SV.redText).textSelection(.enabled)
                    if video.logPath != nil || video.logExists {
                        LogLine(video: video)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .svBox(RoundedRectangle(cornerRadius: SV.Radius.field), fill: SV.bg, line: SV.line,
                       padding: EdgeInsets(vertical: 10, horizontal: 12))
                .padding(.top, 4)
            }
        }
        .padding(.trailing, 2)
        // The expected widest text takes part in the measure without being shown.
        .background(alignment: .topLeading) {
            Text(widestExpected).svFont(SVFont.smallNumbers).lineLimit(1).fixedSize().hidden()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { expectedWidth = $0 }
        }
        .onPreferenceChange(NumbersWidthKey.self) { measured = $0 }
        .onChange(of: measured, initial: true) { numbersWidth = max(expectedWidth, measured) }
        .onChange(of: expectedWidth) { numbersWidth = max(expectedWidth, measured) }
    }

    @State private var expectedWidth: CGFloat = 0
    @State private var measured: CGFloat = 0
}

/// The widest text of the numbers column among the steps shown.
struct NumbersWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// "log: ~/Downloads/name.log" in the box of a failed row: a click opens the log (as Open Log does).
struct LogLine: View {
    @Environment(AppModel.self) private var model
    var video: VideoItem
    @State private var hover = false

    var body: some View {
        let exists = video.logExists
        Button { model.openLog(video) } label: {
            Text("log: \(Text(verbatim: video.logDisplayPath).underline(hover && exists))")
                .svFont(11.5, mono: true).foregroundStyle(SV.redText)
                .multilineTextAlignment(.leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!exists)
        .onHover { hover = $0 }
        .svPointingHand(exists)
        .help(model.t("app.process.row.open_log"))
        .accessibilityLabel(model.t("app.process.row.open_log"))
    }
}

/// One step: icon, label, bar and the numbers on the right (design note 28).
struct StepLine: View {
    @Environment(AppModel.self) private var model
    var step: StepRun
    var failedRow: Bool
    /// The shared width of the numbers column (`StepsPanel`): all bars come out the same length.
    var numbersWidth: CGFloat = 180

    private var labelColor: Color {
        switch step.state {
        case .aborted: SV.redText
        case .waiting, .notRun: SV.text3
        default: SV.text
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            icon.frame(width: 14, height: 14)
            Text(model.stepName(step.key)).svFont(12).foregroundStyle(labelColor).frame(width: 118, alignment: .leading).lineLimit(1)
            bar.frame(maxWidth: .infinity)
            Text(right).svFont(SVFont.smallNumbers).foregroundStyle(rightColor).lineLimit(1)
                .fixedSize()
                .background { GeometryReader { Color.clear.preference(key: NumbersWidthKey.self, value: $0.size.width) } }
                .frame(width: max(numbersWidth, 1), alignment: .trailing)
        }
        .help(help)
    }

    @ViewBuilder private var icon: some View {
        switch step.state {
        case .done: Image(systemName: "checkmark").svFont(11, .bold).foregroundStyle(SV.greenText)
        case .running: Spinner(size: 12)
        case .aborted: Image(systemName: "xmark").svFont(11, .bold).foregroundStyle(SV.redText)
        case .waiting, .notRun: Circle().strokeBorder(SV.glassLine).frame(width: 10, height: 10)
        }
    }

    private var bar: some View {
        let fraction: Double
        let fill: Color
        switch step.state {
        case .done: fraction = 1; fill = SV.green
        case .running: fraction = step.ratio; fill = SV.primary
        case .aborted: fraction = max(step.ratio, 0.08); fill = SV.red
        case .waiting, .notRun: fraction = 0; fill = SV.track
        }
        return SVBar(fraction, height: 4, fill: fill, track: SV.trackSoft)
    }

    private var unitName: String { model.t(step.unit == "segments" ? "app.steps.unit.lines" : "app.steps.unit.frames") }
    private var rateUnit: String { model.t(step.unit == "segments" || step.key == "refine" ? "app.steps.unit.lines_s" : "app.steps.unit.fps") }

    private var right: String {
        let l = model.localizer
        switch step.state {
        case .done:
            let d = step.duration ?? step.elapsed
            // Under a second: "in less than 1 s", not "in 00:00" (design note 64).
            if d < 1 {
                return step.count > 0
                    ? model.t("app.steps.done_quick", ["total": l.number(Double(step.count)), "unit": unitName])
                    : model.t("app.steps.under_second")
            }
            let t = Localizer.clock(d)
            if step.count > 0, let rate = averageRate {
                return model.t("app.steps.done", ["total": l.number(Double(step.count)), "unit": unitName, "t": t,
                                                  "rate": l.number(rate, decimals: rate < 10 ? 1 : 0), "unit_s": rateUnit])
            }
            if step.count > 0 {
                return model.t("app.steps.done_short", ["total": l.number(Double(step.count)), "unit": unitName, "t": t])
            }
            return t
        case .running:
            let count = "\(l.number(Double(step.count))) / \(l.number(Double(step.total)))"
            if let eta = step.eta, let rate = step.rate {
                return model.t("app.steps.running", ["done": l.number(Double(step.count)), "total": l.number(Double(step.total)),
                                                     "eta": Localizer.clock(eta), "rate": l.number(rate, decimals: rate < 10 ? 1 : 0),
                                                     "unit_s": rateUnit])
            }
            return count
        case .waiting:
            if failedRow { return model.t("app.steps.not_run") }
            // An estimate under a second says nothing ("about 0 s"): "waiting" alone (design note 67).
            if let e = step.estimate, e >= 1 { return model.t("app.steps.waiting_est", ["t": model.durationText(e)]) }
            return model.t("app.steps.waiting")
        case .aborted: return model.t("app.steps.aborted")
        case .notRun: return model.t("app.steps.not_run")
        }
    }

    private var averageRate: Double? {
        let d = step.duration ?? step.elapsed
        // Under a second ("330 frames in 0:00") a rate says nothing: it shows from one second on (note 9).
        guard d > 1, step.count > 0 else { return nil }
        return Double(step.count) / d
    }

    private var rightColor: Color {
        switch step.state {
        case .aborted: SV.redText
        case .waiting, .notRun: SV.text3
        default: SV.textCode
        }
    }

    /// The long sentence of the step (design note 18).
    private var help: String {
        step.key == "ocr" ? model.t("app.steps.help.ocr", ["n": model.ocrParams.multiVariant ? 3 : 1]) : model.t("app.steps.help.\(step.key)")
    }
}

// MARK: - Finished row opened (E3)

/// Times per step (both bands on one line) and the three files with their links.
struct FinishedDetail: View {
    @Environment(AppModel.self) private var model
    var video: VideoItem

    private var keys: [String] {
        let plan = video.plan ?? video.times.map { Array($0.keys).sorted() } ?? []
        var out: [String] = []
        for id in plan {
            let key = String(id.split(separator: ":").first ?? Substring(id))
            if !out.contains(key) { out.append(key) }
        }
        return out
    }

    private var bands: [String] {
        let plan = video.plan ?? video.times.map { Array($0.keys).sorted() } ?? []
        var out: [String] = []
        for id in plan {
            let parts = id.split(separator: ":")
            if parts.count > 1, !out.contains(String(parts[1])) { out.append(String(parts[1])) }
        }
        return out
    }

    /// Two columns of the same width, as on board E3: FILES starts at the middle of the row.
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            if let times = video.times, !times.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    // "TEMPI · DIALOGHI · CARTELLI": the bands in the order of the values (board C2-R1).
                    label(([model.t("app.process.row.times")] + bands.map { model.bandName($0) }).joined(separator: model.t("app.common.list_separator")))
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                        ForEach(keys, id: \.self) { key in
                            GridRow {
                                Text(model.stepName(key)).svFont(11.5).foregroundStyle(SV.text2).lineLimit(1).fixedSize()
                                Text(bands.compactMap { times["\(key):\($0)"].map(stepTime) }.joined(separator: model.t("app.common.list_separator")))
                                    .svFont(SVFont.smallNumbers).foregroundStyle(SV.textCode)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 5) {
                label(model.t("app.process.row.files"))
                // The kinds take the width of the longest ("Review report", boards E3 and RV1), the names the rest:
                // a name is cut in the middle only when it really does not fit.
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                    if video.state != .stopped {
                        file(model.t("app.process.row.srt"), video.outputSRT, exists: FileManager.default.fileExists(atPath: video.outputSRT.path))
                        if let report = video.reportPath.map({ URL(fileURLWithPath: $0) }) ?? (video.reportExists ? video.reportURL : nil) {
                            file(model.t("app.process.row.report"), report, exists: video.outputReport != nil)
                        }
                    }
                    file(model.t("app.process.row.log"), video.outputLog, exists: video.logExists)
                }
                HStack(spacing: 14) {
                    UnderlineLink(model.t("app.common.show_in_finder")) { model.showInFinder([video.id]) }
                    if video.state == .done {
                        UnderlineLink(model.t("app.process.row.open_srt")) { model.openSRT(video) }
                    }
                    if video.logExists {
                        UnderlineLink(model.t("app.process.row.open_log")) { model.openLog(video) }
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased()).svFont(10.5, .semibold).foregroundStyle(SV.text3).tracking(0.3).padding(.bottom, 2)
    }

    /// "00:04", or "meno di 1 s" for a step under a second (as the steps say it, design note 64).
    private func stepTime(_ seconds: Double) -> String {
        seconds < 1 ? model.t("app.process.row.under_second") : Localizer.clock(seconds)
    }

    private func file(_ kind: String, _ url: URL, exists: Bool) -> some View {
        GridRow {
            Text(kind).svFont(11.5).foregroundStyle(SV.text2).lineLimit(1).fixedSize()
            Text(url.lastPathComponent).svFont(SVFont.smallNumbers).foregroundStyle(exists ? SV.textCode : SV.text3)
                .strikethrough(!exists, color: SV.text3).lineLimit(1).truncationMode(.middle)
                .help(url.lastPathComponent)
        }
    }
}
