// SPDX-License-Identifier: MIT
// Settings ⌘, (design boards ST1–ST5): General, Tools, Lists, Updates, with
// SettingsKit; the default under every row that has one; Tools and Lists
// locked while a batch runs (design note 12). Adapted from the SettingsView
// of the native macOS app of AnimeUp (by the same author).

import AppKit
import SVShell
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, tools, lists, updates
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .tools: "wrench.and.screwdriver"
        case .lists: "list.bullet"
        case .updates: "arrow.triangle.2.circlepath"
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var tab: SettingsTab = .general

    var body: some View {
        TabView(selection: $tab) {
            ForEach(SettingsTab.allCases) { t in
                SettingsPage(tab: t)
                    .tabItem { Label(model.t("app.settings.tab.\(t.rawValue)"), systemImage: t.symbol) }
                    .tag(t)
            }
        }
        .frame(width: 640)
        .navigationTitle(model.t("app.settings.window_title", ["tab": model.t("app.settings.tab.\(tab.rawValue)")]))
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // The lists may have been edited in the text editor: the counts follow.
            model.refreshLists()
        }
    }
}

struct SettingsPage: View {
    @Environment(AppModel.self) private var model
    var tab: SettingsTab

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            switch tab {
            case .general: GeneralSettings()
            case .tools: ToolsSettings()
            case .lists: ListsSettings()
            case .updates: UpdateSettings()
            }
        }
        .padding(20)
        .frame(width: 640, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(SV.bg)
    }
}

extension AppModel {
    func defaultText(_ value: String) -> String { t("app.settings.default", ["value": value]) }

    /// Tools and Lists are locked while a batch runs (design note 12).
    var settingsLocked: Bool { batch.running }
}

/// The yellow note of ST5.
struct LockedNote: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.settingsLocked {
            NoteView(.yellow, title: model.t("app.settings.locked_title"), text: model.t("app.settings.locked_text"))
        }
    }
}

// MARK: - General (ST1)

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        SettingsGroup {
            SettingsRow(model.t("app.settings.language"), description: model.t("app.settings.language_desc")) {
                CapsuleSegments([("en", "English"), ("it", "Italiano")],
                                selection: Binding(get: { model.language }, set: { model.setLanguage($0) }))
            }
            SettingsRow(model.t("app.settings.appearance"), description: model.t("app.settings.appearance_desc"),
                        defaultText: model.defaultText(model.t("app.settings.theme.system"))) {
                CapsuleSegments([("system", model.t("app.settings.theme.system")), ("light", model.t("app.settings.theme.light")),
                                 ("dark", model.t("app.settings.theme.dark"))], selection: $model.theme)
            }
        }
        SettingsGroup(model.t("app.settings.while_processing")) {
            SettingsRow(model.t("app.settings.notifications"), description: model.t("app.settings.notifications_desc"),
                        defaultText: model.defaultText(model.t("app.settings.on"))) {
                Toggle("", isOn: $model.notifications).toggleStyle(.switch).controlSize(.small).labelsHidden().tint(SV.sysAccent)
            }
            SettingsRow(model.t("app.settings.dock"), defaultText: model.defaultText(model.t("app.settings.on"))) {
                Toggle("", isOn: $model.dockProgress).toggleStyle(.switch).controlSize(.small).labelsHidden().tint(SV.sysAccent)
            }
        }
    }
}

// MARK: - Tools (ST2, ST5)

struct ToolsSettings: View {
    @Environment(AppModel.self) private var model

    private var bundledVersion: String {
        model.toolsStatus?.tools.first { $0.key == "ffmpeg" }?.version ?? AppConfig.ffmpegVersion
    }

    private var ffprobeVersion: String {
        model.toolsStatus?.tools.first { $0.key == "ffprobe" }?.version ?? AppConfig.ffmpegVersion
    }

    var body: some View {
        LockedNote()
        Group {
            SettingsGroup {
                SettingsRow(model.t("app.settings.ffmpeg"), description: model.t("app.settings.ffmpeg_desc"),
                            defaultText: model.defaultText(model.t("app.settings.ffmpeg_default"))) {
                    let brew = model.homebrewFFmpeg
                    let onBrew = brew != nil && model.customFFmpeg?.path == brew?.ffmpegPath
                    let own = model.customFFmpeg != nil && !onBrew
                    let bundledTitle = model.t("app.settings.ffmpeg_bundled", ["version": bundledVersion])
                    let brewTitle = brew.map { model.t("app.settings.ffmpeg_brew", ["version": $0.version, "folder": $0.folder]) }
                    PopupMenu({
                        var items: [SVMenuItem] = [.item(bundledTitle, checked: model.customFFmpeg == nil) { model.useBundledFFmpeg() }]
                        if let brew, let brewTitle { items.append(.item(brewTitle, checked: onBrew) { model.useHomebrewFFmpeg(brew) }) }
                        items.append(.item(model.t("app.settings.ffmpeg_own"), checked: own) { model.chooseOwnFFmpeg() })
                        return items
                    }) {
                        PopupLabel(title: onBrew ? (brewTitle ?? "") : own ? model.t("app.settings.ffmpeg_own") : bundledTitle,
                                   width: 250)
                    }
                    .fixedSize()
                }
                if let custom = model.customFFmpeg {
                    SettingsRow(model.t("app.settings.ffmpeg_path"), description: nil) {
                        VStack(alignment: .trailing, spacing: 6) {
                            HStack(spacing: 8) {
                                PathField(custom.folder.path, symbol: "folder", height: 26).frame(width: 200)
                                Button(model.t("app.common.choose")) { model.chooseOwnFFmpeg() }.svButton(.secondary, .small)
                            }
                            customStatus(custom)
                        }
                    }
                } else {
                    SettingsRow(model.t("app.settings.version"),
                                description: model.t("app.settings.version_val", ["ffmpeg": bundledVersion, "ffprobe": ffprobeVersion])) {
                        if let progress = model.redownload {
                            HStack(spacing: 8) {
                                Spinner(size: 12)
                                Text(model.t("app.settings.downloading", ["done": progress.done / 1_000_000, "total": progress.total / 1_000_000]))
                                    .svFont(12).foregroundStyle(SV.text2)
                                SVBar(progress.total > 0 ? Double(progress.done) / Double(progress.total) : 0).frame(width: 70)
                            }
                        } else {
                            Button(model.t("app.settings.download_again")) { model.redownloadTools() }.svButton(.secondary, .regular)
                                .disabled(model.status != .ready)
                        }
                    }
                }
            }
            .disabled(model.settingsLocked)
            .opacity(model.settingsLocked ? 0.45 : 1)
        }
        .onAppear { model.findHomebrewFFmpeg() }
        SettingsGroup {
            infoRow(model.t("app.settings.engine"),
                    model.t("app.settings.engine_val", ["version": model.hello?.version ?? model.config.appVersion,
                                                        "python": model.hello?.python ?? "…"]))
            infoRow(model.t("app.settings.recognition"),
                    model.tn("app.settings.recognition_val", model.hello?.languages.count ?? 0,
                             ["livetext": model.t(model.hello?.livetext == true ? "app.common.on_state" : "app.common.off_state")]))
        }
    }

    /// The line under the path: found with its versions, ffprobe missing (yellow), or not starting (red).
    @ViewBuilder private func customStatus(_ custom: CustomFFmpeg) -> some View {
        if let error = custom.error {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: "exclamationmark.circle").svFont(11)
                Text(model.t("app.settings.ffmpeg_fails", ["error": error])).svFont(11.5)
            }
            .foregroundStyle(SV.redText)
            .frame(maxWidth: 300, alignment: .trailing)
            .fixedSize(horizontal: false, vertical: true)
        } else if custom.ffprobeMissing {
            Text(model.t("app.settings.ffprobe_missing")).svFont(11.5).foregroundStyle(SV.yellowText)
        } else {
            Text(model.t("app.settings.ffmpeg_found", ["ffmpeg": custom.version ?? "?", "ffprobe": custom.ffprobeVersion ?? "?"]))
                .svFont(SVFont.smallNumbers).foregroundStyle(SV.text2)
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(spacing: 16) {
            Text(title).svFont(13).foregroundStyle(SV.text)
            Spacer()
            Text(value).svFont(SVFont.numbers).foregroundStyle(SV.textCode).lineLimit(1)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
    }
}

/// The popup's label: text and chevrons in a field.
struct PopupLabel: View {
    var title: String
    var width: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            Text(title).svFont(12.5).foregroundStyle(SV.text).lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.up.chevron.down").svFont(9, .semibold).foregroundStyle(SV.text2)
        }
        .frame(width: width - 2 - 20, height: 24)
        .svBox(RoundedRectangle(cornerRadius: SV.Radius.field), fill: SV.control, line: SV.glassLine,
               padding: EdgeInsets(vertical: 0, horizontal: 10))
    }
}

// MARK: - Lists (ST3)

struct ListsSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        LockedNote()
        Group {
            SettingsGroup {
                listRow(kind: "ignore", title: model.t("app.settings.ignore"), list: model.lists?.ignore,
                        description: model.tn("app.settings.ignore_desc", model.lists?.ignore.count ?? 0))
                listRow(kind: "corrections", title: model.t("app.settings.corr"), list: model.lists?.corrections,
                        description: model.tn("app.settings.corr_desc", model.lists?.corrections.count ?? 0))
            }
            Text(model.t("app.settings.lists_note")).svSmall().fixedSize(horizontal: false, vertical: true)
            Text(folderText).svFont(SVFont.numbers).foregroundStyle(SV.textCode)
        }
        .disabled(model.settingsLocked)
        .opacity(model.settingsLocked ? 0.45 : 1)
    }

    private var folderText: String {
        let path = model.configuration.stateFolder.path
        let home = DisplayHome.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private func listRow(kind: String, title: String, list: ListsStatus.List?, description: String) -> some View {
        SettingsRow(title, description: list == nil ? model.t("app.settings.list_missing") : description) {
            HStack(spacing: 8) {
                Button(model.t("app.settings.edit")) { if let list { model.editList(list.path) } }.svButton(.secondary, .small)
                Button(model.t("app.settings.import")) { model.importList(kind: kind) }.svButton(.secondary, .small)
                Button { if let list { model.showListInFinder(list.path) } } label: {
                    Image(systemName: "folder").svFont(13).foregroundStyle(SV.text2).frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(model.t("app.settings.show_in_finder"))
                // Without it VoiceOver reads the symbol's own name ("Sposta" in Italian).
                .accessibilityLabel(model.t("app.settings.show_in_finder"))
            }
            .disabled(list == nil || model.status != .ready)
        }
    }
}

// MARK: - Updates (ST4)

struct UpdateSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        SettingsGroup {
            SettingsRow(model.t("app.settings.auto_check"), description: model.t("app.settings.auto_check_desc"),
                        defaultText: model.defaultText(model.t("app.settings.on"))) {
                Toggle("", isOn: $model.autoCheckUpdates).toggleStyle(.switch).controlSize(.small).labelsHidden().tint(SV.sysAccent)
            }
        }
        SettingsGroup {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle).svFont(13, .semibold).foregroundStyle(statusColor)
                    Text(checkedLine).svSmall()
                }
                Spacer()
                if case .available(_, let url)? = model.lastUpdateResult, model.updateAvailable != nil {
                    Button(model.t("app.common.download")) { NSWorkspace.shared.open(url) }.svButton(.notice, .regular)
                }
                Button(model.t("app.settings.check_now")) { Task { await model.checkForUpdatesQuietly() } }
                    .svButton(.secondary, .regular).disabled(model.checkingUpdates)
            }
            .padding(14)
        }
        HStack(spacing: 16) {
            UnderlineLink(model.t("app.settings.release_notes"), symbol: "arrow.up.right") {
                NSWorkspace.shared.open(AppConfig.releasesURL)
            }
            UnderlineLink(model.t("app.settings.on_github"), symbol: "arrow.up.right") {
                NSWorkspace.shared.open(model.config.repositoryURL)
            }
        }
    }

    private var statusTitle: String {
        switch model.lastUpdateResult {
        case .available(let version, _)? where model.updateAvailable != nil:
            return model.t("app.settings.update_available", ["version": version])
        case .error?:
            return model.t("app.settings.update_error")
        default:
            return model.t("app.settings.up_to_date", ["version": model.config.appVersion])
        }
    }

    private var statusColor: Color {
        switch model.lastUpdateResult {
        case .available? where model.updateAvailable != nil: SV.yellowText
        case .error?: SV.redText
        default: SV.text
        }
    }

    private var checkedLine: String {
        guard let when = model.lastUpdateCheck else { return model.t("app.settings.last_checked", ["when": "—"]) }
        let f = DateFormatter()
        f.locale = model.localizer.locale
        f.doesRelativeDateFormatting = true
        f.formattingContext = .middleOfSentence
        f.dateStyle = .medium
        f.timeStyle = .short
        return model.t("app.settings.last_checked", ["when": f.string(from: when)])
    }
}
