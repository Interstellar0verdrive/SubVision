// SPDX-License-Identifier: MIT
// The pure side of the Review page (boards RV1, R1, C3-06, C3-07): what a review
// report says about itself (lines, lines to re-check, gaps) read from the data
// it carries, the totals under the list, the day a file was processed, the
// reviewed SRTs next to a video and the video's name behind a report file. The
// texts are the app's: these only count and classify.

import Foundation

public enum ReviewData {
    // MARK: - The report's own data

    /// What the title band says of a report: "12 righe · 2 da ricontrollare · 3 buchi".
    public struct Counts: Equatable, Sendable {
        /// The lines of the SRT (the rows not dropped).
        public var lines: Int
        /// The lines the report marks to re-check (yellow or red); nil for a
        /// report that does not mark its rows (1.x).
        public var toCheck: Int?
        /// The lines dropped (they wait in "Scartate").
        public var dropped: Int
        /// The long gaps without subtitles.
        public var gaps: Int

        public init(lines: Int, toCheck: Int?, dropped: Int, gaps: Int) {
            self.lines = lines
            self.toCheck = toCheck
            self.dropped = dropped
            self.gaps = gaps
        }
    }

    /// The JSON of `<script type="application/json" id="qcdata">` in a report,
    /// with the engine's `<\/` escape undone; nil when there is none.
    public static func dataJSON(html: String) -> String? {
        guard let open = html.range(of: "id=\"qcdata\""),
              let start = html.range(of: ">", range: open.upperBound..<html.endIndex),
              let end = html.range(of: "</script>", range: start.upperBound..<html.endIndex) else { return nil }
        return String(html[start.upperBound..<end.lowerBound]).replacingOccurrences(of: "<\\/", with: "</")
    }

    /// The counts of a report, from its data: a row is a line unless `dropped`,
    /// to re-check when its `cls` is "warn" or "bad"; nil when the data cannot be read.
    public static func counts(html: String) -> Counts? {
        guard let json = dataJSON(html: html), let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = object["rows"] as? [[String: Any]] else { return nil }
        let kept = rows.filter { ($0["dropped"] as? Bool) != true }
        let marked = rows.contains { $0["cls"] is String }
        let toCheck = kept.filter { ["warn", "bad"].contains($0["cls"] as? String ?? "") }.count
        return Counts(lines: kept.count, toCheck: marked ? toCheck : nil, dropped: rows.count - kept.count,
                      gaps: (object["gaps"] as? [Any])?.count ?? 0)
    }

    // MARK: - The list

    /// Under the list: "3 video elaborati · 38 righe · 9 buchi".
    public struct Totals: Equatable, Sendable {
        public var videos: Int
        public var lines: Int
        /// nil when no video of the list knows its gaps (a list saved before the engine sent them).
        public var gaps: Int?

        public init(videos: Int, lines: Int, gaps: Int?) {
            self.videos = videos
            self.lines = lines
            self.gaps = gaps
        }
    }

    /// The totals of the rows, each with its lines and its gaps (nil when unknown).
    public static func totals(_ rows: [(lines: Int?, gaps: Int?)]) -> Totals {
        let lines = rows.compactMap(\.lines).reduce(0, +)
        let known = rows.compactMap(\.gaps)
        return Totals(videos: rows.count, lines: lines, gaps: known.isEmpty ? nil : known.reduce(0, +))
    }

    /// When a file was processed, as the list ("oggi 08:57") and the title band
    /// ("elaborato oggi alle 08:57") say it.
    public enum Day: Equatable, Sendable {
        case today, yesterday, earlier
    }

    public static func day(of date: Date, now: Date = Date(), calendar: Calendar = .current) -> Day {
        if calendar.isDate(date, inSameDayAs: now) { return .today }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return .yesterday
        }
        return .earlier
    }

    // MARK: - Files

    /// True when `name` is a reviewed SRT of the video `videoName`, as the report
    /// saves it next to the video: `<stem>-reviewed-<date>.srt` (the chip of the row).
    public static func isReviewedSRT(_ name: String, of videoName: String) -> Bool {
        let stem = (videoName as NSString).deletingPathExtension
        return name.hasPrefix(stem + "-reviewed-") && name.lowercased().hasSuffix(".srt")
    }

    /// The video's name a report file stands for when the list does not know it:
    /// the file's name without `.review.html` (or the 1.x `.revisione.html`) and
    /// without the `_<yyyy-mm-dd>` an older engine put before it.
    public static func videoName(ofReport fileName: String) -> String {
        var name = fileName
        for suffix in [".review.html", ".revisione.html", ".html"] where name.lowercased().hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
            break
        }
        if let m = name.firstMatch(of: #/^(.+)_\d{4}-\d{2}-\d{2}$/#) { name = String(m.1) }
        return name
    }
}
