// SPDX-License-Identifier: MIT
// The main window: the tools window on the first launch, else the shell's
// frame (sidebar or top bar) around the engine status or the current page.

import SVShell
import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var model = model
        Group {
            if model.tools.showsWindow {
                ToolsSetupView(state: model.tools, texts: model.texts, appName: model.config.appName,
                               showLog: { model.showLog() })
                    .onAppear { WindowSizer.toTools(model.config) }
            } else {
                MainSplit(tabs: model.tabs, selection: tabBinding, sidebarChoice: $model.sidebarChoice,
                          texts: model.texts, footer: footer, sizeOverride: model.config.environment("WINDOW"),
                          openSettings: { openSettings() },
                          onClose: { model.windowClosed() },
                          layoutChanged: { narrow, shown in
                              model.sidebarNarrow = narrow
                              model.sidebarShown = shown
                          },
                          sidebarExtra: { SidebarExtra() },
                          topBarTrailing: { TopBarTrailing() },
                          page: { Page() })
            }
        }
        .onAppear { model.reopenMainWindow = { openWindow(id: model.config.mainWindowID) } }
    }

    private var tabBinding: Binding<String> {
        Binding(get: { model.tab.rawValue }, set: { if let t = Tab(rawValue: $0) { model.tab = t } })
    }

    private var footer: ShellFooter {
        ShellFooter(appVersion: model.config.appVersion, engineVersion: model.hello?.version, pythonVersion: model.hello?.python,
                    checkingUpdates: model.checkingUpdates, repositoryURL: model.config.repositoryURL,
                    repositoryMark: Image("GitHubMark"), checkUpdates: { model.checkForUpdates() })
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
            case .process: ProcessView()
            case .preview: PreviewPage()
            case .fix: FixPage()
            }
        }
    }
}

/// The top bar's right side (a narrow window): the inspector button on the
/// pages that have one; the gear is the shell's.
struct TopBarTrailing: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.tab != .fix {
            InspectorButton()
        }
    }
}

/// `sidebar.right`: shows or hides the parameters (⌥⌘I).
struct InspectorButton: View {
    @Environment(AppModel.self) private var model
    @State private var hover = false

    var body: some View {
        Button { model.toggleInspector() } label: {
            Image(systemName: "sidebar.right")
                .svFont(15)
                .foregroundStyle(model.inspectorOpen ? SV.primaryText : SV.text2)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill(hover ? SV.glass : .clear))
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(model.t("app.process.show_inspector_help"))
        .accessibilityLabel(model.t("app.process.show_inspector"))
    }
}
