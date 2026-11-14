// SPDX-License-Identifier: MIT
// The pure logic of the Preview page (design round C3, boards A0, A1, C3-09,
// C3-11): the frames a video's search found so far, zone by zone, and what
// is left of it when it stopped; which test panels a change of the
// parameters makes stale; the video above or below in the list.

import Foundation
import SVEngine

/// The frames of one video's search (`preview.frames`): one per zone, kept as the
/// zones end (each `preview.progress` carries its frame), so a search that stopped
/// keeps what it found and "Retry" asks only for the zones left (board A1).
public struct FrameSearch: Equatable, Sendable {
    /// Why a search ended with zones still without a frame.
    public enum Stop: String, Equatable, Sendable {
        /// Stop, from the page.
        case user
        /// A batch started: the engine stopped the search to run it.
        case batch
        /// The page went to another video while it searched: back on this one it goes on by itself.
        case switched
        /// It reached the end, but some zones could not be read.
        case unreadable
    }

    /// The zones of the video (20).
    public let total: Int
    /// One frame per zone found, in the order of the zones.
    public private(set) var frames: [PreviewFrame] = []
    /// Why the last search ended before every zone had its frame; nil while one runs or when complete.
    public var stop: Stop?

    public init(total: Int) { self.total = max(1, total) }

    /// The search's frames found at once (a test, an engine before C3).
    public init(total: Int, frames: [PreviewFrame]) {
        self.init(total: total)
        for (i, f) in frames.enumerated() { add(f, zone: f.zone ?? i) }
        if !complete { stop = .unreadable }
    }

    public var found: Int { frames.filter(\.hasText).count }
    public var foundSigns: Int { frames.filter(\.hasSigns).count }
    /// Every zone has its frame: nothing to resume.
    public var complete: Bool { frames.count >= total }
    /// The search ended early: board A1 ("stopped at 7 of 20", Retry).
    public var interrupted: Bool { stop != nil && !complete }

    /// The zones without a frame, in order: what "Retry" searches.
    public var zonesLeft: [Int] {
        let have = Set(frames.enumerated().map { zone(of: $0.element, at: $0.offset) })
        return (0..<total).filter { !have.contains($0) }
    }

    /// Whether opening the video should search by itself: never searched, or left for
    /// another video. After Stop, a batch or unreadable zones the page offers Retry instead.
    public static func searchesBySelf(_ search: FrameSearch?) -> Bool {
        guard let search else { return true }
        return search.stop == .switched && !search.complete
    }

    /// A zone's frame, from `preview.progress` or `preview.done`: in its place by zone,
    /// replacing the one of that zone (a resumed zone).
    public mutating func add(_ frame: PreviewFrame, zone: Int) {
        var f = frame
        f.zone = zone
        if let i = frames.firstIndex(where: { $0.zone == zone }) {
            frames[i] = f
        } else {
            let at = frames.firstIndex(where: { ($0.zone ?? .max) > zone }) ?? frames.count
            frames.insert(f, at: at)
        }
    }

    /// A search (or its resumption) starts.
    public mutating func begin() { stop = nil }

    /// `preview.done`: its frames are the zones it searched; zones still without a
    /// frame could not be read.
    public mutating func finish(_ found: [PreviewFrame]) {
        for f in found { if let z = f.zone { add(f, zone: z) } }
        stop = complete ? nil : .unreadable
    }

    /// `preview.stopped`, or the page leaving for another video.
    public mutating func stopped(_ reason: Stop) {
        stop = complete ? nil : reason
    }

    private func zone(of frame: PreviewFrame, at index: Int) -> Int { frame.zone ?? index }
}

/// Which test panels a change of the parameters makes stale (design note 79, C3-11):
/// a band's own values (height, width, and the switch for the signs band) touch only
/// that band; the OCR language, the multiple reading and the minimum confidence both.
public enum PreviewStaleness {
    /// The bands ("bottom", "top", in this order) whose test made with `tested` would not
    /// read the same with `now`.
    public static func staleBands(tested a: OcrParams, now b: OcrParams) -> [String] {
        let both = a.langHint != b.langHint || a.multiVariant != b.multiVariant || a.minConfidence != b.minConfidence
        var bands: [String] = []
        if both || a.bottomKeepPct != b.bottomKeepPct || a.keepWPct != b.keepWPct { bands.append("bottom") }
        if both || a.topBand != b.topBand || a.topKeepPct != b.topKeepPct || a.topKeepWPct != b.topKeepWPct { bands.append("top") }
        return bands
    }
}

/// The video above or below in the list (C3-09: the arrows of the title band, ⌘↑ ⌘↓).
public enum PreviewNeighbours {
    /// The index `step` away from `current` (-1 above, +1 below), skipping the videos
    /// that cannot be previewed; nil at the end of the list. "video 2 di 3" counts them all.
    public static func index(from current: Int, step: Int, count: Int, allowed: (Int) -> Bool) -> Int? {
        guard step != 0, count > 0 else { return nil }
        var i = current + step
        while i >= 0 && i < count {
            if allowed(i) { return i }
            i += step
        }
        return nil
    }
}
