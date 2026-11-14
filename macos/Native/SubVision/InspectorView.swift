// SPDX-License-Identifier: MIT
// The parameters panel (design boards C2-P1–P3, C2-N1, C2-V1/V3, C2-A1–A3;
// design notes 49, 50, 51, 57): a header that keeps the panel's background
// over the scrolled content (a line under it once the content has moved), the
// number of values that differ from the default with "↺ Ripristina" (undone
// with ⌘Z), three tabs remembered in UserDefaults (Lettura, Bande, Righe),
// sections with their own "Predefinito", every parameter bound to its `OcrKey`
// through `@AppStorage`, an accent dot on the values that differ, the default
// in the (?) bubble, the OCR language from `hello.languages`, the frame's
// schema in the main window's Bande, everything locked while a batch runs.
// Everything about values that differ from the default is in the `modified`
// colour, not the accent (design note 81, C3-10, boards I1–I3), and a slider
// away from its default shows a grey tick there that brings it back.

import SVShell
import SwiftUI

/// Where the parameters panel is: the main window (Video, with the frame's schema in
/// Bands) or the Preview page (no schema: the frame is next to it).
enum InspectorPlace { case main, preview }

/// The panel's tabs (design note 51). The raw values are those of `key` in UserDefaults.
enum InspectorTab: String, CaseIterable {
    case read, bands, lines

    /// The UserDefaults key of the chosen tab ("Scegli la lingua" sets it to `read`).
    static let key = "inspector.tab"
}

struct InspectorView: View {
    var place: InspectorPlace = .main
    @Environment(AppModel.self) private var model
    @AppStorage(InspectorTab.key) private var tab: InspectorTab = .read
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
    /// The content has moved under the header: the header shows its bottom line (note 49).
    @State private var scrolled = false

    init(place: InspectorPlace = .main) { self.place = place }

    /// Locked during the batch (C2-P3, C2-A3): the values it started with are in use.
    private var locked: Bool { model.batch.running }
    private let o = ocrDefaults
    /// The width of a slider: the panel less its 16 pt sides.
    private let sliderWidth: CGFloat = 308

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(EdgeInsets(top: 18, leading: 16, bottom: 12, trailing: 16))
                .background(SV.surface)
                .overlay(alignment: .bottom) { Rectangle().fill(scrolled ? SV.line : .clear).frame(height: 1) }
                .zIndex(1)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 0).id("top")
                        notes
                        Group {
                            switch tab {
                            case .read: readTab
                            case .bands: bandsTab
                            case .lines: linesTab
                            }
                        }
                        .disabled(locked)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 0.5 } action: { _, now in
                    scrolled = now
                }
                .onChange(of: tab) { proxy.scrollTo("top", anchor: .top) }
                // "Scegli la lingua" (O7): Lettura, the menu at the top; it opens once it is in place.
                .onChange(of: model.languageMenuRequest) { _, request in
                    guard place == .main else { return }
                    tab = .read
                    proxy.scrollTo("top", anchor: .top)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { languageMenuOpen = request }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SV.surface)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(model.t("app.inspector.title")).svFont(15, .bold).foregroundStyle(SV.text)
                Spacer(minLength: 0)
                // No × even over a narrow window (N2): the top bar's panel button closes it, as Esc does.
            }
            .frame(height: 24)
            Text(model.t("app.inspector.subtitle")).svFont(11.5, leading: 1.4).foregroundStyle(SV.text2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
            if changedCount > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(model.tn("app.inspector.changed_count", changedCount)).foregroundStyle(SV.modified)
                    Spacer(minLength: 0)
                    restoreLink
                }
                .svFont(11.5, leading: 1.4)
                .padding(.top, 1)
            }
            tabs.padding(.top, 12)
        }
    }

    /// "↺ Ripristina" (note 57): every value back to the default, no confirmation, ⌘Z undoes it.
    private var restoreLink: some View {
        Button { model.resetAllParameters() } label: {
            HStack(spacing: 3) {
                Image(systemName: "arrow.counterclockwise").font(.system(size: 9.5, weight: .semibold))
                Text(model.t("app.inspector.restore")).underline(true, color: SV.modified.opacity(0.55))
            }
            .foregroundStyle(SV.modified)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .opacity(locked ? 0.45 : 1)
        .help(model.t("app.inspector.restore_help"))
    }

    /// The capsule tabs, a dot on the ones with a value that differs; they switch during the batch too.
    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(InspectorTab.allCases, id: \.self) { item in
                let on = item == tab
                Button { tab = item } label: {
                    HStack(spacing: 6) {
                        Text(model.t("app.inspector.tab.\(item.rawValue)")).svControlFont(12, on ? .medium : .regular)
                        if tabChanged(item) {
                            Circle().fill(SV.modified).frame(width: 6, height: 6)
                                .accessibilityLabel(model.t("app.inspector.changed"))
                        }
                    }
                    .foregroundStyle(on ? SV.text : SV.text2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 24)
                    .background(Capsule(style: .circular).fill(on ? SV.segOn : .clear)
                        .shadow(color: on ? SV.segShadow : .clear, radius: 1, y: 1))
                    .contentShape(Capsule(style: .circular))
                    .svHover(Capsule(style: .circular), enabled: !on)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        // Round ends, as the board's 999 px radius (a continuous capsule flattens them).
        .svBox(Capsule(style: .circular), fill: SV.glass, line: SV.glassLine, padding: EdgeInsets(vertical: 2, horizontal: 2))
    }

    // MARK: - Notes

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
            lockedNote.padding(.top, 6).padding(.bottom, 2)
        } else if languageMissing && tab == .read {
            NoteView(.yellow, text: model.t("app.inspector.lang_missing", ["lang": languageName(lang)]))
                .padding(.top, 6).padding(.bottom, 2)
        }
    }

    /// The slim accent note with a lock (C2-P3): what the batch uses.
    private var lockedNote: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "lock").svFont(12.5)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            Text(model.t("app.inspector.locked")).svFont(12, leading: 1.45)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(SV.primaryText)
        .svBox(RoundedRectangle(cornerRadius: 8), fill: SV.soft, line: SV.softLine,
               padding: EdgeInsets(vertical: 7, horizontal: 10))
    }

    // MARK: - What differs

    private func differs(_ a: Double, _ b: Double) -> Bool { abs(a - b) > 1e-9 }

    private var recognitionChanges: [Bool] {
        [lang != o.langHint, differs(fps, o.fps), multiVariant != o.multiVariant, differs(minConfidence, o.minConfidence)]
    }
    private var speedChanges: [Bool] { [skipHamming != o.skipHamming, workers != o.workers] }
    private var signsChanges: [Bool] { [topBand != o.topBand, topKeepPct != o.topKeepPct, topKeepWPct != o.topKeepWPct] }
    private var dialogueChanges: [Bool] { [bottomKeepPct != o.bottomKeepPct, keepWPct != o.keepWPct] }
    private var linesChanges: [Bool] {
        [differs(minDuration, o.minDuration), differs(mergeGap, o.mergeGap), wrapWidth != o.wrapWidth, refineTiming != o.refineTiming]
    }
    private var fileChanges: [Bool] { [qcReport != o.qcReport, differs(qcGapWarn, o.qcGapWarn), !useIgnore, !useCorrections] }

    /// The values of the panel that differ from the default (the header's count).
    private var changedCount: Int {
        (recognitionChanges + speedChanges + signsChanges + dialogueChanges + linesChanges + fileChanges).filter { $0 }.count
    }

    private func tabChanged(_ tab: InspectorTab) -> Bool {
        switch tab {
        case .read: (recognitionChanges + speedChanges).contains(true)
        case .bands: (signsChanges + dialogueChanges).contains(true)
        case .lines: (linesChanges + fileChanges).contains(true)
        }
    }

    // MARK: - Lettura

    @ViewBuilder private var readTab: some View {
        InspectorSection(title: model.t("app.inspector.sec.recognition"), changed: recognitionChanges.contains(true),
                         reset: { model.restoreDefaults([OcrKey.langHint, OcrKey.fps, OcrKey.multiVariant, OcrKey.minConfidence]) }) {
            ParamRow(title: model.t("app.inspector.lang"), help: model.t("app.inspector.help.lang"),
                     defaultText: model.t("app.inspector.default_only", ["value": languageName(o.langHint)]),
                     changed: lang != o.langHint, below: true) {
                languagePopup
            }
            ParamRow(title: model.t("app.inspector.fps"), help: model.t("app.inspector.help.fps"),
                     defaultText: model.t("app.inspector.default_range", ["value": model.localizer.number(o.fps), "range": "4–12"]),
                     changed: differs(fps, o.fps), value: model.localizer.number(fps)) {
                SnapSlider(values: [4.0, 6, 8, 10, 12], selection: $fps, width: sliderWidth,
                           defaultValue: o.fps, defaultHelp: defaultHelp(model.localizer.number(o.fps)))
            }
            ParamRow(title: model.t("app.inspector.multi"), help: model.t("app.inspector.help.multi"),
                     defaultText: model.t("app.inspector.default_only", ["value": onOff(o.multiVariant)]), changed: multiVariant != o.multiVariant) {
                InspectorSwitch(isOn: $multiVariant)
            }
            ParamRow(title: model.t("app.inspector.conf"), help: model.t("app.inspector.help.conf"),
                     defaultText: model.t("app.inspector.default_range", ["value": model.localizer.number(o.minConfidence, decimals: 2), "range": "0,10–0,90"]),
                     changed: differs(minConfidence, o.minConfidence), value: model.localizer.number(minConfidence, decimals: 2)) {
                SVSlider(value: Binding(get: { minConfidence }, set: { minConfidence = ($0 * 20).rounded() / 20 }), in: 0.1...0.9,
                         defaultValue: o.minConfidence, defaultHelp: defaultHelp(model.localizer.number(o.minConfidence, decimals: 2)))
            }
        }
        SectionLine()
        InspectorSection(title: model.t("app.inspector.sec.speed"), description: model.t("app.inspector.sec.speed_text"),
                         changed: speedChanges.contains(true), reset: { model.restoreDefaults([OcrKey.skipHamming, OcrKey.workers]) }) {
            ParamRow(title: model.t("app.inspector.skip"), help: model.t("app.inspector.help.skip"),
                     defaultText: model.t("app.inspector.default_range", ["value": o.skipHamming, "range": "0–3"]),
                     changed: skipHamming != o.skipHamming, value: "\(skipHamming)") {
                SnapSlider(values: [0, 1, 2, 3], selection: $skipHamming, width: sliderWidth,
                           defaultValue: o.skipHamming, defaultHelp: defaultHelp("\(o.skipHamming)"))
            }
            ParamRow(title: model.t("app.inspector.workers"), help: model.t("app.inspector.help.workers"),
                     defaultText: model.t("app.inspector.default_range", ["value": o.workers, "range": "1–8"]), changed: workers != o.workers) {
                StepField(value: intBinding($workers), step: 1, range: 1...8, decimals: 0)
            }
        }
    }

    /// The language popup, the whole width: the name, the code in grey (C2-P1).
    private var languagePopup: some View {
        PopupMenu({ languageItems }, openRequest: languageMenuOpen) {
            HStack(spacing: 6) {
                Text(languageName(lang)).svFont(12).foregroundStyle(languageMissing ? SV.yellowText : SV.text).lineLimit(1)
                Text(lang).svFont(11, mono: true).foregroundStyle(SV.text3)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").svFont(9, .semibold).foregroundStyle(SV.text2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .svBox(RoundedRectangle(cornerRadius: SV.Radius.field), fill: SV.control, line: languageMissing ? SV.yellowLine : SV.glassLine,
                   padding: EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 8))
        }
        .disabled(languages == nil)
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

    // MARK: - Bande

    @ViewBuilder private var bandsTab: some View {
        if place == .main {
            BandSchema(signsOn: topBand, topPct: topKeepPct, topWPct: topKeepWPct, bottomPct: bottomKeepPct, bottomWPct: keepWPct,
                       signs: model.t("app.inspector.sec.signs"), signsOff: model.t("app.inspector.schema_signs_off"),
                       dialogue: model.t("app.inspector.sec.dialogue"), label: model.t("app.inspector.schema_label"))
                .padding(.top, 12)
                .padding(.bottom, 4)
            SectionText(model.t("app.inspector.schema_caption")).padding(.bottom, 4)
        } else {
            // The Preview page: the frame is next to the panel (C2-A1, C3-09).
            SectionText(model.t(locked ? "app.inspector.bands_locked" : "app.inspector.bands_preview")).padding(.top, 12)
        }
        InspectorSection(changed: signsChanges.contains(true),
                         reset: { model.restoreDefaults([OcrKey.topBand, OcrKey.topKeepPct, OcrKey.topKeepWPct]) }) {
            HStack(spacing: 6) {
                BandSwatch(color: BandColors.signs)
                Text(model.t("app.inspector.sec.signs")).svFont(12.5, .semibold).foregroundStyle(SV.text)
                InspectorSwitch(isOn: $topBand)
                    .padding(.leading, 6)
                    .help(model.t("app.inspector.help.sig_on"))
            }
        } content: {
            Group {
                pctRow(model.t("app.inspector.top"), help: model.t("app.inspector.help.top"), $topKeepPct, default: o.topKeepPct, range: 5...50)
                pctRow(model.t("app.inspector.topw"), help: model.t("app.inspector.help.topw"), $topKeepWPct, default: o.topKeepWPct, range: 50...100)
            }
            .disabled(!topBand)
        }
        SectionLine()
        InspectorSection(changed: dialogueChanges.contains(true), reset: { model.restoreDefaults([OcrKey.bottomKeepPct, OcrKey.keepWPct]) }) {
            HStack(spacing: 6) {
                BandSwatch(color: BandColors.dialogue)
                Text(model.t("app.inspector.sec.dialogue")).svFont(12.5, .semibold).foregroundStyle(SV.text)
            }
        } content: {
            pctRow(model.t("app.inspector.bottom"), help: model.t("app.inspector.help.bottom"), $bottomKeepPct, default: o.bottomKeepPct, range: 5...80)
            pctRow(model.t("app.inspector.width"), help: model.t("app.inspector.help.width"), $keepWPct, default: o.keepWPct, range: 50...100)
        }
    }

    private func pctRow(_ title: String, help: String, _ value: Binding<Int>, default d: Int, range: ClosedRange<Int>) -> some View {
        ParamRow(title: title, help: help,
                 defaultText: model.t("app.inspector.default_range", ["value": model.t("app.inspector.unit_pct", ["value": d]),
                                                                      "range": "\(range.lowerBound)–\(range.upperBound) %"]),
                 changed: value.wrappedValue != d, value: model.t("app.inspector.unit_pct", ["value": value.wrappedValue])) {
            SVSlider(value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0.rounded()) }),
                     in: Double(range.lowerBound)...Double(range.upperBound),
                     defaultValue: Double(d), defaultHelp: defaultHelp(model.t("app.inspector.unit_pct", ["value": d])))
        }
    }

    // MARK: - Righe

    @ViewBuilder private var linesTab: some View {
        InspectorSection(title: model.t("app.inspector.sec.lines"), changed: linesChanges.contains(true),
                         reset: { model.restoreDefaults([OcrKey.minDuration, OcrKey.mergeGap, OcrKey.wrapWidth, OcrKey.refineTiming]) }) {
            ParamRow(title: model.t("app.inspector.mindur"), help: model.t("app.inspector.help.mindur"),
                     defaultText: model.t("app.inspector.default_only", ["value": seconds(o.minDuration)]), changed: differs(minDuration, o.minDuration)) {
                StepField(value: $minDuration, step: 0.05, range: 0...5, decimals: 2, unit: secondsUnit, width: 64)
            }
            ParamRow(title: model.t("app.inspector.merge"), help: model.t("app.inspector.help.merge"),
                     defaultText: model.t("app.inspector.default_only", ["value": seconds(o.mergeGap, decimals: 1)]), changed: differs(mergeGap, o.mergeGap)) {
                StepField(value: $mergeGap, step: 0.1, range: 0...5, decimals: 1, unit: secondsUnit, width: 64)
            }
            ParamRow(title: model.t("app.inspector.wrap"), help: model.t("app.inspector.help.wrap"),
                     defaultText: model.t("app.inspector.default_range", ["value": o.wrapWidth, "range": "20–80"]), changed: wrapWidth != o.wrapWidth) {
                StepField(value: intBinding($wrapWidth), step: 1, range: 20...80, decimals: 0, width: 64)
            }
            ParamRow(title: model.t("app.inspector.refine"), help: model.t("app.inspector.help.refine"),
                     defaultText: model.t("app.inspector.default_only", ["value": onOff(o.refineTiming)]), changed: refineTiming != o.refineTiming) {
                InspectorSwitch(isOn: $refineTiming)
            }
        }
        SectionLine()
        InspectorSection(title: model.t("app.inspector.sec.files"), changed: fileChanges.contains(true),
                         reset: { model.restoreDefaults([OcrKey.qcReport, OcrKey.qcGapWarn, OcrKey.useIgnore, OcrKey.useCorrections]) }) {
            ParamRow(title: model.t("app.inspector.report"), help: model.t("app.inspector.help.report"),
                     defaultText: model.t("app.inspector.default_only", ["value": onOff(o.qcReport)]), changed: qcReport != o.qcReport) {
                InspectorSwitch(isOn: $qcReport)
            }
            ParamRow(title: model.t("app.inspector.gap"), help: model.t("app.inspector.help.gap"),
                     defaultText: model.t("app.inspector.default_only", ["value": seconds(o.qcGapWarn, decimals: 0)]), changed: differs(qcGapWarn, o.qcGapWarn)) {
                StepField(value: $qcGapWarn, step: 1, range: 1...60, decimals: 0, unit: secondsUnit, width: 64)
            }
            .disabled(!qcReport)
            ParamRow(title: model.t("app.inspector.ignore"), help: model.t("app.inspector.help.ignore"),
                     defaultText: model.t("app.inspector.default_only", ["value": onOff(true)]), changed: !useIgnore,
                     note: listNote(model.lists?.ignore, key: "app.inspector.phrases")) {
                InspectorSwitch(isOn: $useIgnore)
            }
            ParamRow(title: model.t("app.inspector.corr"), help: model.t("app.inspector.help.corr"),
                     defaultText: model.t("app.inspector.default_only", ["value": onOff(true)]), changed: !useCorrections,
                     note: listNote(model.lists?.corrections, key: "app.inspector.corrections")) {
                InspectorSwitch(isOn: $useCorrections)
            }
        }
    }

    /// "12 frasi" · "4 correzioni" · "file mancante" (yellow) next to the list switches (C2-P3).
    private func listNote(_ list: ListsStatus.List?, key: String) -> (String, Color)? {
        guard let list else { return nil }
        if !FileManager.default.fileExists(atPath: list.path) { return (model.t("app.inspector.file_missing"), SV.yellowText) }
        return (model.tn(key, list.count), SV.text2)
    }

    // MARK: - Helpers

    private func intBinding(_ b: Binding<Int>) -> Binding<Double> {
        Binding(get: { Double(b.wrappedValue) }, set: { b.wrappedValue = Int($0.rounded()) })
    }

    /// The tooltip of a slider's default tick: "Predefinito: 28 % · clic per tornarci".
    private func defaultHelp(_ value: String) -> String { model.t("app.inspector.default_tick", ["value": value]) }

    private func onOff(_ on: Bool) -> String { model.t(on ? "app.inspector.on" : "app.inspector.off") }

    private var secondsUnit: String { model.t("app.inspector.unit_s", ["value": ""]).trimmingCharacters(in: .whitespaces) }

    private func seconds(_ value: Double, decimals: Int = 2) -> String {
        model.t("app.inspector.unit_s", ["value": model.localizer.number(value, decimals: decimals)])
    }
}

// MARK: - Sections

/// A section of the panel (`.sec`): its title (or what the band sections put
/// there), "↺ Predefinito" in the `modified` colour when one of its values
/// differs (it resets them, off while disabled: the batch), an optional
/// description, the rows.
struct InspectorSection<Title: View, Content: View>: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isEnabled) private var enabled
    var description: String?
    var changed: Bool
    var reset: () -> Void
    @ViewBuilder var title: () -> Title
    @ViewBuilder var content: () -> Content

    init(description: String? = nil, changed: Bool, reset: @escaping () -> Void,
         @ViewBuilder title: @escaping () -> Title, @ViewBuilder content: @escaping () -> Content) {
        self.description = description
        self.changed = changed
        self.reset = reset
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                title()
                Spacer(minLength: 8)
                Button { reset() } label: {
                    HStack(spacing: 3) {
                        if changed { Image(systemName: "arrow.counterclockwise").font(.system(size: 9.5, weight: .semibold)) }
                        Text(model.t("app.common.defaults"))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .svFont(11.5, .medium)
                .foregroundStyle(changed ? SV.modified.opacity(enabled ? 1 : 0.45) : SV.text3.opacity(0.6))
                .disabled(!changed)
                .help(changed ? model.t("app.inspector.section_reset_help") : "")
            }
            .frame(height: 24)
            if let description { SectionText(description).padding(.bottom, 2) }
            content()
        }
        .padding(.top, 14)
        .padding(.bottom, 12)
    }
}

extension InspectorSection where Title == AnyView {
    /// A section with a plain title (12.5 semibold).
    init(title: String, description: String? = nil, changed: Bool, reset: @escaping () -> Void,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(description: description, changed: changed, reset: reset,
                  title: { AnyView(Text(title).svFont(12.5, .semibold).foregroundStyle(SV.text)) }, content: content)
    }
}

/// The 1 pt line between two sections.
struct SectionLine: View {
    var body: some View { Rectangle().fill(SV.line).frame(height: 1) }
}

/// A section's description, and the captions of the Bande tab (`.sec-d`).
struct SectionText: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).svFont(11.5, leading: 1.4).foregroundStyle(SV.text2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The band's colour before its section's name (10 pt, 3 pt corners).
struct BandSwatch: View {
    var color: Color
    var body: some View {
        RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10).padding(.trailing, 2)
    }
}

// MARK: - Rows

/// A row of the panel (`.prm`, 9 pt above and below): the name with its (?),
/// on the right the value (sliders) or the control (switches, steppers) with
/// the `modified` dot before it when it differs from the default (the value in
/// that colour too, C3-10); sliders and the
/// language menu on the next line (`below`). Disabled, it is dimmed to 0.45
/// (the sliders and the menu dim themselves).
struct ParamRow<Control: View>: View {
    var title: String
    var help: String
    var defaultText: String
    var changed: Bool
    var value: String?
    var note: (String, Color)?
    var below: Bool
    @ViewBuilder var control: () -> Control
    @Environment(\.isEnabled) private var enabled

    init(title: String, help: String, defaultText: String, changed: Bool, value: String? = nil,
         note: (String, Color)? = nil, below: Bool? = nil, @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.help = help
        self.defaultText = defaultText
        self.changed = changed
        self.value = value
        self.note = note
        // A row with a value on the right has its slider under it.
        self.below = below ?? (value != nil)
        self.control = control
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title).svFont(12).foregroundStyle(SV.text).fixedSize(horizontal: false, vertical: true)
                HelpButton(text: help, defaultText: defaultText, title: title)
                Spacer(minLength: 8)
                if let note { Text(note.0).svFont(11.5).foregroundStyle(note.1) }
                if changed { ChangedDot() }
                if let value { Text(value).svFont(SVFont.numbers).foregroundStyle(changed ? SV.modified : SV.textCode) }
                if !below { control() }
            }
            .frame(minHeight: 20)
            .opacity(enabled ? 1 : 0.45)
            if below { control() }
        }
        .padding(.vertical, 9)
    }
}

/// A system switch in the deep cyan of the system controls (`SV.sysAccent`, design note 53).
struct InspectorSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn).toggleStyle(.switch).controlSize(.small).labelsHidden().tint(SV.sysAccent)
    }
}

/// The dot before a value that differs from the default (design note 14), in the
/// `modified` colour (C3-10).
struct ChangedDot: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Circle().fill(SV.modified).frame(width: 6, height: 6)
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

/// A number in a field with a stepper ("0,20 s", "42"): typing commits on Return.
struct StepField: View {
    @Binding var value: Double
    var step: Double
    var range: ClosedRange<Double>
    var decimals: Int
    var unit: String?
    /// The field's width: 56 pt for a count, 64 pt with seconds (C2-P1, C2-P3).
    var width: CGFloat = 56
    @Environment(AppModel.self) private var model
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 4) {
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(SVFont.numbers.font)
                    .foregroundStyle(SV.text)
                    .multilineTextAlignment(.leading)
                    .focused($focused)
                    .onSubmit { commit() }
                    .onChange(of: focused) { _, now in if !now { commit() } }
                    // As wide as the number, so the unit follows it ("0,20 s", C2-P3).
                    .fixedSize()
                    .frame(minWidth: 10, alignment: .leading)
                if let unit { Text(unit).svFont(SVFont.numbers).foregroundStyle(SV.text) }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            .frame(width: width - 18, height: 22)
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

// MARK: - The frame's schema

/// The frame's schema of the main window's Bande tab (C2-P2): the signs band
/// at the top and the dialogue band at the bottom, as high and as wide as the
/// sliders set them, each with its tag and a short light bar for a line of
/// text; the signs band dashed and faded when it is off. Dark in both themes,
/// with square corners.
struct BandSchema: View {
    var signsOn: Bool
    var topPct: Int
    var topWPct: Int
    var bottomPct: Int
    var bottomWPct: Int
    var signs: String
    var signsOff: String
    var dialogue: String
    var label: String

    private static let frameColour = Color(dark: "#0B0C0E", light: "#0B0C0E")

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let sW = w * CGFloat(topWPct) / 100, sH = h * CGFloat(topPct) / 100, sX = (w - sW) / 2
            let dW = w * CGFloat(bottomWPct) / 100, dH = h * CGFloat(bottomPct) / 100
            let dX = (w - dW) / 2, dY = h - dH
            ZStack(alignment: .topLeading) {
                band(BandColors.signs, on: signsOn).frame(width: sW, height: sH).offset(x: sX, y: 0)
                if signsOn { textBar(min(150, sW * 0.5), w: w, centreY: sH / 2) }
                tag(signsOn ? signs : signsOff, fill: BandColors.signs, text: BandColors.signsTagText)
                    .opacity(signsOn ? 1 : 0.6)
                    .offset(x: sX + 6, y: sH + 4)
                band(BandColors.dialogue, on: true).frame(width: dW, height: dH).offset(x: dX, y: dY)
                textBar(min(110, dW * 0.37), w: w, centreY: dY + dH / 2)
                tag(dialogue, fill: BandColors.dialogue, text: BandColors.dialogueTagText)
                    .offset(x: dX + 4, y: dY - 20)
            }
            .frame(width: w, height: h, alignment: .topLeading)
        }
        .frame(height: 174)
        .background(Self.frameColour)
        // Square corners (design note 89): a band at 100 % width runs edge to edge,
        // a rounded clip would cut its border and fill at the corners.
        .clipShape(Rectangle())
        .overlay(Rectangle().strokeBorder(SV.line))
        .accessibilityElement()
        .accessibilityLabel(label)
    }

    /// A band: a 1.5 pt border on a 12 % fill; off, dashed, empty and at half strength.
    private func band(_ colour: Color, on: Bool) -> some View {
        Rectangle().fill(on ? colour.opacity(0.12) : .clear)
            .overlay(Rectangle().strokeBorder(colour, style: StrokeStyle(lineWidth: 1.5, dash: on ? [] : [4, 3])))
            .opacity(on ? 1 : 0.5)
    }

    /// The light bar in the middle of a band: a line of text.
    private func textBar(_ width: CGFloat, w: CGFloat, centreY: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.55))
            .frame(width: width, height: 4)
            .offset(x: (w - width) / 2, y: centreY - 2)
    }

    private func tag(_ text: String, fill: Color, text colour: Color) -> some View {
        Text(text).svFont(10.5, .bold).foregroundStyle(colour)
            .padding(.horizontal, 6)
            .frame(height: 16)
            .background(RoundedRectangle(cornerRadius: 4).fill(fill))
            .fixedSize()
    }
}
