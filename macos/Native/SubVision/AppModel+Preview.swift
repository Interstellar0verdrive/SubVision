// SPDX-License-Identifier: MIT
// Preview (F5.2, design boards A1–A6): `preview.frames` with its progress and
// stop, the frames found (kept per video while the app is open), the current
// frame with its thumbnails, and Try OCR (`preview.test`) with the two
// panels. The bands themselves live in UserDefaults (`OcrKey`), shared with
// the inspector: `BandOverlay.swift` reads and writes them.

import AppKit
import ImageIO
import SVShell
import SwiftUI

/// Everything the Preview page shows; `AppModel.preview` holds it.
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
        /// One small image per frame, made once from the whole frames (design note 30).
        var thumbnails: [NSImage?] = []
        var found: Int { frames.filter(\.hasText).count }
        /// The frames with a sign (design note 78: "17 with text · 5 with signs").
        var foundSigns: Int { frames.filter(\.hasSigns).count }
    }

    enum Test {
        case reading
        /// The reply, with the parameters it ran with (a change after it makes it stale, A5).
        case done(OcrTestReply, params: OcrParams, useIgnore: Bool, useCorrections: Bool)
        case failed(code: String, message: String?)
    }

    static let zones = 20
    static let tries = 3

    var search: Search = .idle
    /// The video the search runs on (the Video menu is disabled meanwhile, A2).
    var searching: UUID?
    var results: [UUID: Result] = [:]
    var test: Test?
    /// The frame the test ran on: another frame, or video, clears the panels.
    var testFrame: String?
    /// The parameters changed after the test (A5: "try again").
    var stale = false
    /// The current whole frame, decoded once per frame.
    var frameImage: NSImage?
    var frameImagePath: String?
    /// The band being dragged with its values: the label next to the handle (A3).
    var drag: BandDrag?
    /// Where the frame is drawn (SwiftUI's global space), for the DebugQA drag commands.
    var frameRect: CGRect = .zero
    /// The Preview window is the key window: the Preview commands of the menu bar act on it.
    var windowKey = false
}

extension AppModel {
    // MARK: - What the page reads

    var previewResult: PreviewState.Result? { previewVideo.flatMap { preview.results[$0.id] } }
    var previewFrames: [PreviewFrame] { previewResult?.frames ?? [] }

    var previewFrame: PreviewFrame? {
        guard let r = previewResult, r.frames.indices.contains(r.index) else { return nil }
        return r.frames[r.index]
    }

    var isSearchingFrames: Bool {
        if case .running = preview.search { return true }
        return false
    }

    var isReadingOCR: Bool {
        if case .reading? = preview.test { return true }
        return false
    }

    /// "Find 20 Frames": the engine up, no batch (A6), no search, a readable
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

    /// The handles: not during the batch (the parameters are locked, A6).
    var canDragBands: Bool { !batch.running && status == .ready }

    // MARK: - The window

    /// The Preview window on a video (the row's Preview button, the ⋯ and context menus,
    /// the menu bar): one window at a time, brought to the front if open (design note 80).
    /// nil keeps the video chosen last.
    func openPreview(_ id: UUID?) {
        if let id, id != previewVideoID { selectPreviewVideo(id) }
        log.info("preview window: \(previewVideo?.name ?? "-")")
    }

    // MARK: - The video

    /// The Video menu: the chosen one is kept (`previewVideoID`), the panels go.
    func selectPreviewVideo(_ id: UUID) {
        guard !isSearchingFrames, id != previewVideoID else { return }
        previewVideoID = id
        clearTest()
        preview.search = .idle
        loadFrameImage()
    }

    // MARK: - Find 20 Frames

    func findFrames() {
        guard canFindFrames, let video = previewVideo else { return }
        preview.searching = video.id
        preview.search = .running(done: 0, total: PreviewState.zones, found: 0)
        clearTest()
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

    /// Stop (A2): `preview.stop`; the engine answers with `preview.stopped`.
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
    /// (about 120 px wide: 20 of them weigh a few hundred KB).
    private func makeThumbnails(for id: UUID, frames: [PreviewFrame]) {
        let paths = frames.map(\.path)
        Task.detached(priority: .utility) {
            let batch = ThumbnailBatch(paths: paths, maxPixels: 120)
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
        clearTest()
        loadFrameImage()
    }

    func nextFrame() { if let r = previewResult { selectFrame(min(r.index + 1, r.frames.count - 1)) } }
    func previousFrame() { if let r = previewResult { selectFrame(max(r.index - 1, 0)) } }

    /// The whole frame on screen, decoded once; nil when the file went (A5: "not available").
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

    func tryOCR() {
        guard canTryOCR, let frame = previewFrame else { return }
        let params = ocrParams, ignore = useIgnore, corrections = useCorrections
        preview.test = .reading
        preview.testFrame = frame.path
        preview.stale = false
        Task {
            do {
                let reply = try await engine.previewTest(frame: frame.path, params: params, useIgnore: ignore, useCorrections: corrections)
                guard preview.testFrame == frame.path, isReadingOCR else { return }
                preview.test = .done(reply, params: params, useIgnore: ignore, useCorrections: corrections)
                log.info("preview.test: bottom \"\(reply.bottom?.text ?? "")\" top \"\(reply.top?.text ?? "")\"")
                applyTestToBadge(reply, frame: frame.path)
                refreshPreviewStale()
            } catch {
                guard preview.testFrame == frame.path, isReadingOCR else { return }
                log.error("preview.test: \(error)")
                preview.test = .failed(code: (error as? EngineError)?.remoteCode ?? "unknown", message: Self.errorDetail(error))
            }
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

    func clearTest() {
        preview.test = nil
        preview.testFrame = nil
        preview.stale = false
    }

    /// After any change in UserDefaults: the test is stale when its parameters differ from today's.
    func refreshPreviewStale() {
        guard case .done(_, let params, let ignore, let corrections)? = preview.test else {
            if preview.stale { preview.stale = false }
            return
        }
        let stale = params != ocrParams || ignore != useIgnore || corrections != useCorrections
        if stale != preview.stale { preview.stale = stale }
    }
}

/// The small images of the strip, made with ImageIO's downsampling decoder:
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
