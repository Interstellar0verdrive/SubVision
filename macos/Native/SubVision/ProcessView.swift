// SPDX-License-Identifier: MIT
// Process, the home (design boards E0, E1, E7): the header, the notes, the
// list of videos, the drop strip and the bottom bar. The batch itself and the
// rows' outcomes come with F5.1.

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
                    // In a narrow window the top bar holds the inspector button (board N1).
                    if !compact { InspectorButton() }
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
        let home = URL(fileURLWithPath: NSHomeDirectory())
        guard let free = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage else { return nil }
        let gb = Double(free) / 1_000_000_000
        guard gb < 10 else { return nil }
        return model.t("app.process.bar.disk_low", ["free": Int(gb.rounded()), "need": 3])
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(alignment: .center, spacing: 14) {
            let ready = model.readyVideos
            Text(model.tn("app.process.bar.ready", ready.count, ["t": model.durationText(model.totalDuration)]))
                .svFont(13, .semibold).foregroundStyle(SV.text).fixedSize()
            Text(model.t("app.process.bar.outputs")).svSmall()
                .frame(maxWidth: 520, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button { model.startBatch() } label: {
                HStack(spacing: 6) {
                    Label(model.t("app.process.bar.start"), systemImage: "play.fill")
                    Text("⌘↩").svFont(10, mono: true).opacity(0.7)
                }
            }
            .svButton(.primary, .regular)
            .disabled(!model.canStart)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(SV.bg)
        .overlay(alignment: .top) { Rectangle().fill(SV.line).frame(height: 1) }
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

/// One video (E1): the status edge and ring, name with chips, folder, the
/// numbers, and what is wrong with it. Click selects, ⌘-click adds, the
/// context menu and ⌫ act on the selection.
struct VideoRow: View {
    @Environment(AppModel.self) private var model
    var video: VideoItem
    var widths: (duration: CGFloat, fps: CGFloat, size: CGFloat?, actions: CGFloat)
    @State private var hover = false

    private var selected: Bool { model.selection.contains(video.id) }
    private var missing: Bool { !video.exists }
    private var unreadable: Bool { video.state == .unreadable }
    private var dim: Bool { unreadable || missing }

    private var edge: Color {
        if unreadable { return SV.red }
        if missing { return SV.yellow }
        return SV.track
    }

    private var circle: StatusCircle.State {
        if unreadable { return .failed }
        if missing { return .warning }
        return .waiting
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            StatusCircle(circle)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(video.name).svFont(12.5, .medium).foregroundStyle(SV.text).lineLimit(2)
                    if video.srtExists {
                        StatusChip(model.t("app.process.row.srt_exists"))
                            .help(model.t("app.process.row.srt_exists_help", ["name": renamedSRT]))
                    }
                }
                Text(video.folder).svFont(11, mono: true).foregroundStyle(SV.text3).lineLimit(1).truncationMode(.middle)
                if unreadable {
                    Text(model.t("app.process.row.unreadable")).svFont(11.5).foregroundStyle(SV.redText)
                        .help(video.problem ?? "")
                } else if missing {
                    Text(model.t("app.process.row.not_found")).svFont(11.5).foregroundStyle(SV.yellowText)
                        .help(model.t("app.process.row.file_missing_help"))
                }
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
            // F5.1: the row's buttons (Stop, Open Report, ⋯).
            HStack(spacing: 6) {}
                .frame(width: widths.actions, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .padding(.leading, 13)
        .padding(.trailing, 16)
        .frame(minHeight: 52)
        .background(selected ? SV.sel : hover ? SV.hoverVeil : .clear)
        .overlay(alignment: .leading) { Rectangle().fill(edge).frame(width: 3) }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { select() }
        .contextMenu {
            Button(model.t("app.menu.show_in_finder")) { model.showInFinder([video.id]) }.disabled(missing)
            Button(model.t("app.process.row.open_in_preview")) { model.openInPreview(video.id) }.disabled(dim)
            Divider()
            Button(model.t("app.menu.remove")) { model.removeWithUndo(selected ? model.selection : [video.id]) }
        }
        .help(video.size.map { "\($0) · \(video.path)" } ?? video.path)
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
