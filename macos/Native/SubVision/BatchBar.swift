// SPDX-License-Identifier: MIT
// The batch bar of the window (design boards C3-01, C3-04, F5, A6): 44 pt at
// the bottom of every page while a batch runs. A spinner, "File 2 of 3 ·
// <name> · the batch ends around 14:20" (a click there goes to Video with the
// running row open), the batch's bar weighted by duration and split into one
// segment per file, the percentage, and Stop All (⌘., alert O2).

import SVShell
import SwiftUI

struct BatchBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.svWindowWidth) private var windowWidth
    @State private var hover = false

    /// The bar's width (`.sgbar`, 280 pt); a narrow window gives it less room.
    private var barWidth: CGFloat { windowWidth < 1000 ? 150 : 280 }

    var body: some View {
        let batch = model.batch
        HStack(spacing: 12) {
            Button { model.showRunningRow() } label: {
                HStack(spacing: 12) {
                    Spinner(size: 14)
                    line
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .underline(hover, color: SV.text3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
            .svPointingHand()
            .help(model.t("app.process.batchbar.open_help"))
            Spacer(minLength: 8)
            SegmentedProgressBar(weights: weights, fraction: batch.fraction ?? 0)
                .frame(width: barWidth)
                .accessibilityElement()
                .accessibilityLabel(model.t("app.process.batchbar.progress_label"))
                .accessibilityValue(model.t("app.process.batchbar.percent", ["n": Int(((batch.fraction ?? 0) * 100).rounded())]))
            Text(model.t("app.process.batchbar.percent", ["n": Int(((batch.fraction ?? 0) * 100).rounded())]))
                // The font's own line box, centred on the bar like the line on the left (the fixed
                // box of `svFont` set it a point low).
                .font(SVFont.smallNumbers.font).foregroundStyle(SV.text2)
                .frame(minWidth: 34, alignment: .trailing)
            Button { model.stopAll() } label: { Label(model.t("app.common.stop_all"), systemImage: "stop.fill") }
                .svButton(.destructive, .small)
                .help(model.t("app.process.bar.stop_all_help"))
        }
        .padding(.leading, 25)
        .padding(.trailing, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SV.raised)
        .overlay(alignment: .top) { Rectangle().fill(SV.line).frame(height: 1) }
        .accessibilityElement(children: .contain)
    }

    /// One segment per file, as wide as its duration (`BatchProgress`); equal ones while
    /// the durations do not cover the batch.
    private var weights: [Double] {
        let w = model.batchWeights
        return w.count == model.batch.total ? w : Array(repeating: 1, count: max(model.batch.total, 1))
    }

    /// "**File 2 di 3** · sintel_eng_hardsub_demo.mp4 · il lotto finisce verso le 08:46".
    private var line: Text {
        let parts = model.batchBarText
        let head = Text(verbatim: parts.head).fontWeight(.semibold)
        return Text("\(head)\(Text(verbatim: parts.tail))").font(.system(size: 12.5)).foregroundStyle(SV.text)
    }
}

extension AppModel {
    /// The batch bar's line: "File 2 di 3" (bold) and " · <name> · il lotto finisce verso le 08:46".
    var batchBarText: (head: String, tail: String) {
        let head = t("app.process.row.file_of", ["i": batch.index, "n": batch.total])
        var rest = batch.name.isEmpty ? [] : [batch.name]
        if let ends = batch.endsAround { rest.append(t("app.process.batchbar.ends", ["time": ends])) }
        return (head, rest.isEmpty ? "" : t("app.common.list_separator") + join(rest))
    }

    /// The batch bar's text: Video, with the row in progress open (C3-01).
    func showRunningRow() {
        tab = .process
        if let video = runningVideo { run.expanded.insert(video.id) }
    }
}
