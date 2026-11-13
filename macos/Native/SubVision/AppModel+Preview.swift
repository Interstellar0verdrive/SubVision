// SPDX-License-Identifier: MIT
// Preview (F5.2, design boards C2-A1–A3, design notes 76, 79, 80): the
// Preview window on one video of the list, `preview.frames` with its
// progress and stop, the frames found (kept per video while the app is
// open), the current frame with its thumbnails, and Try OCR
// (`preview.test`), whose results stay per frame until the app quits. The
// bands themselves live in UserDefaults (`OcrKey`), shared with the
// parameters panel: `BandOverlay.swift` reads and writes them. The window is
// in PreviewWindow.swift, its content in PreviewView.swift.

import AppKit
import ImageIO
import SVShell
import SwiftUI

/// Everything the Preview window shows; `AppModel.preview` holds it.
struct PreviewState {
    enum Search: Equatable {
        case idle
        /// `preview.progress`: zones done of total, and how many had text.
        case running(done: Int, total: Int, found: Int)
        /// `preview.failed`, or `preview.frames` refused (`busy`).
        case failed(code: String, message: String?)
    }

    /// The frames of one video (inventory §4: they stay until the app quits,
    /// so going to another video and back does not search again).
    struct Result {
        var frames: [PreviewFrame]
        /// The frame shown, 0-based.
        var index = 0
        /// One small image per frame, made once from the whole frames (design notes 30, 76).
        var thumbnails: [NSImage?] = []
        var found: Int { frames.filter(\.hasText).count }
        /// The frames with a sign (design note 78: "17 with text · 5 with signs").
        var foundSigns: Int { frames.filter(\.hasSigns).count }
    }

    /// Try OCR on one frame.
    enum Test {
        case reading
        /// The reply, with the parameters it ran with: a change of the ones a band
        /// depends on makes that band's panel stale (design note 79).
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
    /// The video the search runs on (the Video menu is disabled meanwhile).
    var searching: UUID?
    var results: [UUID: Result] = [:]
    /// The tests made, per frame, until the app quits (design note 79): another
    /// frame or video does not clear them.
    var tests: [FrameKey: Test] = [:]
    /// The frame being read: one test at a time.
    var reading: FrameKey?
    /// The parameters as they are now, refreshed on every change of UserDefaults
    /// while the window is open (the panels compare a test's parameters with them).
    var params = OcrParams()
    /// The current whole frame, decoded once per frame.
    var frameImage: NSImage?
    var frameImagePath: String?
    /// The band being dragged with its values: the label next to the handle.
    var drag: BandDrag?
    /// Where the frame is drawn (SwiftUI's global space), for the DebugQA drag commands.
    var frameRect: CGRect = .zero
    /// The Preview window is the key window: the Preview commands of the menu bar act on it.
    var windowKey = false
    /// The one Preview window, while it is open (design note 80).
    var window: PreviewWindowController?
}

extension PreviewBand {
    /// The band's name in `OcrTestReply.bands` and `PreviewFrame.bands`.
    var engineKey: String { self == .dialogue ? "bottom" : "top" }

    /// Whether a test made with `a` still says what one with `b` would (design note 79):
    /// the band's own height and width (and, for the signs, its switch), the OCR language,
    /// the multiple reading and the minimum confidence.
    func sameReading(_ a: OcrParams, _ b: OcrParams) -> Bool {
        guard a.langHint == b.langHint, a.multiVariant == b.multiVariant, a.minConfidence == b.minConfidence else { return false }
        switch self {
        case .dialogue: return a.bottomKeepPct == b.bottomKeepPct && a.keepWPct == b.keepWPct
        case .signs: return a.topBand == b.topBand && a.topKeepPct == b.topKeepPct && a.topKeepWPct == b.topKeepWPct
        }
    }
}

extension AppModel {
    // MARK: - What the window reads

    var previewResult: PreviewState.Result? { previewVideo.flatMap { preview.results[$0.id] } }
    var previewFrames: [PreviewFrame] { previewResult?.frames ?? [] }

    var previewFrame: PreviewFrame? {
        guard let r = previewResult, r.frames.indices.contains(r.index) else { return nil }
        return r.frames[r.index]
    }

    /// The frame on screen, as its test is kept.
    var previewTestKey: PreviewState.FrameKey? {
        guard let video = previewVideo, let frame = previewFrame else { return nil }
        return PreviewState.FrameKey(video: video.id, frame: frame.path)
    }

    /// The test of the frame on screen, if one was made.
    var previewTest: PreviewState.Test? { previewTestKey.flatMap { preview.tests[$0] } }

    /// The band's result on screen is older than the parameters it depends on ("Superato").
    func previewStale(_ band: PreviewBand) -> Bool {
        guard case .done(_, let params)? = previewTest else { return false }
        return !band.sameReading(params, preview.params)
    }

    var isSearchingFrames: Bool {
        if case .running = preview.search { return true }
        return false
    }

    var isReadingOCR: Bool { preview.reading != nil }

    /// "Find 20 Frames": the engine up, no batch, no search, a readable
    /// video (a processed one too: the search is about the bands, not the batch).
    var canFindFrames: Bool {
        guard status == .ready, !batch.running, !isSearchingFrames, let video = previewVideo else { return false }
        return video.state != .unreadable && video.exists
    }

    /// The Video menu's items: every readable video that exists and is not being processed,
    /// the processed ones too (design note 73, the rule of `canFindFrames`).
    func canPreview(_ video: VideoItem) -> Bool {
        video.state != .unreadable && video.state != .running && video.exists
    }

    /// "Try OCR" (⌘T): a frame on screen, Vision answering, nothing else running.
    var canTryOCR: Bool {
        status == .ready && !batch.running && !isSearchingFrames && !isReadingOCR && previewFrame != nil && hello?.vision == true
    }

    /// Previous / Next Frame (⌘← ⌘→).
    var canBrowseFrames: Bool { previewFrames.count > 1 }

    /// The handles: not during the batch (the parameters are locked, C2-A3).
    var canDragBands: Bool { !batch.running && status == .ready }

    /// "Anteprima · 01:03 · 23,976 fps · 2544×1440": the window's subtitle.
    var previewSubtitle: String {
        var parts = [t("app.preview.title")]
        if let video = previewVideo {
            if let duration = video.duration { parts.append(Localizer.clock(duration)) }
            if let fps = video.fps { parts.append(t("app.preview.fps", ["fps": previewFPSText(fps)])) }
            if let size = video.size { parts.append(size) }
        }
        return parts.joined(separator: " · ")
    }

    /// "23,976" or "24": the language's separators, no trailing zeros (as the list's column).
    func previewFPSText(_ fps: Double) -> String {
        let rounded = (fps * 1000).rounded() / 1000
        return localizer.number(rounded, decimals: rounded == rounded.rounded() ? 0 : 3)
    }

    // MARK: - The window

    /// The Preview window on a video (the row's Preview button, the ⋯ and context menus,
    /// the menu bar): one window at a time, brought to the front if open (design note 80).
    /// nil keeps the video chosen last. A video without frames yet starts its search.
    func openPreview(_ id: UUID?) {
        if let id, id != previewVideoID {
            if isSearchingFrames {
                log.info("preview: \(previewVideo?.name ?? "-") is being searched, the window stays on it")
            } else {
                selectPreviewVideo(id)
            }
        }
        if preview.window == nil {
            let controller = PreviewWindowController(model: self)
            controller.onClose = { [weak self] in self?.previewWindowClosed() }
            preview.window = controller
        }
        refreshPreviewParams()
        loadFrameImage()
        preview.window?.show()
        log.info("preview window: \(previewVideo?.name ?? "-")")
        findFramesIfNone()
    }

    /// The window went: the menu bar's Preview commands go off with it.
    private func previewWindowClosed() {
        preview.window = nil
        preview.windowKey = false
        preview.drag = nil
    }

    // MARK: - The video

    /// The chosen video (`previewVideoID`, kept across launches). Its frames and
    /// tests, and those of the others, stay.
    func selectPreviewVideo(_ id: UUID) {
        guard !isSearchingFrames, id != previewVideoID else { return }
        previewVideoID = id
        preview.search = .idle
        preview.drag = nil
        loadFrameImage()
    }

    /// An item of the window's Video menu: the video, and its search when it has no frames yet.
    func choosePreviewVideo(_ id: UUID) {
        selectPreviewVideo(id)
        if preview.window != nil { findFramesIfNone() }
    }

    /// Find 20 Frames by itself, on a video that has none yet (when it can run).
    func findFramesIfNone() {
        guard let video = previewVideo, preview.results[video.id] == nil, canFindFrames else { return }
        findFrames()
    }

    // MARK: - Find 20 Frames

    func findFrames() {
        guard canFindFrames, let video = previewVideo else { return }
        preview.searching = video.id
        preview.search = .running(done: 0, total: PreviewState.zones, found: 0)
        let params = ocrParams
        Task {
            do {
                let reply = try await engine.previewFrames(video: video.path, params: params, n: PreviewState.zones, tries: PreviewState.tries)
                if !reply.started {
                    log.error("preview.frames not started: \(reply.reason ?? "?")")
                    preview.search = .failed(code: reply.reason ?? "busy", message: nil)
                    preview.searching = nil
                }
            } catch {
                log.error("preview.frames: \(error)")
                preview.search = .failed(code: (error as? EngineError)?.remoteCode ?? "unknown", message: Self.errorDetail(error))
                preview.searching = nil
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
            if isSearchingFrames { preview.search = .running(done: p.done, total: p.total, found: p.found) }
        case .previewDone(let done):
            guard let id = preview.searching else { return }
            let frames = done.frames
            var result = PreviewState.Result(frames: frames)
            // The first frame with text, so Try OCR has something to read.
            result.index = frames.firstIndex(where: \.hasText) ?? 0
            result.thumbnails = Array(repeating: nil, count: frames.count)
            preview.results[id] = result
            // New frames: the tests of the old ones of this video go with them.
            preview.tests = preview.tests.filter { $0.key.video != id }
            preview.search = .idle
            preview.searching = nil
            log.info("preview: \(frames.count) frames, \(result.found) with text")
            loadFrameImage()
            makeThumbnails(for: id, frames: frames)
        case .previewStopped:
            preview.search = .idle
            preview.searching = nil
            log.info("preview stopped")
        case .previewFailed(let failed):
            preview.search = .failed(code: failed.error, message: failed.message)
            preview.searching = nil
            log.error("preview failed: \(failed.error) \(failed.message ?? "")")
        default:
            log.debug("event \(name) (not for preview)")
        }
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

    /// The 20 thumbnails, decoded small from the JPEGs off the main thread
    /// (240 px on the long side, design note 76: 20 of them weigh about a megabyte).
    private func makeThumbnails(for id: UUID, frames: [PreviewFrame]) {
        let paths = frames.map(\.path)
        Task.detached(priority: .utility) {
            let batch = ThumbnailBatch(paths: paths, maxPixels: PreviewState.thumbnailPixels)
            await MainActor.run {
                guard var result = self.preview.results[id], result.frames.map(\.path) == paths else { return }
                result.thumbnails = paths.map { batch.images[$0].map { NSImage(cgImage: $0, size: .zero) } }
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

    func nextFrame() { if let r = previewResult { selectFrame(min(r.index + 1, r.frames.count - 1)) } }
    func previousFrame() { if let r = previewResult { selectFrame(max(r.index - 1, 0)) } }

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
            guard let i = result.frames.firstIndex(where: { $0.path == path }) else { continue }
            var f = result.frames[i]
            var bands: [String] = []
            for band in ["bottom", "top"] {
                if let read = reply.bands[band] {
                    if !read.empty { bands.append(band) }
                } else if f.bands.contains(band) {
                    bands.append(band)
                }
            }
            guard bands != f.bands else { continue }
            f.bands = bands
            f.hasText = !bands.isEmpty
            result.frames[i] = f
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
