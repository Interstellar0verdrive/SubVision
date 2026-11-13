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
        CommandGroup(after: .appInfo) {
            Button { model.checkForUpdates() } label: {
                Label(model.t("app.menu.check_updates"), systemImage: "arrow.down.circle")
            }
            .disabled(model.checkingUpdates)
        }
        CommandGroup(replacing: .newItem) {
            Button(model.t("app.menu.open_videos")) { model.openVideos() }
                .keyboardShortcut("o", modifiers: .command)
            Button(model.t("app.menu.open_srt")) { model.openSRTPanel() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Button(model.t("app.menu.open_a_report")) {}
                .keyboardShortcut("o", modifiers: [.command, .option])
                .disabled(true)   // F5.4
        }
        CommandGroup(after: .newItem) {
            Divider()
            // F5.1: the finished row selected, when its report or log is on disk.
            Button(model.t("app.menu.open_report")) {
                if let report = model.selectedFinished?.outputReport { model.openReport(report) }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model.selectedFinished?.outputReport == nil || model.tab != .process)
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
        CommandGroup(after: .pasteboard) {
            Button(model.t("app.menu.select_all")) { model.selectAll() }
                .keyboardShortcut("a", modifiers: .command)
                .disabled(model.tab != .process || model.videos.isEmpty)
        }
        CommandGroup(before: .sidebar) {
            Button(model.t("app.sidebar.tab.process")) { model.tab = .process }.keyboardShortcut("1", modifiers: .command)
            Button(model.t("app.sidebar.tab.preview")) { model.tab = .preview }.keyboardShortcut("2", modifiers: .command)
            Button(model.t("app.sidebar.tab.fix")) { model.tab = .fix }.keyboardShortcut("3", modifiers: .command)
            Divider()
            Button(model.t(model.sidebarShown ? "app.menu.hide_sidebar" : "app.menu.show_sidebar")) { model.toggleSidebar() }
                .keyboardShortcut("s", modifiers: [.control, .command])
                .disabled(model.sidebarNarrow)
            Button(model.t(model.inspectorOpen ? "app.menu.hide_inspector" : "app.menu.show_inspector")) { model.toggleInspector() }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(model.tab == .fix)
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
            Divider()
            // F5.2: Preview, only on its page.
            Button(model.t("app.menu.find_frames")) { model.findFrames() }
                .disabled(model.tab != .preview || !model.canFindFrames)
            Button(model.t("app.menu.try_ocr")) { model.tryOCR() }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(model.tab != .preview || !model.canTryOCR)
            Button(model.t("app.menu.prev_frame")) { model.previousFrame() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(model.tab != .preview || !model.canBrowseFrames)
            Button(model.t("app.menu.next_frame")) { model.nextFrame() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(model.tab != .preview || !model.canBrowseFrames)
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
}
