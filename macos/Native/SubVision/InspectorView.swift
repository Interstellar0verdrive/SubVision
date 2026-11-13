// SPDX-License-Identifier: MIT
// The parameters inspector (design boards I1–I3, D5, D13): five groups that
// open and close (their state in UserDefaults), every parameter bound to its
// `OcrKey` in UserDefaults through `@AppStorage`, an accent dot next to the
// values that differ from the engine's defaults, the default in the (?)
// bubble, "Default" per group and "Restore All Defaults" in the ⋯ menu
// (design note 14), the OCR language from `hello.languages` (design note 19),
// everything locked while a batch runs.

import SVShell
import SwiftUI

struct InspectorView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(OcrKey.fps) private var fps: Double = ocrDefaults.fps
    @AppStorage(OcrKey.langHint) private var lang: String = ocrDefaults.langHint
    @AppStorage(OcrKey.multiVariant) private var multiVariant: Bool = ocrDefaults.multiVariant
    @AppStorage(OcrKey.refineTiming) private var refineTiming: Bool = ocrDefaults.refineTiming
    @AppStorage(OcrKey.minConfidence) private var minConfidence: Double = ocrDefaults.minConfidence
    @AppStorage(OcrKey.bottomKeepPct) private var bottomKeepPct: Int = ocrDefaults.bottomKeepPct
    @AppStorage(OcrKey.keepWPct) private var keepWPct: Int = ocrDefaults.keepWPct
    @AppStorage(OcrKey.topBand) private var topBand: Bool = ocrDefaults.topBand
    @AppStorage(OcrKey.topKeepPct) private var topKeepPct: Int = ocrDefaults.topKeepPct
    @AppStorage(OcrKey.topKeepWPct) private var topKeepWPct: Int = ocrDefaults.topKeepWPct
    @AppStorage(OcrKey.minDuration) private var minDuration: Double = ocrDefaults.minDuration
    @AppStorage(OcrKey.mergeGap) private var mergeGap: Double = ocrDefaults.mergeGap
    @AppStorage(OcrKey.wrapWidth) private var wrapWidth: Int = ocrDefaults.wrapWidth
    @AppStorage(OcrKey.qcReport) private var qcReport: Bool = ocrDefaults.qcReport
    @AppStorage(OcrKey.qcGapWarn) private var qcGapWarn: Double = ocrDefaults.qcGapWarn
    @AppStorage(OcrKey.skipHamming) private var skipHamming: Int = ocrDefaults.skipHamming
    @AppStorage(OcrKey.workers) private var workers: Int = ocrDefaults.workers
    @AppStorage(OcrKey.useIgnore) private var useIgnore = true
    @AppStorage(OcrKey.useCorrections) private var useCorrections = true
    /// The request (`AppModel.languageMenuRequest`) the language menu opens for.
    @State private var languageMenuOpen = 0

    /// Locked during the batch (I3): the values it started with are in use.
    private var locked: Bool { model.batch.running }
    private let o = ocrDefaults

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 28)
                .padding(.bottom, 14)
            Rectangle().fill(SV.line).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        notes.id("top")
                        ocrGroup
                        dialogueGroup
                        signsGroup
                        segmentsGroup
                        advancedGroup
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
                .scrollClipDisabled()
                // "Choose the Language" (O7): the menu is at the top; it opens once it is in place.
                .onChange(of: model.languageMenuRequest) { _, request in
                    proxy.scrollTo("top", anchor: .top)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { languageMenuOpen = request }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SV.bg)
    }

    // MARK: - Header and notes

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(model.t("app.inspector.title")).svFont(SVFont.sectionTitle).foregroundStyle(SV.text)
                Spacer()
                PopupMenu({
                    [.item(model.t("app.inspector.restore_all"), enabled: !locked) { model.resetOcrParams() },
                     .separator,
                     .item(model.t("app.inspector.open_settings")) { openSettings() }]
                }) {
                    Image(systemName: "ellipsis").svFont(13, .semibold).foregroundStyle(SV.text2)
                        .frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .help(model.t("app.common.more"))
                Button { model.toggleInspector() } label: {
                    Image(systemName: "xmark").svFont(11, .semibold).foregroundStyle(SV.text2)
                        .frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(model.t("app.inspector.close"))
            }
            Text(model.t("app.inspector.subtitle")).svSmall().fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The app menu's Settings… item (⌘,), as the person would press it.
    private func openSettings() {
        guard let item = NSApp.mainMenu?.items.first?.submenu?.items.first(where: { $0.keyEquivalent == "," }) else { return }
        NSApp.sendAction(item.action!, to: item.target, from: item)
    }

    /// The language Vision reads here, or nil when the engine has not said yet.
    private var languages: [String]? {
        guard let list = model.hello?.languages, !list.isEmpty else { return nil }
        return list
    }

    private var languageMissing: Bool {
        guard let languages else { return false }
        return !languages.contains { $0.caseInsensitiveCompare(lang) == .orderedSame }
    }

    @ViewBuilder private var notes: some View {
        if locked {
            NoteView(.accent, text: model.t("app.inspector.locked")).padding(.top, 16)
        } else if languageMissing {
            NoteView(.yellow, text: model.t("app.inspector.lang_missing", ["lang": languageName(lang)])).padding(.top, 16)
        }
    }

    // MARK: - OCR

    private var ocrChanged: Bool {
        fps != o.fps || lang != o.langHint || multiVariant != o.multiVariant || refineTiming != o.refineTiming || minConfidence != o.minConfidence
    }

    private var ocrGroup: some View {
        InspectorGroup(id: "ocr", title: model.t("app.inspector.g.ocr"), changed: ocrChanged, locked: locked,
                       reset: { reset(OcrKey.fps, OcrKey.langHint, OcrKey.multiVariant, OcrKey.refineTiming, OcrKey.minConfidence) }) {
            InspectorRow(title: model.t("app.inspector.lang"), help: model.t("app.inspector.help.lang"),
                         defaultText: model.t("app.inspector.default_only", ["value": languageName(o.langHint)]),
                         changed: lang != o.langHint, stacked: true) {
                PopupMenu({ languageItems }, openRequest: languageMenuOpen) {
                    HStack(spacing: 6) {
                        Text(languageName(lang)).svFont(12.5).foregroundStyle(languageMissing ? SV.yellowText : SV.text).lineLimit(1)
                        Text(lang).svFont(11, mono: true).foregroundStyle(SV.text3)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up.chevron.down").svFont(9, .semibold).foregroundStyle(SV.text2)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 24)
                    .svBox(RoundedRectangle(cornerRadius: SV.Radius.field), fill: SV.control, line: languageMissing ? SV.yellowLine : SV.glassLine,
                           padding: EdgeInsets(vertical: 0, horizontal: 10))
                }
                .disabled(languages == nil)
            }
            InspectorSliderRow(title: model.t("app.inspector.fps"), help: model.t("app.inspector.help.fps"),
                               defaultText: model.t("app.inspector.default_range", ["value": model.localizer.number(o.fps), "range": "4–12"]),
                               changed: fps != o.fps, value: model.localizer.number(fps)) {
                SnapSlider(values: [4.0, 6, 8, 10, 12], selection: $fps, width: 268) { _ in "" }
            }
            InspectorRow(title: model.t("app.inspector.multi"), help: model.t("app.inspector.help.multi"),
                         defaultText: model.t("app.inspector.default_only", ["value": onOff(o.multiVariant)]), changed: multiVariant != o.multiVariant) {
                switchControl($multiVariant)
            }
            InspectorRow(title: model.t("app.inspector.refine"), help: model.t("app.inspector.help.refine"),
                         defaultText: model.t("app.inspector.default_only", ["value": onOff(o.refineTiming)]), changed: refineTiming != o.refineTiming) {
                switchControl($refineTiming)
            }
            InspectorSliderRow(title: model.t("app.inspector.conf"), help: model.t("app.inspector.help.conf"),
                               defaultText: model.t("app.inspector.default_range", ["value": model.localizer.number(o.minConfidence, decimals: 2), "range": "0,10–0,90"]),
                               changed: minConfidence != o.minConfidence, value: model.localizer.number(minConfidence, decimals: 2)) {
                SVSlider(value: Binding(get: { minConfidence }, set: { minConfidence = ($0 * 20).rounded() / 20 }), in: 0.1...0.9)
            }
        }
    }

    /// The menu of D13: the Vision languages by name in the app's language, the code in grey.
    private var languageItems: [SVMenuItem] {
        guard let languages else { return [] }
        let sorted = languages.map { ($0, languageName($0)) }.sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
        var items: [SVMenuItem] = [.item(model.t("app.inspector.menu_title"), enabled: false) {}, .separator]
        items += sorted.map { code, name in
            .item(name, detail: code, checked: code.caseInsensitiveCompare(lang) == .orderedSame) { lang = code }
        }
        return items
    }

    /// "Italiano" when Vision has one variant of the language, the whole name when it has several (the code is next to it).
    private func languageName(_ code: String) -> String { model.languageName(code) }

    // MARK: - Bands

    private var dialogueChanged: Bool { bottomKeepPct != o.bottomKeepPct || keepWPct != o.keepWPct }

    private var dialogueGroup: some View {
        InspectorGroup(id: "dlg", title: model.t("app.inspector.g.dlg"), changed: dialogueChanged, locked: locked,
                       reset: { reset(OcrKey.bottomKeepPct, OcrKey.keepWPct) }) {
            pctRow(model.t("app.inspector.bottom"), help: model.t("app.inspector.help.bottom"), $bottomKeepPct, default: o.bottomKeepPct, range: 5...80)
            pctRow(model.t("app.inspector.width"), help: model.t("app.inspector.help.width"), $keepWPct, default: o.keepWPct, range: 50...100)
        }
    }

    private var signsChanged: Bool { topBand != o.topBand || topKeepPct != o.topKeepPct || topKeepWPct != o.topKeepWPct }

    private var signsGroup: some View {
        InspectorGroup(id: "sig", title: model.t("app.inspector.g.sig"), changed: signsChanged, locked: locked,
                       reset: { reset(OcrKey.topBand, OcrKey.topKeepPct, OcrKey.topKeepWPct) },
                       toggle: $topBand, toggleHelp: model.t("app.inspector.help.sig_on"), toggleChanged: topBand != o.topBand) {
            Group {
                pctRow(model.t("app.inspector.top"), help: model.t("app.inspector.help.top"), $topKeepPct, default: o.topKeepPct, range: 5...50)
                pctRow(model.t("app.inspector.topw"), help: model.t("app.inspector.help.topw"), $topKeepWPct, default: o.topKeepWPct, range: 50...100)
            }
            .disabled(!topBand)
            .opacity(topBand ? 1 : 0.45)
        }
    }

    private func pctRow(_ title: String, help: String, _ value: Binding<Int>, default d: Int, range: ClosedRange<Int>) -> some View {
        InspectorSliderRow(title: title, help: help,
                           defaultText: model.t("app.inspector.default_range", ["value": model.t("app.inspector.unit_pct", ["value": d]),
                                                                                "range": "\(range.lowerBound)–\(range.upperBound) %"]),
                           changed: value.wrappedValue != d, value: model.t("app.inspector.unit_pct", ["value": value.wrappedValue])) {
            SVSlider(value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0.rounded()) }),
                     in: Double(range.lowerBound)...Double(range.upperBound))
        }
    }

    // MARK: - Segments

    private var segmentsChanged: Bool { minDuration != o.minDuration || mergeGap != o.mergeGap || wrapWidth != o.wrapWidth }

    private var segmentsGroup: some View {
        InspectorGroup(id: "seg", title: model.t("app.inspector.g.seg"), changed: segmentsChanged, locked: locked,
                       reset: { reset(OcrKey.minDuration, OcrKey.mergeGap, OcrKey.wrapWidth) }) {
            InspectorRow(title: model.t("app.inspector.mindur"), help: model.t("app.inspector.help.mindur"),
                         defaultText: model.t("app.inspector.default_only", ["value": seconds(o.minDuration)]), changed: minDuration != o.minDuration) {
                StepField(value: $minDuration, step: 0.05, range: 0...5, decimals: 2, unit: model.t("app.inspector.unit_s", ["value": ""]).trimmingCharacters(in: .whitespaces))
            }
            InspectorRow(title: model.t("app.inspector.merge"), help: model.t("app.inspector.help.merge"),
                         defaultText: model.t("app.inspector.default_only", ["value": seconds(o.mergeGap)]), changed: mergeGap != o.mergeGap) {
                StepField(value: $mergeGap, step: 0.1, range: 0...5, decimals: 1, unit: model.t("app.inspector.unit_s", ["value": ""]).trimmingCharacters(in: .whitespaces))
            }
            InspectorRow(title: model.t("app.inspector.wrap"), help: model.t("app.inspector.help.wrap"),
                         defaultText: model.t("app.inspector.default_range", ["value": o.wrapWidth, "range": "20–80"]), changed: wrapWidth != o.wrapWidth) {
                StepField(value: intBinding($wrapWidth), step: 1, range: 20...80, decimals: 0)
            }
        }
    }

    // MARK: - Advanced

    private var advancedChanged: Bool {
        qcReport != o.qcReport || qcGapWarn != o.qcGapWarn || skipHamming != o.skipHamming || workers != o.workers || !useIgnore || !useCorrections
    }

    private var advancedGroup: some View {
        InspectorGroup(id: "adv", title: model.t("app.inspector.g.adv"), changed: advancedChanged, locked: locked,
                       reset: { reset(OcrKey.qcReport, OcrKey.qcGapWarn, OcrKey.skipHamming, OcrKey.workers, OcrKey.useIgnore, OcrKey.useCorrections) }) {
            InspectorRow(title: model.t("app.inspector.report"), help: model.t("app.inspector.help.report"),
                         defaultText: model.t("app.inspector.default_only", ["value": onOff(o.qcReport)]), changed: qcReport != o.qcReport) {
                switchControl($qcReport)
            }
            InspectorRow(title: model.t("app.inspector.gap"), help: model.t("app.inspector.help.gap"),
                         defaultText: model.t("app.inspector.default_only", ["value": seconds(o.qcGapWarn, decimals: 0)]), changed: qcGapWarn != o.qcGapWarn) {
                StepField(value: $qcGapWarn, step: 1, range: 1...60, decimals: 0, unit: model.t("app.inspector.unit_s", ["value": ""]).trimmingCharacters(in: .whitespaces))
            }
            .disabled(!qcReport)
            .opacity(qcReport ? 1 : 0.45)
            InspectorSliderRow(title: model.t("app.inspector.skip"), help: model.t("app.inspector.help.skip"),
                               defaultText: model.t("app.inspector.default_range", ["value": o.skipHamming, "range": "0–3"]),
                               changed: skipHamming != o.skipHamming, value: skipHamming == 0 ? model.t("app.inspector.skip_none") : "\(skipHamming)") {
                SnapSlider(values: [0, 1, 2, 3], selection: $skipHamming, width: 268) { _ in "" }
            }
            InspectorRow(title: model.t("app.inspector.workers"), help: model.t("app.inspector.help.workers"),
                         defaultText: model.t("app.inspector.default_range", ["value": o.workers, "range": "1–8"]), changed: workers != o.workers) {
                StepField(value: intBinding($workers), step: 1, range: 1...8, decimals: 0)
            }
            InspectorRow(title: model.t("app.inspector.ignore"), help: model.t("app.inspector.help.ignore"),
                         defaultText: model.t("app.inspector.default_only", ["value": onOff(true)]), changed: !useIgnore,
                         note: listNote(model.lists?.ignore, key: "app.inspector.phrases")) {
                switchControl($useIgnore)
            }
            InspectorRow(title: model.t("app.inspector.corr"), help: model.t("app.inspector.help.corr"),
                         defaultText: model.t("app.inspector.default_only", ["value": onOff(true)]), changed: !useCorrections,
                         note: listNote(model.lists?.corrections, key: "app.inspector.corrections")) {
                switchControl($useCorrections)
            }
        }
    }

    /// "12 frasi" · "4 correzioni" · "file mancante" (yellow) next to the list switches (I3).
    private func listNote(_ list: ListsStatus.List?, key: String) -> (String, Color)? {
        guard let list else { return nil }
        if !FileManager.default.fileExists(atPath: list.path) { return (model.t("app.inspector.file_missing"), SV.yellowText) }
        return (model.tn(key, list.count), SV.text2)
    }

    // MARK: - Helpers

    private func switchControl(_ value: Binding<Bool>) -> some View {
        Toggle("", isOn: value).toggleStyle(.switch).controlSize(.small).labelsHidden().tint(SV.primary)
    }

    private func intBinding(_ b: Binding<Int>) -> Binding<Double> {
        Binding(get: { Double(b.wrappedValue) }, set: { b.wrappedValue = Int($0.rounded()) })
    }

    private func onOff(_ on: Bool) -> String { model.t(on ? "app.common.on_state" : "app.common.off_state") }

    private func seconds(_ value: Double, decimals: Int = 2) -> String {
        model.t("app.inspector.unit_s", ["value": model.localizer.number(value, decimals: decimals)])
    }

    /// "Default" of a group: the keys go, the engine's defaults are back.
    private func reset(_ keys: String...) {
        for key in keys { model.defaults.removeObject(forKey: key) }
    }
}

// MARK: - Group

/// A group of the inspector: chevron, title, an optional switch (the signs
/// band), "Default" lit when a value differs; open or closed in UserDefaults.
struct InspectorGroup<Content: View>: View {
    @Environment(AppModel.self) private var model
    var id: String
    var title: String
    var changed: Bool
    var locked: Bool
    var reset: () -> Void
    var toggle: Binding<Bool>?
    var toggleHelp: String?
    var toggleChanged = false
    @ViewBuilder var content: () -> Content
    @AppStorage private var open: Bool

    init(id: String, title: String, changed: Bool, locked: Bool, reset: @escaping () -> Void,
         toggle: Binding<Bool>? = nil, toggleHelp: String? = nil, toggleChanged: Bool = false,
         @ViewBuilder content: @escaping () -> Content) {
        self.id = id
        self.title = title
        self.changed = changed
        self.locked = locked
        self.reset = reset
        self.toggle = toggle
        self.toggleHelp = toggleHelp
        self.toggleChanged = toggleChanged
        self.content = content
        _open = AppStorage(wrappedValue: true, "inspector.group.\(id)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right").svFont(10, .semibold).foregroundStyle(SV.text2)
                            .rotationEffect(.degrees(open ? 90 : 0))
                        Text(title).svFont(13, .semibold).foregroundStyle(SV.text)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if let toggle {
                    HStack(spacing: 4) {
                        if toggleChanged { ChangedDot() }
                        Toggle("", isOn: toggle).toggleStyle(.switch).controlSize(.small).labelsHidden().tint(SV.primary)
                            .help(toggleHelp ?? "")
                    }
                    .disabled(locked)
                    .opacity(locked ? 0.45 : 1)
                }
                Spacer()
                Button(model.t("app.common.defaults")) { reset() }
                    .buttonStyle(.plain)
                    .font(SVFont.small.font)
                    .foregroundStyle(changed && !locked ? SV.primaryText : SV.text3)
                    .disabled(!changed || locked)
            }
            .frame(height: 36)
            if open {
                VStack(alignment: .leading, spacing: 10) { content() }
                    .padding(.bottom, 12)
                    .disabled(locked)
                    .opacity(locked ? 0.45 : 1)
            }
            Rectangle().fill(SV.line).frame(height: 1)
        }
    }
}

/// The accent dot next to a value that differs from the default (design note 14).
struct ChangedDot: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Circle().fill(SV.primary).frame(width: 5, height: 5)
            .help(model.t("app.inspector.changed"))
            .accessibilityLabel(model.t("app.inspector.changed"))
    }
}

/// The (?) bubble: the long explanation and the default (with its range).
struct HelpButton: View {
    var text: String
    var defaultText: String
    var title: String
    @State private var shown = false
    @State private var hover = false

    var body: some View {
        Button { shown.toggle() } label: {
            Text("?").svFont(9, .semibold).foregroundStyle(hover || shown ? SV.text : SV.text3)
                .frame(width: 14, height: 14)
                .background(Circle().fill(hover || shown ? SV.glass : .clear))
                .overlay(Circle().strokeBorder(SV.glassLine))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .popover(isPresented: $shown, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).svFont(12.5, .semibold).foregroundStyle(SV.text)
                Text(text).svSmall(SV.text).fixedSize(horizontal: false, vertical: true)
                Text(defaultText).svFont(11.5).foregroundStyle(SV.text2)
            }
            .padding(14)
            .frame(width: 290, alignment: .leading)
        }
        .accessibilityLabel(title)
    }
}

/// A one-line row: title with its (?), the dot when changed, the control on
/// the right (`stacked`: the control takes the next line, for the language menu).
struct InspectorRow<Control: View>: View {
    var title: String
    var help: String
    var defaultText: String
    var changed: Bool
    var stacked = false
    var note: (String, Color)?
    @ViewBuilder var control: () -> Control

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title).svFont(12.5).foregroundStyle(SV.text2).fixedSize(horizontal: false, vertical: true)
                HelpButton(text: help, defaultText: defaultText, title: title)
                Spacer(minLength: 8)
                if let note { Text(note.0).svFont(11.5).foregroundStyle(note.1) }
                if changed { ChangedDot() }
                if !stacked { control() }
            }
            if stacked { control() }
        }
    }
}

/// A two-line row: title, (?), the value on the right; the slider under it.
struct InspectorSliderRow<Slider: View>: View {
    var title: String
    var help: String
    var defaultText: String
    var changed: Bool
    var value: String
    @ViewBuilder var slider: () -> Slider

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title).svFont(12.5).foregroundStyle(SV.text2).fixedSize(horizontal: false, vertical: true)
                HelpButton(text: help, defaultText: defaultText, title: title)
                Spacer(minLength: 8)
                if changed { ChangedDot() }
                Text(value).svFont(SVFont.numbers).foregroundStyle(SV.textCode)
            }
            slider()
        }
    }
}

/// A number in a field with a stepper ("0,20 s", "42"): typing commits on Return.
struct StepField: View {
    @Binding var value: Double
    var step: Double
    var range: ClosedRange<Double>
    var decimals: Int
    var unit: String?
    @Environment(AppModel.self) private var model
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 4) {
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(SVFont.numbers.font)
                    .foregroundStyle(SV.textCode)
                    .multilineTextAlignment(.leading)
                    .focused($focused)
                    .onSubmit { commit() }
                    .onChange(of: focused) { _, now in if !now { commit() } }
                if let unit { Text(unit).svFont(SVFont.numbers).foregroundStyle(SV.text3) }
            }
            .frame(width: 60, height: 24)
            .svBox(RoundedRectangle(cornerRadius: SV.Radius.field), fill: SV.control, line: SV.glassLine,
                   padding: EdgeInsets(vertical: 0, horizontal: 8))
            Stepper("", value: $value, in: range, step: step).labelsHidden().controlSize(.small)
        }
        .onAppear { text = format(value) }
        .onChange(of: value) { _, now in if !focused { text = format(now) } }
    }

    private func format(_ v: Double) -> String { model.localizer.number(v, decimals: decimals) }

    private func commit() {
        let normalised = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        if let v = Double(normalised) {
            let stepped = (v / step).rounded() * step
            value = min(max(stepped, range.lowerBound), range.upperBound)
        }
        text = format(value)
    }
}
