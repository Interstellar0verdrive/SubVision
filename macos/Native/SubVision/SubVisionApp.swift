// SPDX-License-Identifier: MIT
// SubVision 2.0: the native macOS app. The window frame, the tools window,
// the engine client and the design system come from SubVisionKit (SVShell).
// Adapted from the app of the native macOS app of AnimeUp (by the same author).

import AppKit
import SVShell
import SwiftUI

@main
struct SubVisionApp: App {
    @NSApplicationDelegateAdaptor(ShellAppDelegate.self) private var delegate
    @State private var model = AppModel()

    init() {
        // Before any window: the saved appearance, so nothing flashes the other one.
        delegate.willFinishLaunching = { ShellTheme.applySaved() }
    }

    var body: some Scene {
        ShellWindow(config: model.config) {
            MainView()
                .environment(model)
                .onAppear { wire() }
        }
        .commands {
            AppCommands(model: model)
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }

    /// The delegate's decisions and the model's start, once the window is there.
    private func wire() {
        delegate.quitBlocker = { model.shouldBlockQuit() }
        delegate.dockMenu = { model.dockMenu() }
        delegate.willTerminate = {
            // The engine goes with the app, right away.
            Task { await model.engine.terminateNow() }
        }
        SVAlert.iconSource = .default
        model.start()
        #if DEBUG
        DebugSnapshot.scheduleIfAsked(model: model)
        DebugQA.scheduleIfAsked(model: model)
        #endif
    }
}
