// SPDX-License-Identifier: MIT
// The list of videos of Process (F4.4): drops and Open Videos… with
// subfolders, `videos.probe`, removal with undo, the skipped items, and the
// list kept between launches in `<state>/records/videos.json` (design note 8).

import AppKit
import SVShell
import UniformTypeIdentifiers

/// One row of the list. F5.1 adds the outcome of a batch to it.
struct VideoItem: Identifiable, Codable, Equatable {
    enum State: String, Codable {
        /// Goes into the next batch.
        case ready
        /// `videos.probe` found no video track: left out of the batch.
        case unreadable
        // F5.1: waiting, running, done, noSubs, failed, stopped.
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
}

extension AppModel {
    private var videosFile: URL { configuration.stateFolder.appendingPathComponent("records/videos.json") }

    func loadVideos() {
        guard let data = try? Data(contentsOf: videosFile) else { return }
        do {
            videos = try JSONDecoder().decode([VideoItem].self, from: data)
        } catch {
            log.error("videos.json: \(error)")
        }
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

    /// Rows that can be removed now (not the ones a batch is working on, F5.1).
    var canRemoveSelection: Bool { !selection.isEmpty }

    func selectAll() { selection = Set(videos.map(\.id)) }

    func showInFinder(_ ids: Set<UUID>) {
        let urls = videos.filter { ids.contains($0.id) }.map(\.url)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func openInPreview(_ id: UUID) {
        previewVideoID = id
        tab = .preview
    }

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
