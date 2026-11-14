// SPDX-License-Identifier: MIT
// The bridge between the review report (HTML in a WKWebView) and the app
// (F5.4, spike S2). The report posts to the script message handler
// `subvision`: `{type:"export", name, srt}` becomes `<name>` next to the
// report and gets `{ok, path, name, bytes}` back; `{type:"state", json}` becomes
// `<name>.review.json` next to it; `{type:"confirm", title, text, confirm,
// cancel, destructive}` ("Reset all…", board R4) is the app's alert, answered
// with `{confirmed}`. At load the saved state is injected
// as `window.__subvisionState` and the app's language as
// `window.__subvisionLang` (the report carries Italian and English; a change
// of language while the report is open goes to `window.__subvisionSetLang`);
// a report written by the 1.x (no bridge of its own) gets one from a user
// script. `<a download>` is the safety net.

import AppKit
import SVShell
import WebKit

/// What the bridge found out about the report file, before loading it.
struct ReportFile {
    enum Kind { case bridged, legacy }
    var url: URL
    var kind: Kind
    /// `DATA.srtName` of the report: the `localStorage` key of the 1.x is built on it.
    var srtName: String?
    /// Lines, lines to re-check and gaps from the report's data (the title band, R1).
    var counts: ReviewData.Counts?

    /// Reads the file; nil when it cannot be read or is not a review report.
    init?(url: URL) {
        guard let data = FileManager.default.contents(atPath: url.path),
              let html = String(data: data, encoding: .utf8), html.contains("id=\"qcdata\"") else { return nil }
        self.url = url
        kind = html.contains("messageHandlers.subvision") ? .bridged : .legacy
        counts = ReviewData.counts(html: html)
        if let m = html.firstMatch(of: /"srtName":\s*"((?:[^"\\]|\\.)*)"/) {
            srtName = String(m.1).replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
        }
    }

    var folder: URL { url.deletingLastPathComponent() }

    /// `<stem>.review.json` next to the report (`a.review.html` → `a.review.json`).
    var stateURL: URL {
        let name = url.lastPathComponent
        if name.lowercased().hasSuffix(".review.html") {
            return folder.appendingPathComponent(String(name.dropLast(5)) + ".json")
        }
        return url.deletingPathExtension().appendingPathExtension("review.json")
    }
}

/// The outcome of an export the bridge tells the page about.
enum ReportSaveOutcome {
    case saved(URL)
    /// Writing next to the original failed: the page asks where else (R3).
    case failed(name: String, error: String)
}

@MainActor
final class ReportBridge: NSObject {
    static let handlerName = "subvision"
    #if DEBUG
    /// Debug: answers the report's questions without a dialog (`report-confirm yes|no`):
    /// the `confirm` message of "Reset all…", `confirm()`, the overwrite question.
    static var debugConfirm: Bool?
    #endif

    let file: ReportFile
    let t: (String, [String: Any]) -> String
    var log: AppLog { AppLog.shared }

    /// Called on every export, after the file is written (or not).
    var onExport: (ReportSaveOutcome) -> Void = { _ in }
    /// The export failed next to the original: asks the person for another place.
    /// Returns the URL chosen, nil to give up.
    var askWhereToSave: (String) -> URL? = { _ in nil }
    /// Every write of the review state (`<name>.review.json`): true when it went through.
    var onStateWrite: (Bool) -> Void = { _ in }
    var onNavigationFinished: () -> Void = {}
    var onNavigationFailed: (Error) -> Void = { _ in }

    private(set) var webView: WKWebView!
    private let controller = WKUserContentController()
    private(set) var lastStateWritten: Date?
    /// The downloads in flight, by identity, with their destination.
    private var downloads: [ObjectIdentifier: URL] = [:]
    /// The alert of the page that is up ("Reset all…", a `confirm()`, the overwrite question), for the debug commands.
    private(set) var pageAlert: SVAlertPresentation?

    /// The app's language ("it" | "en"): the report shows its texts in it.
    private(set) var language: String

    init(file: ReportFile, language: String, t: @escaping (String, [String: Any]) -> String) {
        self.file = file
        self.language = language
        self.t = t
        super.init()
        let config = WKWebViewConfiguration()
        config.userContentController = controller
        // The page's own memory (localStorage, keyed by the SRT's name) must not outlive the report:
        // the review state is `<name>.review.json`, and a report made again for the same video
        // would otherwise start from the old choices.
        config.websiteDataStore = .nonPersistent()
        controller.addScriptMessageHandler(self, contentWorld: .page, name: Self.handlerName)
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.underPageBackgroundColor = .clear
    }

    /// Breaks the cycle with the content controller when the page goes back to the list.
    func detach() {
        // An alert still up answers Cancel first: WebKit wants its completion handler called.
        if let open = pageAlert, open.isOpen { open.press(open.alert.buttons.count - 1) }
        controller.removeAllScriptMessageHandlers()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    // MARK: - Loading

    func load() {
        installUserScripts()
        webView.loadFileURL(file.url, allowingReadAccessTo: file.folder)
    }

    /// The saved state, fresh from the disk, before every load of the document
    /// (also the reload after "Reset all", which must see the empty state).
    private func installUserScripts() {
        controller.removeAllUserScripts()
        controller.addUserScript(WKUserScript(source: "window.__subvisionLang = \(Self.jsString(language));\n",
                                              injectionTime: .atDocumentStart, forMainFrameOnly: true))
        if let json = savedStateJSON() {
            var source = "window.__subvisionState = JSON.parse(\(Self.jsString(json)));\n"
            if file.kind == .legacy, let key = file.srtName {
                // The 1.x reads localStorage only: the saved state goes there first.
                source += "try { localStorage.setItem(\(Self.jsString("voc26_rev_" + key)), \(Self.jsString(json))); } catch (e) {}\n"
            }
            controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        if file.kind == .legacy {
            controller.addUserScript(WKUserScript(source: Self.legacyShim, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
    }

    /// `<name>.review.json` as a JSON object, or nil when absent or not an object.
    private func savedStateJSON() -> String? {
        guard let data = FileManager.default.contents(atPath: file.stateURL.path),
              let object = try? JSONSerialization.jsonObject(with: data), object is [String: Any],
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    /// A JavaScript string literal of `text` (JSON-escaped, U+2028/9 too).
    static func jsString(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\u{2028}": out += "\\u2028"
            case "\u{2029}": out += "\\u2029"
            default:
                if scalar.value < 0x20 { out += String(format: "\\u%04x", scalar.value) } else { out.unicodeScalars.append(scalar) }
            }
        }
        return out + "\""
    }

    /// The bridge for a report of the 1.x: the same `export` and `state`
    /// messages, grafted on its own `setState`, `exportSrt` and `resetAll`
    /// (declared at top level, so reassignable on `window`; `saved`, `LSKEY`,
    /// `DATA` and `T` are its global bindings).
    static let legacyShim = #"""
    (function () {
      const H = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.subvision;
      if (!H || typeof buildSrt !== 'function' || typeof setState !== 'function') return;
      const send = () => { try { H.postMessage({type: 'state', json: JSON.stringify(saved)}); } catch (e) {} };
      const origSetState = window.setState;
      window.setState = function (id, patch) { origSetState(id, patch); send(); };
      window.persistState = function () {
        try { localStorage.setItem(LSKEY, JSON.stringify(saved)); } catch (e) {}
        send();
      };
      window.exportSrt = async function () {
        const out = buildSrt();
        if (out == null) return;
        const fname = DATA.srtName.replace(/\.srt$/i, '') + '-reviewed-' + stamp() + '.srt';
        const mi = window._lastMergeInfo || 0;
        const mergeNote = mi > 0 ? ' · ' + mi + ' ' + T.mergedDupes : '';
        try {
          const r = await Promise.resolve(H.postMessage({type: 'export', name: fname, srt: out}));
          flash(T.srtSaved + ' (' + ((r && r.path) || fname) + ')' + mergeNote);
        } catch (e) {
          flash((T.srtError || 'Error:') + ' ' + e);
        }
      };
      window.resetAll = function () {
        if (!confirm(T.confirmReset)) return;
        saved = {};
        send();
        try { localStorage.removeItem(LSKEY); } catch (e) {}
        location.reload();
      };
      // The hint about Chrome, Safari and the Downloads folder does not apply here.
      try {
        const hint = document.querySelector('.sum .hint');
        const br = hint && hint.querySelector('br');
        if (br) { while (br.nextSibling) br.nextSibling.remove(); br.remove(); }
      } catch (e) {}
      window.__subvisionBridge = 'legacy';
    })();
    """#

    // MARK: - JavaScript from the app

    /// The app's language changed: the page switches in place (no reload, the edits stay),
    /// and the next load ("Reset all" reloads) starts in it.
    func setLanguage(_ code: String) {
        guard code != language else { return }
        language = code
        installUserScripts()
        webView.evaluateJavaScript("window.__subvisionSetLang && window.__subvisionSetLang(\(Self.jsString(code)))")
    }

    /// Runs `body` as an async function in the page and returns its value
    /// (`callAsyncJavaScript`: promises are awaited, `evaluateJavaScript` would not).
    func call(_ body: String) async throws -> Any? {
        try await webView.callAsyncJavaScript(body, arguments: [:], in: nil, contentWorld: .page)
    }

    // MARK: - Files

    /// Where an export goes: `name` next to the report. The name is the report's
    /// own (`<srt stem>-reviewed-<date>.srt`), kept to its last component.
    private func exportTarget(_ name: String) -> URL {
        let clean = URL(fileURLWithPath: name).lastPathComponent
        return file.folder.appendingPathComponent(clean.hasSuffix(".srt") ? clean : clean + ".srt")
    }

    /// Writes `srt` there, atomically.
    private func writeExport(name: String, srt: String) throws -> URL {
        let target = exportTarget(name)
        try Data(srt.utf8).write(to: target, options: .atomic)
        return target
    }

    /// The export's name is there already (the date in it goes to the minute, so
    /// a second save within the minute lands on the first): Replace or Cancel.
    /// Not modal; `answer` gets true for Replace.
    private func confirmReplace(_ target: URL, answer: @escaping @MainActor (Bool) -> Void) {
        #if DEBUG
        if let reply = Self.debugConfirm {
            answer(reply)
            return
        }
        #endif
        let a = SVAlert(icon: AlertIconName.info, tone: .yellow, title: t("app.report.replace_title", [:]),
                        text: t("app.report.replace_text", ["name": target.lastPathComponent]))
        a.button(t("app.report.replace_btn", [:]), role: .primary)
        a.button(t("app.common.cancel", [:]), cancel: true)
        pageAlert = a.present(over: webView.window) { [weak self] index in
            self?.pageAlert = nil
            answer(index == 0)
        }
    }

    /// A `confirm()` or `alert()` of the page as the app's alert: a short
    /// question is the title; a long one goes under a title of the app's.
    private func pageAlert(_ message: String, cancel: Bool, answer: @escaping @MainActor (Bool) -> Void) {
        let short = message.count <= 72 && !message.contains("\n")
        let a = SVAlert(icon: AlertIconName.info, tone: .accent, title: short ? message : t("app.report.confirm_title", [:]),
                        text: short ? "" : message)
        a.button(t("app.common.ok", [:]), role: .primary)
        if cancel { a.button(t("app.common.cancel", [:]), cancel: true) }
        pageAlert = a.present(over: webView.window) { [weak self] index in
            self?.pageAlert = nil
            answer(index == 0)
        }
    }

    /// "Reset all…" of the report (board R4): its title and text, the destructive button
    /// and Cancel, which is the default (Return cancels: a key pressed by mistake loses nothing).
    /// Not modal; `answer` gets true for the destructive button.
    func confirmMessage(title: String, text: String, confirm: String, cancel: String, destructive: Bool,
                        answer: @escaping @MainActor (Bool) -> Void) {
        #if DEBUG
        if let reply = Self.debugConfirm {
            answer(reply)
            return
        }
        #endif
        let a = SVAlert(icon: AlertIconName.info, tone: destructive ? .red : .accent, title: title, text: text)
        a.button(cancel.isEmpty ? t("app.common.cancel", [:]) : cancel, role: .primary, cancel: true)
        a.button(confirm.isEmpty ? t("app.common.ok", [:]) : confirm, role: destructive ? .destructive : .secondary)
        pageAlert = a.present(over: webView.window) { [weak self] index in
            self?.pageAlert = nil
            answer(index == 1)
        }
    }

    private func writeState(_ json: String) {
        do {
            try Data(json.utf8).write(to: file.stateURL, options: .atomic)
            lastStateWritten = Date()
            onStateWrite(true)
        } catch {
            log.error("report state \(file.stateURL.lastPathComponent): \(error)")
            onStateWrite(false)
        }
    }
}

// MARK: - Messages from the report

extension ReportBridge {
    /// Writes the export and answers the report; when the folder cannot be
    /// written the page asks for another place (R3).
    private func export(name: String, srt: String, replyHandler: @escaping (Any?, String?) -> Void) {
        do {
            let url = try writeExport(name: name, srt: srt)
            log.info("report export \(url.lastPathComponent) (\(srt.utf8.count) bytes)")
            replyHandler(["ok": true, "path": url.path, "name": url.lastPathComponent, "bytes": srt.utf8.count], nil)
            onExport(.saved(url))
        } catch {
            log.error("report export \(name): \(error)")
            onExport(.failed(name: name, error: String(describing: error)))
            // R3: another place, chosen by the person; the report learns the outcome.
            if let elsewhere = askWhereToSave(name) {
                do {
                    try Data(srt.utf8).write(to: elsewhere, options: .atomic)
                    replyHandler(["ok": true, "path": elsewhere.path, "name": elsewhere.lastPathComponent, "bytes": srt.utf8.count], nil)
                    onExport(.saved(elsewhere))
                } catch {
                    replyHandler(nil, t("app.report.save_failed", [:]))
                }
            } else {
                replyHandler(nil, t("app.report.save_failed", [:]))
            }
        }
    }
}

extension ReportBridge: WKScriptMessageHandlerWithReply {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else {
            replyHandler(nil, "bad message")
            return
        }
        switch type {
        case "export":
            guard let name = body["name"] as? String, let srt = body["srt"] as? String else {
                replyHandler(nil, "bad export")
                return
            }
            // The same name twice (two saves within the minute): ask before replacing.
            if FileManager.default.fileExists(atPath: exportTarget(name).path) {
                confirmReplace(exportTarget(name)) { [self] replace in
                    if replace {
                        export(name: name, srt: srt, replyHandler: replyHandler)
                    } else {
                        log.info("report export \(name): not replaced")
                        replyHandler(nil, t("app.report.replace_cancelled", [:]))
                    }
                }
            } else {
                export(name: name, srt: srt, replyHandler: replyHandler)
            }
        case "confirm":
            confirmMessage(title: body["title"] as? String ?? "", text: body["text"] as? String ?? "",
                           confirm: body["confirm"] as? String ?? "", cancel: body["cancel"] as? String ?? "",
                           destructive: body["destructive"] as? Bool ?? false) { [self] confirmed in
                log.info("report confirm \(confirmed ? "yes" : "no")")
                replyHandler(["confirmed": confirmed], nil)
            }
        case "state":
            guard let json = body["json"] as? String else {
                replyHandler(nil, "bad state")
                return
            }
            writeState(json)
            replyHandler(["ok": true], nil)
        default:
            replyHandler(nil, "unknown type \(type)")
        }
    }
}

// MARK: - Navigation

extension ReportBridge: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 preferences: WKWebpagePreferences, decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        let url = navigationAction.request.url
        if navigationAction.shouldPerformDownload || url?.scheme == "blob" {
            // `<a download>` of a report without the bridge: the safety net.
            decisionHandler(.download, preferences)
            return
        }
        if navigationAction.targetFrame?.isMainFrame ?? true, let url {
            if url.isFileURL, url.standardizedFileURL == file.url.standardizedFileURL {
                // The document itself (first load, or the reload after "Reset all").
                installUserScripts()
                decisionHandler(.allow, preferences)
                return
            }
            if navigationAction.navigationType == .linkActivated || !url.isFileURL {
                // Links leave the app: the browser handles them.
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel, preferences)
                return
            }
        }
        decisionHandler(.allow, preferences)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onNavigationFinished()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onNavigationFailed(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onNavigationFailed(error)
    }
}

// MARK: - Downloads (the safety net)

extension ReportBridge: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        // Next to the report, with the report's own name; a second copy gets a number.
        let clean = URL(fileURLWithPath: suggestedFilename).lastPathComponent
        var target = file.folder.appendingPathComponent(clean)
        var n = 2
        while FileManager.default.fileExists(atPath: target.path) {
            let stem = URL(fileURLWithPath: clean).deletingPathExtension().lastPathComponent
            let ext = URL(fileURLWithPath: clean).pathExtension
            target = file.folder.appendingPathComponent("\(stem) \(n)" + (ext.isEmpty ? "" : "." + ext))
            n += 1
        }
        downloads[ObjectIdentifier(download)] = target
        completionHandler(target)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let url = downloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
        log.info("report download \(url.lastPathComponent)")
        onExport(.saved(url))
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let url = downloads.removeValue(forKey: ObjectIdentifier(download))
        log.error("report download \(url?.lastPathComponent ?? "?"): \(error)")
        onExport(.failed(name: url?.lastPathComponent ?? "", error: String(describing: error)))
    }
}

// MARK: - The page's own dialogs

extension ReportBridge: WKUIDelegate {
    /// `confirm()` of "Reset all": the app's alert, with the page's question.
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        #if DEBUG
        if let answer = Self.debugConfirm {
            completionHandler(answer)
            return
        }
        #endif
        // Not modal: WebKit waits for the completion handler, nothing else waits for the alert.
        pageAlert(message, cancel: true) { completionHandler($0) }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        pageAlert(message, cancel: false) { _ in completionHandler() }
    }
}
