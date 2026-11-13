// SPDX-License-Identifier: MIT
// Try OCR (design boards A4, A5): one panel per band with the voted text,
// confidence and agreement, the alternatives, the final text (what the SRT
// would get, `{\an8}` first for the signs band) and the time taken; the
// panel while it reads, the empty band, the error, and the "parameters
// changed" line when the test is older than the inspector's values.

import AppKit
import SVShell
import SwiftUI

/// The two panels side by side, one under the other in a narrow page.
struct OcrTestPanels: View {
    @Environment(AppModel.self) private var model
    var test: PreviewState.Test
    var stale: Bool
    var narrow: Bool

    var body: some View {
        let layout = narrow ? AnyLayout(VStackLayout(spacing: 16)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        layout {
            switch test {
            case .reading:
                OcrTestPanel(band: .dialogue, state: .reading, stale: false)
                if BandValues.signsOn { OcrTestPanel(band: .signs, state: .reading, stale: false) }
            case .done(let reply, _, _, _):
                OcrTestPanel(band: .dialogue, state: reply.bottom.map { .result($0) } ?? .empty, stale: stale)
                if let top = reply.top { OcrTestPanel(band: .signs, state: .result(top), stale: stale) }
            case .failed(let code, let message):
                OcrTestPanel(band: .dialogue, state: .failed(model.previewErrorText(code: code, message: message)), stale: false)
            }
        }
    }
}

/// One band's panel (`.panel` of the boards).
struct OcrTestPanel: View {
    enum State {
        case reading
        case result(OcrTestReply.Band)
        /// The reply had no entry for this band.
        case empty
        case failed(String)
    }

    @Environment(AppModel.self) private var model
    var band: PreviewBand
    var state: State
    var stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3).fill(band.color).frame(width: 10, height: 10)
                Text(model.t(band == .dialogue ? "app.preview.panel_dlg" : "app.preview.panel_sig"))
                    .svFont(13, .semibold).foregroundStyle(SV.text)
            }
            .padding(.bottom, 6)
            switch state {
            case .reading:
                HStack(spacing: 8) {
                    Spinner(size: 12)
                    Text(model.t("app.preview.reading")).svFont(12).foregroundStyle(SV.text2)
                }
                .padding(.vertical, 30)
            case .result(let r):
                result(r)
            case .empty:
                NoteView(.neutral, text: model.t("app.preview.no_text_band"))
                    .padding(.top, 4)
            case .failed(let text):
                NoteView(.red, text: text)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .svBox(RoundedRectangle(cornerRadius: SV.Radius.card), fill: SV.surface, line: SV.line,
               padding: EdgeInsets(vertical: 14, horizontal: 16))
    }

    @ViewBuilder
    private func result(_ r: OcrTestReply.Band) -> some View {
        Text(model.tn("app.preview.vote", r.variants ?? r.alts.count + 1, ["ms": Int(r.ms.rounded())]))
            .svSmall()
            .padding(.bottom, 6)
        textBox(r.text, mono: false)
        if r.text.isEmpty && r.empty {
            NoteView(.neutral, text: model.t("app.preview.no_text_band"))
                .padding(.top, 10)
        } else {
            Text(model.t("app.preview.conf", ["c": Int((r.conf * 100).rounded()), "a": Int((r.agree * 100).rounded())]))
                .svSmall()
                .padding(.top, 6)
            if !r.alts.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(model.t("app.preview.alts")).svSmall()
                    FlowChips(r.alts)
                }
                .padding(.top, 6)
            }
            HStack(spacing: 6) {
                Text(model.t("app.preview.final").uppercased()).svFont(10.5, .semibold).foregroundStyle(SV.text3).tracking(0.3)
                HelpDot(text: model.t("app.preview.final_help"))
                Spacer(minLength: 0)
                Button(model.t("app.preview.copy")) { copy(r.finalText) }
                    .svButton(.plain, .small)
                    .disabled(r.finalText.isEmpty)
            }
            .padding(.top, 10).padding(.bottom, 4)
            textBox(r.finalText, mono: true)
            if stale {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill").svFont(11)
                    Text(model.t("app.preview.stale")).svFont(12)
                }
                .foregroundStyle(SV.yellowText)
                .padding(.top, 6)
            }
        }
    }

    /// The voted or the final text in an inset box; "‹empty›" in italics when there is none.
    private func textBox(_ text: String, mono: Bool) -> some View {
        Group {
            if text.isEmpty {
                Text(model.t("app.preview.empty_text")).svFont(13).italic().foregroundStyle(SV.text3)
            } else {
                Text(text).svFont(mono ? 12.5 : 13, mono: mono, leading: 1.45).foregroundStyle(SV.text)
                    .textSelection(.enabled)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .svBox(RoundedRectangle(cornerRadius: SV.Radius.icon), fill: SV.inset, line: SV.line,
               padding: EdgeInsets(vertical: 8, horizontal: 10))
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// The alternatives as chips, wrapping when they are many.
struct FlowChips: View {
    var items: [String]
    init(_ items: [String]) { self.items = items }

    var body: some View {
        // A few short readings fit one line; long lines wrap inside their chip instead.
        HStack(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, alt in
                Text(alt).svFont(11, mono: true).foregroundStyle(SV.text2).lineLimit(2)
                    .svBox(RoundedRectangle(cornerRadius: 9), fill: SV.chipBg, line: SV.chipLine,
                           padding: EdgeInsets(vertical: 1, horizontal: 8))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The small "?" of the boards: a tooltip on hover.
struct HelpDot: View {
    var text: String

    var body: some View {
        Text(verbatim: "?").svFont(9, .semibold).foregroundStyle(SV.text2)
            .frame(width: 14, height: 14)
            .overlay(Circle().strokeBorder(SV.glassLine))
            .help(text)
    }
}
