// SPDX-License-Identifier: MIT
// Sub fix (F5.3, design boards F1–F3): the file card, the four options, the
// note on the parameters shared with Process, Run Sub fix and the outcome
// (green note with Show in Finder and Open, red notes for the errors, yellow
// for a drop that is not an .srt). The whole page takes a dropped .srt, also
// with a file already chosen. No inspector here (design note 1).

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
    /// The width of the boards' column (file card, options, notes).
    static let columnWidth: CGFloat = 720

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                PageTop(title: model.t("app.fix.title"), intro: model.t("app.fix.intro")) {
                    OpenSRTButton()
                }
                .padding(.bottom, 18)
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        outcome
                        if let path = model.fixPath {
                            FixFileCard(url: path, lines: model.fix.lines, duration: model.fix.duration)
                        }
                        FixOptions()
                            .padding(.top, 20)
                        sharedNote
                            .padding(.top, 10)
                    }
                    .frame(maxWidth: Self.columnWidth, alignment: .leading)
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

    // MARK: - The shared parameters (design note 1)

    private var sharedNote: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "info.circle").svFont(12).foregroundStyle(SV.text3)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.fixSharedNote).svSmall().fixedSize(horizontal: false, vertical: true)
                UnderlineLink(model.t("app.fix.show_params")) { model.showFixParameters() }
            }
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Spacer(minLength: 8)
            if model.fix.running { Spinner(size: 14) }
            Button { model.runFix() } label: {
                HStack(spacing: 6) {
                    Label(model.t("app.fix.run"), systemImage: "play.fill")
                    Text("⌘↩").svFont(10, mono: true).opacity(0.7)
                }
            }
            .svButton(.primary, .regular)
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

/// "Open SRT… ⇧⌘O" at the title's level (every board of Sub fix).
struct OpenSRTButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button { model.openSRTPanel() } label: {
            HStack(spacing: 6) {
                Label(model.t("app.fix.open"), systemImage: "doc")
                Text("⇧⌘O").svFont(10, mono: true).foregroundStyle(SV.text3)
            }
        }
        .svButton(.secondary, .regular)
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
                Text(folder).svFont(SVFont.numbers).foregroundStyle(SV.textCode)
                    .lineLimit(1).truncationMode(.middle)
                Text(meta).svSmall()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(model.t("app.common.change")) { model.openSRTPanel() }.svButton(.secondary, .small)
        }
        .svBox(RoundedRectangle(cornerRadius: SV.Radius.card), fill: SV.surface, line: SV.line,
               padding: EdgeInsets(vertical: 14, horizontal: 18))
    }

    /// "~/Movies/Show/Season 1".
    private var folder: String {
        let dir = url.deletingLastPathComponent().path
        let home = NSHomeDirectory()
        return dir.hasPrefix(home) ? "~" + dir.dropFirst(home.count) : dir
    }

    /// "642 lines · 23:40"; the count alone when the SRT has no readable end.
    private var meta: String {
        let n = lines ?? 0
        guard let duration else { return model.tn("app.fix.file_meta", n, ["t": "–"]) }
        return model.tn("app.fix.file_meta", n, ["t": Localizer.clock(duration)])
    }
}

/// "What to fix": the three switches and the shortest line, which only
/// counts while the flashes go (board F1; dimmed on F2 with flashes kept).
struct FixOptions: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        SettingsGroup(model.t("app.fix.options")) {
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

/// The small accent switch of the settings rows.
struct FixSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn).toggleStyle(.switch).controlSize(.small).labelsHidden().tint(SV.primary)
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
