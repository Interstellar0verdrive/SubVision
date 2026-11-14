// SPDX-License-Identifier: MIT
// The Preview window (design boards C2-A1–A3, design note 80): a window of
// its own, as HandBrake's, opened from a row's Preview button. The app's
// title row (the video's name over "Anteprima · 01:03 · 23,976 fps ·
// 2544×1440", the Video menu, Find 20 Frames), the frame block on the left
// (PreviewView.swift) and the parameters panel fixed on the right, the same
// values as the main window's. One window at a time, kept by
// `AppModel.preview.window`; AppKit lists it in the Window menu by itself.

import AppKit
import SVShell
import SwiftUI

/// The one Preview window. `isReleasedWhenClosed` is off: the model keeps the
/// controller until the window closes.
@MainActor
final class PreviewWindowController: NSWindowController, NSWindowDelegate {
    /// The board's window, and the smallest one the block still fits in.
    static let defaultSize = CGSize(width: 1280, height: 860)
    static let minSize = CGSize(width: 900, height: 640)
    static let frameName = "preview"

    unowned let model: AppModel
    var onClose: () -> Void = {}
    private var keyMonitor: Any?
    private var defaultsObserver: NSObjectProtocol?

    init(model: AppModel) {
        self.model = model
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.defaultSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        super.init(window: window)
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("preview")
        window.minSize = Self.minSize
        window.delegate = self
        let root = PreviewWindowView(setTitle: { [weak window] in window?.title = $0 })
            .environment(model)
            .environment(\.svChrome, model.config.chrome)
        let hosting = NSHostingView(rootView: root)
        // The window's own minimum only: the content's would add the title bar's height to it.
        hosting.sizingOptions = []
        window.contentView = hosting
        // The size and place of the last Preview window.
        if !window.setFrameUsingName(Self.frameName) { window.center() }
        window.setFrameAutosaveName(Self.frameName)
        watch()
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        window?.minSize = Self.minSize
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// ← → browse the frames while the window is key (not while a text field has the keys),
    /// and every change of UserDefaults (the panel here or in the main window, the handles)
    /// refreshes the parameters the test panels compare with.
    private func watch() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, event.window === window, window.attachedSheet == nil,
                  event.keyCode == 123 || event.keyCode == 124,
                  event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
                  !(window.firstResponder is NSText) else { return event }
            if event.keyCode == 123 { self.model.previousFrame() } else { self.model.nextFrame() }
            return nil
        }
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                                                  queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.refreshPreviewParams() }
        }
    }

    /// The hosting view, which must not size the window (it would add the title bar's
    /// height to the content's minimum), also clears `minSize`: the minimum is kept here.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(width: max(frameSize.width, Self.minSize.width), height: max(frameSize.height, Self.minSize.height))
    }

    func windowDidBecomeKey(_ notification: Notification) { model.preview.windowKey = true }
    func windowDidResignKey(_ notification: Notification) { model.preview.windowKey = false }

    func windowWillClose(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
        defaultsObserver = nil
        model.preview.windowKey = false
        onClose()
    }

    #if DEBUG
    /// A PNG of the window as it is on screen (`cacheDisplay` of the whole frame view).
    func capture(to path: String) -> Bool {
        guard let window, let root = window.contentView?.superview ?? window.contentView,
              let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { return false }
        root.cacheDisplay(in: root.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: URL(fileURLWithPath: path))
            AppLog.shared.info("snapshot \(path)")
            return true
        } catch {
            AppLog.shared.error("snapshot \(path) failed: \(error)")
            return false
        }
    }

    /// The window in every scheme asked (`<path>-dark.png`, `-light.png` with two), as `report-capture`.
    func capture(_ path: String, schemes: [ColorScheme]) async -> [String] {
        let saved = NSApp.appearance
        defer { NSApp.appearance = saved }
        var written: [String] = []
        for scheme in schemes {
            if schemes.count > 1 { NSApp.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua) }
            window?.displayIfNeeded()
            try? await Task.sleep(for: .milliseconds(500))
            let p = schemes.count > 1 ? SVShell.DebugSnapshot.path(path, scheme) : path
            if capture(to: p) { written.append(p) }
        }
        return written
    }
    #endif
}

/// The window's content: title row, the frame block, the parameters panel.
struct PreviewWindowView: View {
    var setTitle: (String) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.svChrome) private var chrome
    @State private var lightsAnchor: CGRect?

    /// "Anteprima · _test-1.mkv" in the Window menu.
    private var title: String {
        guard let name = model.previewVideo?.name else { return model.t("app.preview.title") }
        return model.t("app.preview.window_title", ["name": name])
    }

    var body: some View {
        VStack(spacing: 0) {
            PreviewTitleRow()
            Rectangle().fill(SV.line).frame(height: 1)
            HStack(spacing: 0) {
                PreviewContent()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                // C2-A1: always beside the block, never laid over it (no ×).
                InspectorView(place: .preview)
                    .frame(width: chrome.inspectorWidth)
                    .frame(maxHeight: .infinity)
                    .background(SV.surface)
                    .overlay(alignment: .leading) { Rectangle().fill(SV.line).frame(width: 1) }
            }
        }
        .background(SV.bg)
        .ignoresSafeArea()
        .background(WindowChrome(anchor: lightsAnchor, minSize: PreviewWindowController.minSize))
        .onPreferenceChange(TrafficLightsAnchor.self) { lightsAnchor = $0 }
        .onChange(of: title, initial: true) { setTitle(title) }
    }
}

/// 52 pt (`.wtitle`): the lights, the video's name over the subtitle, "Video" with its
/// menu, Find 20 Frames.
struct PreviewTitleRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            TrafficLightsSlot()
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: model.previewVideo?.name ?? model.t("app.preview.title"))
                    .svFont(13, .semibold)
                    .foregroundStyle(SV.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: model.previewSubtitle)
                    .svFont(11.5)
                    .foregroundStyle(SV.text3)
                    .lineLimit(1)
            }
            .padding(.leading, 8)
            Spacer(minLength: 12)
            PreviewVideoMenu()
            // Board A0: before any frame the box under it has the button; the header has it
            // from the search on (off while it runs, A1).
            if model.previewResult != nil || model.isSearchingFrames {
                findButton
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(SV.raised)
    }

    /// Secondary, as on the boards; off during the batch and while it searches.
    private var findButton: some View {
        let again = model.previewResult != nil
        return Button { model.findFrames() } label: {
            Label(model.t("app.preview.find"), systemImage: "magnifyingglass")
        }
        .svButton(.secondary, .regular)
        .fixedSize()
        .disabled(!model.canFindFrames)
        .help(model.t(again ? "app.preview.find_again_help" : "app.preview.find_help"))
    }
}

/// "Video" and the menu of the list's videos: the chosen one checked, the
/// duration on the right, the one being processed off with "in corso"
/// (C2-A3). Off while a search runs; open during the batch.
struct PreviewVideoMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            Text(model.t("app.preview.video")).svSmall()
            PopupMenu({
                model.videos.map { video in
                    let detail = video.state == .running ? model.t("app.preview.in_progress") : video.duration.map(Localizer.clock)
                    return .item(video.name, detail: detail, checked: video.id == model.previewVideo?.id,
                                 enabled: model.canPreview(video)) {
                        model.choosePreviewVideo(video.id)
                    }
                }
            }) {
                PopupLabel(title: model.previewVideo?.name ?? "", width: 200)
            }
            .fixedSize()
            .disabled(model.isSearchingFrames || model.videos.isEmpty)
        }
        .fixedSize()
    }
}
