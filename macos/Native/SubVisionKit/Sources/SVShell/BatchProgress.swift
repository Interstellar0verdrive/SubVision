// SPDX-License-Identifier: MIT
// The batch's fraction and time left by work, not by file count. The engine
// samples every video at the batch's frames per second, so its steps (frames
// to extract and read, targets to refine) grow with the video's duration:
// each file weighs its duration in seconds. Two files, the first half as long
// as the second: at the end of the first the batch is at one third.

import Foundation

public enum BatchProgress {
    /// Each file's weight: its duration in seconds. An unknown one (nil, or not
    /// positive) takes the average of the known ones; with none known, 1 each
    /// (by file count, as before).
    public static func weights(_ durations: [Double?]) -> [Double] {
        let known = durations.compactMap { $0 }.filter { $0 > 0 }
        let fallback = known.isEmpty ? 1 : known.reduce(0, +) / Double(known.count)
        return durations.map { d in
            guard let d, d > 0 else { return fallback }
            return d
        }
    }

    /// The batch's fraction (0...1): the files before `current` (0-based) over,
    /// `fileFraction` of the one at `current` done.
    public static func fraction(weights: [Double], current: Int, fileFraction: Double) -> Double {
        let total = weights.reduce(0, +)
        guard total > 0, weights.indices.contains(current) else { return 0 }
        let before = weights[..<current].reduce(0, +)
        let f = min(max(fileFraction, 0), 1)
        return min(max((before + weights[current] * f) / total, 0), 1)
    }

    /// Seconds of work per unit of weight (per second of video), measured on the
    /// files done: `measured` maps a file's index to the seconds it took. nil
    /// when none is done.
    public static func rate(weights: [Double], measured: [Int: Double]) -> Double? {
        var seconds = 0.0, units = 0.0
        for (i, s) in measured where weights.indices.contains(i) && s >= 0 {
            seconds += s
            units += weights[i]
        }
        return units > 0 ? seconds / units : nil
    }

    /// Seconds left in the batch: `currentLeft` for the file in progress, plus
    /// `rate` × weight for each file after it. nil without either.
    public static func remaining(weights: [Double], current: Int, currentLeft: Double?, rate: Double?) -> Double? {
        guard let currentLeft, let rate else { return nil }
        let after = current + 1 < weights.count ? weights[(current + 1)...].reduce(0, +) : 0
        return max(0, currentLeft) + rate * after
    }
}
