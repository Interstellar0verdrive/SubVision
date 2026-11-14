// SPDX-License-Identifier: MIT
// The main window: the tools window on the first launch, else the shell's
// frame (navigation N-A, design round C3: the pages as segments of the top
// bar at every width) around the engine status or the current page, the batch
// bar at the bottom while a batch runs and the end-of-batch sheet over
// whatever page is open (C3-12).

import SVShell
import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            if model.tools.showsWindow {
                ToolsSetupView(state: model.tools, texts: model.texts, appName: model.config.appName,
                               showLog: { model.showLog() })
                    .onAppear { WindowSizer.toTools(model.config) }
            } else {
                MainSplit(tabs: model.tabs, selection: tabBinding, texts: model.texts,
                          sizeOverride: model.config.environment("WINDOW"),
                          openSettings: { openSettings() },
                          onClose: { model.windowClosed() },
                          showsBottomBar: model.batch.running,
                          topBarTrailing: { TopBarTrailing() },
                          page: { Page() },
                          bottomBar: { BatchBar() })
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { model.mainWindowWidth = $0 }
                    // E6, C3-12: the end of the batch over the page in front, no jump to Video.
                    .sheet(isPresented: Binding(get: { model.run.showSummary }, set: { if !$0 { model.markSummarySeen() } })) {
                        FinishedSheet()
                    }
            }
        }
        .onAppear { model.reopenMainWindow = { openWindow(id: model.config.mainWindowID) } }
    }

    private var tabBinding: Binding<String> {
        Binding(get: { model.tab.rawValue }, set: { if let t = Tab(rawValue: $0) { model.tab = t } })
    }
}

extension AppModel {
    /// The top bar's segments (C3-01): Video with a spinner while a batch runs, Review, then Sub fix among the tools.
    var tabs: [ShellTab] {
        [ShellTab(id: Tab.process.rawValue, symbol: Tab.process.symbol, title: t("app.sidebar.tab.process"), busy: batch.running),
         ShellTab(id: Tab.review.rawValue, symbol: Tab.review.symbol, title: t("app.sidebar.tab.review")),
         ShellTab(id: Tab.fix.rawValue, symbol: Tab.fix.symbol, title: t("app.sidebar.tab.fix"), separatorBefore: true)]
    }
}

/// The engine status until the engine is up, then the page of the tab.
struct Page: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.status != .ready {
            EngineStatusView(status: model.status, texts: model.texts, retry: { model.retry() }, showLog: { model.showLog() })
        } else {
            switch model.tab {
            case .process:
                // C3-09 (P-A): the Preview page slides over the list, which stays as it was
                // under it (scroll, drawers) for the way back.
                ZStack {
                    ProcessView()
                        .allowsHitTesting(!model.preview.shown)
                        .accessibilityHidden(model.preview.shown)
                    if model.preview.shown {
                        PreviewPage()
                    }
                }
            case .review: ReviewPage()
            case .fix: FixPage()
            }
        }
    }
}

/// The top bar's right side, before the shell's gear: a newer release (the yellow
/// chip, in place of the sidebar's update card) and, in a narrow window, the
/// parameters button on the pages that have the panel (N1, N2).
struct TopBarTrailing: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let update = model.updateAvailable {
            TopBarChip(model.t("app.common.update_chip", ["version": update.version]), tone: .yellow) {
                NSWorkspace.shared.open(update.url)
            }
            .help(model.t("app.common.update_chip_help"))
        }
        if model.tab == .process, model.inspectorOverlays {
            ChromeIconButton("sidebar.right", help: model.t("app.process.show_inspector_help"), on: model.inspectorOpen) {
                model.toggleInspector()
            }
        }
    }
}
