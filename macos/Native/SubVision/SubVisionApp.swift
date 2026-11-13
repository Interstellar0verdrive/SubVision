// SPDX-License-Identifier: MIT
// SubVision 2.0: the native macOS app. The window frame, the tools window,
// the engine client and the design system come from SubVisionKit (SVShell).

import AppKit
import SVShell
import SwiftUI

@main
struct SubVisionApp: App {
    @NSApplicationDelegateAdaptor(ShellAppDelegate.self) private var delegate

    static let config = AppShellConfig(
        appName: "SubVision", bundleIdentifier: "io.github.interstellar0verdrive.subvision",
        repositoryURL: URL(string: "https://github.com/Interstellar0verdrive/SubVision")!,
        releaseAPIURL: URL(string: "https://api.github.com/repos/Interstellar0verdrive/SubVision/releases/latest")!,
        releasePageURL: URL(string: "https://github.com/Interstellar0verdrive/SubVision/releases/latest")!,
        logSubsystem: "io.github.interstellar0verdrive.subvision", fallbackVersion: "2.0.0")

    var body: some Scene {
        ShellWindow(config: Self.config) {
            // F4.1: the frame builds; the engine and the pages come with F4.2–F4.4.
            EngineStatusView(status: .starting, retry: {}, showLog: {})
                .background(SV.bg)
        }
    }
}
