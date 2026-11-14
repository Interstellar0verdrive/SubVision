// SPDX-License-Identifier: MIT
// The list of videos of Process (F4.4): drops and Open Videos… with
// subfolders, `videos.probe`, removal with undo, the skipped items, and the
// list kept between launches in `<state>/records/videos.json` (design note 8).
// Since C3 there is no selection: each row has a checkbox, "process it"
// (`VideoChecks`), and the keyboard moves a focus ring over the rows.

import AppKit
import SVShell
import UniformTypeIdentifiers

/// One row of the list, with the outcome of its last batch (design notes 8–9):
/// the outcome stays until Process Again or Remove Finished.
struct VideoItem: Identifiable, Codable, Equatable {
    enum State: String, Codable {
        /// Goes into the next batch.
        case ready
        /// `videos.probe` found no video track: left out of the batch.
        case unreadable
        /// In the batch that runs, not started yet.
        case waiting
        /// The file the batch works on.
        case running
        /// SRT written.
        case done
        /// Finished, no subtitles found (`batch.file.done.empty`).
        case noSubs
        /// `batch.file.failed`.
        case failed
        /// Stopped by the person (`batch.file.stopped`).
        case stopped

        /// Done, failed or stopped: an outcome to keep, to show or to clear.
        var isFinished: Bool { [.done, .noSubs, .failed, .stopped].contains(self) }
        /// Part of the batch in progress.
        var inBatch: Bool { self == .waiting || self == .running }
    }

    var id: UUID
    var path: String
    var state: State = .ready
    var probed = false
    var duration: Double?
    var fps: Double?
    var width: Int?
    var height: Int?
    /// The reason it cannot be read (`detail` of `probe_failed`).
    var problem: String?
    var added: Date

    // The outcome of the last batch (nil until one ran this file).
    /// Lines in the SRT.
    var segments: Int?
    var dropped: Int?
    var refined: Int?
    /// Seconds the file took.
    var elapsed: Double?
    /// Seconds per step, by `key:band`.
    var times: [String: Double]?
    /// The steps of the last plan (`key:band`), to list the times in order.
    var plan: [String]?
    /// Where the engine wrote the SRT, the report and the log (the SRT may carry a date in its name).
    var srtPath: String?
    var reportPath: String?
    var logPath: String?
    /// `batch.file.failed.error` (`code (k=v, …)` or `Type: message`): the one line for the logs.
    var error: String?
    /// The other fields of `batch.file.failed` (F6; nil from an engine that does not send them,
    /// and in a list saved before): the stable code, the short text for the row, the technical
    /// detail for the box under the steps, and what the code's sentence names.
    var failCode: String?
    var failText: String?
    var failDetail: String?
    var failTool: String?
    var failPath: String?
    var failLine: Int?
    /// A tool that exited with an error: name, exit status, last complaint (11.3.4).
    var failProgram: String?
    var failStatus: Int?
    var failReason: String?
    /// `key:band` of the step it failed or stopped in.
    var atStep: String?
    /// The long gaps without subtitles of the report, `[start, end]` in seconds (Review, board C2-R1).
    var gaps: [[Double]]?
    /// The OCR language and the frames per second the file was processed with ("Italiano · 12 fps").
    var ocrLang: String?
    var ocrFPS: Double?
    /// The gap threshold of the report, in seconds ("oltre 6 s").
    var gapWarn: Double?
    /// When the outcome arrived.
    var finished: Date?
    /// The row's checkbox (C3-02): nil until the person changes it, then what they chose. A video
    /// to do comes in checked, a finished one is not (checked by hand it "will be redone").
    var checked: Bool?
    /// ffprobe's codec names of the first video and audio streams, and the file's size (the to-do drawer).
    var videoCodec: String?
    var audioCodec: String?
    var bytes: Int64?

    init(path: String) {
        id = UUID()
        self.path = path
        added = Date()
    }

    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.lastPathComponent }

    /// "~/Movies/Show/Season 1".
    var folder: String {
        let dir = url.deletingLastPathComponent().path
        let home = NSHomeDirectory()
        return dir.hasPrefix(home) ? "~" + dir.dropFirst(home.count) : dir
    }

    /// `<stem>.srt` next to the video.
    var srtURL: URL { url.deletingPathExtension().appendingPathExtension("srt") }
    var srtExists: Bool { FileManager.default.fileExists(atPath: srtURL.path) }
    var exists: Bool { FileManager.default.fileExists(atPath: path) }
    var size: String? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return "\(width)×\(height)"
    }

    /// The row's checkbox as `VideoChecks` reads it: to do, finished, or never a box
    /// (unreadable, the file gone, in the batch that runs).
    var checkKind: CheckKind {
        guard state != .unreadable, exists else { return .excluded }
        switch state {
        case .ready: return .todo
        case .done, .noSubs, .failed, .stopped: return .finished
        case .waiting, .running, .unreadable: return .excluded
        }
    }

    var isChecked: Bool { checked ?? (state == .ready) }
    var checkRow: CheckRow<UUID> { CheckRow(id: id, kind: checkKind, checked: isChecked) }
    /// A finished row checked by hand: "verrà rifatto" (C3-02).
    var willRedo: Bool { state.isFinished && isChecked && checkKind == .finished }

    /// The SRT the last batch wrote (or `<stem>.srt`), its report and its log.
    var outputSRT: URL { srtPath.map { URL(fileURLWithPath: $0) } ?? srtURL }
    var outputLog: URL { logPath.map { URL(fileURLWithPath: $0) } ?? url.deletingPathExtension().appendingPathExtension("log") }
    var logExists: Bool { FileManager.default.fileExists(atPath: outputLog.path) }
    /// The report of the last batch, when it exists on disk.
    var outputReport: URL? {
        let candidate = reportPath.map { URL(fileURLWithPath: $0) } ?? reportURL
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }
    /// The engine's code of the failure (`app.errors.<code>`): the field, else the first word of `error`.
    var errorCode: String? {
        if let failCode, !failCode.isEmpty { return failCode }
        guard let first = error?.split(separator: " ", maxSplits: 1).first, !first.hasSuffix(":") else { return nil }
        return String(first)
    }

    /// The technical detail for the box under the steps (E4): the engine's
    /// `detail`, else `error` without the `unknown (…)` or `code (detail=…)` wrapping.
    var errorDetail: String? {
        if let failDetail, !failDetail.isEmpty { return failDetail }
        guard var text = error?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if let open = text.firstIndex(of: "("), text.hasSuffix(")"), !text[..<open].contains(":"),
           text[..<open].trimmingCharacters(in: .whitespaces).allSatisfy({ $0.isLetter || $0 == "_" }) {
            text = String(text[text.index(after: open)...].dropLast())
            if text.hasPrefix("detail=") { text = String(text.dropFirst("detail=".count)) }
        }
        return text
    }

    /// The short text for the row (E4): the engine's `text`, else the detail
    /// without the exception's type name ("OCRError: ").
    var errorShort: String? {
        if let failText, !failText.isEmpty { return failText }
        guard let detail = errorDetail else { return nil }
        if let m = detail.firstMatch(of: /^[A-Za-z_][A-Za-z0-9_.]*:\s+(.+)$/.dotMatchesNewlines()) { return String(m.1) }
        return detail
    }

    /// "~/Downloads/name.log": the log as the box of E4 writes it.
    var logDisplayPath: String {
        let path = outputLog.path, home = NSHomeDirectory()
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    /// Drops the outcome: back to the next batch (Process Again, design note 9).
    mutating func resetOutcome() {
        state = .ready
        segments = nil; dropped = nil; refined = nil; elapsed = nil; times = nil; plan = nil
        srtPath = nil; reportPath = nil; logPath = nil; error = nil; atStep = nil; finished = nil
        gaps = nil; ocrLang = nil; ocrFPS = nil; gapWarn = nil
        failCode = nil; failText = nil; failDetail = nil; failTool = nil; failPath = nil; failLine = nil
        failProgram = nil; failStatus = nil; failReason = nil
    }
}

extension AppModel {
    private var videosFile: URL { configuration.stateFolder.appendingPathComponent("records/videos.json") }

    func loadVideos() {
        guard let data = try? Data(contentsOf: videosFile) else { return }
        do {
            videos = try JSONDecoder().decode([VideoItem].self, from: data)
            // A batch the last run never finished (a crash, a kill): those rows are ready again.
            for i in videos.indices where videos[i].state.inBatch { videos[i].resetOutcome() }
        } catch {
            log.error("videos.json: \(error)")
        }
        loadSummary()
    }

    func saveVideos() {
        do {
            try FileManager.default.createDirectory(at: videosFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(videos).write(to: videosFile, options: .atomic)
        } catch {
            log.error("videos.json: \(error)")
        }
    }

    /// The rows the next batch takes: the checked ones that have a box (`VideoChecks`).
    var checkedVideos: [VideoItem] { videos.filter { $0.checkRow.toProcess } }

    /// About how long the checked videos take with the parameters of now (the bottom bar);
    /// nil while a duration is not known yet.
    var checkedEstimate: Double? {
        let estimates = checkedVideos.map(estimate)
        guard !estimates.isEmpty, estimates.allSatisfy({ $0 != nil }) else { return nil }
        return estimates.compactMap { $0 }.reduce(0, +)
    }

    // MARK: - Estimates (C3-02)

    static let estimateRateKey = "estimate.rate"

    /// The work the parameters of now ask for (`WorkEstimate.factor`).
    var estimateFactor: Double { Self.factor(ocrParams) }

    static func factor(_ p: OcrParams) -> Double {
        WorkEstimate.factor(fps: p.fps, multiVariant: p.multiVariant, signs: p.topBand, refine: p.refineTiming)
    }

    /// About how long a video takes with the parameters of now; nil before its duration is known.
    func estimate(_ video: VideoItem) -> Double? {
        guard let duration = video.duration, duration > 0 else { return nil }
        return WorkEstimate.seconds(duration: duration, factor: estimateFactor, rate: estimateRate)
    }

    /// A file done teaches the rate (its seconds over its duration and its batch's work).
    func learnRate(elapsed: Double, duration: Double?, factor: Double?) {
        guard let duration, let factor, let observed = WorkEstimate.observedRate(elapsed: elapsed, duration: duration, factor: factor) else { return }
        estimateRate = WorkEstimate.learn(previous: estimateRate, observed: observed)
    }

    /// "2 h 14 min", "48 min", "55 s".
    func durationText(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = total / 60 % 60
        if h > 0 { return "\(h) h \(m) min" }
        if m > 0 { return "\(m) min" }
        return "\(total) s"
    }

    // MARK: - Adding

    /// Dropped items or the ones of Open Videos…: the videos among them (folders
    /// walked, subfolders when asked), the rest noted (E1), nothing twice (O8b).
    func add(_ urls: [URL], subfolders: Bool? = nil) {
        let recursive = subfolders ?? includeSubfolders
        let found = VideoScan.videos(in: urls, recursive: recursive)
        let fm = FileManager.default
        var folders: [URL] = [], skipped: [String] = []
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                folders.append(url)
            } else if !VideoScan.defaultExtensions.contains(url.pathExtension.lowercased()) {
                skipped.append(url.lastPathComponent)
            }
        }
        if !skipped.isEmpty { skippedItems = skipped }
        if found.isEmpty {
            if let folder = folders.first, VideoScan.videos(in: folders, recursive: recursive).isEmpty {
                Alerts.noVideos(self, folder: folder, subfolders: recursive) { [weak self] in self?.add(folders, subfolders: true) }
            }
            return
        }
        let known = Set(videos.map { $0.url.standardizedFileURL.path })
        var fresh: [VideoItem] = []
        var already = 0
        for url in found {
            if known.contains(url.standardizedFileURL.path) { already += 1; continue }
            fresh.append(VideoItem(path: url.path))
        }
        if fresh.isEmpty {
            if already > 0 { Alerts.alreadyInList(self, count: already) }
            return
        }
        videos.append(contentsOf: fresh)
        saveVideos()
        log.info("added \(fresh.count) videos (\(already) already there, \(skipped.count) skipped)")
        Task { await probe(fresh.map(\.id)) }
    }

    /// File › Open Videos… (⌘O): files and folders, "Include subfolders" in the panel.
    func openVideos() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = VideoScan.defaultExtensions.compactMap { UTType(filenameExtension: $0) } + [.folder]
        panel.message = t("app.menu.open_panel_videos")
        panel.prompt = t("app.common.open")
        let box = SubfoldersAccessory(title: t("app.menu.include_subfolders"), on: includeSubfolders)
        panel.accessoryView = box.view
        panel.isAccessoryViewDisclosed = true
        guard panel.runModal() == .OK else { return }
        includeSubfolders = box.isOn
        add(panel.urls, subfolders: box.isOn)
    }

    /// `videos.probe` for the rows that never got it (new ones, or after an engine restart).
    func probe(_ ids: [UUID]) async {
        guard status == .ready else { return }
        let paths = videos.filter { ids.contains($0.id) }.map(\.path)
        guard !paths.isEmpty else { return }
        do {
            let infos = try await engine.probe(paths)
            for info in infos {
                guard let i = videos.firstIndex(where: { $0.path == info.path }) else { continue }
                videos[i].probed = true
                // A probe again (the codecs of a row probed before C3) leaves an outcome as it is.
                let open = videos[i].state == .ready || videos[i].state == .unreadable
                if info.error != nil {
                    if open { videos[i].state = .unreadable }
                    videos[i].problem = info.message ?? info.error
                } else {
                    videos[i].duration = info.duration
                    videos[i].fps = info.fps
                    videos[i].width = info.width
                    videos[i].height = info.height
                    videos[i].videoCodec = info.videoCodec
                    videos[i].audioCodec = info.audioCodec
                    if open { videos[i].state = .ready }
                    videos[i].problem = nil
                }
                let size = (try? FileManager.default.attributesOfItem(atPath: videos[i].path)[.size]) as? NSNumber
                videos[i].bytes = size?.int64Value
            }
            saveVideos()
        } catch {
            log.error("videos.probe: \(error)")
        }
    }

    /// After the engine is up: the rows not probed yet, and the ones probed before the
    /// codecs were read (once per launch).
    func refreshVideos() async {
        let pending = videos.filter {
            $0.exists && !$0.state.inBatch && (!$0.probed || ($0.state != .unreadable && $0.videoCodec == nil && !codecProbed.contains($0.id)))
        }.map(\.id)
        codecProbed.formUnion(pending)
        if !pending.isEmpty { await probe(pending) }
    }

    // MARK: - Removing

    /// Remove from List (⌫, the context menu), undone with ⌘Z.
    func removeWithUndo(_ ids: Set<UUID>) {
        let removed = videos.enumerated().filter { ids.contains($0.element.id) }
        guard !removed.isEmpty else { return }
        // The focus goes to the row after the last one removed (or before, at the end).
        if let focus = focusedRow, ids.contains(focus) {
            let after = videos.drop { $0.id != focus }.dropFirst().first { !ids.contains($0.id) }
            let before = videos.prefix { $0.id != focus }.last { !ids.contains($0.id) }
            focusedRow = (after ?? before)?.id
        }
        videos.removeAll { ids.contains($0.id) }
        // The note on skipped items talks about this list: an empty list drops it (design note 45).
        if videos.isEmpty { skippedItems = [] }
        saveVideos()
        let undo = NSApp.keyWindow?.undoManager ?? NSApp.mainWindow?.undoManager
        undo?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                for (index, item) in removed.sorted(by: { $0.offset < $1.offset }) {
                    model.videos.insert(item, at: min(index, model.videos.count))
                }
                model.saveVideos()
            }
        }
        undo?.setActionName(t("app.menu.undo_remove"))
    }

    /// Process Again (the ⋯ and context menus): the finished row is checked, "will be redone",
    /// and keeps its outcome until the batch takes it; the new SRT gets the date in its name (C3-02).
    func processAgain(_ ids: Set<UUID>) {
        for i in videos.indices where ids.contains(videos[i].id) && videos[i].checkKind == .finished {
            videos[i].checked = true
        }
        saveVideos()
    }

    // MARK: - Checkboxes (C3-02)

    var checkRows: [CheckRow<UUID>] { videos.map(\.checkRow) }

    /// A row's box clicked: a to-do row on and off; a finished one to "will be redone" and back.
    func toggleCheck(_ id: UUID) {
        guard !batch.running, let i = videos.firstIndex(where: { $0.id == id }), videos[i].checkKind != .excluded else { return }
        let value = !videos[i].isChecked
        // Back to its default: a row that never was changed reads as before.
        videos[i].checked = value == (videos[i].state == .ready) ? nil : value
        saveVideos()
    }

    /// The list header's box (C3-02): some → all, all → none, only on the rows that have a box.
    func toggleHeader() {
        guard !batch.running else { return }
        let change = VideoChecks.headerToggle(checkRows)
        guard !change.isEmpty else { return }
        for i in videos.indices {
            guard let value = change[videos[i].id] else { continue }
            videos[i].checked = value == (videos[i].state == .ready) ? nil : value
        }
        saveVideos()
    }

    var headerCheck: CheckState { VideoChecks.headerState(checkRows) }

    /// Retry on a failed or stopped row (C3-05, E5): at once when nothing else waits,
    /// else checked, with the others, for the next batch.
    func retry(_ id: UUID) {
        guard let video = videos.first(where: { $0.id == id }), video.checkKind == .finished else { return }
        let others = checkedVideos.filter { $0.id != id }.count
        switch VideoChecks.retry(batchRunning: batch.running, othersChecked: others) {
        case .startNow:
            startBatch(only: [id])
        case .check:
            processAgain([id])
        }
    }

    // MARK: - Focus (C3-02: the keyboard's ring, no selection)

    var focusedVideo: VideoItem? { focusedRow.flatMap { id in videos.first { $0.id == id } } }

    /// ↑ ↓: the ring to the row above or below (the first or the last one when none has it).
    func moveFocus(by step: Int) {
        guard !videos.isEmpty else { return }
        guard let id = focusedRow, let i = videos.firstIndex(where: { $0.id == id }) else {
            focusedRow = (step > 0 ? videos.first : videos.last)?.id
            return
        }
        focusedRow = videos[min(max(i + step, 0), videos.count - 1)].id
    }

    /// A row's drawer: open or closed (a click on the row, Space, → and ←).
    func setDrawer(_ id: UUID, open: Bool) {
        if open { run.expanded.insert(id) } else { run.expanded.remove(id) }
    }

    func toggleDrawer(_ id: UUID) { setDrawer(id, open: !run.expanded.contains(id)) }

    /// The focused row can be removed (⌫, File › Remove from List): not while the batch works on it.
    var canRemoveFocused: Bool { focusedVideo.map { !$0.state.inBatch } ?? false }

    func removeFocused() {
        guard canRemoveFocused, let id = focusedRow else { return }
        removeWithUndo([id])
    }

    /// Remove Finished (the bottom bar): every done, failed or stopped row goes.
    func clearFinished() {
        removeWithUndo(Set(videos.filter { $0.state.isFinished }.map(\.id)))
    }

    var finishedVideos: [VideoItem] { videos.filter { $0.state.isFinished } }

    /// Every row that has a box, checked (the header's "all").
    func checkAll() {
        guard !batch.running else { return }
        for i in videos.indices where videos[i].checkKind == .todo { videos[i].checked = nil }
        saveVideos()
    }

    /// Edit › Select All (⌘A): on the Video page, with the main window in front and no text
    /// being edited, every to-do row checked; anywhere else the first responder's own Select All.
    func selectAllInContext() {
        let window = NSApp.keyWindow
        let main = window?.identifier?.rawValue.hasPrefix(config.mainWindowID) == true
        if main, tab == .process, !preview.shown, !videos.isEmpty, !(window?.firstResponder is NSText) {
            checkAll()
        } else {
            NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: nil, from: nil)
        }
    }

    func showInFinder(_ ids: Set<UUID>) {
        let urls = videos.filter { ids.contains($0.id) }.map(\.url)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// The row's Preview button, its menus: the Preview page on that video (C3-09).
    func openInPreview(_ id: UUID) { openPreview(id) }

    /// The video the Preview page shows: the chosen one, else the first of the list.
    var previewVideo: VideoItem? {
        videos.first { $0.id == previewVideoID } ?? videos.first
    }
}

/// The "Include subfolders" box of the Open panel.
@MainActor
final class SubfoldersAccessory {
    let view: NSView
    private let button: NSButton

    init(title: String, on: Bool) {
        button = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        button.state = on ? .on : .off
        button.sizeToFit()
        let box = NSView(frame: NSRect(x: 0, y: 0, width: max(240, button.frame.width + 40), height: 32))
        button.frame.origin = NSPoint(x: (box.frame.width - button.frame.width) / 2, y: 8)
        box.addSubview(button)
        view = box
    }

    var isOn: Bool { button.state == .on }
}
