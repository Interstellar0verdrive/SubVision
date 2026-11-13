// SPDX-License-Identifier: MIT
// The app's alerts (design boards O1–O8), drawn as SVAlert. Adapted from
// the Alerts of the native macOS app of AnimeUp (by the same author).

import AppKit
import SVShell

@MainActor
enum Alerts {
    enum ImportChoice { case append, replace }

    /// The last non-modal alert that is not O1/O2 (O7, an error), while it is up: for `DebugQA`.
    static weak var shown: SVAlertPresentation?

    /// O3: ⌘Q with a batch running. True quits.
    static func confirmQuit(_ model: AppModel) -> Bool {
        let b = model.batch
        let a = SVAlert(icon: AlertIconName.quit, tone: .yellow, title: model.t("app.alerts.quit_title"),
                        text: model.t("app.alerts.quit_text", ["name": b.name, "i": b.index, "n": b.total]))
        a.button(model.t("app.alerts.quit_btn"), role: .destructiveSolid)
        a.button(model.t("app.common.cancel"))
        return a.runModal() == 0
    }

    /// O4: the window closed with a batch running, the first time only.
    static func closeNotice(_ model: AppModel) {
        let a = SVAlert(icon: AlertIconName.windowClose, tone: .accent, title: model.t("app.alerts.close_title"),
                        text: model.t("app.alerts.close_text"))
        a.button(model.t("app.common.ok"), role: .primary)
        a.checkbox = model.t("app.alerts.dont_show")
        // Not modal: the batch it talks about keeps reporting under it.
        a.present { _ in
            if a.checked { model.defaults.set(true, forKey: DefaultsKey.closeNoticeOff) }
        }
    }

    /// O8a: a folder without videos; "Look in Subfolders" when they were not searched.
    static func noVideos(_ model: AppModel, folder: URL, subfolders: Bool, lookDeeper: @escaping () -> Void) {
        let a = SVAlert(icon: AlertIconName.folderEmpty, tone: .yellow,
                        title: model.t("app.alerts.novideos_title", ["folder": folder.lastPathComponent]),
                        text: subfolders ? "" : model.t("app.alerts.novideos_text"))
        // Not modal (as O8b and O8d): videos are added during a batch too.
        if subfolders {
            a.button(model.t("app.common.ok"), role: .primary)
            a.present { _ in }
        } else {
            a.button(model.t("app.alerts.look_sub"), role: .primary)
            a.button(model.t("app.common.ok"))
            a.present { if $0 == 0 { lookDeeper() } }
        }
    }

    /// O8b: the videos were in the list already.
    static func alreadyInList(_ model: AppModel, count: Int) {
        let a = SVAlert(icon: AlertIconName.info, tone: .accent, title: model.tn("app.alerts.already_title", count),
                        text: model.t("app.alerts.already_text"))
        a.button(model.t("app.common.ok"), role: .primary)
        a.present { _ in }
    }

    /// O8c: Import… a list that already has lines. nil cancels.
    static func importList(_ model: AppModel, name: String, existing: Int) -> ImportChoice? {
        guard existing > 0 else { return .replace }
        let a = SVAlert(icon: AlertIconName.info, tone: .accent, title: model.t("app.alerts.import_title", ["name": name]),
                        text: model.tn("app.alerts.import_text", existing))
        a.button(model.t("app.alerts.import_add"), role: .primary)
        a.button(model.t("app.alerts.import_replace"))
        a.button(model.t("app.common.cancel"))
        switch a.runModal() {
        case 0: return .append
        case 1: return .replace
        default: return nil
        }
    }

    /// O8d: the outcome of Check for Updates…, in its three tones.
    static func updateResult(_ model: AppModel, _ result: UpdateResult) {
        let name = model.config.appName
        switch result {
        case .available(let version, let url):
            let a = SVAlert(icon: AlertIconName.update, tone: .yellow,
                            title: model.t("app.alerts.update_title", ["version": version]),
                            text: model.t("app.alerts.update_text", ["current": model.config.appVersion]))
            a.button(model.t("app.common.download"), role: .primary)
            a.button(model.t("app.alerts.later"), cancel: true)
            a.present { if $0 == 0 { NSWorkspace.shared.open(url) } }
        case .upToDate:
            let a = SVAlert(icon: AlertIconName.update, tone: .accent,
                            title: model.t("app.settings.up_to_date", ["version": model.config.appVersion]), text: "")
            a.button(model.t("app.common.ok"), role: .primary)
            a.present { _ in }
        case .error(let message):
            model.log.error("update check (\(name)) failed: \(message)")
            let a = SVAlert(icon: AlertIconName.update, tone: .red, title: model.t("app.settings.update_error"),
                            text: model.t("app.alerts.update_error_text"))
            a.button(model.t("app.common.ok"), role: .primary)
            a.present { _ in }
        }
    }

    // MARK: - F5.1 (O1, O2, O7)

    /// O1 (Stop this file) or O2 (Stop the whole batch), not modal: the
    /// batch's events keep coming while it is up. `answer` gets true for Stop.
    static func confirmStop(_ model: AppModel, _ kind: StopAlert.Kind, answer: @escaping @MainActor (Bool) -> Void) -> SVAlertPresentation {
        let a: SVAlert
        switch kind {
        case .file(_, let name):
            a = SVAlert(icon: AlertIconName.stopFile, tone: .red, title: model.t("app.alerts.stop_title", ["name": name]),
                        text: model.t("app.alerts.stop_text"))
            a.button(model.t("app.common.stop"), role: .destructiveSolid)
        case .all:
            a = SVAlert(icon: AlertIconName.stopAll, tone: .red, title: model.t("app.alerts.stopall_title"),
                        text: model.t("app.alerts.stopall_text"))
            a.button(model.t("app.common.stop_all"), role: .destructiveSolid)
        }
        a.button(model.t("app.common.continue"), cancel: true)
        return a.present(over: WindowSizer.main(model.config).flatMap { $0.isVisible ? $0 : nil }) { answer($0 == 0) }
    }

    /// O7: the OCR language saved is not one Vision reads here; "Choose the Language" opens the inspector.
    static func languageUnsupported(_ model: AppModel, language: String, count: Int) {
        // "Latino", not "Latino (Città del Vaticano)": the same name as the inspector's menu.
        let name = model.languageName(language)
        let a = SVAlert(icon: AlertIconName.language, tone: .yellow, title: model.t("app.alerts.lang_title", ["lang": name]),
                        text: model.tn("app.alerts.lang_text", count))
        a.button(model.t("app.alerts.lang_btn"), role: .primary)
        a.button(model.t("app.common.cancel"), cancel: true)
        // Not modal (as O1/O2): nothing on the main actor waits behind it.
        shown = a.present { if $0 == 0 { model.showLanguageMenu() } }
    }

    /// A plain error (red), OK.
    static func error(_ model: AppModel, title: String, text: String) {
        let a = SVAlert(icon: AlertIconName.error, tone: .red, title: title, text: text)
        a.button(model.t("app.common.ok"), role: .primary)
        shown = a.present { _ in }
    }
}
