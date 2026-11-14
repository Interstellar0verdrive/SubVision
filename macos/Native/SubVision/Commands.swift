// SPDX-License-Identifier: MIT
// Board O9: the menu bar. Every button in the window has its command here;
// items that don't apply are dimmed, not hidden. Adapted from the Commands
// of the native macOS app of AnimeUp (by the same author).

import AppKit
import SVShell
import SwiftUI

struct AppCommands: Commands {
    var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // ⌘Q also when a sheet is open; with a batch running the delegate asks (O3).
        CommandGroup(replacing: .appTermination) {
            Button(model.t("app.menu.quit")) { model.quitApp() }
                .keyboardShortcut("q", modifiers: .command)
        }
        CommandGroup(replacing: .appInfo) {
            Button { model.showAbout() } label: { Label(model.t("app.menu.about"), systemImage: "info.circle") }
        }
        // Version and GitHub left the sidebar for the app menu (C3-01, board O9).
        CommandGroup(after: .appInfo) {
            Button { model.checkForUpdates() } label: {
                Label(model.t("app.menu.check_updates"), systemImage: "arrow.down.circle")
            }
            .disabled(model.checkingUpdates)
            Button { model.openRepository() } label: {
                Label(model.t("app.menu.github"), systemImage: "arrow.up.right.square")
            }
        }
        CommandGroup(replacing: .newItem) {
            Button(model.t("app.menu.open_videos")) { model.openVideos() }
                .keyboardShortcut("o", modifiers: .command)
            Button(model.t("app.menu.open_srt")) { model.openSRTPanel() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Button(model.t("app.menu.open_a_report")) { model.openReportPanel() }
                .keyboardShortcut("o", modifiers: [.command, .option])
        }
        CommandGroup(after: .newItem) {
            Divider()
            // Review (⌘R): the row with the focus on Video (C3-02), the row selected on Review.
            Button(model.t("app.menu.open_report")) {
                if let video = model.reviewTarget { model.review(video) }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model.reviewTarget?.outputReport == nil)
            // The row with the focus on Video: no selection any more (C3-02).
            Button(model.t("app.menu.show_in_finder")) { if let id = model.focusedRow { model.showInFinder([id]) } }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.focusedVideo?.exists != true || model.tab != .process)
            Button(model.t("app.menu.open_file_log")) {
                if let video = model.focusedVideo { model.openLog(video) }
            }
            .disabled(model.focusedVideo?.logExists != true || model.tab != .process)
            Divider()
            Button(model.t("app.menu.remove")) { model.removeFocused() }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(!model.canRemoveFocused || model.tab != .process)
        }
        // One Select All (design note 44): the system's group is replaced, so Cut, Copy and
        // Paste go to the first responder as before, and ⌘A selects the text being edited
        // or, on the Video page, every row.
        CommandGroup(replacing: .pasteboard) {
            Button(model.t("app.menu.cut")) { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }
                .keyboardShortcut("x", modifiers: .command)
            Button(model.t("app.menu.copy")) { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) }
                .keyboardShortcut("c", modifiers: .command)
            Button(model.t("app.menu.paste")) { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) }
                .keyboardShortcut("v", modifiers: .command)
            Button(model.t("app.menu.select_all")) { model.selectAllInContext() }
                .keyboardShortcut("a", modifiers: .command)
        }
        CommandGroup(before: .sidebar) {
            // The page shown has its check mark (board O9).
            pageItem(.process, "app.sidebar.tab.process", "1")
            pageItem(.review, "app.sidebar.tab.review", "2")
            pageItem(.fix, "app.sidebar.tab.fix", "3")
            Divider()
            // Board O9: the round ‹ of the title band, from the menu (C3-07, C3-09).
            Button(model.t("app.menu.back")) { model.backAction?() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!model.canGoBack)
            // The panel never closes beside a wide page (C3-03): the item, and ⌥⌘I, are there
            // only while a narrow window lays it over the page (N1, N2).
            if model.inspectorOverlays {
                Divider()
                Button(model.t(model.inspectorOpen ? "app.menu.hide_inspector" : "app.menu.show_inspector")) { model.toggleInspector() }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                    .disabled(model.tab != .process)
            }
            Divider()
        }
        CommandMenu(model.t("app.menu.process")) {
            // "Elabora i video spuntati" (C3-02, DS2): the checked rows.
            Button(model.t("app.menu.start")) { model.startBatch() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.canStart || model.tab == .fix)
            Button(model.t("app.menu.stop_file")) { model.stopCurrentFile() }
                .keyboardShortcut(".", modifiers: [.command, .option])
                .disabled(!model.batch.running)
            Button(model.t("app.menu.stop_all")) { model.stopAll() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!model.batch.running)
            // Board O9: the parameters' defaults belong to the batch menu, not to View.
            Button(model.t("app.menu.restore_defaults")) { model.resetAllParameters() }
                .disabled(model.batch.running)
            Divider()
            // Preview (design note 80): on the row with the focus, else on the video shown last.
            Button(model.t("app.menu.preview")) { model.openPreview(model.focusedRow) }
                .keyboardShortcut("y", modifiers: .command)
                .disabled(model.videos.isEmpty)
            // In the Preview window, when it is the key window.
            Button(model.t("app.menu.find_frames")) { model.findFrames() }
                .disabled(!model.preview.windowKey || !model.canFindFrames)
            Button(model.t("app.menu.try_ocr")) { model.tryOCR() }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(!model.preview.windowKey || !model.canTryOCR)
            Button(model.t("app.menu.prev_frame")) { model.previousFrame() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(!model.preview.windowKey || !model.canBrowseFrames)
            Button(model.t("app.menu.next_frame")) { model.nextFrame() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(!model.preview.windowKey || !model.canBrowseFrames)
            Divider()
            // F5.3: active only on the Sub fix page, where Start is not (design note 15).
            Button(model.t("app.menu.run_fix")) { model.runFix() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.canRunFix || model.tab != .fix)
        }
        CommandGroup(after: .windowArrangement) {
            Button(model.t("app.menu.main_window")) { openWindow(id: model.config.mainWindowID) }
                .keyboardShortcut("0", modifiers: .command)
            // "Preview · <video>" (board O9): the video the window shows, or would show.
            Button(previewWindowTitle) { model.openPreview(nil) }
                .disabled(model.videos.isEmpty)
        }
        CommandGroup(replacing: .help) {
            Button(model.t("app.menu.guide")) { NSWorkspace.shared.open(AppConfig.guideURL) }
            Divider()
            Button(model.t("app.menu.open_log")) { model.showAppLog() }
                .keyboardShortcut("l", modifiers: [.command, .option])
            Button(model.t("app.menu.report_problem")) { NSWorkspace.shared.open(AppConfig.issuesURL) }
        }
    }

    private var previewWindowTitle: String {
        guard let name = model.previewVideo?.name else { return model.t("app.menu.preview_window") }
        return model.t("app.menu.preview_window_named", ["name": name])
    }

    /// A page of View: a toggle, so the menu shows the check mark on the page in front.
    private func pageItem(_ tab: Tab, _ key: String, _ shortcut: Character) -> some View {
        Toggle(model.t(key), isOn: Binding(get: { model.tab == tab }, set: { _ in model.showPage(tab) }))
            .keyboardShortcut(KeyEquivalent(shortcut), modifiers: .command)
    }
}
