// SPDX-License-Identifier: MIT
// Sub fix (F5.3, design boards F1–F3, C2-S1/S2): the file card, the four
// options and the parameters shared with Video (their real controls, bound to
// the same UserDefaults keys as the Parameters panel), Run Sub fix with the
// name of the copy, and the outcome (green note with Show in Finder and Open,
// red notes for the errors, yellow for a drop that is not an .srt). Two
// columns in a wide page, one in a narrow one. The whole page takes a dropped
// .srt, also with a file already chosen. No inspector here (design note 1).

import AppKit
import SVShell
import SwiftUI

/// Sub fix: the empty state (F0) until an SRT is chosen, then the page.
struct FixPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.fixPath == nil {
            FixEmptyView()
        } else {
            FixReadyView()
        }
    }
}

/// F1–F3: the page with a file chosen.
struct FixReadyView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.svPageTop) private var top
    @State private var dropTargeted = false
    /// The width of the page's content: two columns from `twoColumnsFrom` on.
    @State private var contentWidth: CGFloat = 1000
    /// The width of the single column of a narrow page (file card, options, notes).
    static let columnWidth: CGFloat = 720
    /// The page's content width from which the shared box goes beside the file and the options.
    static let twoColumnsFrom: CGFloat = 860

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                PageTop(title: model.t("app.fix.title"), intro: model.t("app.fix.intro")) { EmptyView() }
                    .padding(.bottom, 18)
                // Scrolls only when the content does not fit.
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        outcome
                        // The page's own width decides (a `ViewThatFits` would measure the texts unwrapped).
                        if contentWidth >= Self.twoColumnsFrom {
                            HStack(alignment: .top, spacing: 24) {
                                FixLeftColumn().frame(maxWidth: .infinity, alignment: .topLeading)
                                FixSharedSection().frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 20) {
                                FixLeftColumn()
                                FixSharedSection()
                            }
                            .frame(maxWidth: Self.columnWidth, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.automatic)
            }
            .padding(.horizontal, 28)
            .padding(.top, top)
            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The dashed accent frame of the drop areas, only while something is dragged over.
        .background { if dropTargeted { RoundedRectangle(cornerRadius: 12).fill(SV.soft) } }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12).strokeBorder(SV.primary, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            }
        }
        .fileDrop(isTargeted: $dropTargeted) { model.receiveFixDrop($0) }
    }

    // MARK: - Outcome (F2, F3)

    @ViewBuilder private var outcome: some View {
        if let outcome = model.fix.outcome {
            Group {
                switch outcome {
                case .created(let path, let count):
                    NoteView(.green, title: model.tn("app.fix.created", count, ["name": URL(fileURLWithPath: path).lastPathComponent]),
                             text: model.t("app.fix.created_text")) {
                        HStack(spacing: 8) {
                            Button(model.t("app.common.show_in_finder")) { model.showFixOutputInFinder() }
                                .buttonStyle(SVTintedButtonStyle(.green))
                            Button(model.t("app.common.open")) { model.openFixOutput() }
                                .buttonStyle(SVTintedButtonStyle(.green))
                        }
                    }
                case .noValidSegments:
                    NoteView(.red, title: model.t("app.fix.no_valid"), text: model.t("app.fix.no_valid_text"))
                case .notSrt:
                    NoteView(.yellow, text: model.t("app.fix.only_srt"))
                default:
                    NoteView(.red, text: model.fixErrorText(outcome) ?? "")
                }
            }
            .padding(.bottom, 14)
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(alignment: .center, spacing: 12) {
            // The name the engine will give the copy (`fix.py`), next to the source; not once
            // the copy is made, where it would repeat the green note's name (README shots, 14/11).
            if !model.fixDone, let name = model.fixCopyName {
                Text(model.t("app.fix.copy_next", ["name": name])).svSmall()
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if model.fix.running { Spinner(size: 14) }
            Button { model.runFix() } label: { Label(model.t("app.fix.run"), systemImage: "play.fill") }
            .svButton(.primary, .regular)
            .help(model.t("app.fix.run_help"))
            // ⌘↩ fires from here: AppKit keeps one menu item per key equivalent,
            // and Start (Process) holds ⌘↩ in the menu; with Start disabled the
            // key would do nothing on this page (design note 15, verified).
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!model.canRunFix)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(SV.bg)
        .overlay(alignment: .top) { Rectangle().fill(SV.line).frame(height: 1) }
    }
}

/// The small caps label over a box (the boards' `.label`: 11 pt semibold, margin 0 0 6 2).
struct FixLabel: View {
    var text: String

    var body: some View {
        Text(text).svLabel().textCase(.uppercase).tracking(0.4)
            .padding(EdgeInsets(top: 0, leading: 2, bottom: 6, trailing: 0))
    }
}

/// The left column: "Selected file" over the file card, "What to fix" over the four options.
struct FixLeftColumn: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FixLabel(text: model.t("app.fix.file_label"))
            if let path = model.fixPath {
                FixFileCard(url: path, lines: model.fix.lines, duration: model.fix.duration)
            }
            FixLabel(text: model.t("app.fix.options")).padding(.top, 20)
            FixOptions()
        }
    }
}

/// The file card: name, folder, "642 lines · 23:40", Change… (board F1).
struct FixFileCard: View {
    @Environment(AppModel.self) private var model
    var url: URL
    var lines: Int?
    var duration: Double?

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "doc").svFont(28, .light).foregroundStyle(SV.text2)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(url.lastPathComponent).svFont(13, .medium).foregroundStyle(SV.text)
                    .lineLimit(1).truncationMode(.middle)
                Text(folder).svFont(11, mono: true).foregroundStyle(SV.text3)   // as the rows of Video (boards F1, F4)
                    .lineLimit(1).truncationMode(.middle)
                Text(meta).svSmall()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(model.t("app.common.change")) { model.openSRTPanel() }.svButton(.secondary, .small)
                .help(model.t("app.fix.change_help"))
        }
        .svBox(RoundedRectangle(cornerRadius: SV.Radius.card), fill: SV.surface, line: SV.line,
               padding: EdgeInsets(vertical: 14, horizontal: 18))
    }

    /// "~/Movies/Show/Season 1".
    private var folder: String {
        let dir = url.deletingLastPathComponent().path
        let home = DisplayHome.path
        return dir.hasPrefix(home) ? "~" + dir.dropFirst(home.count) : dir
    }

    /// "642 lines · 23:40"; the count alone when the SRT has no readable end.
    private var meta: String {
        let n = lines ?? 0
        guard let duration else { return model.tn("app.fix.file_meta", n, ["t": "–"]) }
        return model.tn("app.fix.file_meta", n, ["t": Localizer.clock(duration)])
    }
}

/// The box of the four options: the three switches and the shortest line,
/// which only counts while the flashes go (board F1; dimmed on F2 with flashes kept).
struct FixOptions: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        SettingsGroup {
            SettingsRow(model.t("app.fix.merge"), description: model.t("app.fix.merge_desc")) {
                FixSwitch(isOn: $model.fix.merge)
            }
            SettingsRow(model.t("app.fix.no_subs"), description: model.t("app.fix.no_subs_desc")) {
                FixSwitch(isOn: $model.fix.ignore)
            }
            SettingsRow(model.t("app.fix.flash"), description: model.t("app.fix.flash_desc")) {
                FixSwitch(isOn: $model.fix.flash)
            }
            SettingsRow(model.t("app.fix.min")) {
                SecondsStepper(value: $model.fix.minDuration, range: FixState.minDurationRange, step: FixState.minDurationStep,
                               text: { model.localizer.number($0, decimals: 1) + " s" })
            }
            .disabled(!model.fix.flash)
            .opacity(model.fix.flash ? 1 : 0.45)
        }
        .disabled(model.fix.running)
    }
}

/// "Shared with Video" (C2-S1/S2): the real controls of the parameters Sub fix
/// takes from the Parameters panel, on the same UserDefaults keys, so the two
/// stay in sync. Locked while a batch runs, like the panel.
struct FixSharedSection: View {
    @Environment(AppModel.self) private var model
    @AppStorage(OcrKey.mergeGap) private var mergeGap: Double = ocrDefaults.mergeGap
    @AppStorage(OcrKey.wrapWidth) private var wrapWidth: Int = ocrDefaults.wrapWidth
    @AppStorage(OcrKey.langHint) private var lang: String = ocrDefaults.langHint
    @AppStorage(OcrKey.useIgnore) private var useIgnore = true
    @AppStorage(OcrKey.useCorrections) private var useCorrections = true

    private var locked: Bool { model.batch.running }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FixLabel(text: model.t("app.fix.shared_label"))
            VStack(spacing: 0) {
                note
                    .padding(EdgeInsets(top: 14, leading: 14, bottom: 3, trailing: 14))
                VStack(spacing: 0) {
                    SettingsRow(model.t("app.fix.merge_gap"), description: model.t("app.fix.merge_gap_desc")) {
                        StepField(value: $mergeGap, step: 0.1, range: 0...5, decimals: 1, unit: secondsUnit, width: 64)
                    }
                    line
                    SettingsRow(model.t("app.fix.wrap"), description: model.t("app.fix.wrap_desc")) {
                        StepField(value: intBinding($wrapWidth), step: 1, range: 20...80, decimals: 0, width: 64)
                    }
                    line
                    SettingsRow(model.t("app.fix.lang"), description: model.t("app.fix.lang_desc")) { languagePopup }
                    line
                    listRow("app.fix.use_ignore", list: model.lists?.ignore, key: "app.fix.ignore_count", isOn: $useIgnore)
                    line
                    listRow("app.fix.use_corr", list: model.lists?.corrections, key: "app.fix.corr_count", isOn: $useCorrections)
                }
                .disabled(locked)
                .opacity(locked ? 0.45 : 1)
            }
            .svBox(RoundedRectangle(cornerRadius: SV.Radius.card), fill: SV.surface, line: SV.line)
        }
    }

    /// A row like `SettingsRow`, its description counting the list ("12 phrases to remove"),
    /// in yellow when the file is missing, nothing while the engine has not said.
    private func listRow(_ title: String, list: ListsStatus.List?, key: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.t(title)).svFont(13).foregroundStyle(SV.text)
                if let list {
                    let missing = !FileManager.default.fileExists(atPath: list.path)
                    Text(missing ? model.t("app.inspector.file_missing") : model.tn(key, list.count))
                        .svFont(SVFont.small).foregroundStyle(missing ? SV.yellowText : SV.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            FixSwitch(isOn: isOn)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
    }

    private var line: some View { Rectangle().fill(SV.line).frame(height: 1) }

    /// The slim accent note: what the box is (info), or the lock while a batch runs.
    private var note: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: locked ? "lock" : "info.circle").svFont(12.5)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            Text(model.t(locked ? "app.inspector.locked" : "app.fix.shared_note")).svFont(12, leading: 1.45)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(SV.primaryText)
        .svBox(RoundedRectangle(cornerRadius: 8), fill: SV.soft, line: SV.softLine,
               padding: EdgeInsets(vertical: 7, horizontal: 10))
    }

    private var secondsUnit: String { model.t("app.inspector.unit_s", ["value": ""]).trimmingCharacters(in: .whitespaces) }

    private func intBinding(_ b: Binding<Int>) -> Binding<Double> {
        Binding(get: { Double(b.wrappedValue) }, set: { b.wrappedValue = Int($0.rounded()) })
    }

    // MARK: - Language

    private var languages: [String]? {
        guard let list = model.hello?.languages, !list.isEmpty else { return nil }
        return list
    }

    private var languageMissing: Bool {
        guard let languages else { return false }
        return !languages.contains { $0.caseInsensitiveCompare(lang) == .orderedSame }
    }

    /// The popup of the Parameters panel, 170 pt wide: the name, the code in grey.
    private var languagePopup: some View {
        PopupMenu({ languageItems }) {
            HStack(spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(model.languageName(lang)).svFont(12).foregroundStyle(languageMissing ? SV.yellowText : SV.text).lineLimit(1)
                    Text(lang).svFont(11, mono: true).foregroundStyle(SV.text3).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").svFont(9, .semibold).foregroundStyle(SV.text2)
            }
            .frame(width: 170, height: 22)
            .svBox(RoundedRectangle(cornerRadius: SV.Radius.field), fill: SV.control, line: languageMissing ? SV.yellowLine : SV.glassLine,
                   padding: EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 8))
        }
        .disabled(languages == nil)
    }

    /// The Vision languages by name in the app's language, the code in grey; the current one checked.
    private var languageItems: [SVMenuItem] {
        guard let languages else { return [] }
        let sorted = languages.map { ($0, model.languageName($0)) }.sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
        var items: [SVMenuItem] = [.item(model.t("app.inspector.menu_title"), enabled: false) {}, .separator]
        items += sorted.map { code, name in
            .item(name, detail: code, checked: code.caseInsensitiveCompare(lang) == .orderedSame) { lang = code }
        }
        return items
    }
}

/// The small accent switch of the settings rows.
struct FixSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn).toggleStyle(.switch).controlSize(.small).labelsHidden().tint(SV.sysAccent)
    }
}

/// A value in a mono field with a stepper beside it ("0,2 s"): the field of
/// the boards (DS3), drawn here so the snapshots show it as it is.
struct SecondsStepper: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var text: (Double) -> String
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        HStack(spacing: 6) {
            Text(text(value)).svFont(SVFont.numbers).foregroundStyle(SV.textCode)
                .frame(width: 54, height: 24)
                .svBox(RoundedRectangle(cornerRadius: SV.Radius.field), fill: SV.inset, line: SV.line)
            VStack(spacing: 0) {
                stepButton("chevron.up") { nudge(+1) }
                Rectangle().fill(SV.line).frame(height: 1)
                stepButton("chevron.down") { nudge(-1) }
            }
            .frame(width: 16, height: 24)
            .svBox(RoundedRectangle(cornerRadius: 5), fill: SV.glass, line: SV.glassLine)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(text(value))
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).svFont(7, .bold).foregroundStyle(SV.text2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    /// One step up or down, kept on the grid of `step` and inside `range`.
    private func nudge(_ direction: Double) {
        let next = value + direction * step
        let snapped = (next / step).rounded() * step
        value = min(max(snapped, range.lowerBound), range.upperBound)
    }
}
