// SPDX-License-Identifier: MIT
// Copied and adapted from the native macOS app of AnimeUp (AnimeUp/AppModel+Tools.swift
// and ToolsSetupView.swift), by the same author: the tools come from the app's
// configuration, the engine methods are parameters, and a row can be a step of
// unknown length as well as a download.

import AppKit
import Observation
import SVDesign
import SVEngine
import SwiftUI

/// The first-launch tools window: what it shows and what it asks the engine.
/// The app feeds it `tools.status` and the engine's events; it keeps the rows.
///
/// Order: the runtime (uv + Python) until `hello`, then the missing downloads
/// (`tools.install`, `tools.progress`), then the tasks (`warmup`, until
/// `warmup.done`). The window goes when every row is done.
@MainActor
@Observable
public final class ToolsSetupState {
    public enum Phase: Equatable, Sendable {
        /// Not decided yet (engine starting).
        case unknown
        /// All tools verified: the main window.
        case notNeeded
        /// The window is up and downloading (or about to).
        case installing
        /// A row failed: Try Again / Show Log / Quit.
        case failed(key: String, error: String)
    }

    public struct Row: Equatable, Identifiable, Sendable {
        public var tool: ToolRow
        public var state: ToolProgress.State = .waiting
        public var bytes: Int64 = 0
        public var total: Int64 = 0
        /// A task's real duration, from `warmup.done`.
        public var seconds: Double?
        /// When a task row started: its bar runs against the expected time.
        public var startedAt: Date?
        public var id: String { tool.key }

        public init(tool: ToolRow, state: ToolProgress.State = .waiting, bytes: Int64 = 0, total: Int64 = 0,
                    seconds: Double? = nil, startedAt: Date? = nil) {
            self.tool = tool
            self.state = state
            self.bytes = bytes
            self.total = total
            self.seconds = seconds
            self.startedAt = startedAt
        }
    }

    public private(set) var phase: Phase = .unknown
    /// The rows shown: the missing downloads, the runtime on the very first launch, the tasks.
    public private(set) var rows: [Row] = []
    /// The runtime was being set up when the window opened (very first launch).
    public private(set) var runtimePending = false
    public private(set) var startedAt: Double?
    public private(set) var startBytes: Int64 = 0

    @ObservationIgnored public let tools: [ToolRow]
    @ObservationIgnored public let methods: ToolsMethods
    @ObservationIgnored public let engine: EngineClient?
    @ObservationIgnored public var log: AppLog = .shared
    /// The languages the `warmup` task prepares (the OCR language of the
    /// inspector); empty lets the engine pick its default.
    @ObservationIgnored public var warmupLanguages: [String] = []
    /// Called when the window should go away (every tool verified).
    @ObservationIgnored public var onFinished: @MainActor () -> Void = {}

    public init(tools: [ToolRow], methods: ToolsMethods = .standard, engine: EngineClient?) {
        self.tools = tools
        self.methods = methods
        self.engine = engine
    }

    public var showsWindow: Bool {
        switch phase {
        case .installing, .failed: true
        default: false
        }
    }

    private var runtime: ToolRow? { tools.first { $0.kind == .runtime } }
    private var tasks: [ToolRow] { tools.filter { $0.kind == .task } }
    private var downloads: [ToolRow] { tools.filter { $0.kind == .download } }

    /// Very first launch: no Python environment yet, so the window opens
    /// straight away with the runtime downloading and every tool waiting.
    public func prepareIfFirstLaunch(stateFolder: URL, marker: String = ".venv") {
        guard let runtime, !FileManager.default.fileExists(atPath: stateFolder.appendingPathComponent(marker).path) else { return }
        phase = .installing
        runtimePending = true
        rows = [Row(tool: runtime, state: .running)] + downloads.map { Row(tool: $0) } + tasks.map { Row(tool: $0) }
    }

    /// After `hello`: the runtime is there.
    public func runtimeReady() {
        if let i = rows.firstIndex(where: { $0.tool.kind == .runtime }) { rows[i].state = .done }
    }

    /// After `tools.status`: open the window for what's missing, or not.
    /// The tasks run on the very first launch, or when `runTasks` says so
    /// (the app saw macOS change since the last warm-up).
    public func decide(_ status: ToolsStatusReply, runTasks: Bool? = nil) {
        runtimeReady()
        let missing = Set(status.missingKeys)
        let keys = downloads.map(\.key).filter { missing.contains($0) }
        let withTasks = !tasks.isEmpty && (runTasks ?? runtimePending)
        if keys.isEmpty && !withTasks {
            finish()
            return
        }
        var rows: [Row] = []
        if runtimePending, let runtime { rows.append(Row(tool: runtime, state: .done)) }
        rows += downloads.filter { keys.contains($0.key) }.map { Row(tool: $0) }
        if withTasks { rows += tasks.map { Row(tool: $0) } }
        self.rows = rows
        phase = .installing
        log.info("tools missing: \(keys.joined(separator: ",")), tasks: \(withTasks)")
        if keys.isEmpty { advance() } else { install(keys) }
    }

    /// Asks `tools.status` and decides. Used after the engine is up, and after `tools.done`.
    public func refresh() async {
        guard let engine else { return }
        let status: ToolsStatusReply
        do {
            status = try await engine.call(methods.status)
        } catch {
            log.error("tools.status: \(error)")
            return
        }
        if showsWindow {
            if status.allPresent {
                for i in rows.indices where rows[i].tool.kind == .download { rows[i].state = .done }
                advance()
            }
        } else {
            decide(status)
        }
    }

    private func install(_ keys: [String]) {
        guard let engine, !keys.isEmpty else { return }
        Task { _ = try? await engine.raw(methods.install, params: ["keys": keys]) }
    }

    /// The downloads are done: start the first waiting task, or finish.
    private func advance() {
        guard failure == nil else { return }
        let ready = rows.allSatisfy { $0.tool.kind == .task || $0.state == .done }
        guard ready else { return }
        if rows.allSatisfy({ $0.state == .done }) { finish(); return }
        guard !rows.contains(where: { $0.tool.kind == .task && $0.state == .running }),
              let i = rows.firstIndex(where: { $0.tool.kind == .task && $0.state == .waiting }) else { return }
        rows[i].state = .running
        rows[i].startedAt = Date()
        guard let engine else { return }
        let params: [String: any Sendable] = warmupLanguages.isEmpty ? [:] : ["languages": warmupLanguages]
        let method = methods.warmup
        Task { _ = try? await engine.raw(method, params: params) }
    }

    /// An event from the engine: progress of a row, the end of the install,
    /// the end of the warm-up.
    public func apply(_ event: EngineEvent) {
        if event.name == methods.progressEvent, let p = try? event.decode(as: ToolProgress.self) {
            progress(p)
        } else if event.name == methods.doneEvent {
            Task { await refresh() }
        } else if event.name == methods.warmupDoneEvent {
            let done = try? event.decode(as: WarmupDone.self)
            for i in rows.indices where rows[i].tool.kind == .task && rows[i].state == .running {
                rows[i].state = .done
                rows[i].seconds = done?.seconds
            }
            advance()
        }
    }

    /// A row's progress. The app also reports a task that cannot run this way
    /// (`hello.vision` false: `.failed` with the error it wants to show).
    public func progress(_ p: ToolProgress) {
        guard let i = rows.firstIndex(where: { $0.tool.key == p.key }) else { return }
        rows[i].state = p.state
        if let b = p.bytes { rows[i].bytes = b }
        if let t = p.total, t > 0 { rows[i].total = t }
        if p.state == .done { rows[i].bytes = max(rows[i].bytes, rows[i].total) }
        if startedAt == nil && p.state == .running && rows[i].tool.kind == .download {
            startedAt = Date().timeIntervalSince1970
            startBytes = totals.done
        }
        if p.state == .failed {
            phase = .failed(key: p.key, error: p.error ?? "")
        } else if p.state == .done {
            advance()
        }
    }

    public func retry() {
        let keys = rows.filter { $0.tool.kind == .download && $0.state != .done }.map(\.tool.key)
        phase = .installing
        for i in rows.indices where rows[i].state == .failed { rows[i].state = .waiting }
        if keys.isEmpty { advance() } else { install(keys) }
    }

    private func finish() {
        let wasShowing = showsWindow
        phase = .notNeeded
        runtimePending = false
        if wasShowing { onFinished() }
    }

    /// The window came back on a later launch for the downloads only (T4 left).
    public var isReturnForDownloads: Bool {
        !runtimePending && !rows.isEmpty && rows.allSatisfy { $0.tool.kind == .download }
    }

    /// The window came back on a later launch for the tasks only (T4 right: a macOS update).
    public var isReturnForTasks: Bool {
        !runtimePending && !rows.isEmpty && rows.allSatisfy { $0.tool.kind == .task }
    }

    /// The task in progress (the warm-up), when the downloads are over.
    public var runningTask: Row? {
        rows.first { $0.tool.kind == .task && $0.state == .running }
    }

    /// Bytes done / total across the download rows (the runtime counts by its nominal size).
    public var totals: (done: Int64, total: Int64, index: Int, count: Int) {
        var done: Int64 = 0, total: Int64 = 0
        let sized = rows.filter { $0.tool.kind != .task }
        for r in sized {
            let nominal = r.tool.megabytes * 1_000_000
            let t = r.total > 0 ? r.total : nominal
            total += t
            done += r.state == .done ? t : min(r.bytes, t)
        }
        let index = sized.filter { $0.state == .done }.count + 1
        return (done, total, min(index, max(1, sized.count)), sized.count)
    }

    public var failure: (key: String, error: String)? {
        if case .failed(let key, let error) = phase { return (key, error) }
        return nil
    }
}

/// Before the app, when tools are missing: the window turns into the main
/// window when everything is verified.
public struct ToolsSetupView: View {
    var state: ToolsSetupState
    var texts: ShellTexts
    var appName: String
    var appIcon: NSImage
    var showLog: () -> Void
    var quit: () -> Void

    public init(state: ToolsSetupState, texts: ShellTexts = .english, appName: String, appIcon: NSImage? = nil,
                showLog: @escaping () -> Void, quit: @escaping () -> Void = { NSApp.terminate(nil) }) {
        self.state = state
        self.texts = texts
        self.appName = appName
        self.appIcon = appIcon ?? NSApp?.applicationIconImage ?? NSImage(named: NSImage.applicationIconName) ?? NSImage()
        self.showLog = showLog
        self.quit = quit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                // The icon's own margins leave about 62 pt visible at 72 (board T1).
                Image(nsImage: appIcon)
                    .resizable().frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text(headTitle).svFont(17, .bold).foregroundStyle(SV.text)
                    Text(headText).svSmall().fixedSize(horizontal: false, vertical: true)
                }
            }
            if let failed = state.failure {
                if isTask(failed.key) {
                    NoteView(.red, title: texts.toolsTaskFailedTitle, text: texts.toolsTaskFailedText)
                        .help(failed.error)
                } else {
                    NoteView(.red, title: texts.toolsStoppedTitle,
                             text: ShellTexts.fill(failed.error.lowercased().contains("checksum") ? texts.toolsStoppedChecksum : texts.toolsStoppedText,
                                                   ["tool": name(failed.key)])
                                + "\n" + texts.toolsStoppedKept)
                        .help(failed.error)
                }
            } else {
                let totals = state.totals
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if state.runningTask != nil {
                        Text(texts.toolsPreparing).svFont(13, .semibold).foregroundStyle(SV.text)
                        if !texts.toolsPreparingTime.isEmpty {
                            Text(texts.toolsPreparingTime).svFont(12).foregroundStyle(SV.text2)
                        }
                    } else if totals.count > 0 {
                        Text(ShellTexts.fill(texts.toolsDownloading, ["i": totals.index, "n": totals.count]))
                            .svFont(13, .semibold).foregroundStyle(SV.text)
                        Text(ShellTexts.fill(texts.toolsProgress, ["done": totals.done / 1_000_000, "total": totals.total / 1_000_000]) + timeLeft(totals))
                            .svFont(12).foregroundStyle(SV.text2)
                    } else {
                        Text(texts.toolsPreparing).svFont(13, .semibold).foregroundStyle(SV.text)
                    }
                }
            }
            rows
                .padding(.top, 4)
            HStack(spacing: 8) {
                if state.failure != nil {
                    UnderlineLink(texts.showLog, tone: .red, action: showLog)
                    Spacer()
                    Button(texts.quit, action: quit).svButton(.secondary, .regular)
                    Button(texts.retry) { state.retry() }.svButton(.primary, .regular)
                } else {
                    Text(state.runningTask != nil ? texts.toolsWarmupNote : texts.toolsInside).svSmall()
                    Spacer()
                    Button(texts.quit, action: quit).svButton(.secondary, .regular)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 44)
        .padding(.bottom, 24)
        .frame(width: 600)
        .background(SV.bg)
    }

    /// The header: the welcome on the first launch, else why the window is back (T4).
    private var headTitle: String {
        if state.isReturnForDownloads { return texts.toolsOneMissingTitle }
        if state.isReturnForTasks { return texts.toolsAgainTitle }
        return ShellTexts.fill(texts.welcome, ["app": appName])
    }

    private var headText: String {
        if state.isReturnForDownloads { return ShellTexts.fill(texts.toolsOneMissingText, ["mb": totalMB]) }
        if state.isReturnForTasks { return texts.toolsAgainText }
        return ShellTexts.fill(texts.toolsIntro1, ["app": appName, "mb": totalMB]) + "\n" + texts.toolsIntro2
    }

    /// " · about a minute left", from the bytes since the window opened.
    private func timeLeft(_ t: (done: Int64, total: Int64, index: Int, count: Int)) -> String {
        guard let start = state.startedAt, t.done > state.startBytes else { return "" }
        let rate = Double(t.done - state.startBytes) / max(1, Date().timeIntervalSince1970 - start)
        let left = Double(t.total - t.done) / max(1, rate)
        guard left.isFinite, left > 0 else { return "" }
        return " · " + (left < 90 ? texts.toolsMinuteLeft : ShellTexts.fill(texts.toolsMinutesLeft, ["n": Int((left / 60).rounded())]))
    }

    /// What the warm-up usually takes (spike S5): the task bar runs against it.
    static let expectedTaskSeconds: Double = 30

    private var totalMB: Int {
        Int(state.rows.reduce(Int64(0)) { $0 + $1.tool.megabytes })
    }

    private func name(_ key: String) -> String {
        state.tools.first { $0.key == key }?.name ?? key
    }

    private func isTask(_ key: String) -> Bool {
        state.tools.first { $0.key == key }?.kind == .task
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(Array(state.rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Rectangle().fill(SV.line).frame(height: 1) }
                rowView(row)
            }
        }
        .background(RoundedRectangle(cornerRadius: SV.Radius.field).fill(SV.surface))
        .overlay(RoundedRectangle(cornerRadius: SV.Radius.field).strokeBorder(SV.line))
        .clipShape(RoundedRectangle(cornerRadius: SV.Radius.field))
    }

    private func rowView(_ row: ToolsSetupState.Row) -> some View {
        let running = row.state == .running
        let isFailed = row.state == .failed
        let tool = row.tool
        let title = tool.version.isEmpty ? tool.name : tool.name + " " + tool.version
        let detail = !tool.detail.isEmpty ? tool.detail : tool.kind == .runtime ? texts.toolsRuntime : ""
        return HStack(spacing: 10) {
            icon(row.state)
            // Only the name goes bold in the running or failed row; the detail stays regular and grey.
            let name = Text(title).fontWeight(running || isFailed ? .semibold : .regular)
                .foregroundStyle(isFailed ? SV.redText : running || row.state == .done ? SV.text : SV.text2)
            let tail = Text(detail.isEmpty ? "" : " · " + detail).foregroundStyle(SV.text3)
            Text("\(name)\(tail)")
                .svFont(12.5)
                .lineLimit(1)
            Spacer(minLength: 8)
            if running, tool.kind == .download, row.total > 0 {
                SVBar(Double(row.bytes) / Double(row.total)).frame(width: 90)
            }
            if running, tool.kind == .task, let start = row.startedAt {
                // A bar against the expected 30 s, and the seconds so far: the task gives no progress of its own.
                TimelineView(.periodic(from: start, by: 1)) { context in
                    let elapsed = context.date.timeIntervalSince(start)
                    HStack(spacing: 10) {
                        SVBar(min(0.95, elapsed / Self.expectedTaskSeconds)).frame(width: 90)
                        Text(ShellTexts.fill(texts.toolsSeconds, ["n": Int(elapsed)]))
                            .svFont(SVFont.smallNumbers).foregroundStyle(SV.text3)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
            if isFailed { StatusChip(texts.stopped, tone: .red) }
            if isFailed, tool.kind == .task {
                // The size column stays empty, so the chip sits where the bar was (board T3).
                Color.clear.frame(width: 44)
            }
            if let seconds = row.seconds {
                Text(ShellTexts.fill(texts.toolsSeconds, ["n": Int(seconds.rounded())]))
                    .svFont(SVFont.smallNumbers).foregroundStyle(SV.text3)
                    .frame(width: 44, alignment: .trailing)
            } else if tool.megabytes > 0 {
                Text(ShellTexts.fill(texts.toolsMegabytes, ["n": tool.megabytes]))
                    .svFont(SVFont.smallNumbers).foregroundStyle(SV.text3)
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 33)
        .background(running ? SV.soft : isFailed ? SV.redSoft : .clear)
    }

    /// The 22 pt ring of the design (note 38), shared with the file rows.
    private func icon(_ state: ToolProgress.State) -> some View {
        let circle: StatusCircle.State = switch state {
        case .done: .done
        case .running: .running
        case .failed: .failed
        case .waiting: .waiting
        }
        return StatusCircle(circle)
    }
}
