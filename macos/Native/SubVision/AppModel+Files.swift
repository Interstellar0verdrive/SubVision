// SPDX-License-Identifier: MIT
// The list of videos of Process (F4.4): drops and Open Videos… with
// subfolders, `videos.probe`, removal with undo, the skipped items, and the
// list kept between launches in `<state>/records/videos.json` (design note 8).

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
    /// `key:band` of the step it failed or stopped in.
    var atStep: String?
    /// The long gaps without subtitles of the report, `[start, end]` in seconds (Review, board C2-R1).
    var gaps: [[Double]]?
    /// The OCR language and the frames per second the file was processed with ("Italiano · 12 fps").
    var ocrLang: String?
    var ocrFPS: Double?
    /// When the outcome arrived.
    var finished: Date?

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
        gaps = nil; ocrLang = nil; ocrFPS = nil
        failCode = nil; failText = nil; failDetail = nil; failTool = nil; failPath = nil; failLine = nil
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

    var readyVideos: [VideoItem] { videos.filter { $0.state == .ready && $0.exists } }

    /// "3 video · 48 min in tutto".
    var totalDuration: Double { readyVideos.compactMap(\.duration).reduce(0, +) }

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
                if info.error != nil {
                    videos[i].state = .unreadable
                    videos[i].problem = info.message ?? info.error
                } else {
                    videos[i].duration = info.duration
                    videos[i].fps = info.fps
                    videos[i].width = info.width
                    videos[i].height = info.height
                    videos[i].state = .ready
                    videos[i].problem = nil
                }
            }
            saveVideos()
        } catch {
            log.error("videos.probe: \(error)")
        }
    }

    /// After the engine is up: the rows not probed yet.
    func refreshVideos() async {
        let pending = videos.filter { !$0.probed && $0.exists }.map(\.id)
        if !pending.isEmpty { await probe(pending) }
    }

    // MARK: - Removing

    /// Remove from List (⌫, the context menu), undone with ⌘Z.
    func removeWithUndo(_ ids: Set<UUID>) {
        let removed = videos.enumerated().filter { ids.contains($0.element.id) }
        guard !removed.isEmpty else { return }
        videos.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
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

    func removeSelection() { removeWithUndo(selection) }

    /// Rows that can be removed now (not the ones a batch is working on).
    var canRemoveSelection: Bool {
        !selection.isEmpty && !videos.contains { selection.contains($0.id) && $0.state.inBatch }
    }

    /// Process Again (the row, the context menu): a finished row goes back to ready (design note 9).
    func processAgain(_ ids: Set<UUID>) {
        for i in videos.indices where ids.contains(videos[i].id) && videos[i].state.isFinished {
            videos[i].resetOutcome()
        }
        saveVideos()
    }

    /// Remove Finished (the bottom bar): every done, failed or stopped row goes.
    func clearFinished() {
        removeWithUndo(Set(videos.filter { $0.state.isFinished }.map(\.id)))
    }

    var finishedVideos: [VideoItem] { videos.filter { $0.state.isFinished } }

    func selectAll() { selection = Set(videos.map(\.id)) }

    func showInFinder(_ ids: Set<UUID>) {
        let urls = videos.filter { ids.contains($0.id) }.map(\.url)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// The row's Preview button, its menus: the Preview window on that video (design note 80).
    func openInPreview(_ id: UUID) { openPreview(id) }

    /// The sidebar's Preview line: the chosen video, else the first of the list.
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
