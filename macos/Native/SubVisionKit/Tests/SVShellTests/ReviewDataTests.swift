// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import SVShell

struct ReviewDataTests {
    /// A report as the engine writes it: the data in a JSON script, `</` escaped.
    static func report(_ data: String) -> String {
        """
        <!DOCTYPE html><html><head><script id="appmode">var x = 1;</script></head><body>
        <div id="rows"></div>
        <script type="application/json" id="qcdata">\(data)</script>
        <script>const DATA = JSON.parse(document.getElementById('qcdata').textContent);</script>
        </body></html>
        """
    }

    @Test func countsLinesToCheckDroppedAndGaps() {
        let html = Self.report("""
        {"srtName": "a.srt", "rows": [
          {"id": "s1", "text": "ok", "cls": "", "dropped": false},
          {"id": "s2", "text": "<i>tag<\\/i>", "cls": "warn", "dropped": false},
          {"id": "s3", "text": "bad", "cls": "bad", "dropped": false},
          {"id": "s4", "text": "noise", "cls": "bad", "dropped": true}],
         "gaps": [{"start": 0, "end": 3}, {"start": 41, "end": 44}], "gapWarn": 3}
        """)
        #expect(ReviewData.counts(html: html) == .init(lines: 3, toCheck: 2, dropped: 1, gaps: 2))
        #expect(ReviewData.dataJSON(html: html)?.contains("<i>tag</i>") == true)
    }

    @Test func aReportOfTheOneXHasNoMarks() {
        // No `cls` on the rows, no gaps: the lines only.
        let html = Self.report(#"{"rows": [{"id": "s1", "text": "a"}, {"id": "s2", "text": "b", "dropped": true}]}"#)
        #expect(ReviewData.counts(html: html) == .init(lines: 1, toCheck: nil, dropped: 1, gaps: 0))
    }

    @Test func noDataNoCounts() {
        #expect(ReviewData.counts(html: "<html><body>nothing</body></html>") == nil)
        #expect(ReviewData.counts(html: Self.report("not json")) == nil)
    }

    @Test func totalsUnderTheList() {
        // RV1: "3 video elaborati · 38 righe · 9 buchi".
        let rows: [(lines: Int?, gaps: Int?)] = [(12, 3), (14, 3), (12, 3)]
        #expect(ReviewData.totals(rows) == .init(videos: 3, lines: 38, gaps: 9))
        // A row that does not know its gaps counts none; no row knowing them: no gaps at all.
        #expect(ReviewData.totals([(5, nil), (nil, 2)]) == .init(videos: 2, lines: 5, gaps: 2))
        #expect(ReviewData.totals([(5, nil)]).gaps == nil)
        #expect(ReviewData.totals([]) == .init(videos: 0, lines: 0, gaps: nil))
    }

    @Test func detailsLeaveOutWhatIsZero() {
        #expect(ReviewData.details(lines: 12, toCheck: 2, gaps: 3) == [.lines(12), .toCheck(2), .gaps(3)])
        // "12 righe · elaborato oggi alle 08:57": no "0 da ricontrollare", no "0 buchi".
        #expect(ReviewData.details(lines: 12, toCheck: 0, gaps: 0) == [.lines(12)])
        // A 1.x report does not mark its rows; a list saved before the gaps were sent does not know them.
        #expect(ReviewData.details(lines: 12, toCheck: nil, gaps: nil) == [.lines(12)])
        #expect(ReviewData.details(lines: 24, gaps: 0) == [.lines(24)])
        // Without subtitles: nothing to count.
        #expect(ReviewData.details(lines: 0, toCheck: 0, gaps: 0).isEmpty)
        #expect(ReviewData.details(lines: nil, gaps: 4) == [.gaps(4)])
    }

    @Test func theDayOfAProcessedFile() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Rome"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 9, minute: 12)))
        let morning = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 0, minute: 5)))
        let lateYesterday = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 23, minute: 59)))
        let before = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 22, minute: 43)))
        #expect(ReviewData.day(of: morning, now: now, calendar: calendar) == .today)
        #expect(ReviewData.day(of: lateYesterday, now: now, calendar: calendar) == .yesterday)
        #expect(ReviewData.day(of: before, now: now, calendar: calendar) == .earlier)
    }

    @Test func reviewedSRTsOfAVideo() {
        #expect(ReviewData.isReviewedSRT("sintel_ita_hardsub_demo-reviewed-20261114-0912.srt", of: "sintel_ita_hardsub_demo.mp4"))
        #expect(ReviewData.isReviewedSRT("a.b-reviewed-1.SRT", of: "a.b.mkv"))
        #expect(!ReviewData.isReviewedSRT("sintel_ita_hardsub_demo.srt", of: "sintel_ita_hardsub_demo.mp4"))
        #expect(!ReviewData.isReviewedSRT("sintel_eng_hardsub_demo-reviewed-1.srt", of: "sintel_ita_hardsub_demo.mp4"))
        #expect(!ReviewData.isReviewedSRT("sintel_ita_hardsub_demo-reviewed-1.srt.bak", of: "sintel_ita_hardsub_demo.mp4"))
    }

    @Test func theVideoBehindAReportFile() {
        #expect(ReviewData.videoName(ofReport: "sintel_ita_hardsub_demo.review.html") == "sintel_ita_hardsub_demo")
        #expect(ReviewData.videoName(ofReport: "show_2026-11-13.revisione.html") == "show")
        #expect(ReviewData.videoName(ofReport: "notes.HTML") == "notes")
        #expect(ReviewData.videoName(ofReport: "plain") == "plain")
    }
}
