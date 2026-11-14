// SPDX-License-Identifier: MIT
import Testing
@testable import SVShell

struct BatchProgressTests {
    @Test func theShortFirstFileIsAThird() {
        // Two files, the first half as long as the second.
        let w = BatchProgress.weights([600, 1200])
        #expect(BatchProgress.fraction(weights: w, current: 0, fileFraction: 1) == 1.0 / 3)
        #expect(BatchProgress.fraction(weights: w, current: 1, fileFraction: 0) == 1.0 / 3)
        #expect(BatchProgress.fraction(weights: w, current: 1, fileFraction: 0.5) == 2.0 / 3)
        #expect(BatchProgress.fraction(weights: w, current: 1, fileFraction: 1) == 1)
        #expect(BatchProgress.fraction(weights: w, current: 0, fileFraction: 0) == 0)
    }

    @Test func unknownDurationsTakeTheAverage() {
        #expect(BatchProgress.weights([10, nil, 30, 0]) == [10, 20, 30, 20])
        // None known: by file count.
        let w = BatchProgress.weights([nil, nil])
        #expect(w == [1, 1])
        #expect(BatchProgress.fraction(weights: w, current: 1, fileFraction: 0) == 0.5)
        #expect(BatchProgress.fraction(weights: [], current: 0, fileFraction: 1) == 0)
    }

    @Test func timeLeftScalesWithTheQueuedDurations() {
        let w = BatchProgress.weights([10, 20, 30])
        // The first file took 30 s for 10 s of video: 3 s per second.
        let rate = BatchProgress.rate(weights: w, measured: [0: 30])
        #expect(rate == 3)
        // 60 s left on the second, then 30 s of video at 3 s each.
        #expect(BatchProgress.remaining(weights: w, current: 1, currentLeft: 60, rate: rate) == 150)
        // On the last file only its own time is left.
        #expect(BatchProgress.remaining(weights: w, current: 2, currentLeft: 12, rate: rate) == 12)
        // Two files measured: the rate is their total over their duration.
        #expect(BatchProgress.rate(weights: w, measured: [0: 30, 1: 30]) == 2)
        // Nothing measured, or nothing known of the file in progress: no estimate.
        #expect(BatchProgress.rate(weights: w, measured: [:]) == nil)
        #expect(BatchProgress.remaining(weights: w, current: 0, currentLeft: nil, rate: 3) == nil)
        #expect(BatchProgress.remaining(weights: w, current: 0, currentLeft: 5, rate: nil) == nil)
    }
}
