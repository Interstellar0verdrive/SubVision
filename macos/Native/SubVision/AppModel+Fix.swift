// SPDX-License-Identifier: MIT
// Sub fix (F5.3, design boards F0–F3): the SRT chosen (drop or Open SRT…),
// the four options kept in UserDefaults under `fix.*`, the note on the
// parameters shared with Process, `srt.fix` and its outcome. `srt.fix` is
// never `busy`: the page works during a batch (design note 11).

import AppKit
import SVShell
import UniformTypeIdentifiers

/// The UserDefaults keys of the four options.
enum FixKey {
    static let merge = "fix.merge"
    static let ignore = "fix.ignore"
    static let flash = "fix.flash"
    static let minDuration = "fix.minDuration"
}

/// What the last run left on the page (one note at a time, boards F2/F3).
enum FixOutcome: Equatable {
    /// The fixed copy was written next to the source.
    case created(path: String, count: Int)
    /// `no_valid_segments`: every line was removed.
    case noValidSegments
    /// `bad_srt`: the file cannot be read as an SRT; the 1-based line where it gave up.
    case unreadable(line: Int)
    /// `not_found`: the source went away.
    case notFound(path: String)
    /// Something dropped that is not an .srt (yellow note).
    case notSrt
    /// Any other error, as the engine said it.
    case failed(message: String)
}

/// Everything the Sub fix page shows; `AppModel.fix` holds it. The options
/// write themselves to UserDefaults as they change.
struct FixState {
    var merge: Bool { didSet { UserDefaults.standard.set(merge, forKey: FixKey.merge) } }
    var ignore: Bool { didSet { UserDefaults.standard.set(ignore, forKey: FixKey.ignore) } }
    var flash: Bool { didSet { UserDefaults.standard.set(flash, forKey: FixKey.flash) } }
    /// The flash threshold in seconds (0.1–2.0 by 0.1), used when `flash` is on.
    var minDuration: Double { didSet { UserDefaults.standard.set(minDuration, forKey: FixKey.minDuration) } }
    /// Timed blocks of the chosen SRT and the end of its last one, for the file card.
    var lines: Int?
    var duration: Double?
    var running = false
    var outcome: FixOutcome?

    static let minDurationRange = 0.1...2.0
    static let minDurationStep = 0.1

    init() {
        let d = UserDefaults.standard
        merge = d.value(FixKey.merge, or: true)
        ignore = d.value(FixKey.ignore, or: true)
        flash = d.value(FixKey.flash, or: true)
        minDuration = d.value(FixKey.minDuration, or: 0.2)
    }
}

/// What the app reads of an SRT by itself: the timed blocks and the end of
/// the last one (the file card), and the first line with text (the `line` of
/// `bad_srt`, which the client does not carry through from the engine's reply).
enum SrtPeek {
    static func read(_ url: URL) -> (lines: Int, duration: Double?)? {
        guard let text = contents(url) else { return nil }
        var count = 0
        var last: Double?
        for raw in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            guard raw.contains("-->") else { continue }
            count += 1
            let parts = raw.components(separatedBy: "-->")
            if parts.count == 2, let end = seconds(parts[1]) { last = end }
        }
        return (count, last)
    }

    /// 1-based number of the first non-empty line (where a parse gives up), as `fix.py` counts it.
    static func firstTextLine(_ url: URL) -> Int {
        guard let text = contents(url) else { return 1 }
        for (i, line) in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated()
        where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            return i + 1
        }
        return 1
    }

    private static func contents(_ url: URL) -> String? {
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) { return utf8 }
        return try? String(contentsOf: url, encoding: .isoLatin1)
    }

    /// `00:23:40,120` (or with a dot) → seconds.
    private static func seconds(_ stamp: String) -> Double? {
        let clean = stamp.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
        let parts = clean.replacingOccurrences(of: ",", with: ".").split(separator: ":").compactMap { Double($0) }
        guard parts.count == 3 else { return nil }
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    }
}

extension AppModel {
    /// Off for an SRT the app read no timed block from (the red note is up already).
    var canRunFix: Bool { fixPath != nil && (fix.lines ?? 0) > 0 && status == .ready && !fix.running }

    /// The sidebar's Sub fix line: the file, "Created · 618 lines", "No valid segments".
    var fixSubtitle: String {
        guard let path = fixPath else { return t("app.sidebar.no_srt") }
        switch fix.outcome {
        case .created(_, let count): return tn("app.sidebar.fix_done", count)
        case .noValidSegments: return t("app.sidebar.fix_none")
        default: return path.lastPathComponent
        }
    }

    /// A check on the sidebar tab once the fixed copy is written (board F2).
    var fixDone: Bool {
        if case .created = fix.outcome { return true }
        return false
    }

    // MARK: - Choosing the SRT

    /// The file the page works on: drop, Open SRT…, Change…. A new file clears the outcome.
    func chooseSRT(_ url: URL) {
        fixPath = url
        fix.outcome = nil
        let peek = SrtPeek.read(url)
        fix.lines = peek?.lines
        fix.duration = peek?.duration
        // No timed block at all: the engine would refuse it too (`bad_srt`). Say it now,
        // with the line where the parse gives up, and keep Run off (note 26).
        if (peek?.lines ?? 0) == 0 { fix.outcome = .unreadable(line: SrtPeek.firstTextLine(url)) }
        tab = .fix
        log.info("sub fix: \(url.path) (\(peek?.lines ?? 0) lines)")
    }

    /// File › Open SRT… (⇧⌘O), the page's button and Change….
    func openSRTPanel() {
        tab = .fix
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText]
        panel.message = t("app.menu.open_panel_srt")
        panel.prompt = t("app.common.open")
        if let current = fixPath { panel.directoryURL = current.deletingLastPathComponent() }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        chooseSRT(url)
    }

    /// Dropped items (the whole page takes them, also with a file chosen): the
    /// first .srt among them, else the yellow note of board F3.
    func receiveFixDrop(_ urls: [URL]) {
        if let srt = VideoScan.videos(in: urls, extensions: ["srt"], recursive: false).first {
            chooseSRT(srt)
        } else if !urls.isEmpty {
            fix.outcome = .notSrt
        }
    }

    // MARK: - The shared parameters (design note 1)

    /// "Also uses the parameters of Process: merging within 0.6 s, wrapping at 42, Italian, …".
    var fixSharedNote: String {
        let p = ocrParams
        return t("app.fix.shared", ["gap": localizer.number(p.mergeGap, decimals: 1), "wrap": p.wrapWidth,
                                    "lang": languageName(p.langHint)])
    }

    /// An OCR language by name, in the app's language: "Italiano" for `it-IT`
    /// when Vision's list has one variant of that language, the whole name
    /// ("Portoghese (Brasile)", "Cinese semplificato") when it has several;
    /// the code when macOS has no name for it.
    func languageName(_ code: String) -> String {
        func base(_ c: String) -> String { (c.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? c).lowercased() }
        let variants = Set((hello?.languages ?? []).filter { base($0) == base(code) }.map { $0.lowercased() }).union([code.lowercased()])
        let locale = localizer.locale
        let name = variants.count > 1 ? locale.localizedString(forIdentifier: code) : locale.localizedString(forLanguageCode: base(code))
        guard let name, !name.isEmpty else { return code }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// "Show Parameters": Process with the inspector open.
    func showFixParameters() {
        tab = .process
        inspectorOpen = true
    }

    // MARK: - Running

    /// Run Sub fix (⌘↩): `srt.fix` with the four options and the shared
    /// parameters; the outcome goes in `fix.outcome` (boards F2, F3).
    func runFix() {
        guard canRunFix, let path = fixPath else { return }
        fix.running = true
        fix.outcome = nil
        let options = fix
        Task {
            defer { fix.running = false }
            do {
                let reply = try await engine.srtFix(path: path.path, merge: options.merge, ignore: options.ignore,
                                                    flash: options.flash, minDuration: options.minDuration,
                                                    params: ocrParams, useIgnore: useIgnore, useCorrections: useCorrections)
                fix.outcome = .created(path: reply.outPath, count: reply.count)
                log.info("sub fix: \(reply.count) lines -> \(reply.outPath)")
            } catch {
                fix.outcome = fixOutcome(for: error, source: path)
                log.error("srt.fix: \(error)")
            }
        }
    }

    /// The engine's error as the page shows it, with the line of `bad_srt`
    /// and the path of `not_found` the engine sends (`RemoteErrorInfo`). An
    /// engine that does not send them: the line is found again here the way
    /// the engine finds it (the first line with text), the path is the source.
    private func fixOutcome(for error: Error, source: URL) -> FixOutcome {
        let info = (error as? EngineError)?.remoteInfo
        switch (error as? EngineError)?.remoteCode {
        case "no_valid_segments": return .noValidSegments
        case "bad_srt": return .unreadable(line: info?.line ?? SrtPeek.firstTextLine(source))
        case "not_found": return .notFound(path: info?.path ?? source.path)
        default: return .failed(message: info?.detail ?? String(describing: error))
        }
    }

    /// The red note's text for the errors that are not `no_valid_segments`.
    func fixErrorText(_ outcome: FixOutcome) -> String? {
        switch outcome {
        case .unreadable(let line): return t("app.fix.unreadable", ["why": t("app.errors.bad_srt", ["line": line])])
        case .notFound(let path): return t("app.errors.not_found", ["path": path])
        case .failed(let message): return t("app.errors.unknown", ["detail": message])
        default: return nil
        }
    }

    /// The fixed copy of the last run.
    var fixOutputURL: URL? {
        if case .created(let path, _) = fix.outcome { return URL(fileURLWithPath: path) }
        return nil
    }

    func showFixOutputInFinder() {
        guard let url = fixOutputURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// "Open": the fixed copy in the app macOS uses for .srt files.
    func openFixOutput() {
        guard let url = fixOutputURL else { return }
        NSWorkspace.shared.open(url)
    }
}
