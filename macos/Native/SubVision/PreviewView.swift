// SPDX-License-Identifier: MIT
// The Preview page's content under its title band (design boards C2-A1–A3,
// C3 A0–A6, design notes 76, 79): one block as wide as the frame, centred
// left of the parameters panel, that never scrolls and fills the height.
// The frame with its bands and handles between the arrows, the caption with
// the badge, the thumbnails in two rows of ten as wide as the frame, the
// summary with Try OCR, and always the two panels Dialogue | Signs, as tall
// as each other, in what is left. The frame shrinks so that all of it fits
// (in a window too short for that, the block scrolls). Before a frame is
// shown, a frame-shaped box with the search (A0), the search that stopped
// with «Riprova» (A1) or a short text, and the frames found so far.

import AppKit
import SVShell
import SwiftUI

/// The measures of the block in a content area of `size` (C2-A1 at 1280 × 860:
/// frame 732 × 414, thumbnails 68 × 38, panels 176). The frame is as wide as the
/// height lets everything fit with the panels at least `panelsMin` tall, never
/// wider than the area less the arrows, and never wider than `maxFrameWidth`.
struct PreviewLayout: Equatable {
    static let top: CGFloat = 22
    static let bottom: CGFloat = 22
    /// The arrows: 30 pt circles, their outer edge 46 pt from the frame's (`left: -46px`).
    static let arrow: CGFloat = 46
    /// Past the arrows, to the edge of the area.
    static let margin: CGFloat = 16
    static let captionTop: CGFloat = 12
    static let caption: CGFloat = 18
    static let captionBottom: CGFloat = 10
    /// Between thumbnails, and between the two rows.
    static let gap: CGFloat = 6
    static let columns = 10
    static let rows = 2
    static let summaryTop: CGFloat = 10
    static let summary: CGFloat = 28
    static let panelsTop: CGFloat = 16
    /// The panels' least height: room for a two-line reading, its line and the stale note.
    static let panelsMin: CGFloat = 170
    static let minFrameWidth: CGFloat = 320
    /// In a large window the frame stops growing here; the block stays centred.
    static let maxFrameWidth: CGFloat = 640

    var size: CGSize
    var frameWidth: CGFloat
    var frameHeight: CGFloat
    var thumbWidth: CGFloat
    var thumbHeight: CGFloat
    var panels: CGFloat

    /// `notes`: the notes over the frame, with their gap (0 without).
    init(size: CGSize, aspect: CGFloat, notes: CGFloat) {
        let a = aspect > 0 ? aspect : 16 / 9
        let g = Self.gap, n = CGFloat(Self.columns)
        let fixed = Self.top + notes + Self.captionTop + Self.caption + Self.captionBottom + CGFloat(Self.rows - 1) * g
            + Self.summaryTop + Self.summary + Self.panelsTop + Self.panelsMin + Self.bottom
        // The frame and two rows of thumbnails: w / a + 2 · (w − 9 g) / 10 / a.
        let rows = CGFloat(Self.rows)
        let byHeight = ((size.height - fixed) * a + rows * (n - 1) * g / n) / (1 + rows / n)
        let byWidth = size.width - 2 * (Self.arrow + Self.margin)
        let w = max(Self.minFrameWidth, min(byWidth, byHeight, Self.maxFrameWidth)).rounded(.down)
        self.size = size
        frameWidth = w
        frameHeight = (w / a).rounded()
        thumbWidth = (w - (n - 1) * g) / n
        thumbHeight = (thumbWidth / a).rounded()
        panels = size.height - (Self.top + notes + frameHeight + Self.captionTop + Self.caption + Self.captionBottom
            + rows * thumbHeight + (rows - 1) * g + Self.summaryTop + Self.summary + Self.panelsTop + Self.bottom)
    }

    /// Everything in the area, the panels at least their least height (one point of rounding allowed).
    var fits: Bool { panels >= Self.panelsMin - 1 && frameWidth + 2 * Self.arrow <= size.width }

    /// The area's height that gives the panels `panels` with this frame.
    func height(panels: CGFloat) -> CGFloat { size.height - self.panels + panels }
}

/// The block, or the box before the frames.
struct PreviewContent: View {
    @Environment(AppModel.self) private var model
    @State private var notesHeight: CGFloat = 0

    /// The frame's proportions: the frame's own, else the video's, else 16:9.
    private var aspect: CGFloat {
        if let f = model.previewFrame, f.width > 0, f.height > 0 { return CGFloat(f.width) / CGFloat(f.height) }
        if let v = model.previewVideo, let w = v.width, let h = v.height, w > 0, h > 0 { return CGFloat(w) / CGFloat(h) }
        return 16 / 9
    }

    var body: some View {
        GeometryReader { g in
            let layout = PreviewLayout(size: g.size, aspect: aspect, notes: notesHeight)
            // A window too short for the whole block: the panels keep their least height and it scrolls.
            let fitted = layout.panels >= PreviewLayout.panelsMin - 1 ? layout
                : PreviewLayout(size: CGSize(width: g.size.width, height: layout.height(panels: PreviewLayout.panelsMin)),
                                aspect: aspect, notes: notesHeight)
            ScrollView(.vertical) {
                Group {
                    if let result = model.previewResult, result.index != nil, !result.frames.isEmpty, !model.isSearchingPreviewVideo {
                        FrameBlock(result: result, layout: fitted, notes: { notes })
                            .previewMetric("block")
                    } else {
                        // Boards A0, A1: the same block before a frame is shown and while they are searched.
                        EmptyFrameBlock(layout: fitted, notes: { notes })
                            .previewMetric("block")
                    }
                }
                .frame(width: g.size.width, height: max(g.size.height, fitted.size.height), alignment: .top)
            }
            .scrollDisabled(fitted == layout)
            .scrollIndicators(fitted == layout ? .never : .automatic)
            #if DEBUG
            .onChange(of: layout, initial: true) {
                PreviewMetrics.layout = fitted
                PreviewMetrics.scrolls = fitted != layout
            }
            #endif
        }
        .previewMetric("content")
        .clipped()
    }

    /// The search that failed, that stopped (once a frame is shown), or found no text
    /// anywhere: over the frame, as wide as it.
    @ViewBuilder
    private var notes: some View {
        VStack(spacing: 8) {
            if case .failed(let code, let message) = model.preview.search {
                NoteView(.red, text: model.previewErrorText(code: code, message: message)) {
                    Button { model.preview.search = .idle } label: {
                        Image(systemName: "xmark").svFont(11, .semibold).frame(width: 22, height: 22).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(model.t("app.common.dismiss"))
                }
            } else if stoppedNote, let result = model.previewResult {
                // A1 after a click on a thumbnail: the box is gone, the stop and «Riprova» stay over the frame.
                NoteView(.neutral, title: model.t("app.preview.stopped_title", ["k": result.frames.count, "n": result.search.total]),
                         text: model.t(result.search.stop == .user ? "app.preview.stopped_user" : "app.preview.stopped_text")) {
                    RetryFramesButton(primary: false)
                }
            }
            if noTextNote {
                NoteView(.yellow, text: model.t("app.preview.none_found")) { EmptyView() }
            }
        }
        .padding(.bottom, hasNotes ? 12 : 0)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { notesHeight = $0 }
    }

    /// The search stopped short and a frame is shown (A1 once a thumbnail was clicked).
    private var stoppedNote: Bool {
        guard let result = model.previewResult, !model.isSearchingPreviewVideo else { return false }
        return !result.search.complete && result.index != nil
    }

    /// Board A5: every zone searched, none with text.
    private var noTextNote: Bool {
        guard let result = model.previewResult, !model.isSearchingPreviewVideo else { return false }
        return result.search.complete && result.found == 0
    }

    private var hasNotes: Bool {
        if case .failed = model.preview.search { return true }
        return stoppedNote || noTextNote
    }
}

/// «Riprova» (A1): the search goes on with the zones left; off while it cannot run (a batch).
struct RetryFramesButton: View {
    @Environment(AppModel.self) private var model
    var primary = true

    var body: some View {
        Button { model.findFrames() } label: { Label(model.t("app.common.retry"), systemImage: "arrow.clockwise") }
            .svButton(primary ? .primary : .secondary, primary ? .regular : .small)
            .fixedSize()
            .disabled(!model.canFindFrames)
            .help(model.t("app.preview.retry_help"))
    }
}

/// C2-A1–A3: the frame between the arrows, caption, thumbnails, summary, panels.
struct FrameBlock<Notes: View>: View {
    @Environment(AppModel.self) private var model
    var result: PreviewState.Result
    var layout: PreviewLayout
    @ViewBuilder var notes: () -> Notes

    private var index: Int { result.index ?? 0 }
    private var frame: PreviewFrame? { result.frames.indices.contains(index) ? result.frames[index] : nil }

    var body: some View {
        VStack(spacing: 0) {
            notes()
            FrameBox(frame: frame, width: layout.frameWidth, height: layout.frameHeight)
                .overlay(alignment: .leading) { navButton(previous: true).offset(x: -PreviewLayout.arrow) }
                .overlay(alignment: .trailing) { navButton(previous: false).offset(x: PreviewLayout.arrow) }
                .previewMetric("frame")
            caption
                .frame(height: PreviewLayout.caption)
                .padding(.top, PreviewLayout.captionTop)
                .padding(.bottom, PreviewLayout.captionBottom)
            PreviewThumbnails(result: result, layout: layout)
                .previewMetric("thumbs")
            summaryRow
                .frame(height: PreviewLayout.summary)
                .padding(.top, PreviewLayout.summaryTop)
            OcrTestPanels()
                .frame(height: max(layout.panels, 0))
                .padding(.top, PreviewLayout.panelsTop)
        }
        .frame(width: layout.frameWidth)
        .padding(.top, PreviewLayout.top)
    }

    private func navButton(previous: Bool) -> some View {
        let off = previous ? index == 0 : index >= result.frames.count - 1
        return Button { previous ? model.previousFrame() : model.nextFrame() } label: {
            Image(systemName: previous ? "chevron.left" : "chevron.right").svFont(13, .semibold).foregroundStyle(SV.text)
                .frame(width: 30, height: 30)
                .background(Circle().fill(SV.glass))
                .overlay(Circle().strokeBorder(SV.glassLine))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(off)
        .opacity(off ? 0.45 : 1)
        .help(model.t(previous ? "app.preview.prev_frame" : "app.preview.next_frame"))
        .accessibilityLabel(model.t(previous ? "app.preview.prev_frame" : "app.preview.next_frame"))
    }

    /// "Fotogramma 9 di 20 · 00:00:27" and the badge, centred.
    @ViewBuilder
    private var caption: some View {
        if let frame {
            HStack(spacing: 10) {
                Text(model.frameCaption(frame, index: index, count: result.frames.count))
                    .svFont(12, mono: true).foregroundStyle(SV.text2)
                badge(frame)
            }
        }
    }

    /// Text in the dialogue (green), at the top (blue), in both (green and blue), none (grey).
    @ViewBuilder
    private func badge(_ frame: PreviewFrame) -> some View {
        switch (frame.hasDialogue, frame.hasSigns) {
        case (true, true): BothBandsChip(text: model.t("app.preview.badge_both"))
        case (true, false): StatusChip(model.t("app.preview.badge_dlg"), tone: .green)
        case (false, true): StatusChip(model.t("app.preview.badge_sig"), tone: .accent)
        default: StatusChip(model.t("app.preview.badge_none"), tone: .neutral)
        }
    }

    /// "20 fotogrammi · 17 con testo · 5 con cartelli · 3 senza testo", then Try OCR
    /// ("Non disponibile durante il lotto" before it during the batch, C2-A3).
    private var summaryRow: some View {
        HStack(spacing: 10) {
            // A narrow block: the short summary.
            ViewThatFits(in: .horizontal) {
                Text(summary(short: false)).svSmall().fixedSize()
                Text(summary(short: true)).svSmall().lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            if model.batch.running {
                // Whole (board A6): the summary takes its short form instead.
                Text(model.t("app.preview.batch_off")).svSmall(SV.text3).lineLimit(1).fixedSize()
            }
            Button { model.tryOCR() } label: { Label(model.t("app.preview.test"), systemImage: "magnifyingglass") }
                .svButton(.primary, .regular)
                .fixedSize()
                .disabled(!model.canTryOCR)
                .help(model.t("app.preview.test_help"))
        }
        .previewMetric("summary")
    }

    /// The signs counted when their band is on, or when the search found some (design note 78).
    private func summary(short: Bool) -> String {
        let values: [String: Any] = ["n": result.frames.count, "k": result.found, "s": result.foundSigns,
                                     "m": result.frames.count - result.found]
        // Board A5: "20 fotogrammi · nessuno con testo".
        if result.found == 0 { return model.t("app.preview.summary_no_text", values) }
        let signs = model.ocrParams.topBand || result.foundSigns > 0
        let key = short ? (signs ? "app.preview.summary_signs_short" : "app.preview.summary_short")
            : (signs ? "app.preview.summary_signs" : "app.preview.summary")
        return model.t(key, values)
    }
}

/// Boards A0 and A1: the block before a frame is shown, laid out as `FrameBlock`: the
/// frame-shaped box (the search's progress and Stop, the search that stopped and
/// «Riprova», or a short text), the arrows, "Ricerca in corso" / "7 fotogrammi su 20",
/// the frames found so far (clickable) then the empty places of the zones left, the
/// summary with Try OCR off and the two panels.
struct EmptyFrameBlock<Notes: View>: View {
    @Environment(AppModel.self) private var model
    var layout: PreviewLayout
    @ViewBuilder var notes: () -> Notes

    /// The search of the video shown: zones done of total, frames with text (zero while it
    /// waits for another video's search to stop).
    private var progress: (done: Int, total: Int, found: Int)? {
        guard model.isSearchingPreviewVideo else { return nil }
        if case .running(let done, let total, let found) = model.preview.search, model.preview.searching == model.previewVideo?.id {
            return (done, total, found)
        }
        return (0, PreviewState.zones, 0)
    }

    private var frames: [PreviewFrame] { model.previewFrames }
    private var total: Int { model.previewResult?.search.total ?? PreviewState.zones }

    var body: some View {
        VStack(spacing: 0) {
            notes()
            PreviewPlaceholder(width: layout.frameWidth, height: layout.frameHeight)
                .overlay(alignment: .leading) { arrow(previous: true).offset(x: -PreviewLayout.arrow) }
                .overlay(alignment: .trailing) { arrow(previous: false).offset(x: PreviewLayout.arrow) }
                .previewMetric("frame")
            Text(caption)
                .svFont(12, mono: true).foregroundStyle(SV.text3)
                .frame(height: PreviewLayout.caption)
                .padding(.top, PreviewLayout.captionTop)
                .padding(.bottom, PreviewLayout.captionBottom)
            slots
                .previewMetric("thumbs")
            HStack(spacing: 10) {
                Text(summary).svSmall().lineLimit(1)
                Spacer(minLength: 8)
                Button { model.tryOCR() } label: { Label(model.t("app.preview.test"), systemImage: "magnifyingglass") }
                    .svButton(.primary, .regular)
                    .fixedSize()
                    .disabled(true)
                    .help(model.t("app.preview.test_help"))
            }
            .frame(height: PreviewLayout.summary)
            .padding(.top, PreviewLayout.summaryTop)
            .previewMetric("summary")
            OcrTestPanels()
                .frame(height: max(layout.panels, 0))
                .padding(.top, PreviewLayout.panelsTop)
        }
        .frame(width: layout.frameWidth)
        .padding(.top, PreviewLayout.top)
    }

    /// "Ricerca in corso", "7 fotogrammi su 20", "Nessun fotogramma".
    private var caption: String {
        if progress != nil { return model.t("app.preview.caption_searching") }
        if !frames.isEmpty { return model.t("app.preview.caption_partial", ["k": frames.count, "n": total]) }
        return model.t("app.preview.caption_none")
    }

    /// "12 di 20 zone · 9 con testo" while it searches, "7 di 20 zone · 5 con testo" once it stopped.
    private var summary: String {
        if let p = progress { return model.t("app.preview.summary_searching", ["i": p.done, "n": p.total, "k": p.found]) }
        if let r = model.previewResult, !r.frames.isEmpty {
            return model.t("app.preview.summary_searching", ["i": r.frames.count, "n": r.search.total, "k": r.found])
        }
        return model.t("app.preview.summary_none")
    }

    /// Two rows of ten: the frames found so far, in the order of their zones (a click shows one),
    /// then the places of the zones left, dashed.
    private var slots: some View {
        VStack(alignment: .leading, spacing: PreviewLayout.gap) {
            ForEach(0..<PreviewLayout.rows, id: \.self) { row in
                HStack(spacing: PreviewLayout.gap) {
                    ForEach(0..<PreviewLayout.columns, id: \.self) { column in
                        let i = row * PreviewLayout.columns + column
                        if let result = model.previewResult, result.frames.indices.contains(i) {
                            PreviewThumbnail(result: result, i: i, layout: layout, selectable: progress == nil)
                        } else {
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(SV.line, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                                .frame(width: layout.thumbWidth, height: layout.thumbHeight)
                        }
                    }
                }
            }
        }
    }

    /// Off while it searches; once it stopped, → shows the first frame found, ← the last.
    private func arrow(previous: Bool) -> some View {
        let off = progress != nil || frames.isEmpty
        return Button { previous ? model.previousFrame() : model.nextFrame() } label: {
            Image(systemName: previous ? "chevron.left" : "chevron.right").svFont(13, .semibold).foregroundStyle(SV.text)
                .frame(width: 30, height: 30)
                .background(Circle().fill(SV.glass))
                .overlay(Circle().strokeBorder(SV.glassLine))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(off)
        .opacity(off ? 0.45 : 1)
        .help(model.t(previous ? "app.preview.prev_frame" : "app.preview.next_frame"))
        .accessibilityLabel(model.t(previous ? "app.preview.prev_frame" : "app.preview.next_frame"))
    }
}

/// The 20 thumbnails in two rows of ten, each row exactly as wide as the frame
/// (`.thg`, `.th2`, design note 76): the chosen one ringed in the accent, the ones
/// without text grey at half strength, dots for the bands with text.
struct PreviewThumbnails: View {
    @Environment(AppModel.self) private var model
    var result: PreviewState.Result
    var layout: PreviewLayout

    var body: some View {
        VStack(alignment: .leading, spacing: PreviewLayout.gap) {
            ForEach(0..<PreviewLayout.rows, id: \.self) { row in
                let start = row * PreviewLayout.columns
                HStack(spacing: PreviewLayout.gap) {
                    ForEach(start..<start + PreviewLayout.columns, id: \.self) { i in
                        if result.frames.indices.contains(i) {
                            PreviewThumbnail(result: result, i: i, layout: layout, selectable: true)
                        } else if !result.search.complete {
                            // A search that stopped short (A1): the places of the zones left.
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(SV.line, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                                .frame(width: layout.thumbWidth, height: layout.thumbHeight)
                        }
                    }
                }
                .frame(width: layout.frameWidth, height: layout.thumbHeight, alignment: .leading)
            }
        }
    }
}

/// One thumbnail: the chosen one ringed in the accent, the ones without text grey at half
/// strength, dots for the bands with text; a click shows its frame.
struct PreviewThumbnail: View {
    @Environment(AppModel.self) private var model
    var result: PreviewState.Result
    var i: Int
    var layout: PreviewLayout
    var selectable: Bool

    var body: some View {
        let f = result.frames[i]
        let selected = i == result.index
        return ZStack(alignment: .bottomTrailing) {
            Group {
                if let image = result.thumbnail(i) {
                    Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(SV.track)
                }
            }
            .frame(width: layout.thumbWidth, height: layout.thumbHeight)
            .clipped()
            if f.hasText {
                BandDots(dialogue: f.hasDialogue, signs: f.hasSigns)
                    .padding(2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .saturation(f.hasText ? 1 : 0)
        .opacity(f.hasText ? 1 : 0.5)
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(selected ? SV.primary : SV.line, lineWidth: selected ? 2 : 1))
        .contentShape(Rectangle())
        .onTapGesture { if selectable { model.selectFrame(i) } }
        .help(model.frameCaption(f, index: i, count: result.frames.count))
    }
}

/// Before a frame is shown: the frame's shape, dashed, with the search's progress and Stop
/// (A0), the search that stopped and «Riprova» (A1), or a short text (no video, the batch,
/// a video that cannot be read).
struct PreviewPlaceholder: View {
    @Environment(AppModel.self) private var model
    var width: CGFloat
    var height: CGFloat

    var body: some View {
        Group {
            if model.isSearchingPreviewVideo {
                searching
            } else if let result = model.previewResult, !result.search.complete, !failed {
                stopped(result)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "viewfinder").svFont(failed ? 22 : 30, .light)
                    Text(text).svFont(failed ? 12 : 13).multilineTextAlignment(.center)
                    if failed { RetryFramesButton().padding(.top, 4) }
                }
                .foregroundStyle(SV.text3)
                .padding(24)
            }
        }
        .frame(width: width, height: height)
        .background(RoundedRectangle(cornerRadius: SV.Radius.field).fill(SV.inset))
        .overlay(RoundedRectangle(cornerRadius: SV.Radius.field)
            .strokeBorder(SV.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .clipped()
    }

    private var failed: Bool { if case .failed = model.preview.search { return true }; return false }

    private var text: String {
        if model.previewVideo == nil { return model.t("app.preview.no_video") }
        if failed { return model.t("app.preview.unavailable") }
        if model.batch.running { return model.t("app.preview.placeholder_batch") }
        return model.t("app.preview.unavailable")
    }

    /// A0, centred: the spinner, "Cerco 20 fotogrammi… zona 12 di 20 · 9 con testo", its bar,
    /// what the search does, Stop. Zero while another video's search stops first.
    private var searching: some View {
        var done = 0, total = PreviewState.zones, found = 0
        if case .running(let d, let t, let f) = model.preview.search, model.preview.searching == model.previewVideo?.id {
            (done, total, found) = (d, t, f)
        }
        return VStack(spacing: 10) {
            Spinner(size: 18)
            Text(model.t("app.preview.searching", ["i": done, "n": total, "k": found])).svFont(13.5, .semibold).foregroundStyle(SV.text)
            SVBar(total > 0 ? Double(done) / Double(total) : 0)
                .frame(width: min(320, width - 48))
            Text(model.t("app.preview.search_help")).svSmall().multilineTextAlignment(.center)
                .frame(maxWidth: 520).fixedSize(horizontal: false, vertical: true)
            Button { model.stopFrames() } label: { Label(model.t("app.common.stop"), systemImage: "stop.fill") }
                .svButton(.secondary, .small)
                .padding(.top, 2)
        }
        .padding(24)
    }

    /// A1: "La ricerca dei fotogrammi si è fermata a 7 di 20.", why, «Riprova» (it resumes).
    private func stopped(_ result: PreviewState.Result) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "viewfinder").svFont(30, .light).foregroundStyle(SV.text3)
                .padding(.bottom, 2)
            Text(model.t("app.preview.stopped_title", ["k": result.frames.count, "n": result.search.total]))
                .svFont(13.5, .semibold).foregroundStyle(SV.text).multilineTextAlignment(.center)
            Text(model.t(result.search.stop == .user ? "app.preview.stopped_user" : "app.preview.stopped_text"))
                .svSmall().multilineTextAlignment(.center)
                .frame(maxWidth: 520).fixedSize(horizontal: false, vertical: true)
            RetryFramesButton()
                .padding(.top, 4)
        }
        .padding(24)
    }
}

/// The whole frame at `width` × `height`, the bands over it; "Anteprima non
/// disponibile" when the JPEG cannot be read.
struct FrameBox: View {
    @Environment(AppModel.self) private var model
    var frame: PreviewFrame?
    var width: CGFloat
    var height: CGFloat

    var body: some View {
        @Bindable var model = model
        let size = CGSize(width: width, height: height)
        ZStack(alignment: .topLeading) {
            if let image = model.preview.frameImage {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    // Square, as the bands over it (design note 89): a band at 100 % width
                    // would leave the rounded corners showing inside its border.
                    .clipShape(Rectangle())
                    .overlay(Rectangle().strokeBorder(SV.line))
                BandOverlay(size: size, editable: model.canDragBands, drag: $model.preview.drag)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "viewfinder").svFont(22, .light)
                    Text(model.t("app.preview.unavailable")).svFont(12)
                }
                .foregroundStyle(SV.text3)
                .frame(width: size.width, height: size.height)
                // Square, as the frame (design note 89).
                .background(Rectangle().fill(SV.surface))
                .overlay(Rectangle().strokeBorder(SV.line))
            }
        }
        .frame(width: size.width, height: size.height)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.preview.frameRect = $0 }
    }
}

/// The dots of a thumbnail (`.th2 .dots`): green for a line, blue for a sign, both side by side.
struct BandDots: View {
    var dialogue: Bool
    var signs: Bool

    var body: some View {
        HStack(spacing: 2) {
            if dialogue { Circle().fill(BandColors.dialogue).frame(width: 5, height: 5) }
            if signs { Circle().fill(BandColors.signs).frame(width: 5, height: 5) }
        }
    }
}

/// "Testo nei dialoghi e nei cartelli" (`.chip.both`): the chip of a frame with both,
/// with the two colours of the bands.
struct BothBandsChip: View {
    var text: String

    var body: some View {
        HStack(spacing: 5) {
            HStack(spacing: 2) {
                Circle().fill(BandColors.dialogue).frame(width: 6, height: 6)
                Circle().fill(BandColors.signs).frame(width: 6, height: 6)
            }
            Text(text).offset(y: -0.5)
        }
        .font(SVFont.smallNumbers.font)
        .frame(height: SVFont.smallNumbers.lineHeight)
        .foregroundStyle(SV.text)
        .svBox(Capsule(), fill: SVTone.neutral.background, line: SVTone.neutral.line,
               padding: EdgeInsets(vertical: 1, horizontal: 8))
        .fixedSize()
    }
}

// MARK: - Debug measures

/// Where the block's pieces were drawn last (SwiftUI's global space, that is the
/// window's), for `preview-layout`. Not observed: nothing redraws for them.
@MainActor
enum PreviewMetrics {
    static var layout: PreviewLayout?
    /// The window is too short for the block: it scrolls, the panels at their least height.
    static var scrolls = false
    static var rects: [String: CGRect] = [:]
}

extension View {
    /// Debug: records the view's frame under `name` in `PreviewMetrics`.
    @ViewBuilder
    func previewMetric(_ name: String) -> some View {
        #if DEBUG
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { PreviewMetrics.rects[name] = $0 }
        #else
        self
        #endif
    }
}
