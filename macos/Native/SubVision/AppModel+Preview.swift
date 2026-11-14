// SPDX-License-Identifier: MIT
// Preview (F5.2; design round C3, boards C3-09, C3-11, A0–A6): a page
// inside Video (P-A) on one video of the list, entered from a row's
// «Anteprima», ⌘Y or the drawer's frames and left with the title band's ‹
// (⌘[). The first time a video is shown its 20 frames are searched by
// themselves (`preview.frames`, zone by zone, each progress event with its
// frame) and kept per video while the app is open; a search that stops (the
// batch, Stop, an unreadable part) keeps what it found and «Riprova» asks
// only for the zones left. Try OCR (`preview.test`) keeps its results per
// frame until the app quits. The bands themselves live in UserDefaults
// (`OcrKey`), shared with the parameters panel: `BandOverlay.swift` reads and
// writes them. The page is in PreviewPage.swift, its content in PreviewView.swift.

import AppKit
import ImageIO
import SVShell
import SwiftUI

/// Everything the Preview page shows; `AppModel.preview` holds it.
struct PreviewState {
    enum Search: Equatable {
        case idle
        /// `preview.progress` of the video being searched: zones done of total, and how
        /// many of its frames have text.
        case running(done: Int, total: Int, found: Int)
        /// `preview.failed`, or `preview.frames` refused (`busy`).
        case failed(code: String, message: String?)
    }

    /// The frames of one video (inventory §4: they stay until the app quits,
    /// so going to another video and back does not search again).
    struct Result {
        var search: FrameSearch
        /// The frame shown, 0-based; nil while none is chosen (a search that stopped
        /// shows its box with «Riprova» until a thumbnail is clicked, board A1).
        var index: Int?
        /// One small image per frame, by path, made once from the whole frames (design notes 30, 76).
        var thumbnails: [String: NSImage] = [:]

        init(total: Int = PreviewState.zones) { search = FrameSearch(total: total) }

        var frames: [PreviewFrame] { search.frames }
        /// The thumbnail of frame `i` (nil until it is decoded): the page's strip and the drawer's.
        func thumbnail(_ i: Int) -> NSImage? { frames.indices.contains(i) ? thumbnails[frames[i].path] : nil }
        var found: Int { search.found }
        /// The frames with a sign (design note 78: "17 with text · 5 with signs").
        var foundSigns: Int { search.foundSigns }
    }

    /// Try OCR on one frame.
    enum Test {
        case reading
        /// The reply, with the parameters it ran with: a change of the ones a band
        /// depends on makes that band's panel stale (design note 79, C3-11).
        case done(OcrTestReply, params: OcrParams)
        case failed(code: String, message: String?)
    }

    /// A frame of a video: where its test is kept (design note 79).
    struct FrameKey: Hashable {
        var video: UUID
        var frame: String
    }

    static let zones = 20
    static let tries = 3
    /// The thumbnails' long side, in pixels (design note 76: about 240, was 120).
    static let thumbnailPixels = 240

    var search: Search = .idle
    /// The video the engine searches now.
    var searching: UUID?
    /// The search was stopped to go to another video: its stop is `.switched` (it goes
    /// on by itself when that video comes back) and the video shown starts its own.
    var switching = false
    var results: [UUID: Result] = [:]
    /// The tests made, per frame, until the app quits (design note 79): another
    /// frame or video does not clear them.
    var tests: [FrameKey: Test] = [:]
    /// The frame being read: one test at a time.
    var reading: FrameKey?
    /// The parameters as they are now, refreshed on every change of UserDefaults
    /// while the page is shown (the panels compare a test's parameters with them).
    var params = OcrParams()
    /// The current whole frame, decoded once per frame.
    var frameImage: NSImage?
    var frameImagePath: String?
    /// The band being dragged with its values: the label next to the handle.
    var drag: BandDrag?
    /// Where the frame is drawn (SwiftUI's global space), for the DebugQA drag commands.
    var frameRect: CGRect = .zero
    /// The Preview page is over the list of Video (C3-09, P-A).
    var shown = false
    /// The page is sliding out (back to the list); it closes at the end of the slide.
    var leaving = false
    /// What the list had when the page came: its selection (put back on the way out, so
    /// the list's keys do not act on rows nobody sees) and the panel's tab.
    var savedSelection: Set<UUID> = []
    var savedTab: String?
    /// `AppModel.backGeneration` right after the page set `backAction`.
    var backGeneration: Int?
}

extension PreviewBand {
    /// The band's name in `OcrTestReply.bands` and `PreviewFrame.bands`.
    var engineKey: String { self == .dialogue ? "bottom" : "top" }
}

extension AppModel {
    // MARK: - What the page reads

    var previewResult: PreviewState.Result? { previewVideo.flatMap { preview.results[$0.id] } }
    var previewFrames: [PreviewFrame] { previewResult?.frames ?? [] }

    var previewFrame: PreviewFrame? {
        guard let r = previewResult, let i = r.index, r.frames.indices.contains(i) else { return nil }
        return r.frames[i]
    }

    /// The frame on screen, as its test is kept.
    var previewTestKey: PreviewState.FrameKey? {
        guard let video = previewVideo, let frame = previewFrame else { return nil }
        return PreviewState.FrameKey(video: video.id, frame: frame.path)
    }

    /// The test of the frame on screen, if one was made.
    var previewTest: PreviewState.Test? { previewTestKey.flatMap { preview.tests[$0] } }

    /// The band's result on screen is older than the parameters it depends on (C3-11).
    func previewStale(_ band: PreviewBand) -> Bool {
        guard case .done(_, let params)? = previewTest else { return false }
        return PreviewStaleness.staleBands(tested: params, now: preview.params).contains(band.engineKey)
    }

    /// The page is in front: on Video, over the list.
    var previewShown: Bool { preview.shown && tab == .process }

    /// The engine searches frames (of any video).
    var isSearchingFrames: Bool {
        if case .running = preview.search { return true }
        return false
    }

    /// The video shown is the one being searched, or waits for the search of another
    /// to stop before its own starts (board A0).
    var isSearchingPreviewVideo: Bool {
        guard let id = previewVideo?.id else { return false }
        if isSearchingFrames { return preview.searching == id || preview.switching }
        return false
    }

    var isReadingOCR: Bool { preview.reading != nil }

    /// The search can run on the video shown: the engine up, no batch, no other search,
    /// a readable video (a processed one too: the search is about the bands, not the batch).
    var canFindFrames: Bool {
        guard status == .ready, !batch.running, !isSearchingFrames, let video = previewVideo else { return false }
        return video.state != .unreadable && video.exists
    }

    /// The videos the page can show, and the arrows reach: every readable video that
    /// exists and is not being processed, the processed ones too (design note 73).
    func canPreview(_ video: VideoItem) -> Bool {
        video.state != .unreadable && video.state != .running && video.exists
    }

    /// "Try OCR" (⌘T): a frame on screen, Vision answering, nothing else running.
    var canTryOCR: Bool {
        status == .ready && !batch.running && !isSearchingFrames && !isReadingOCR && previewFrame != nil && hello?.vision == true
    }

    /// Previous / Next Frame (⌘← ⌘→).
    var canBrowseFrames: Bool { !previewFrames.isEmpty && !isSearchingPreviewVideo }

    /// The handles: not during the batch (the parameters are locked, C2-A3).
    var canDragBands: Bool { !batch.running && status == .ready }

    /// "01:03 · 23,976 fps · 2544×1440 · 20 fotogrammi trovati da soli · 17 con testo":
    /// the title band's details (the last part once every zone has its frame).
    var previewDetails: String {
        guard let video = previewVideo else { return "" }
        var parts: [String] = []
        if let duration = video.duration { parts.append(Localizer.clock(duration)) }
        if let fps = video.fps { parts.append(t("app.preview.fps", ["fps": previewFPSText(fps)])) }
        if let size = video.size { parts.append(size) }
        if let r = previewResult, r.search.complete, !isSearchingPreviewVideo {
            parts.append(t("app.preview.found_by_itself", ["n": r.frames.count, "k": r.found]))
        }
        return parts.joined(separator: " · ")
    }

    /// "23,976" or "24": the language's separators, no trailing zeros (as the list's column).
    func previewFPSText(_ fps: Double) -> String {
        let rounded = (fps * 1000).rounded() / 1000
        return localizer.number(rounded, decimals: rounded == rounded.rounded() ? 0 : 3)
    }

    // MARK: - The page

    /// The Preview page on a video (a row's «Anteprima», its menus, the drawer's frames, ⌘Y):
    /// on Video, over the list. nil keeps the video shown last; `frame` (0-based, among the
    /// frames found) shows that frame, as a click on the drawer's strip. A video never
    /// searched starts its search.
    func openPreview(_ id: UUID?, frame: Int? = nil) {
        if !preview.shown {
            // The list's selection and the panel's tab wait for the way back; the panel shows Bande.
            preview.savedSelection = selection
            selection = []
            preview.savedTab = defaults.string(forKey: InspectorTab.key)
            defaults.set(InspectorTab.bands.rawValue, forKey: InspectorTab.key)
            preview.shown = true
        }
        preview.leaving = false
        if tab != .process { showPage(.process) }
        if let id { showPreviewVideo(id) }
        if let frame { selectFrame(frame) }
        refreshPreviewParams()
        loadFrameImage()
        log.info("preview: \(previewVideo?.name ?? "-")")
        findFramesIfNeeded()
    }

    /// The title band's ‹ and View › Back: the page slides out, then `closePreview`.
    func leavePreview() {
        guard preview.shown else { return }
        // The slide is the page's; a page not on screen closes at once.
        if tab == .process, status == .ready { preview.leaving = true } else { closePreview() }
    }

    /// Back to the list, as it was: its selection, the drawers as they were, the panel's tab.
    func closePreview() {
        guard preview.shown else { return }
        preview.shown = false
        preview.leaving = false
        preview.drag = nil
        let ids = Set(videos.map(\.id))
        selection = preview.savedSelection.intersection(ids)
        preview.savedSelection = []
        if let saved = preview.savedTab, defaults.string(forKey: InspectorTab.key) == InspectorTab.bands.rawValue {
            defaults.set(saved, forKey: InspectorTab.key)
        }
        preview.savedTab = nil
    }

    // MARK: - The video

    /// Another video on the page (the arrows, ⌘↑ ⌘↓, `openPreview`). Its frames and tests,
    /// and those of the others, stay. A search running on the one left stops (it goes on by
    /// itself when that video comes back) and the new one searches once it has stopped.
    func showPreviewVideo(_ id: UUID) {
        guard id != previewVideo?.id || previewVideoID == nil else { return }
        previewVideoID = id
        preview.drag = nil
        if case .failed = preview.search { preview.search = .idle }
        if isSearchingFrames, let searching = preview.searching, searching != id, !preview.switching {
            preview.switching = true
            stopFrames()
        }
        loadFrameImage()
        findFramesIfNeeded()
    }

    /// The video `step` rows away in the list (-1 above, +1 below) that the page can show.
    func previewNeighbour(_ step: Int) -> VideoItem? {
        guard let current = previewVideoIndex,
              let i = PreviewNeighbours.index(from: current, step: step, count: videos.count, allowed: { self.canPreview(self.videos[$0]) })
        else { return nil }
        return videos[i]
    }

    /// The position of the video shown in the list ("video 1 di 3").
    var previewVideoIndex: Int? {
        guard let id = previewVideo?.id else { return nil }
        return videos.firstIndex { $0.id == id }
    }

    /// The title band's arrows, ⌘↑ ⌘↓.
    func showNeighbourVideo(_ step: Int) {
        guard previewShown, let video = previewNeighbour(step) else { return }
        showPreviewVideo(video.id)
    }

    // MARK: - The frames

    /// The search starts by itself on a video never searched (or left while it searched),
    /// when it can run; after Stop, a batch or an unreadable part the page offers «Riprova».
    func findFramesIfNeeded() {
        guard preview.shown, let video = previewVideo, canFindFrames,
              FrameSearch.searchesBySelf(preview.results[video.id]?.search) else { return }
        findFrames()
    }

    /// The search of the video shown: the whole of it the first time, the zones left after a
    /// stop («Riprova», board A1). The zones look at the same points every time, so there is
    /// nothing to search again once every zone has its frame.
    func findFrames() {
        guard canFindFrames, let video = previewVideo else { return }
        var result = preview.results[video.id] ?? PreviewState.Result()
        if result.search.complete { return }
        let zones: [Int]? = preview.results[video.id] == nil ? nil : result.search.zonesLeft
        result.search.begin()
        preview.results[video.id] = result
        preview.searching = video.id
        preview.search = .running(done: result.search.total - (zones?.count ?? result.search.total),
                                  total: result.search.total, found: result.found)
        let params = ocrParams
        Task {
            do {
                let reply = try await engine.previewFrames(video: video.path, params: params, n: PreviewState.zones,
                                                           tries: PreviewState.tries, zones: zones)
                if !reply.started {
                    log.error("preview.frames not started: \(reply.reason ?? "?")")
                    searchEnded(.failed(code: reply.reason ?? "busy", message: nil), video: video.id)
                }
            } catch {
                log.error("preview.frames: \(error)")
                searchEnded(.failed(code: (error as? EngineError)?.remoteCode ?? "unknown", message: Self.errorDetail(error)), video: video.id)
            }
        }
    }

    /// Stop: `preview.stop`; the engine answers with `preview.stopped`.
    func stopFrames() {
        guard isSearchingFrames else { return }
        Task {
            do { _ = try await engine.previewStop() } catch { log.error("preview.stop: \(error)") }
        }
    }

    /// The `preview.*` events, from the one consumer in `AppModel.listen()`.
    func handlePreview(_ message: EngineMessage, name: String) {
        switch message {
        case .previewProgress(let p):
            guard isSearchingFrames, let id = preview.searching, var result = preview.results[id] else { return }
            if let frame = p.frame, let zone = p.zone ?? frame.zone {
                result.search.add(frame, zone: zone)
                preview.results[id] = result
                makeThumbnails(for: id, paths: [frame.path])
            }
            preview.search = .running(done: p.done, total: p.total, found: result.found)
        case .previewDone(let done):
            guard let id = preview.searching, var result = preview.results[id] else { return }
            result.search.finish(done.frames)
            // The first frame with text, so Try OCR has something to read; a search that
            // stopped short waits for a click on a thumbnail (A1).
            if result.index == nil, result.search.complete {
                result.index = result.frames.firstIndex(where: \.hasText) ?? 0
            }
            preview.results[id] = result
            log.info("preview: \(result.frames.count) frames, \(result.found) with text")
            makeThumbnails(for: id, paths: result.frames.map(\.path).filter { result.thumbnails[$0] == nil })
            searchEnded(.idle, video: id)
        case .previewStopped(let stopped):
            guard let id = preview.searching else { return }
            let reason: FrameSearch.Stop = preview.switching ? .switched : (stopped.reason == "batch" ? .batch : .user)
            preview.results[id]?.search.stopped(reason)
            log.info("preview stopped (\(reason.rawValue))")
            searchEnded(.idle, video: id)
        case .previewFailed(let failed):
            log.error("preview failed: \(failed.error) \(failed.message ?? "")")
            guard let id = preview.searching else { return }
            searchEnded(.failed(code: failed.error, message: failed.message), video: id)
        default:
            log.debug("event \(name) (not for preview)")
        }
    }

    /// A search ended (done, stopped, failed, refused): the page goes on with the video
    /// shown, which searches by itself if it was waiting for this one to stop.
    private func searchEnded(_ search: PreviewState.Search, video id: UUID) {
        let switched = preview.switching
        preview.switching = false
        preview.searching = nil
        // A failure belongs to the video shown; one of a video left behind is not shown on another.
        if case .failed = search, id != previewVideo?.id { preview.search = .idle } else { preview.search = search }
        // The video could not be read: what was found stays, «Riprova» tries the rest.
        if case .failed = search { preview.results[id]?.search.stopped(.unreadable) }
        loadFrameImage()
        if switched || id != previewVideo?.id { findFramesIfNeeded() }
    }

    /// The engine's own `detail` of an error (`RemoteErrorInfo`), else the error as it describes itself.
    static func errorDetail(_ error: Error) -> String {
        if let detail = (error as? EngineError)?.remoteInfo?.detail, !detail.isEmpty { return detail }
        return String(describing: error)
    }

    /// `app.errors.<code>` with what the engine said; unknown codes fall back to `unknown`.
    func previewErrorText(code: String, message: String?) -> String {
        let values: [String: Any] = ["detail": message ?? code, "tool": "ffprobe", "path": previewVideo?.path ?? ""]
        return localizer.has("app.errors.\(code)") ? t("app.errors.\(code)", values) : t("app.errors.unknown", values)
    }

    /// The thumbnails of `paths`, decoded small from the JPEGs off the main thread
    /// (240 px on the long side, design note 76: 20 of them weigh about a megabyte).
    private func makeThumbnails(for id: UUID, paths: [String]) {
        guard !paths.isEmpty else { return }
        Task.detached(priority: .utility) {
            let batch = ThumbnailBatch(paths: paths, maxPixels: PreviewState.thumbnailPixels)
            await MainActor.run {
                guard var result = self.preview.results[id] else { return }
                for path in paths where result.frames.contains(where: { $0.path == path }) {
                    result.thumbnails[path] = batch.images[path].map { NSImage(cgImage: $0, size: .zero) }
                }
                self.preview.results[id] = result
            }
        }
    }

    // MARK: - Browsing

    func selectFrame(_ index: Int) {
        guard let video = previewVideo, var result = preview.results[video.id], result.frames.indices.contains(index) else { return }
        guard result.index != index else { return }
        result.index = index
        preview.results[video.id] = result
        loadFrameImage()
    }

    /// ⌘→, →, the arrow right of the frame; with no frame chosen yet, the first.
    func nextFrame() {
        guard let r = previewResult, !r.frames.isEmpty else { return }
        selectFrame(r.index.map { min($0 + 1, r.frames.count - 1) } ?? 0)
    }

    /// ⌘←, ←, the arrow left of the frame; with no frame chosen yet, the last.
    func previousFrame() {
        guard let r = previewResult, !r.frames.isEmpty else { return }
        selectFrame(r.index.map { max($0 - 1, 0) } ?? r.frames.count - 1)
    }

    /// The whole frame on screen, decoded once; nil when the file went ("not available").
    func loadFrameImage() {
        let path = previewFrame?.path
        guard path != preview.frameImagePath else { return }
        preview.frameImagePath = path
        preview.frameImage = path.flatMap { NSImage(contentsOfFile: $0) }
    }

    /// "Frame 8 of 20 · 00:00:20".
    func frameCaption(_ frame: PreviewFrame, index: Int, count: Int) -> String {
        let total = max(0, Int(frame.ts.rounded()))
        let ts = String(format: "%02d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
        return t("app.preview.frame_of", ["i": index + 1, "n": count, "ts": ts])
    }

    // MARK: - Try OCR

    /// Try OCR on the frame on screen; its result stays with that frame (design note 79).
    /// The stale panels' «Riprova OCR con i nuovi parametri» runs it again (C3-11).
    func tryOCR() {
        guard canTryOCR, let key = previewTestKey else { return }
        let params = ocrParams, ignore = useIgnore, corrections = useCorrections
        preview.tests[key] = .reading
        preview.reading = key
        preview.params = params
        Task {
            do {
                let reply = try await engine.previewTest(frame: key.frame, params: params, useIgnore: ignore, useCorrections: corrections)
                preview.tests[key] = .done(reply, params: params)
                log.info("preview.test: bottom \"\(reply.bottom?.text ?? "")\" top \"\(reply.top?.text ?? "")\"")
                applyTestToBadge(reply, frame: key.frame)
            } catch {
                log.error("preview.test: \(error)")
                preview.tests[key] = .failed(code: (error as? EngineError)?.remoteCode ?? "unknown", message: Self.errorDetail(error))
            }
            preview.reading = nil
        }
    }

    /// After Try OCR the frame's badge and dot say what the full reading found, not the
    /// quick probe of the search (design note 77): a band that reads nothing loses its colour.
    /// A band the test did not read (the signs band off) keeps what the search said.
    func applyTestToBadge(_ reply: OcrTestReply, frame path: String) {
        for (id, var result) in preview.results {
            guard let f = result.frames.first(where: { $0.path == path }) else { continue }
            var bands: [String] = []
            for band in ["bottom", "top"] {
                if let read = reply.bands[band] {
                    if !read.empty { bands.append(band) }
                } else if f.bands.contains(band) {
                    bands.append(band)
                }
            }
            guard bands != f.bands else { continue }
            var changed = f
            changed.bands = bands
            changed.hasText = !bands.isEmpty
            result.search.add(changed, zone: f.zone ?? 0)
            preview.results[id] = result
        }
    }

    /// Forgets the test of the frame on screen.
    func clearTest() {
        guard let key = previewTestKey, preview.reading != key else { return }
        preview.tests[key] = nil
    }

    /// After any change in UserDefaults: today's parameters, which the panels compare their test with.
    func refreshPreviewParams() {
        let now = ocrParams
        if now != preview.params { preview.params = now }
    }
}

/// The small images of the thumbnails, made with ImageIO's downsampling decoder:
/// the whole JPEG is never decoded at full size.
struct ThumbnailBatch: @unchecked Sendable {
    var images: [String: CGImage] = [:]

    init(paths: [String], maxPixels: Int) {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        for path in paths {
            guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { continue }
            images[path] = image
        }
    }
}
