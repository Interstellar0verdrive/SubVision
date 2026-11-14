// SPDX-License-Identifier: MIT
// The five frames of a video for the to-do drawer's strip (`videos.thumbs`):
// taken as soon as a video enters the list (after its probe), and at launch
// for the videos already there (the engine keeps them in its cache, so those
// answer at once). One video at a time, in the background; never during a
// batch (the engine would answer `busy`): the queue waits for its end. The
// strip shows them until the Preview has found its own frames for that video
// (`FromPreview` in ProcessDrawers.swift).

import AppKit
import SVShell
import SwiftUI

/// The frames taken for the drawers; `AppModel.videoFrames` holds them.
struct VideoFramesState {
    enum Entry {
        /// The five small images in order (nil for a frame the engine could not take).
        case done([NSImage?])
        /// Nothing could be taken (an unreadable video, an engine error): the empty boxes.
        case failed
    }

    /// The thumbnails' long side, in pixels: the drawer draws them 64 × 36 pt (2x on Retina).
    static let thumbnailPixels = 160
    static let count = 5

    var entries: [UUID: Entry] = [:]
    /// The videos waiting for their turn, in the order they came.
    var queue: [UUID] = []
    /// The video the engine works on now.
    var working: UUID?
    /// Debug: rows shown as extracting whatever their state (a capture of the shimmer).
    var heldExtracting: Set<UUID> = []
}

/// What the to-do drawer's strip shows for a video.
enum DrawerStrip {
    /// The empty boxes (not taken yet, or the frames could not be taken).
    case none
    /// The boxes shimmer while the five frames are taken.
    case extracting
    /// The five frames of the video («Fotogrammi del video»).
    case video([NSImage?])
    /// The frames the Preview found («Dall'Anteprima»).
    case preview(PreviewState.Result)

    /// The DebugQA name: `none`, `extracting`, `video:5`, `preview:20`.
    var debugName: String {
        switch self {
        case .none: "none"
        case .extracting: "extracting"
        case .video(let images): "video:\(images.compactMap { $0 }.count)"
        case .preview(let result): "preview:\(result.frames.count)"
        }
    }
}

extension AppModel {
    /// The strip of a video's drawer: the Preview's frames when it found some, else the five
    /// frames of the video, else the shimmer while they are taken, else the empty boxes.
    func drawerStrip(_ video: VideoItem) -> DrawerStrip {
        if let result = preview.results[video.id], !result.frames.isEmpty { return .preview(result) }
        if videoFrames.heldExtracting.contains(video.id) { return .extracting }
        switch videoFrames.entries[video.id] {
        case .done(let images)?:
            return images.contains { $0 != nil } ? .video(images) : .none
        case .failed?:
            return .none
        case nil:
            return framesComing(video) ? .extracting : .none
        }
    }

    /// The frames are on their way: being taken, queued with nothing in the way, or the video
    /// just came in and waits for its probe.
    private func framesComing(_ video: VideoItem) -> Bool {
        guard status == .ready, video.exists, video.state != .unreadable else { return false }
        if videoFrames.working == video.id { return true }
        guard !batch.running else { return false }
        return videoFrames.queue.contains(video.id) || !video.probed
    }

    /// Queues the videos that have no frames yet (the probed, readable ones) and starts.
    func queueVideoFrames(_ ids: [UUID]) {
        for id in ids {
            guard let video = videos.first(where: { $0.id == id }), video.probed, video.state != .unreadable else { continue }
            if case .done? = videoFrames.entries[id] { continue }
            if videoFrames.working == id || videoFrames.queue.contains(id) { continue }
            videoFrames.entries[id] = nil
            videoFrames.queue.append(id)
        }
        pumpVideoFrames()
    }

    /// The next video of the queue, when nothing else is being taken and no batch runs.
    func pumpVideoFrames() {
        guard videoFrames.working == nil, status == .ready, !batch.running else { return }
        while let id = videoFrames.queue.first {
            videoFrames.queue.removeFirst()
            guard let video = videos.first(where: { $0.id == id }), video.exists, video.state != .unreadable else { continue }
            videoFrames.working = id
            Task(priority: .utility) { await takeVideoFrames(video) }
            return
        }
    }

    private func takeVideoFrames(_ video: VideoItem) async {
        let id = video.id
        do {
            let reply = try await engine.videoThumbs(path: video.path, duration: video.duration)
            if reply.isBusy {
                // A batch started meanwhile: back at the head of the queue, until it ends.
                videoFrames.queue.insert(id, at: 0)
                videoFrames.working = nil
                return
            }
            let frames = reply.frames ?? []
            let paths = frames.compactMap { $0 }
            log.info("videos.thumbs: \(video.name) \(paths.count)/\(frames.count) in \(reply.seconds ?? 0) s\(reply.cached == true ? " (cached)" : "")")
            if paths.isEmpty {
                videoFrames.entries[id] = .failed
            } else {
                let batch = await Task.detached(priority: .utility) {
                    ThumbnailBatch(paths: paths, maxPixels: VideoFramesState.thumbnailPixels)
                }.value
                let images = frames.map { path in path.flatMap { batch.images[$0] }.map { NSImage(cgImage: $0, size: .zero) } }
                videoFrames.entries[id] = images.contains { $0 != nil } ? .done(images) : .failed
            }
        } catch {
            log.error("videos.thumbs: \(error)")
            videoFrames.entries[id] = .failed
        }
        videoFrames.working = nil
        pumpVideoFrames()
    }
}
