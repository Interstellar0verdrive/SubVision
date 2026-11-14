// SPDX-License-Identifier: MIT
// The Preview page (design round C3, P-A; boards C3-09, A0–A6): inside
// Video, over the list, as the report is inside Review. It comes in from
// the right in 0.25 s and goes back the same way to the list as it was. The
// title band («Anteprima di» + the video's name, its details, «video 1 di 3»
// and the arrows to the video above and below), the frame block on the left
// (PreviewView.swift) and the same parameters panel as Video, on Bande,
// beside it (laid over the page in a narrow window, as the list's). View ›
// Back (⌘[) runs the band's ‹ through `AppModel.backAction`; Process has
// ⌘↑ ⌘↓ for the arrows and ⌘T, ⌘← ⌘→ for the frame; plain ← → browse the
// frames too.

import AppKit
import Combine
import SVShell
import SwiftUI

struct PreviewPage: View {
    @Environment(AppModel.self) private var model
    /// The page has slid into place (0.25 s from the right; back the same way).
    @State private var inPlace = false
    @State private var keyMonitor: Any?

    static let slide = 0.25

    var body: some View {
        @Bindable var model = model
        InspectorSplit(isOpen: $model.inspectorOpen) {
            GeometryReader { g in
                VStack(spacing: 0) {
                    PreviewTitleBand()
                    PreviewContent()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(SV.bg)
                .offset(x: inPlace ? 0 : g.size.width)
            }
            .clipped()
        } inspector: {
            // The same panel as Video's, on Bande (`openPreview`); no schema of the frame: the frame is here.
            InspectorView(place: .preview)
        }
        .onAppear {
            withAnimation(.easeOut(duration: Self.slide)) { inPlace = true }
            claimBack()
            installKeys()
            model.refreshPreviewParams()
        }
        .onDisappear {
            releaseBack()
            removeKeys()
        }
        .onChange(of: model.preview.leaving) { _, leaving in
            guard leaving else { return }
            withAnimation(.easeIn(duration: Self.slide)) { inPlace = false } completion: {
                model.closePreview()
            }
        }
        // Every change of the parameters (the panel, the handles): the test panels compare with them.
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).receive(on: RunLoop.main)) { _ in
            model.refreshPreviewParams()
        }
        // At the end of a batch, a video never searched searches by itself.
        .onChange(of: model.batch.running) { _, running in if !running { model.findFramesIfNeeded() } }
        .onChange(of: model.status) { _, _ in model.findFramesIfNeeded() }
        // The list emptied: nothing to preview.
        .onChange(of: model.videos.isEmpty) { _, empty in if empty { model.closePreview() } }
    }

    // MARK: - Back

    /// View › Back (⌘[) runs the band's ‹. Set after the other pages' appear and
    /// disappear handlers of the same change, so none of them clears it.
    private func claimBack() {
        DispatchQueue.main.async {
            guard model.previewShown else { return }
            model.backAction = { [weak model] in model?.leavePreview() }
            model.preview.backGeneration = model.backGeneration
        }
    }

    /// Cleared on the way out, unless another page has set its own since.
    private func releaseBack() {
        DispatchQueue.main.async {
            guard let mine = model.preview.backGeneration, model.backGeneration == mine else { return }
            model.preview.backGeneration = nil
            guard !model.previewShown else { return }
            model.backAction = nil
        }
    }

    // MARK: - Keys

    /// ← → browse the frames while the page is in front (not while a text field has the keys
    /// or a sheet is up); ⌘← ⌘→ are the menu's.
    private func installKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [model] event in
            guard event.keyCode == 123 || event.keyCode == 124,
                  event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
                  model.previewShown, !model.preview.leaving, model.canBrowseFrames,
                  let window = event.window, window.isMainWindow, window.attachedSheet == nil,
                  !(window.firstResponder is NSText) else { return event }
            if event.keyCode == 123 { model.previousFrame() } else { model.nextFrame() }
            return nil
        }
    }

    private func removeKeys() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}

/// C3-09: the round ‹, «Anteprima di» + the video's name, its details, then «video 1 di 3»
/// and the arrows to the video above and below in the list (⌘↑ ⌘↓ in Process).
struct PreviewTitleBand: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TitleBand(prefix: model.t("app.preview.title_prefix"), name: model.previewVideo?.name ?? "",
                  subtitle: model.previewDetails, backHelp: model.t("app.preview.back_help", ["key": model.backKey]),
                  maxContentWidth: 1000, shortcut: false, back: { model.leavePreview() }) {
            if let i = model.previewVideoIndex {
                Text(model.t("app.preview.video_of", ["i": i + 1, "n": model.videos.count]))
                    .svFont(12.5).foregroundStyle(SV.text2)
                    .padding(.trailing, 6)
            }
            arrow(-1)
            arrow(1)
        }
    }

    private func arrow(_ step: Int) -> some View {
        let help = model.t(step < 0 ? "app.preview.prev_video_help" : "app.preview.next_video_help")
        let off = model.previewNeighbour(step) == nil
        return Button { model.showNeighbourVideo(step) } label: {
            Image(systemName: step < 0 ? "chevron.up" : "chevron.down")
                .svFont(12, .semibold).foregroundStyle(SV.text)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(SV.glass))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(SV.glassLine))
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(off)
        .opacity(off ? 0.45 : 1)
        .help(help)
        .accessibilityLabel(help)
    }
}
