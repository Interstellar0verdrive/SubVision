// SPDX-License-Identifier: MIT
// The drawers of the Video list (design round C3, boards C3-02–C3-05, E3,
// E10, N1): what a row shows under itself once opened.
//   to do      what is known of the video (duration, fps, size, codecs, weight,
//              read with ffprobe when it entered the list), what it will read
//              with the parameters of now and how long that takes, its SRT, and
//              the frames the Preview found
//   running    the steps by band, a bar and a state each, as a real table
//   done       the time of each step as a table, the result, the files
//   failed     the steps with a cross where it broke, what happened in plain
//              words, the technical line, the log and Finder
//   unreadable why, and Finder

import AppKit
import SVShell
import SwiftUI

/// The drawer of a row, by its state.
struct VideoDrawer: View {
    var video: VideoItem
    var columns: ListColumns

    var body: some View {
        switch video.state {
        case .ready, .waiting:
            TodoDrawer(video: video, narrow: columns.narrow)
        case .running:
            StepsTable(video: video, narrow: columns.narrow)
        case .done, .noSubs:
            DoneDrawer(video: video)
        case .failed, .stopped:
            FailedDrawer(video: video, narrow: columns.narrow)
        case .unreadable:
            UnreadableDrawer(video: video)
        }
    }
}

/// The Review page's opened row uses the same times, result and files (until Review becomes the report's page).
typealias FinishedDetail = DoneDrawer

// MARK: - Pieces

/// "TEMPO DI OGNI TAPPA" (`.dh`): 10.5 pt semibold, capitals.
struct DrawerHeading: View {
    var text: String
    var color: Color = SV.text3

    var body: some View {
        Text(text.uppercased()).svFont(10.5, .semibold).foregroundStyle(color).tracking(0.4)
            .padding(.bottom, 6)
    }
}

/// Keys and values (`.kv2`): the key in grey, the value in text or in mono.
struct KeyValues: View {
    struct Row: Identifiable {
        var key: String
        var value: String
        var mono = false
        var id: String { key }
    }

    var rows: [Row]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
            ForEach(rows) { row in
                GridRow {
                    Text(row.key).svFont(12).foregroundStyle(SV.text3).lineLimit(1).fixedSize()
                    if row.mono {
                        Text(row.value).svFont(11.5, mono: true).foregroundStyle(SV.textCode).lineLimit(1).truncationMode(.middle)
                            .help(row.value)
                    } else {
                        Text(row.value).svFont(12).foregroundStyle(SV.text).lineLimit(2)
                    }
                }
            }
        }
    }
}

/// The swatch of a band (green dialogue, blue signs).
struct DrawerSwatch: View {
    var band: String
    var on = true

    var body: some View {
        RoundedRectangle(cornerRadius: 2).fill(band == "top" ? signsBlue : SV.green).frame(width: 9, height: 9)
            .opacity(on ? 1 : 0.35)
    }
}

extension AppModel {
    /// The steps of a plan (`key:band`) in order, once each, and its bands.
    func planKeys(_ plan: [String]) -> (keys: [String], bands: [String]) {
        var keys: [String] = [], bands: [String] = []
        for id in plan {
            let parts = id.split(separator: ":").map(String.init)
            if let key = parts.first, !keys.contains(key) { keys.append(key) }
            if parts.count > 1, !bands.contains(parts[1]) { bands.append(parts[1]) }
        }
        return (keys, bands)
    }

    /// "Estrazione dei fotogrammi", "Lettura OCR ×3" (the narrow table: "Estrazione").
    func tableStepName(_ key: String, narrow: Bool = false) -> String {
        if narrow, localizer.has("app.process.drawer.step_short.\(key)") { return t("app.process.drawer.step_short.\(key)") }
        if key == "ocr" { return t("app.process.drawer.step.ocr", ["n": ocrParams.multiVariant ? 3 : 1]) }
        return localizer.has("app.process.drawer.step.\(key)") ? t("app.process.drawer.step.\(key)") : stepName(key)
    }

    /// "00:34", "< 1 s".
    func stepTimeText(_ seconds: Double) -> String {
        seconds < 1 ? t("app.process.drawer.under_second") : Localizer.clock(seconds)
    }

    /// "18,4 MB", "1,24 GB".
    func diskText(_ bytes: Int64) -> String {
        let b = Double(bytes)
        if b >= 1_000_000_000 { return "\(localizer.number(b / 1_000_000_000, decimals: 2)) GB" }
        if b >= 1_000_000 { return "\(localizer.number(b / 1_000_000, decimals: 1)) MB" }
        return "\(localizer.number(max(b / 1000, 1), decimals: 0)) kB"
    }

    /// "H.264 · AAC" from ffprobe's names.
    func codecText(_ video: VideoItem) -> String? {
        let parts = [video.videoCodec, video.audioCodec].compactMap { $0 }.map(Self.codecName)
        return parts.isEmpty ? nil : join(parts)
    }

    static func codecName(_ name: String) -> String {
        let known = ["h264": "H.264", "hevc": "HEVC", "h265": "HEVC", "av1": "AV1", "vp9": "VP9", "vp8": "VP8",
                     "mpeg4": "MPEG-4", "mpeg2video": "MPEG-2", "prores": "ProRes", "aac": "AAC", "ac3": "AC-3",
                     "eac3": "E-AC-3", "mp3": "MP3", "opus": "Opus", "flac": "FLAC", "vorbis": "Vorbis",
                     "truehd": "TrueHD", "dts": "DTS", "alac": "ALAC", "pcm_s16le": "PCM", "pcm_s24le": "PCM"]
        return known[name.lowercased()] ?? name.uppercased()
    }

    /// "23,976" or "24": the language's separators, no trailing zeros (the list's column).
    func listFPSText(_ fps: Double) -> String {
        let rounded = (fps * 1000).rounded() / 1000
        return localizer.number(rounded, decimals: rounded == rounded.rounded() ? 0 : 3)
    }

    /// A sentence of the catalogue with `{name}` in mono, the rest as it is.
    func sentence(_ key: String, name: String, font: CGFloat = 12, color: Color = SV.text) -> Text {
        let marker = "\u{1}"
        let parts = t(key, ["name": marker]).components(separatedBy: marker)
        var text = Text(verbatim: parts.first ?? "").font(.system(size: font)).foregroundStyle(color)
        if parts.count > 1 {
            text = Text("\(text)\(Text(verbatim: name).font(.system(size: font - 0.5, design: .monospaced)).foregroundStyle(color))\(Text(verbatim: parts[1]).font(.system(size: font)).foregroundStyle(color))")
        }
        return text
    }
}

// MARK: - To do (C3-02, C3-03)

struct TodoDrawer: View {
    @Environment(AppModel.self) private var model
    var video: VideoItem
    var narrow: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if narrow {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 24) { known; reads }
                    srt
                }
            } else {
                HStack(alignment: .top, spacing: 28) {
                    known.frame(width: 200, alignment: .leading)
                    reads.frame(width: 290, alignment: .leading)
                    srt.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            FromPreview(video: video, narrow: narrow)
                .padding(.top, 12)
                .overlay(alignment: .top) { Rectangle().fill(SV.detailLine).frame(height: 1) }
        }
    }

    /// «Il video»: what ffprobe said when it entered the list, "—" until then.
    private var known: some View {
        let dash = "—"
        return VStack(alignment: .leading, spacing: 0) {
            DrawerHeading(text: model.t("app.process.drawer.video"))
            KeyValues(rows: [
                .init(key: model.t("app.process.drawer.duration"), value: video.duration.map(Localizer.clock) ?? dash),
                .init(key: model.t("app.process.drawer.frames"),
                      value: video.fps.map { model.t("app.process.drawer.fps", ["fps": model.listFPSText($0)]) } ?? dash),
                .init(key: model.t("app.process.drawer.size"), value: video.size ?? dash),
                .init(key: model.t("app.process.drawer.codec"), value: model.codecText(video) ?? dash),
                .init(key: model.t("app.process.drawer.disk"), value: video.bytes.map(model.diskText) ?? dash),
            ])
        }
    }

    /// «Cosa leggerà»: the bands and the language of the parameters of now, and the estimate.
    private var reads: some View {
        let p = model.ocrParams
        let readings = p.multiVariant ? 3 : 1
        return VStack(alignment: .leading, spacing: 0) {
            DrawerHeading(text: model.t("app.process.drawer.reads"))
            bandLine(swatch: AnyView(DrawerSwatch(band: "bottom")), model.t("app.steps.band.dialogue"),
                     model.t("app.process.drawer.dialogue_where", ["pct": p.bottomKeepPct]))
            bandLine(swatch: AnyView(DrawerSwatch(band: "top", on: p.topBand)), model.t("app.steps.band.signs"),
                     p.topBand ? model.t("app.process.drawer.signs_where", ["pct": p.topKeepPct]) : model.t("app.process.drawer.signs_off"))
            // The texts on one baseline, the symbol on the middle of their capitals.
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: "character.bubble").font(.system(size: 10.5)).foregroundStyle(SV.text3).frame(width: 9)
                    .svOnCapsMiddle(12)
                Text(model.t("app.process.drawer.language")).svFont(12).foregroundStyle(SV.text)
                Text("· \(model.languageName(p.langHint))").svFont(12).foregroundStyle(SV.text3)
                Text(p.langHint).svFont(11, mono: true).foregroundStyle(SV.text3)
            }
            .frame(height: 22)
            estimateLine(fps: p.fps, readings: readings)
                .padding(.top, 6)
        }
    }

    private func bandLine(swatch: AnyView, _ name: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            swatch.svOnCapsMiddle(12)
            Text(name).svFont(12).foregroundStyle(SV.text)
            Text(detail).svFont(12).foregroundStyle(SV.text3).lineLimit(1)
        }
        .frame(height: 22)
    }

    /// "Stima con i parametri attuali: **circa 01:16** · 12 fps, 3 letture".
    private func estimateLine(fps: Double, readings: Int) -> some View {
        let lead = Text(model.t("app.process.drawer.estimate") + " ").foregroundStyle(SV.text2)
        let about = Text(model.estimate(video).map { model.t("app.process.row.about", ["t": Localizer.clock($0)]) } ?? "—")
            .fontWeight(.semibold).foregroundStyle(SV.text)
        let tail = Text(model.t("app.common.list_separator")
                        + model.tn("app.process.drawer.estimate_tail", readings, ["fps": model.listFPSText(fps)])).foregroundStyle(SV.text2)
        return Text("\(lead)\(about)\(tail)").font(.system(size: 12)).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
    }

    /// «SRT»: none yet (and its name), or the one already there in yellow (C3-03).
    private var srt: some View {
        VStack(alignment: .leading, spacing: 0) {
            DrawerHeading(text: model.t("app.process.drawer.srt"))
            if video.srtExists {
                let title = Text(model.t("app.process.drawer.srt_exists") + " ").font(.system(size: 12, weight: .semibold)).foregroundStyle(SV.yellowText)
                Text("\(title)\(model.sentence("app.process.drawer.srt_exists_text", name: video.srtURL.lastPathComponent, color: SV.yellowText))")
                    .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            } else {
                model.sentence("app.process.drawer.srt_none", name: video.srtURL.lastPathComponent)
                    .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The frames under a to-do drawer. «Dall'Anteprima»: five of the frames the Preview found,
/// the count and Open the Preview (C3-02, C3-03). Before the Preview ran, «Fotogrammi del
/// video»: five frames taken as the video entered the list (`AppModel+VideoFrames.swift`),
/// shimmering while they are taken; empty boxes when they could not be. A click on a frame
/// opens the Preview (on that frame, for the Preview's own).
struct FromPreview: View {
    @Environment(AppModel.self) private var model
    var video: VideoItem
    var narrow: Bool

    var body: some View {
        let strip = model.drawerStrip(video)
        HStack(spacing: 12) {
            // The texts' capitals on the middle of the frames and the button (the line boxes of
            // `svFont` put them half a point low).
            DrawerHeading(text: model.t(heading(strip))).padding(.bottom, -6)
                .svBaseline(ofCentred: 10.5)
            HStack(spacing: 6) {
                switch strip {
                case .preview(let result):
                    ForEach(Array(shown(result).enumerated()), id: \.offset) { _, item in
                        frameButton(index: item.index) { thumb(item.image, frame: item.frame) }
                    }
                case .video(let images):
                    ForEach(0..<VideoFramesState.count, id: \.self) { i in
                        if let image = images.indices.contains(i) ? images[i] : nil {
                            frameButton(index: nil) { videoThumb(image) }
                        } else {
                            emptyBox
                        }
                    }
                case .extracting:
                    ForEach(0..<VideoFramesState.count, id: \.self) { i in ShimmerBox(delay: Double(i) * 0.12) }
                case .none:
                    ForEach(0..<VideoFramesState.count, id: \.self) { _ in emptyBox }
                }
            }
            if !narrow {
                Text(caption(strip)).svFont(12).foregroundStyle(SV.text2).lineLimit(1)
                    .svBaseline(ofCentred: 12)
            }
            Spacer(minLength: 0)
            if case .preview = strip {
                Button { model.openInPreview(video.id) } label: { Label(model.t("app.process.drawer.open_preview"), systemImage: "viewfinder") }
                    .svButton(.secondary, .small)
                    .disabled(!model.canPreview(video))
                    .help(model.t("app.process.row.preview_help"))
            } else {
                Button { model.openInPreview(video.id) } label: { Label(model.t("app.process.row.preview"), systemImage: "viewfinder") }
                    .svButton(.secondary, .small)
                    .disabled(!model.canPreview(video))
                    .help(model.t("app.process.drawer.preview_help"))
            }
        }
    }

    private func heading(_ strip: DrawerStrip) -> String {
        switch strip {
        case .preview, .none: "app.process.drawer.from_preview"
        case .video, .extracting: "app.process.drawer.video_frames"
        }
    }

    /// "20 fotogrammi · 17 con testo", "L'Anteprima ne cerca 20 con il testo", "Nessun fotogramma ancora".
    private func caption(_ strip: DrawerStrip) -> String {
        switch strip {
        case .preview(let result): model.t("app.process.drawer.frames_found", ["n": result.frames.count, "k": result.found])
        case .video, .extracting: model.t("app.process.drawer.video_frames_note", ["n": PreviewState.zones])
        case .none: model.t("app.process.drawer.no_frames")
        }
    }

    /// A frame that opens the Preview: on that frame (`index`, among the Preview's), or on the video.
    private func frameButton<Content: View>(index: Int?, @ViewBuilder _ content: () -> Content) -> some View {
        Button { model.openPreview(video.id, frame: index) } label: { content() }
            .buttonStyle(.plain)
            .disabled(!model.canPreview(video))
            .help(model.t(index == nil ? "app.process.drawer.preview_help" : "app.process.row.preview_help"))
    }

    private var emptyBox: some View {
        RoundedRectangle(cornerRadius: 4).strokeBorder(SV.glassLine, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            .frame(width: 64, height: 36)
    }

    /// Five frames, the ones with text first, in their order; `index` is the frame's among all.
    private func shown(_ result: PreviewState.Result) -> [(index: Int, frame: PreviewFrame, image: NSImage?)] {
        let all = result.frames.enumerated().map { (index: $0.offset, frame: $0.element, image: result.thumbnail($0.offset)) }
        let withText = all.filter(\.frame.hasText), without = all.filter { !$0.frame.hasText }
        return Array((withText + without).prefix(5))
    }

    private func thumb(_ image: NSImage?, frame: PreviewFrame) -> some View {
        ZStack(alignment: .bottomTrailing) {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 64, height: 36).clipped()
                    .opacity(frame.hasText ? 1 : 0.5)
            } else {
                Rectangle().fill(SV.raised)
            }
            HStack(spacing: 2) {
                if frame.hasDialogue { Circle().fill(SV.green).frame(width: 5, height: 5) }
                if frame.hasSigns { Circle().fill(signsBlue).frame(width: 5, height: 5) }
            }
            .padding(2)
        }
        .frame(width: 64, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(SV.line))
        .contentShape(Rectangle())
    }

    /// A frame of the video: no dots (nobody has looked for text in it yet).
    private func videoThumb(_ image: NSImage) -> some View {
        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            .frame(width: 64, height: 36).clipped()
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(SV.line))
            .contentShape(Rectangle())
    }
}

/// A box of the strip while the video's frames are taken: a soft light that sweeps across
/// it; still, as a plain box, with Reduce Motion.
private struct ShimmerBox: View {
    var delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: 4).fill(SV.raised)
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, SV.glassLine, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.8)
                            .offset(x: phase * geo.size.width * 1.4)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(SV.line))
            .frame(width: 64, height: 36)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false).delay(delay)) { phase = 1 }
            }
    }
}

// MARK: - Done (C3-03, E3)

/// The time of each step as a table, the result, the files.
struct DoneDrawer: View {
    @Environment(AppModel.self) private var model
    var video: VideoItem

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            if let times = video.times, !times.isEmpty {
                TimesTable(video: video, times: times)
                    .frame(width: 330, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 14) {
                result
                files
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var result: some View {
        VStack(alignment: .leading, spacing: 0) {
            DrawerHeading(text: model.t("app.process.drawer.result"))
            KeyValues(rows: resultRows)
            if let gaps = video.gaps, !gaps.isEmpty {
                Text(gapLine(gaps)).svFont(12).foregroundStyle(SV.yellowText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
        }
    }

    private var resultRows: [KeyValues.Row] {
        let n = video.segments ?? 0
        let dropped = video.dropped ?? 0
        var rows = [KeyValues.Row(key: model.t("app.process.drawer.lines"),
                                  value: dropped > 0 ? model.tn("app.process.drawer.lines_dropped", dropped, ["n": n, "d": dropped])
                                                     : model.t("app.process.drawer.lines_none_dropped", ["n": n]))]
        if let refined = video.refined {
            rows.append(.init(key: model.t("app.process.drawer.refined"), value: "\(refined)"))
        }
        var took: [String] = []
        if let elapsed = video.elapsed { took.append(Localizer.clock(elapsed)) }
        if let lang = video.ocrLang { took.append(model.languageName(lang)) }
        if let fps = video.ocrFPS { took.append(model.t("app.process.drawer.fps", ["fps": model.listFPSText(fps)])) }
        if !took.isEmpty { rows.append(.init(key: model.t("app.process.drawer.took"), value: model.join(took))) }
        return rows
    }

    /// "3 buchi oltre 3 s: 00:00 → 00:03 · 00:41 → 00:44 · 00:51 → 00:55" (the ranges up to three).
    private func gapLine(_ gaps: [[Double]]) -> String {
        let seconds = model.localizer.number(video.gapWarn ?? model.ocrParams.qcGapWarn)
        let head = model.tn("app.process.drawer.gaps", gaps.count, ["s": seconds])
        guard gaps.count <= 3 else { return head }
        let ranges = gaps.filter { $0.count == 2 }.map { "\(Localizer.clock($0[0].rounded(.down))) → \(Localizer.clock($0[1].rounded(.up)))" }
        return head + ": " + model.join(ranges)
    }

    private var files: some View {
        VStack(alignment: .leading, spacing: 0) {
            DrawerHeading(text: model.t("app.process.drawer.files"))
            KeyValues(rows: fileRows)
            HStack(spacing: 8) {
                Button { model.showInFinder([video.id]) } label: { Label(model.t("app.common.show_in_finder"), systemImage: "macwindow") }
                    .svButton(.secondary, .small)
                    .disabled(!video.exists)
                Button { model.openSRT(video) } label: { Label(model.t("app.process.drawer.open_srt"), systemImage: "doc") }
                    .svButton(.secondary, .small)
                    .disabled(!FileManager.default.fileExists(atPath: video.outputSRT.path))
                Button { model.openLog(video) } label: { Label(model.t("app.process.row.open_log"), systemImage: "list.bullet.rectangle") }
                    .svButton(.secondary, .small)
                    .disabled(!video.logExists)
            }
            .padding(.top, 10)
        }
    }

    private var fileRows: [KeyValues.Row] {
        var rows: [KeyValues.Row] = []
        if FileManager.default.fileExists(atPath: video.outputSRT.path) || video.state == .done {
            rows.append(.init(key: model.t("app.process.drawer.srt"), value: video.outputSRT.lastPathComponent, mono: true))
        }
        if let report = video.outputReport {
            rows.append(.init(key: model.t("app.process.drawer.report"), value: report.lastPathComponent, mono: true))
        }
        rows.append(.init(key: model.t("app.process.drawer.log"), value: video.outputLog.lastPathComponent, mono: true))
        return rows
    }
}

/// «Tempo di ogni tappa» (C3-03): Tappa · Dialoghi · Cartelli, the numbers aligned, a Total row.
struct TimesTable: View {
    @Environment(AppModel.self) private var model
    var video: VideoItem
    var times: [String: Double]

    var body: some View {
        let plan = video.plan ?? Array(times.keys).sorted()
        let (keys, bands) = model.planKeys(plan)
        VStack(alignment: .leading, spacing: 0) {
            DrawerHeading(text: model.t("app.process.drawer.times"))
            row(height: 22) {
                Text(model.t("app.process.drawer.step").uppercased()).svFont(10.5, .semibold).foregroundStyle(SV.text3).tracking(0.4)
            } values: {
                ForEach(bands, id: \.self) { band in
                    Text(model.bandName(band).uppercased()).svFont(10.5, .semibold).foregroundStyle(SV.text3).tracking(0.4)
                }
            }
            ForEach(keys, id: \.self) { key in
                row(height: 24) {
                    Text(model.tableStepName(key)).svFont(12).foregroundStyle(SV.text).lineLimit(1)
                } values: {
                    ForEach(bands, id: \.self) { band in
                        Text(times["\(key):\(band)"].map(model.stepTimeText) ?? "—").svFont(11.5, mono: true).foregroundStyle(SV.textCode)
                    }
                }
            }
            row(height: 24, line: false) {
                Text(model.t("app.process.drawer.total")).svFont(12, .semibold).foregroundStyle(SV.text)
            } values: {
                ForEach(bands, id: \.self) { band in
                    let total = keys.compactMap { times["\($0):\(band)"] }.reduce(0, +)
                    Text(model.stepTimeText(total)).svFont(11.5, .semibold, mono: true).foregroundStyle(SV.text)
                }
            }
        }
    }

    private func row<Label: View, Values: View>(height: CGFloat, line: Bool = true, @ViewBuilder label: () -> Label,
                                                 @ViewBuilder values: () -> Values) -> some View {
        HStack(spacing: 0) {
            label().frame(maxWidth: .infinity, alignment: .leading)
            Group(subviews: values()) { cells in
                ForEach(cells) { cell in cell.frame(width: 84, alignment: .trailing) }
            }
        }
        .frame(height: height)
        .overlay(alignment: .bottom) { if line { Rectangle().fill(SV.detailLine).frame(height: 1) } }
    }
}

// MARK: - Steps by band: running (C3-04, N1) and failed (C3-05)

/// The steps of the file in progress, or of a failed or stopped one, by band: a bar and a state
/// in each cell (bars 140 pt; 56 in a narrow window and beside the failure's text).
struct StepsTable: View {
    @Environment(AppModel.self) private var model
    var video: VideoItem
    var narrow: Bool
    /// The full step names even with the narrow columns (beside the failure's text, C3-05).
    var longNames = false

    private var steps: [StepRun] { video.state == .running ? model.run.steps : model.stoppedSteps(video) }
    private var failed: Bool { video.state != .running }

    var body: some View {
        let steps = steps
        let (keys, bands) = model.planKeys(steps.map(\.id))
        let labelWidth: CGFloat = narrow && !longNames ? 136 : 150
        let gap: CGFloat = narrow ? 12 : 18
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: gap) {
                header(Text(model.t("app.process.drawer.step").uppercased())).frame(width: labelWidth, alignment: .leading)
                ForEach(bands, id: \.self) { band in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        DrawerSwatch(band: band).svOnCapsMiddle(10.5)
                        header(Text(model.bandName(band).uppercased()))
                    }
                    .frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22, alignment: .leading)
                    .overlay(alignment: .bottom) { line }
                }
            }
            .overlay(alignment: .bottomLeading) { line.frame(width: labelWidth) }
            ForEach(keys, id: \.self) { key in
                HStack(spacing: gap) {
                    Text(model.tableStepName(key, narrow: narrow && !longNames)).svFont(12).foregroundStyle(SV.text).lineLimit(1)
                        .frame(width: labelWidth, height: 24, alignment: .leading)
                        .overlay(alignment: .bottom) { line }
                    ForEach(bands, id: \.self) { band in
                        let step = steps.first { $0.id == "\(key):\(band)" }
                        StepCell(step: step, failedRow: failed, stoppedRow: video.state == .stopped, barWidth: narrow ? 56 : 140)
                            .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24, alignment: .leading)
                            .overlay(alignment: .bottom) { line }
                    }
                }
            }
        }
    }

    private func header(_ text: Text) -> some View {
        text.font(.system(size: 10.5, weight: .semibold)).foregroundStyle(SV.text3).tracking(0.4).lineLimit(1)
    }

    private var line: some View { Rectangle().fill(SV.detailLine).frame(height: 1) }
}

extension AppModel {
    /// A failed or stopped row's steps from its plan and `atStep`: done before, aborted there, not run after.
    func stoppedSteps(_ video: VideoItem) -> [StepRun] {
        guard let plan = video.plan else { return [] }
        var seen = false
        return plan.map { id in
            let parts = id.split(separator: ":").map(String.init)
            var s = StepRun(key: parts.first ?? id, band: parts.count > 1 ? parts[1] : "bottom")
            if id == video.atStep { s.state = .aborted; seen = true; s.ratio = 0.35 }
            else if seen || video.atStep == nil { s.state = .notRun }
            else { s.state = .done; s.ratio = 1 }
            if let t = video.times?[id] { s.duration = t; s.elapsed = t }
            return s
        }
    }
}

/// One cell of the steps table: the icon, the bar, the state ("00:01", "412 / 756 · ETA 00:16",
/// "circa 00:05", "interrotta qui", "non eseguita").
struct StepCell: View {
    @Environment(AppModel.self) private var model
    var step: StepRun?
    var failedRow: Bool
    /// Stopped by the person, not failed: the step where it stopped in lilac, with the hand (boards E3, E5).
    var stoppedRow = false
    var barWidth: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            icon.frame(width: 14, height: 14)
            SVBar(fraction, height: 4, fill: fill, track: SV.trackSoft).frame(width: barWidth)
            Text(text).svFont(11, mono: true).foregroundStyle(color).lineLimit(1)
        }
        .help(step.map { model.stepLabel($0.id) } ?? "")
    }

    private var state: StepRun.State { step?.state ?? (failedRow ? .notRun : .waiting) }

    @ViewBuilder private var icon: some View {
        switch state {
        case .done: Image(systemName: "checkmark").svFont(10, .bold).foregroundStyle(SV.greenText)
        case .running: Spinner(size: 11)
        case .aborted:
            if stoppedRow { Image(systemName: "hand.raised").svFont(10, .semibold).foregroundStyle(SV.stopped) }
            else { Image(systemName: "xmark").svFont(10, .bold).foregroundStyle(SV.redText) }
        case .waiting: Circle().strokeBorder(SV.glassLine).frame(width: 9, height: 9)
        case .notRun: Circle().strokeBorder(SV.glassLine, style: StrokeStyle(lineWidth: 1, dash: [2, 1.5])).frame(width: 9, height: 9)
        }
    }

    private var fraction: Double {
        switch state {
        case .done: 1
        case .running: step?.ratio ?? 0
        case .aborted: max(step?.ratio ?? 0, 0.08)
        case .waiting, .notRun: 0
        }
    }

    private var fill: Color {
        switch state {
        case .done: SV.green
        case .running: SV.primary
        case .aborted: stoppedRow ? SV.stopped : SV.red
        case .waiting, .notRun: SV.track
        }
    }

    private var color: Color {
        switch state {
        case .running: SV.text
        case .aborted: stoppedRow ? SV.stopped : SV.redText
        case .waiting, .notRun: SV.text3
        case .done: SV.text2
        }
    }

    private var text: String {
        guard let step else { return model.t(failedRow ? "app.steps.not_run" : "app.steps.waiting") }
        let l = model.localizer
        switch state {
        case .done: return model.stepTimeText(step.duration ?? step.elapsed)
        case .running:
            let done = l.number(Double(step.count)), total = l.number(Double(step.total))
            guard step.total > 0 else { return "…" }
            if let eta = step.eta, barWidth > 100 {
                return model.t("app.process.drawer.running", ["done": done, "total": total, "eta": Localizer.clock(eta)])
            }
            return "\(done) / \(total)"
        case .waiting:
            if let e = step.estimate, e >= 1 { return model.t("app.process.row.about", ["t": Localizer.clock(e)]) }
            return model.t("app.steps.waiting")
        case .aborted: return model.t(stoppedRow ? "app.steps.stopped_here" : "app.steps.aborted")
        case .notRun: return model.t("app.steps.not_run")
        }
    }
}

// MARK: - Failed and stopped (C3-05)

struct FailedDrawer: View {
    @Environment(AppModel.self) private var model
    var video: VideoItem
    var narrow: Bool

    var body: some View {
        if narrow {
            VStack(alignment: .leading, spacing: 14) {
                if video.plan != nil { StepsTable(video: video, narrow: true) }
                story
            }
        } else {
            HStack(alignment: .top, spacing: 28) {
                if video.plan != nil {
                    StepsTable(video: video, narrow: true, longNames: true).frame(maxWidth: .infinity, alignment: .leading)
                }
                story.frame(width: video.plan != nil ? 290 : nil, alignment: .leading)
                    .frame(maxWidth: video.plan != nil ? nil : .infinity, alignment: .leading)
            }
        }
    }

    /// «Cosa è successo» in plain words, the technical line small in red mono, the log and Finder.
    private var story: some View {
        VStack(alignment: .leading, spacing: 0) {
            DrawerHeading(text: model.t("app.process.drawer.what_happened"), color: video.state == .failed ? SV.redText : SV.text3)
            Text(plain).svFont(12.5).foregroundStyle(SV.text).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            if video.state == .failed, let detail = video.errorDetail {
                Text(detail).svFont(11, mono: true).foregroundStyle(SV.redText).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .svBox(RoundedRectangle(cornerRadius: 6), fill: SV.bg, line: SV.line,
                           padding: EdgeInsets(vertical: 6, horizontal: 8))
                    .padding(.top, 8)
            }
            HStack(spacing: 8) {
                Button { model.openLog(video) } label: { Label(model.t("app.process.row.open_log"), systemImage: "list.bullet.rectangle") }
                    .svButton(.secondary, .small)
                    .disabled(!video.logExists)
                Button { model.showInFinder([video.id]) } label: { Label(model.t("app.common.show_in_finder"), systemImage: "macwindow") }
                    .svButton(.secondary, .small)
                    .disabled(!video.exists)
            }
            .padding(.top, 10)
        }
    }

    private var plain: String {
        if video.state == .stopped {
            return model.t("app.process.drawer.stopped_text", ["step": model.stepPhrase(video.atStep), "band": model.bandPhrase(video.atStep)])
        }
        var first = model.rowFailedText(video).trimmingCharacters(in: .whitespaces)
        if let last = first.last, !".!?".contains(last) { first += "." }
        return model.t("app.process.drawer.failed_text", ["error": first])
    }
}

// MARK: - Unreadable (E7)

struct UnreadableDrawer: View {
    @Environment(AppModel.self) private var model
    var video: VideoItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DrawerHeading(text: model.t("app.process.drawer.what_happened"), color: SV.redText)
            Text(model.t("app.process.drawer.unreadable_text")).svFont(12.5).foregroundStyle(SV.text)
                .fixedSize(horizontal: false, vertical: true)
            if let problem = video.problem, !problem.isEmpty {
                Text(problem).svFont(11, mono: true).foregroundStyle(SV.redText).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .svBox(RoundedRectangle(cornerRadius: 6), fill: SV.bg, line: SV.line,
                           padding: EdgeInsets(vertical: 6, horizontal: 8))
                    .padding(.top, 8)
            }
            Button { model.showInFinder([video.id]) } label: { Label(model.t("app.common.show_in_finder"), systemImage: "macwindow") }
                .svButton(.secondary, .small)
                .disabled(!video.exists)
                .padding(.top, 10)
        }
        .frame(maxWidth: 520, alignment: .leading)
    }
}
