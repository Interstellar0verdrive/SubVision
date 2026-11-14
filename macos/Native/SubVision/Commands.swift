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
            // Review (⌘R): the finished row selected on Video, the row selected on Review.
            Button(model.t("app.menu.open_report")) {
                if let video = model.reviewTarget { model.review(video) }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model.reviewTarget?.outputReport == nil)
            Button(model.t("app.menu.show_in_finder")) { model.showInFinder(model.selection) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.selection.isEmpty)
            Button(model.t("app.menu.open_file_log")) {
                if let video = model.selectedFinished { model.openLog(video) }
            }
            .disabled(model.selectedFinished?.logExists != true || model.tab != .process)
            Divider()
            Button(model.t("app.menu.remove")) { model.removeSelection() }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(!model.canRemoveSelection || model.tab != .process)
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
            // The Preview page (C3-09): on the row selected, else on the video shown last.
            Button(model.t("app.menu.preview")) { model.openPreview(model.selectedSingle?.id) }
                .keyboardShortcut("y", modifiers: .command)
                .disabled(model.videos.isEmpty)
            // On the Preview page (board O9); each has its button on the page too.
            Button(model.t("app.menu.try_ocr")) { model.tryOCR() }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(!model.previewShown || !model.canTryOCR)
            Button(model.t("app.menu.prev_frame")) { model.previousFrame() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(!model.previewShown || !model.canBrowseFrames)
            Button(model.t("app.menu.next_frame")) { model.nextFrame() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(!model.previewShown || !model.canBrowseFrames)
            Button(model.t("app.menu.prev_video")) { model.showNeighbourVideo(-1) }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(!model.previewShown || model.previewNeighbour(-1) == nil)
            Button(model.t("app.menu.next_video")) { model.showNeighbourVideo(1) }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(!model.previewShown || model.previewNeighbour(1) == nil)
            Divider()
            // F5.3: active only on the Sub fix page, where Start is not (design note 15).
            Button(model.t("app.menu.run_fix")) { model.runFix() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.canRunFix || model.tab != .fix)
        }
        CommandGroup(after: .windowArrangement) {
            Button(model.t("app.menu.main_window")) { openWindow(id: model.config.mainWindowID) }
                .keyboardShortcut("0", modifiers: .command)
        }
        CommandGroup(replacing: .help) {
            Button(model.t("app.menu.guide")) { NSWorkspace.shared.open(AppConfig.guideURL) }
            Divider()
            Button(model.t("app.menu.open_log")) { model.showAppLog() }
                .keyboardShortcut("l", modifiers: [.command, .option])
            Button(model.t("app.menu.report_problem")) { NSWorkspace.shared.open(AppConfig.issuesURL) }
        }
    }

    /// A page of View: a toggle, so the menu shows the check mark on the page in front.
    private func pageItem(_ tab: Tab, _ key: String, _ shortcut: Character) -> some View {
        Toggle(model.t(key), isOn: Binding(get: { model.tab == tab }, set: { _ in model.showPage(tab) }))
            .keyboardShortcut(KeyEquivalent(shortcut), modifiers: .command)
    }
}
