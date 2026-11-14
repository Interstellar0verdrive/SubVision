// SPDX-License-Identifier: MIT
import SVEngine
import Testing
@testable import SVShell

struct PreviewSearchTests {
    private func frame(_ zone: Int, _ bands: [String] = ["bottom"]) -> PreviewFrame {
        PreviewFrame(zone: zone, path: String(format: "/p/%03d.jpg", zone), bands: bands)
    }

    @Test func framesComeInZoneOrderAsTheZonesEnd() {
        var s = FrameSearch(total: 5)
        s.begin()
        // The zones end out of order (four workers).
        s.add(frame(3), zone: 3)
        s.add(frame(0, []), zone: 0)
        s.add(frame(1, ["bottom", "top"]), zone: 1)
        #expect(s.frames.map(\.zone) == [0, 1, 3])
        #expect(s.found == 2 && s.foundSigns == 1)
        #expect(s.zonesLeft == [2, 4] && !s.complete && !s.interrupted)
        // A zone found again replaces its frame.
        s.add(frame(3, []), zone: 3)
        #expect(s.frames.map(\.zone) == [0, 1, 3] && s.found == 1)
    }

    @Test func aStopKeepsTheFramesAndRetryAsksForTheRest() {
        var s = FrameSearch(total: 20)
        s.begin()
        for z in 0..<7 { s.add(frame(z), zone: z) }
        s.stopped(.batch)
        // Board A1: "stopped at 7 of 20", Retry searches the 13 zones left.
        #expect(s.interrupted && s.stop == .batch && s.frames.count == 7)
        #expect(s.zonesLeft == Array(7..<20))
        #expect(!FrameSearch.searchesBySelf(s))
        s.begin()
        #expect(!s.interrupted)
        s.finish((7..<20).map { frame($0) })
        #expect(s.complete && s.stop == nil && s.frames.map(\.zone) == Array(0..<20))
        // A stop that comes after the last zone changes nothing.
        s.stopped(.user)
        #expect(s.stop == nil && !s.interrupted)
    }

    @Test func zonesThatCannotBeReadLeaveTheSearchInterrupted() {
        var s = FrameSearch(total: 4)
        s.begin()
        s.finish([frame(0), frame(1), frame(3)])
        #expect(s.stop == .unreadable && s.interrupted && s.zonesLeft == [2])
        // The frames of an engine before C3 (no zone): their order is their zone.
        let old = FrameSearch(total: 2, frames: [PreviewFrame(path: "/a.jpg", bands: []), PreviewFrame(path: "/b.jpg", bands: ["top"])])
        #expect(old.complete && old.stop == nil && old.frames.map(\.zone) == [0, 1] && old.foundSigns == 1)
    }

    @Test func whenTheSearchStartsByItself() {
        #expect(FrameSearch.searchesBySelf(nil))
        var s = FrameSearch(total: 3)
        s.add(frame(0), zone: 0)
        s.stopped(.switched)
        #expect(FrameSearch.searchesBySelf(s))
        s.stopped(.user)
        #expect(!FrameSearch.searchesBySelf(s))
        s.finish([frame(1), frame(2)])
        #expect(!FrameSearch.searchesBySelf(s))
    }

    @Test func staleBands() {
        let base = OcrParams()
        #expect(PreviewStaleness.staleBands(tested: base, now: base).isEmpty)
        var p = base
        // A band's own values touch that band only (C3-11).
        p.topKeepPct = 26
        #expect(PreviewStaleness.staleBands(tested: base, now: p) == ["top"])
        p = base; p.topBand.toggle()
        #expect(PreviewStaleness.staleBands(tested: base, now: p) == ["top"])
        p = base; p.topKeepWPct = 90
        #expect(PreviewStaleness.staleBands(tested: base, now: p) == ["top"])
        p = base; p.bottomKeepPct = 30
        #expect(PreviewStaleness.staleBands(tested: base, now: p) == ["bottom"])
        p = base; p.keepWPct = 80
        #expect(PreviewStaleness.staleBands(tested: base, now: p) == ["bottom"])
        // The language, the multiple reading and the confidence touch both.
        p = base; p.langHint = "en-US"
        #expect(PreviewStaleness.staleBands(tested: base, now: p) == ["bottom", "top"])
        p = base; p.multiVariant.toggle()
        #expect(PreviewStaleness.staleBands(tested: base, now: p) == ["bottom", "top"])
        p = base; p.minConfidence = 0.5
        #expect(PreviewStaleness.staleBands(tested: base, now: p) == ["bottom", "top"])
        // What the test does not read does not matter.
        p = base; p.fps = 6; p.mergeGap = 1; p.wrapWidth = 30
        #expect(PreviewStaleness.staleBands(tested: base, now: p).isEmpty)
    }

    @Test func neighbours() {
        let all = { (_: Int) in true }
        #expect(PreviewNeighbours.index(from: 0, step: 1, count: 3, allowed: all) == 1)
        #expect(PreviewNeighbours.index(from: 0, step: -1, count: 3, allowed: all) == nil)
        #expect(PreviewNeighbours.index(from: 2, step: 1, count: 3, allowed: all) == nil)
        #expect(PreviewNeighbours.index(from: 2, step: -1, count: 3, allowed: all) == 1)
        // The video in progress (or unreadable) is skipped.
        let notOne = { (i: Int) in i != 1 }
        #expect(PreviewNeighbours.index(from: 0, step: 1, count: 3, allowed: notOne) == 2)
        #expect(PreviewNeighbours.index(from: 2, step: -1, count: 3, allowed: notOne) == 0)
        #expect(PreviewNeighbours.index(from: 0, step: 1, count: 2, allowed: notOne) == nil)
        #expect(PreviewNeighbours.index(from: 0, step: 0, count: 3, allowed: all) == nil)
        #expect(PreviewNeighbours.index(from: 0, step: 1, count: 0, allowed: all) == nil)
    }
}
