// SPDX-License-Identifier: MIT
import Testing
@testable import SVShell

struct VideoChecksTests {
    typealias Row = CheckRow<Int>

    @Test func whichRowsHaveABox() {
        #expect(Row(id: 0, kind: .todo, checked: false).hasBox)
        #expect(Row(id: 0, kind: .todo, checked: true).toProcess)
        // A finished row: a box only once checked by hand ("verrà rifatto").
        #expect(!Row(id: 0, kind: .finished, checked: false).hasBox)
        #expect(Row(id: 0, kind: .finished, checked: true).hasBox)
        #expect(Row(id: 0, kind: .finished, checked: true).toProcess)
        // Unreadable: never, even if a stale flag says checked.
        #expect(!Row(id: 0, kind: .excluded, checked: true).hasBox)
        #expect(!Row(id: 0, kind: .excluded, checked: true).toProcess)
    }

    @Test func theHeaderCountsOnlyTheRowsWithABox() {
        // C3-02: two to do, both checked, one done: the header is full.
        let rows = [Row(id: 0, kind: .todo, checked: true), Row(id: 1, kind: .finished, checked: false),
                    Row(id: 2, kind: .todo, checked: true), Row(id: 3, kind: .excluded, checked: false)]
        #expect(VideoChecks.headerState(rows) == .on)
        // One of the two unchecked: "−".
        var some = rows
        some[2].checked = false
        #expect(VideoChecks.headerState(some) == .mixed)
        some[0].checked = false
        #expect(VideoChecks.headerState(some) == .off)
        // Nothing with a box: off and not clickable.
        let none = [Row(id: 0, kind: .finished, checked: false), Row(id: 1, kind: .excluded, checked: false)]
        #expect(VideoChecks.headerState(none) == .off)
        #expect(!VideoChecks.headerEnabled(none))
        #expect(VideoChecks.headerEnabled(rows))
    }

    @Test func headerClicksCycleSomeAllNone() {
        // E9: three done, five to do checked, two to do unchecked.
        var rows = (0..<3).map { Row(id: $0, kind: .finished, checked: false) }
            + (3..<8).map { Row(id: $0, kind: .todo, checked: true) }
            + (8..<10).map { Row(id: $0, kind: .todo, checked: false) }
        #expect(VideoChecks.headerState(rows) == .mixed)
        // "−" → all: only the two unchecked rows change; the done ones are not touched.
        let toAll = VideoChecks.headerToggle(rows)
        #expect(toAll == [8: true, 9: true])
        for (id, value) in toAll { rows[id].checked = value }
        #expect(VideoChecks.headerState(rows) == .on)
        // All → none.
        let toNone = VideoChecks.headerToggle(rows)
        #expect(Set(toNone.keys) == Set(3..<10))
        #expect(toNone.values.allSatisfy { !$0 })
        for (id, value) in toNone { rows[id].checked = value }
        #expect(VideoChecks.headerState(rows) == .off)
        #expect(rows[0..<3].allSatisfy { !$0.checked })
        // None → all again.
        #expect(Set(VideoChecks.headerToggle(rows).keys) == Set(3..<10))
    }

    @Test func noneReturnsAHandCheckedFinishedRowToItsOutcome() {
        var rows = [Row(id: 0, kind: .finished, checked: true), Row(id: 1, kind: .todo, checked: true),
                    Row(id: 2, kind: .finished, checked: false)]
        #expect(VideoChecks.headerState(rows) == .on)
        #expect(VideoChecks.toProcess(rows) == [0, 1])
        let change = VideoChecks.headerToggle(rows)
        #expect(change == [0: false, 1: false])
        for (id, value) in change { rows[id].checked = value }
        #expect(!rows[0].hasBox)
        // From none, all checks the to-do row only: the done one stays done.
        #expect(VideoChecks.headerToggle(rows) == [1: true])
    }

    @Test func theBottomBarSaysWhatProcessDoes() {
        #expect(VideoChecks.startButton(checked: 2) == .process(2))
        #expect(VideoChecks.startButton(checked: 1) == .process(1))
        #expect(VideoChecks.startButton(checked: 0) == .nothing)
        // C3-03: one to do and one done: the count wins.
        #expect(VideoChecks.summary(checked: 1, seconds: 76, done: 1, noSubs: 0, failed: 0, stopped: 0) == .toProcess(count: 1, seconds: 76))
        // C3-05, E3: nothing checked, outcomes.
        #expect(VideoChecks.summary(checked: 0, seconds: nil, done: 1, noSubs: 1, failed: 1, stopped: 1)
                == .outcomes(done: 1, noSubs: 1, failed: 1, stopped: 1))
        #expect(VideoChecks.summary(checked: 0, seconds: nil, done: 0, noSubs: 0, failed: 0, stopped: 0) == .nothingChecked)
    }

    @Test func retryStartsAtOnceWithoutABatchAndQueuesDuringOne() {
        // No batch: that file alone, now (the other checked rows wait for later).
        #expect(VideoChecks.retry(batchRunning: false) == .startNow)
        // A batch runs: the file goes "In coda, dopo il lotto".
        #expect(VideoChecks.retry(batchRunning: true) == .queue)
    }

    @Test func theRetryQueueKeepsTheClickOrderOnce() {
        var queue = RetryQueue<Int>()
        #expect(queue.isEmpty)
        let first = queue.add(3), second = queue.add(1)
        #expect(first && second)
        // A second click on the same row does not queue it twice.
        let again = queue.add(3)
        #expect(!again)
        #expect(queue.ids == [3, 1])
        #expect(queue.contains(1) && !queue.contains(2))
        queue.remove(3)
        #expect(queue.ids == [1])
        #expect(RetryQueue([2, 2, 5]).ids == [2, 5])
    }

    @Test func afterTheBatchTheQueueStartsUnlessStopAll() {
        // The batch ended by itself (or its last file was stopped alone): the queue starts, in order.
        var queue = RetryQueue([4, 2, 7])
        var started = queue.drain(stoppedAll: false) { _ in true }
        #expect(started == [4, 2, 7])
        #expect(queue.isEmpty)
        // A row removed from the list (or whose file is gone) meanwhile is left out.
        queue = RetryQueue([4, 2, 7])
        started = queue.drain(stoppedAll: false) { $0 != 2 }
        #expect(started == [4, 7])
        #expect(queue.isEmpty)
        // Stop All: nothing starts, and the queue is dropped all the same.
        queue = RetryQueue([4, 2])
        started = queue.drain(stoppedAll: true) { _ in true }
        #expect(started.isEmpty)
        #expect(queue.isEmpty)
    }

    @Test func theEstimateFollowsTheParameters() {
        let defaults = WorkEstimate.factor(fps: 12, multiVariant: true, signs: true, refine: true)
        #expect(abs(defaults - 1) < 1e-9)
        // An episode of 24 min with the defaults and no measure yet: about 1.5–2 h.
        let episode = WorkEstimate.seconds(duration: 24 * 60, factor: defaults, rate: nil)
        #expect(episode > 1.5 * 3600 && episode < 2 * 3600)
        // Half the frames, half the work; one reading instead of three, much less.
        #expect(abs(WorkEstimate.factor(fps: 6, multiVariant: true, signs: true, refine: true) - 0.5) < 1e-9)
        #expect(WorkEstimate.factor(fps: 12, multiVariant: false, signs: true, refine: true) < 0.45)
        #expect(WorkEstimate.factor(fps: 12, multiVariant: true, signs: false, refine: true) < 1)
        // A measured file sets the rate; the next one is mixed in by half.
        let observed = WorkEstimate.observedRate(elapsed: 64, duration: 55, factor: defaults)!
        #expect(abs(WorkEstimate.seconds(duration: 55, factor: defaults, rate: observed) - 64) < 1e-9)
        #expect(WorkEstimate.learn(previous: nil, observed: 2) == 2)
        #expect(WorkEstimate.learn(previous: 2, observed: 4) == 3)
        #expect(WorkEstimate.observedRate(elapsed: 0, duration: 55, factor: 1) == nil)
    }
}
