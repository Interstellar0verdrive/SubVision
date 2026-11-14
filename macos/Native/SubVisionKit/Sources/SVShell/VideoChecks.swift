// SPDX-License-Identifier: MIT
// The checkboxes of the Video list (design round C3, boards C3-02, C3-05,
// E1–E9): one box per row says "process it". A video to do has a box and
// comes in checked; a finished one (done, no subtitles, failed, stopped)
// shows its outcome and has a box only once the person checks it by hand
// ("will be redone"); an unreadable one never has a box. The header's box
// acts only on the rows that have a box. The bottom bar says what Process
// will do with them. Pure logic, so the tests can read it.

import Foundation
import SVDesign

/// What a row of the list is, as far as its checkbox goes.
public enum CheckKind: Sendable, Equatable {
    /// A video to do: always a box.
    case todo
    /// Done, done without subtitles, failed or stopped: a box only when checked by hand.
    case finished
    /// Cannot be processed (unreadable, file gone): never a box.
    case excluded
}

/// One row as the checkbox logic sees it.
public struct CheckRow<ID: Hashable & Sendable>: Sendable, Equatable {
    public var id: ID
    public var kind: CheckKind
    public var checked: Bool

    public init(id: ID, kind: CheckKind, checked: Bool) {
        self.id = id
        self.kind = kind
        self.checked = checked
    }

    /// The row shows a box: a video to do, or a finished one the person checked.
    public var hasBox: Bool {
        switch kind {
        case .todo: true
        case .finished: checked
        case .excluded: false
        }
    }

    /// The row goes into the next batch.
    public var toProcess: Bool { hasBox && checked }
}

public enum VideoChecks {
    /// The header's box over the rows that have a box: none, some ("−") or all.
    public static func headerState<ID>(_ rows: [CheckRow<ID>]) -> CheckState {
        let boxed = rows.filter(\.hasBox)
        return CheckState.of(checked: boxed.filter(\.checked).count, total: boxed.count)
    }

    /// The header can be clicked: some row has a box (and no batch runs, the caller's part).
    public static func headerEnabled<ID>(_ rows: [CheckRow<ID>]) -> Bool { rows.contains(where: \.hasBox) }

    /// A click on the header's box: from all, none (a finished row checked by hand goes back
    /// to its outcome); from none or some, all. Only the rows that have a box change; the
    /// reply holds the new value of each row that changes.
    public static func headerToggle<ID>(_ rows: [CheckRow<ID>]) -> [ID: Bool] {
        let boxed = rows.filter(\.hasBox)
        let target = headerState(rows) != .on
        var out: [ID: Bool] = [:]
        for row in boxed where row.checked != target { out[row.id] = target }
        return out
    }

    /// The rows the next batch takes, in the list's order.
    public static func toProcess<ID>(_ rows: [CheckRow<ID>]) -> [ID] { rows.filter(\.toProcess).map(\.id) }

    /// What the bottom bar of Video says on its left (boards C3-02, C3-05, E3, E5).
    public enum Summary: Sendable, Equatable {
        /// "2 da elaborare · circa 3 min": some rows checked (`seconds` nil without an estimate).
        case toProcess(count: Int, seconds: Double?)
        /// "1 fatto · 1 senza sottotitoli · 1 non riuscito · 1 fermato" and Remove Finished:
        /// nothing checked, outcomes in the list.
        case outcomes(done: Int, noSubs: Int, failed: Int, stopped: Int)
        /// Nothing checked and no outcome.
        case nothingChecked
    }

    public static func summary(checked: Int, seconds: Double?, done: Int, noSubs: Int, failed: Int, stopped: Int) -> Summary {
        if checked > 0 { return .toProcess(count: checked, seconds: seconds) }
        if done + noSubs + failed + stopped > 0 { return .outcomes(done: done, noSubs: noSubs, failed: failed, stopped: stopped) }
        return .nothingChecked
    }

    /// The bottom bar's primary button: "Elabora 2 video" with the count, or off as
    /// "Nessun video da elaborare" with none checked.
    public enum StartButton: Sendable, Equatable {
        case process(Int)
        case nothing
    }

    public static func startButton(checked: Int) -> StartButton { checked > 0 ? .process(checked) : .nothing }

    /// What Retry on a failed or stopped row does (C3-05, E5): with no batch running and
    /// nothing else checked it processes that file at once; otherwise it checks the row,
    /// which joins the others for the next batch.
    public enum RetryAction: Sendable, Equatable {
        case startNow
        case check
    }

    public static func retry(batchRunning: Bool, othersChecked: Int) -> RetryAction {
        !batchRunning && othersChecked == 0 ? .startNow : .check
    }
}

/// About how long a video takes with the parameters of now (the to-do drawer and
/// the bottom bar, C3-02): seconds of work per second of video, scaled by what the
/// parameters ask for. The rate is learned from the files done; before the first one
/// it is the app's own promise ("an episode of 24 min ≈ 1.5–2 h" with the defaults).
public enum WorkEstimate {
    /// Seconds of work per second of video with the default parameters, before any file was measured.
    public static let defaultRate = 4.0

    /// The work the parameters ask for, relative to the defaults (12 fps, three readings with a
    /// vote, the signs band on, boundaries refined) = 1. Frames grow with the frames per second;
    /// the OCR (the bulk of the time, about 0.9 of it) reads each frame once instead of three
    /// times without the vote; the signs band is about 0.37 of a file with both; refining is
    /// about 0.08 (the step times of boards C3-03 and E3).
    public static func factor(fps: Double, multiVariant: Bool, signs: Bool, refine: Bool) -> Double {
        let frames = max(fps, 0.5) / 12
        let readings = multiVariant ? 1 : 0.11 + 0.89 / 3
        let bands = signs ? 1 : 0.63
        let refining = refine ? 1 : 0.92
        return frames * readings * bands * refining
    }

    /// Seconds a video of `duration` seconds takes at `factor`, with the rate learned (or the default).
    public static func seconds(duration: Double, factor: Double, rate: Double?) -> Double {
        max(0, duration) * max(0, factor) * (rate ?? defaultRate)
    }

    /// The rate a finished file shows: its seconds over its duration and the work its parameters asked for.
    public static func observedRate(elapsed: Double, duration: Double, factor: Double) -> Double? {
        guard elapsed > 0, duration > 0, factor > 0 else { return nil }
        return elapsed / (duration * factor)
    }

    /// The rate to keep after a file: half the old one, half the new (the first one as it is).
    public static func learn(previous: Double?, observed: Double) -> Double {
        guard let previous, previous > 0 else { return observed }
        return (previous + observed) / 2
    }
}
