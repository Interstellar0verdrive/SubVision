// SPDX-License-Identifier: MIT
// Try OCR's two panels (design boards C2-A1–A3, design note 79): always
// there under the summary, Dialogue | Signs, as tall as each other. Each
// says what its band read on the frame on screen: the text in an inset box,
// confidence, agreement and readings under it, the kind of OCR and the time
// in its header; before a test the prompt, during the batch when the test
// comes back, the spinner while it reads, the empty band, the error, the
// signs band off with its switch, and over a result whose parameters
// changed since a grey note that says so with «Riprova OCR con i nuovi
// parametri» (C3-11; the old result at half strength until it is redone).

import AppKit
import SVShell
import SwiftUI

/// The two panels side by side (`.panel2`, 12 pt apart), filling the height given.
struct OcrTestPanels: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            OcrTestPanel(band: .dialogue)
                .previewMetric("panel.dialogue")
            OcrTestPanel(band: .signs)
                .previewMetric("panel.signs")
        }
    }
}

/// One band's panel.
struct OcrTestPanel: View {
    private enum Content {
        /// No test on this frame yet: "Premi Prova OCR…".
        case prompt
        /// No test, and none until the batch ends.
        case batch
        case reading
        case result(OcrTestReply.Band, multi: Bool)
        /// The band was read and holds no text.
        case empty(OcrTestReply.Band, multi: Bool)
        case failed(String)
        /// The signs band is off: its switch.
        case signsOff
    }

    @Environment(AppModel.self) private var model
    @AppStorage(OcrKey.topBand) private var signsOn = ocrDefaults.topBand
    var band: PreviewBand

    var body: some View {
        let content = self.content
        VStack(alignment: .leading, spacing: 6) {
            header(content)
            // The panel keeps the height the block gives it: what does not fit (the grey note of
            // C3-11 over a result, in a short window) scrolls under the header.
            ViewThatFits(in: .vertical) {
                body(content)
                ScrollView(.vertical) { body(content).fixedSize(horizontal: false, vertical: true) }
                    .scrollIndicators(.automatic)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: SV.Radius.card).fill(SV.surface))
        .overlay(RoundedRectangle(cornerRadius: SV.Radius.card).strokeBorder(SV.line))
        .clipShape(RoundedRectangle(cornerRadius: SV.Radius.card))
    }

    /// The note when the result is stale, then the result (dimmed until it is redone).
    private func body(_ content: Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if stale(content) {
                staleNote
            }
            contentView(content)
                .opacity(stale(content) ? 0.5 : 1)
                .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var content: Content {
        if band == .signs && !signsOn { return .signsOff }
        switch model.previewTest {
        case .reading?:
            return .reading
        case .failed(let code, let message)?:
            return .failed(model.previewErrorText(code: code, message: message))
        case .done(let reply, let params)?:
            if let read = reply.bands[band.engineKey] {
                return read.empty || read.text.isEmpty ? .empty(read, multi: params.multiVariant) : .result(read, multi: params.multiVariant)
            }
            // Not read (the signs band was off then): as if there were no test.
            return model.batch.running ? .batch : .prompt
        case nil:
            return model.batch.running ? .batch : .prompt
        }
    }

    private func stale(_ content: Content) -> Bool {
        switch content {
        case .result, .empty: model.previewStale(band)
        default: false
        }
    }

    // MARK: Header

    /// The swatch, the band's name and, after a test, "OCR con voto · 214 ms" on the right.
    private func header(_ content: Content) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3).fill(band.color).frame(width: 10, height: 10)
            Text(model.t(band.nameKey)).svFont(13, .semibold).foregroundStyle(SV.text)
            Spacer(minLength: 8)
            if let meta = meta(content) {
                // A narrow panel: the time alone.
                ViewThatFits(in: .horizontal) {
                    Text(meta.long).svFont(11.5).foregroundStyle(SV.text3).fixedSize()
                    Text(meta.short).svFont(11.5).foregroundStyle(SV.text3).lineLimit(1)
                }
                .layoutPriority(1)
            }
        }
        .frame(height: 18)
    }

    private func meta(_ content: Content) -> (long: String, short: String)? {
        switch content {
        case .result(let r, let multi), .empty(let r, let multi):
            let ms = ["ms": Int(r.ms.rounded())]
            return (model.t(multi ? "app.preview.meta_vote" : "app.preview.meta_single", ms), model.t("app.preview.meta_ms", ms))
        default:
            return nil
        }
    }

    // MARK: Content

    @ViewBuilder
    private func contentView(_ content: Content) -> some View {
        switch content {
        case .prompt:
            // Boards A0, A1: before the frames, what comes first; with frames but none shown, pick one.
            centred(symbol: "magnifyingglass", text: model.t(promptKey))
        case .batch:
            centred(symbol: "magnifyingglass", text: model.t("app.preview.panel_batch"))
        case .reading:
            HStack(spacing: 8) {
                Spinner(size: 12)
                Text(model.t("app.preview.reading")).svFont(12).foregroundStyle(SV.text2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .result(let r, let multi):
            VStack(alignment: .leading, spacing: 6) {
                textBox(r)
                Text(confidence(r, multi: multi)).svSmall().fixedSize(horizontal: false, vertical: true)
                // Board A4: the other readings of the vote, in mono chips (all of them in the tooltip).
                if !r.alts.isEmpty {
                    HStack(spacing: 6) {
                        Text(model.t("app.preview.alts")).svSmall().fixedSize()
                        ForEach(Array(r.alts.prefix(2).enumerated()), id: \.offset) { _, alt in
                            Text(alt).svFont(10.5, mono: true).foregroundStyle(SV.textCode)
                                .lineLimit(1).truncationMode(.tail)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 4).fill(SV.chipBg))
                                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(SV.chipLine))
                        }
                    }
                    .help(tooltip(r))
                }
            }
        case .empty:
            // Board A5: the reading box, empty, and the sentence under it, as a result is laid out.
            VStack(alignment: .leading, spacing: 6) {
                Text(model.t("app.preview.empty_read")).svFont(13, leading: 1.45).foregroundStyle(SV.text3)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(RoundedRectangle(cornerRadius: SV.Radius.icon).fill(SV.inset))
                    .overlay(RoundedRectangle(cornerRadius: SV.Radius.icon).strokeBorder(SV.line))
                Text(model.t("app.preview.no_text_band")).svSmall().fixedSize(horizontal: false, vertical: true)
            }
        case .failed(let text):
            NoteView(.red, text: text) { EmptyView() }
        case .signsOff:
            // Board A5: "Turn on the signs band [switch]", what the test reads without it under.
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Text(model.t("app.preview.signs_turn_on")).svFont(12).foregroundStyle(SV.text)
                    InspectorSwitch(isOn: $signsOn)
                        .disabled(model.batch.running)
                        .help(model.t("app.inspector.help.sig_on"))
                }
                Text(model.t("app.preview.signs_off")).svFont(12).foregroundStyle(SV.text3)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var promptKey: String {
        if model.previewFrame != nil { return "app.preview.panel_prompt" }
        if model.previewFrames.isEmpty || model.isSearchingPreviewVideo { return "app.preview.panel_no_frames" }
        return "app.preview.panel_choose"
    }

    /// `.panel2 .empty`: a symbol and a short text in the middle of the panel.
    private func centred(symbol: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).svFont(12)
            Text(text).svFont(12).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(SV.text3)
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// `.textbox`: what the band read. The final text (what the SRT would get) and the
    /// alternatives in the tooltip; both texts in the context menu.
    private func textBox(_ r: OcrTestReply.Band) -> some View {
        Text(r.text).svFont(13, leading: 1.45).foregroundStyle(SV.text)
            .lineLimit(4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: SV.Radius.icon).fill(SV.inset))
            .overlay(RoundedRectangle(cornerRadius: SV.Radius.icon).strokeBorder(SV.line))
            .help(tooltip(r))
            .contextMenu {
                Button(model.t("app.preview.copy_final")) { copy(r.finalText) }.disabled(r.finalText.isEmpty)
                Button(model.t("app.preview.copy_read")) { copy(r.text) }
            }
    }

    /// "Testo finale: …" and "Alternative: … · …".
    private func tooltip(_ r: OcrTestReply.Band) -> String {
        var lines = ["\(model.t("app.preview.final")): \(r.finalText)"]
        if !r.alts.isEmpty { lines.append("\(model.t("app.preview.alts")): \(r.alts.joined(separator: " · "))") }
        return lines.joined(separator: "\n")
    }

    /// "Confidenza 94 % · accordo 100 % · 3 letture"; one reading: the confidence alone.
    private func confidence(_ r: OcrTestReply.Band, multi: Bool) -> String {
        let reads = r.variants ?? r.alts.count + 1
        let values: [String: Any] = ["c": Int((r.conf * 100).rounded()), "a": Int((r.agree * 100).rounded())]
        if !multi { return model.t("app.preview.conf_single", values) }
        return reads > 1 ? model.tn("app.preview.conf_reads", reads, values) : model.t("app.preview.conf", values)
    }

    /// C3-11: a neutral note (grey, an info symbol, not the yellow of the defaults) that says the
    /// parameters changed after this test and the text under it is from before, with the button
    /// that runs the test again on this frame (⌘T, as Try OCR).
    private var staleNote: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "info.circle").svFont(12)
                Text(model.t("app.preview.stale_text")).svFont(12, leading: 1.4).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(SV.text2)
            // A narrow panel: the short label, so the panel never grows past its half of the block.
            ViewThatFits(in: .horizontal) {
                retryButton("app.preview.stale_retry").padding(.leading, 20)
                retryButton("app.preview.stale_retry")
                retryButton("app.preview.stale_retry_short")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: SV.Radius.field).fill(SVTone.neutral.background))
        .overlay(RoundedRectangle(cornerRadius: SV.Radius.field).strokeBorder(SVTone.neutral.line))
    }

    private func retryButton(_ key: String) -> some View {
        Button { model.tryOCR() } label: { Label(model.t(key), systemImage: "arrow.clockwise") }
            .svButton(.secondary, .small)
            .fixedSize()
            .disabled(!model.canTryOCR)
            .help(model.t("app.preview.stale_retry_help"))
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
