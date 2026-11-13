// SPDX-License-Identifier: MIT
// Preview (design boards A1–A6, D6): the video chosen from the list, Find 20
// Frames with its progress and Stop, the frame with the two bands and their
// handles, the arrows, the badge, the strip of thumbnails, Try OCR with the
// two panels, read-only during the batch. The inspector is the same as on
// Process (design note 1).

import AppKit
import SVShell
import SwiftUI

/// The empty state (A0) until a video is in the list, then the page.
struct PreviewPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.videos.isEmpty {
            PreviewEmptyView()
        } else {
            PreviewView()
        }
    }
}

struct PreviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.svPageTop) private var top
    @Environment(\.svChrome) private var chrome
    @Environment(\.svWindowWidth) private var windowWidth

    var body: some View {
        @Bindable var model = model
        InspectorSplit(isOpen: $model.inspectorOpen) {
            page
        } inspector: {
            InspectorView()
        }
    }

    /// A narrow window: the title alone, the inspector button in the top bar (board N1).
    private var compact: Bool { windowWidth < chrome.collapseBelow }

    /// The intro shows while there is nothing else to look at (A1, A2).
    private var showsIntro: Bool { !compact && model.previewResult == nil }

    private var page: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageTop(title: model.t("app.preview.title"), intro: showsIntro ? model.t("app.preview.intro") : nil,
                    introBelow: model.inspectorOpen) {
                PreviewVideoMenu()
                if !model.isSearchingFrames {
                    findButton
                }
                if !compact { InspectorButton() }
            }
            .padding(.bottom, 18)
            notes
            content
        }
        .padding(.horizontal, 28)
        .padding(.top, top)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { model.loadFrameImage() }
        // The inspector or the handles changed a value: the test, if any, is older than it.
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            model.refreshPreviewStale()
        }
    }

    /// "Find 20 Frames" (primary) the first time, "Find Again" (secondary) after (A1, A3).
    private var findButton: some View {
        let again = model.previewResult != nil
        return Button { model.findFrames() } label: {
            Label(model.t(again ? "app.preview.find_again" : "app.preview.find"), systemImage: "magnifyingglass")
        }
        .svButton(again ? .secondary : .primary, .regular)
        .fixedSize()
        .disabled(!model.canFindFrames)
        .help(model.t("app.preview.find_help"))
    }

    // MARK: - Notes

    @ViewBuilder
    private var notes: some View {
        if model.batch.running {
            NoteView(.accent, text: model.t("app.preview.readonly"))
                .padding(.bottom, 18)
        }
        if case .failed(let code, let message) = model.preview.search {
            NoteView(.red, text: model.previewErrorText(code: code, message: message)) {
                Button { model.preview.search = .idle } label: {
                    Image(systemName: "xmark").svFont(11, .semibold).frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(model.t("app.common.dismiss"))
            }
            .padding(.bottom, 18)
        }
        if let result = model.previewResult, !result.frames.isEmpty, result.found == 0, !model.isSearchingFrames {
            NoteView(.yellow, text: model.t("app.preview.none_found")) {
                Button(model.t("app.process.show_inspector")) { model.toggleInspector() }
                    .buttonStyle(SVTintedButtonStyle(.yellow))
            }
            .padding(.bottom, 18)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if case .running(let done, let total, let found) = model.preview.search {
            searching(done: done, total: total, found: found)
        } else if let result = model.previewResult, !result.frames.isEmpty {
            FrameViewer(result: result)
        } else {
            placeholder
        }
    }

    /// A1: the empty frame box; A5: "Preview not available" after a failure.
    private var placeholder: some View {
        let failed: Bool = { if case .failed = model.preview.search { return true }; return false }()
        return VStack(spacing: 8) {
            Image(systemName: "viewfinder").svFont(failed ? 22 : 40, .light)
            Text(model.t(failed ? "app.preview.unavailable" : "app.preview.placeholder")).svFont(failed ? 12 : 13)
        }
        .foregroundStyle(SV.text3)
        .frame(maxWidth: 940, maxHeight: 400)
        .background(RoundedRectangle(cornerRadius: SV.Radius.field).fill(SV.surface))
        .overlay(RoundedRectangle(cornerRadius: SV.Radius.field).strokeBorder(SV.line))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A2: the bar of the search with Stop, and what the search does.
    private func searching(done: Int, total: Int, found: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Spinner(size: 14)
                Text(model.t("app.preview.searching", ["i": done, "n": total, "k": found])).svFont(13, .semibold).foregroundStyle(SV.text)
                Spacer(minLength: 8)
                Button { model.stopFrames() } label: { Label(model.t("app.common.stop"), systemImage: "stop.fill") }
                    .svButton(.secondary, .small)
            }
            SVBar(total > 0 ? Double(done) / Double(total) : 0)
            Text(model.t("app.preview.find_help")).svSmall().fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// "Video" and the menu of the list's videos (the chosen one checked); off
/// while a search runs or during the batch.
struct PreviewVideoMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            Text(model.t("app.preview.video")).svSmall()
            PopupMenu({
                model.videos.map { video in
                    .item(video.name, checked: video.id == model.previewVideo?.id, enabled: video.state == .ready && video.exists) {
                        model.selectPreviewVideo(video.id)
                    }
                }
            }) {
                PopupLabel(title: model.previewVideo?.name ?? "", width: 250)
            }
            .fixedSize()
            .disabled(model.isSearchingFrames || model.batch.running)
        }
        .fixedSize()
    }
}

/// A3, A4, A6: the frame with its bands between the arrows, the caption with
/// the badge, the strip, the summary and Try OCR; with a test, the panels
/// under a smaller frame (A4).
struct FrameViewer: View {
    @Environment(AppModel.self) private var model
    var result: PreviewState.Result

    private static let navWidth: CGFloat = 30 + 14
    /// Caption, strip, summary and the Try OCR button under the frame (A3).
    private static let underFrame: CGFloat = 12 + 20 + 10 + 18 + 6 + 18 + 16 + 28
    private static let testFrameWidth: CGFloat = 560
    /// The frame never grows past the box of board A1.
    private static let maxFrameWidth: CGFloat = 940

    private var frame: PreviewFrame? { result.frames.indices.contains(result.index) ? result.frames[result.index] : nil }
    private var aspect: CGFloat {
        guard let frame, frame.width > 0, frame.height > 0 else { return 16 / 9 }
        return CGFloat(frame.width) / CGFloat(frame.height)
    }

    var body: some View {
        GeometryReader { g in
            if let test = model.preview.test {
                withPanels(test, in: g.size)
            } else {
                browsing(in: g.size)
            }
        }
    }

    // MARK: A3 / A6

    private func browsing(in size: CGSize) -> some View {
        let width = min(Self.maxFrameWidth, size.width - 2 * Self.navWidth, max(200, (size.height - Self.underFrame) * aspect))
        let small = size.width < 20 * 48 + 2 * Self.navWidth
        return VStack(spacing: 0) {
            HStack(spacing: 14) {
                navButton(previous: true)
                FrameBox(frame: frame, width: width, aspect: aspect)
                navButton(previous: false)
            }
            caption.padding(.top, 12)
            strip(small: small).padding(.top, 10)
            Text(model.t("app.preview.summary", ["n": result.frames.count, "k": result.found, "m": result.frames.count - result.found]))
                .svSmall().padding(.top, 6)
            // At the foot of the page, as on board A3 (note 22).
            Spacer(minLength: 16)
            tryButton(primary: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { model.previousFrame(); return .handled }
        .onKeyPress(.rightArrow) { model.nextFrame(); return .handled }
    }

    // MARK: A4 / A5

    private func withPanels(_ test: PreviewState.Test, in size: CGSize) -> some View {
        let narrow = size.width < 760
        let column: CGFloat = narrow ? 0 : 300
        let width = max(240, min(Self.testFrameWidth, size.width - 2 * Self.navWidth - column))
        return ScrollView {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 14) {
                    navButton(previous: true)
                    FrameBox(frame: frame, width: width, aspect: aspect)
                    navButton(previous: false)
                    if !narrow {
                        VStack(alignment: .leading, spacing: 8) {
                            if let frame {
                                Text(model.frameCaption(frame, index: result.index, count: result.frames.count))
                                    .svFont(12, mono: true).foregroundStyle(SV.text2)
                                badge(frame)
                            }
                            tryButton(primary: false)
                        }
                        .padding(.leading, 12)
                        .frame(width: column - 26, alignment: .leading)
                    }
                }
                if narrow {
                    caption.padding(.top, 12)
                    tryButton(primary: false).padding(.top, 10)
                }
                OcrTestPanels(test: test, stale: model.preview.stale, narrow: size.width < 700)
                    .padding(.top, 18)
            }
            .frame(maxWidth: .infinity)
        }
        .scrollClipDisabled()
    }

    // MARK: Pieces

    private func navButton(previous: Bool) -> some View {
        Button { previous ? model.previousFrame() : model.nextFrame() } label: {
            Image(systemName: previous ? "chevron.left" : "chevron.right").svFont(13, .semibold).foregroundStyle(SV.text)
                .frame(width: 30, height: 30)
                .background(Circle().fill(SV.glass))
                .overlay(Circle().strokeBorder(SV.glassLine))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(previous ? result.index == 0 : result.index >= result.frames.count - 1)
        .opacity((previous ? result.index == 0 : result.index >= result.frames.count - 1) ? 0.45 : 1)
        .help(model.t(previous ? "app.preview.prev_frame" : "app.preview.next_frame"))
        .accessibilityLabel(model.t(previous ? "app.preview.prev_frame" : "app.preview.next_frame"))
    }

    /// "Frame 8 of 20 · 00:00:20" and the badge.
    @ViewBuilder
    private var caption: some View {
        if let frame {
            HStack(spacing: 10) {
                Text(model.frameCaption(frame, index: result.index, count: result.frames.count))
                    .svFont(12, mono: true).foregroundStyle(SV.text2)
                badge(frame)
            }
        }
    }

    /// Text in the dialogue (green), at the top (blue), none (grey).
    private func badge(_ frame: PreviewFrame) -> some View {
        switch frame.band {
        case "bottom": StatusChip(model.t("app.preview.badge_dlg"), tone: .green)
        case "top": StatusChip(model.t("app.preview.badge_sig"), tone: .accent)
        default: StatusChip(model.t("app.preview.badge_none"), tone: .neutral)
        }
    }

    /// The 20 thumbnails with a dot on the ones with text (design note 30).
    private func strip(small: Bool) -> some View {
        let w: CGFloat = small ? 32 : 42, h: CGFloat = small ? 14 : 18
        return HStack(spacing: 6) {
            ForEach(Array(result.frames.enumerated()), id: \.offset) { i, f in
                let selected = i == result.index
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let image = result.thumbnails.indices.contains(i) ? result.thumbnails[i] : nil {
                            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Rectangle().fill(SV.track)
                        }
                    }
                    .frame(width: w, height: h)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .saturation(f.hasText ? 1 : 0)
                    .opacity(f.hasText ? 1 : 0.5)
                    if f.hasText {
                        Circle().fill(f.band == "top" ? BandColors.signs : BandColors.dialogue)
                            .frame(width: 5, height: 5)
                            .padding(2)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(selected ? SV.primary : SV.line, lineWidth: selected ? 2 : 1))
                .contentShape(Rectangle())
                .onTapGesture { model.selectFrame(i) }
                .help(model.frameCaption(f, index: i, count: result.frames.count))
            }
        }
    }

    /// "Try OCR on This Frame ⌘T": primary under the strip (A3), secondary by the frame (A4).
    private func tryButton(primary: Bool) -> some View {
        Button { model.tryOCR() } label: {
            HStack(spacing: 6) {
                Label(model.t("app.preview.test"), systemImage: "magnifyingglass")
                Text(verbatim: "⌘T").svFont(10, mono: true).opacity(0.7)
            }
        }
        .svButton(primary ? .primary : .secondary, .regular)
        .disabled(!model.canTryOCR)
        .help(model.t("app.preview.test_help"))
    }
}

/// The whole frame at `width`, the bands over it; "Preview not available"
/// when the JPEG cannot be read (A5).
struct FrameBox: View {
    @Environment(AppModel.self) private var model
    var frame: PreviewFrame?
    var width: CGFloat
    var aspect: CGFloat

    var body: some View {
        @Bindable var model = model
        let size = CGSize(width: width, height: (width / aspect).rounded())
        ZStack(alignment: .topLeading) {
            if let image = model.preview.frameImage {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: SV.Radius.field))
                    .overlay(RoundedRectangle(cornerRadius: SV.Radius.field).strokeBorder(SV.line))
                BandOverlay(size: size, editable: model.canDragBands, drag: $model.preview.drag)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "viewfinder").svFont(22, .light)
                    Text(model.t("app.preview.unavailable")).svFont(12)
                }
                .foregroundStyle(SV.text3)
                .frame(width: size.width, height: size.height)
                .background(RoundedRectangle(cornerRadius: SV.Radius.field).fill(SV.surface))
                .overlay(RoundedRectangle(cornerRadius: SV.Radius.field).strokeBorder(SV.line))
            }
        }
        .frame(width: size.width, height: size.height)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.preview.frameRect = $0 }
    }
}
