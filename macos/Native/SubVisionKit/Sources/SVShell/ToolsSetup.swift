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

/// `tools.status`, the part the window needs: which tools are verified.
public struct ToolsStatusReply: Decodable, Sendable, Equatable {
    public struct Tool: Decodable, Sendable, Equatable {
        public var key: String
        public var verified: Bool
        public var version: String?

        public init(key: String, verified: Bool, version: String? = nil) {
            self.key = key
            self.verified = verified
            self.version = version
        }
    }

    public var tools: [Tool]

    public init(tools: [Tool]) { self.tools = tools }

    public var allVerified: Bool { tools.allSatisfy(\.verified) }
    public var missingKeys: [String] { tools.filter { !$0.verified }.map(\.key) }
}

/// A `tools.progress` event.
public struct ToolProgress: Decodable, Sendable, Equatable {
    public enum State: String, Decodable, Sendable { case waiting, running, done, failed }
    public var key: String
    public var state: State
    public var bytes: Int64?
    public var total: Int64?
    public var error: String?

    public init(key: String, state: State, bytes: Int64? = nil, total: Int64? = nil, error: String? = nil) {
        self.key = key
        self.state = state
        self.bytes = bytes
        self.total = total
        self.error = error
    }
}

/// The first-launch tools window: what it shows and what it asks the engine.
/// The app feeds it `tools.status` and the engine's events; it keeps the rows.
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
        /// A tool failed: Try Again / Show Log / Quit.
        case failed(key: String, error: String)
    }

    public struct Row: Equatable, Identifiable, Sendable {
        public var tool: ToolRow
        public var state: ToolProgress.State = .waiting
        public var bytes: Int64 = 0
        public var total: Int64 = 0
        public var id: String { tool.key }

        public init(tool: ToolRow, state: ToolProgress.State = .waiting, bytes: Int64 = 0, total: Int64 = 0) {
            self.tool = tool
            self.state = state
            self.bytes = bytes
            self.total = total
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
        rows = downloads.map { Row(tool: $0) } + [Row(tool: runtime, state: .running)] + tasks.map { Row(tool: $0) }
    }

    /// After `hello`: the runtime is there.
    public func runtimeReady() {
        if let i = rows.firstIndex(where: { $0.tool.kind == .runtime }) { rows[i].state = .done }
    }

    /// After `tools.status`: open the window for what's missing, or not.
    public func decide(_ status: ToolsStatusReply) {
        runtimeReady()
        let missing = Set(status.missingKeys)
        let keys = downloads.map(\.key).filter { missing.contains($0) }
        // Nothing to download: done, unless this is the very first launch and the
        // engine still has its tasks (a warm-up) to run.
        if keys.isEmpty && (tasks.isEmpty || !runtimePending) {
            finish()
            return
        }
        var rows = downloads.filter { keys.contains($0.key) }.map { Row(tool: $0) }
        if runtimePending, let runtime { rows.append(Row(tool: runtime, state: .done)) }
        rows += tasks.map { Row(tool: $0) }
        self.rows = rows
        phase = .installing
        log.info("tools missing: \(keys.joined(separator: ","))")
        install(keys)
    }

    /// Asks `tools.status` and decides. Used after the engine is up, and after `tools.done`.
    public func refresh() async {
        guard let engine, let status = try? await engine.call(methods.status, as: ToolsStatusReply.self) else { return }
        if showsWindow {
            let tasksDone = rows.filter { $0.tool.kind == .task }.allSatisfy { $0.state == .done }
            if status.allVerified && tasksDone { finish() }
        } else {
            decide(status)
        }
    }

    private func install(_ keys: [String]) {
        guard let engine else { return }
        Task { _ = try? await engine.raw(methods.install, params: ["keys": keys]) }
    }

    /// An event from the engine: progress of a row, or the end of the install.
    public func apply(_ event: EngineEvent) {
        if event.name == methods.progressEvent, let p = try? event.decode(as: ToolProgress.self) {
            progress(p)
        } else if event.name == methods.doneEvent {
            Task { await refresh() }
        }
    }

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
        }
        if rows.allSatisfy({ $0.state == .done }) { finish() }
    }

    public func retry() {
        let keys = rows.filter { $0.tool.kind == .download && $0.state != .done }.map(\.tool.key)
        phase = .installing
        for i in rows.indices where rows[i].state == .failed { rows[i].state = .waiting }
        install(keys)
    }

    private func finish() {
        let wasShowing = showsWindow
        phase = .notNeeded
        runtimePending = false
        if wasShowing { onFinished() }
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
                Image(nsImage: appIcon)
                    .resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(ShellTexts.fill(texts.welcome, ["app": appName])).svFont(17, .bold).foregroundStyle(SV.text)
                    Text(ShellTexts.fill(texts.toolsIntro1, ["app": appName, "mb": totalMB]) + "\n" + texts.toolsIntro2)
                        .svSmall().fixedSize(horizontal: false, vertical: true)
                }
            }
            if let failed = state.failure {
                NoteView(.red, title: texts.toolsStoppedTitle,
                         text: ShellTexts.fill(failed.error.lowercased().contains("checksum") ? texts.toolsStoppedChecksum : texts.toolsStoppedText,
                                               ["tool": name(failed.key)])
                            + "\n" + texts.toolsStoppedKept)
                    .help(failed.error)
            } else {
                let totals = state.totals
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if totals.count > 0 {
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
            HStack(spacing: 8) {
                if state.failure != nil {
                    UnderlineLink(texts.showLog, tone: .red, action: showLog)
                    Spacer()
                    Button(texts.quit, action: quit).svButton(.secondary, .regular)
                    Button(texts.retry) { state.retry() }.svButton(.primary, .regular)
                } else {
                    Text(texts.toolsInside).svSmall()
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

    /// " · about a minute left", from the bytes since the window opened.
    private func timeLeft(_ t: (done: Int64, total: Int64, index: Int, count: Int)) -> String {
        guard let start = state.startedAt, t.done > state.startBytes else { return "" }
        let rate = Double(t.done - state.startBytes) / max(1, Date().timeIntervalSince1970 - start)
        let left = Double(t.total - t.done) / max(1, rate)
        guard left.isFinite, left > 0 else { return "" }
        return " · " + (left < 90 ? texts.toolsMinuteLeft : ShellTexts.fill(texts.toolsMinutesLeft, ["n": Int((left / 60).rounded())]))
    }

    private var totalMB: Int {
        Int(state.rows.reduce(Int64(0)) { $0 + $1.tool.megabytes })
    }

    private func name(_ key: String) -> String {
        state.tools.first { $0.key == key }?.name ?? key
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
        let detail = tool.kind == .runtime ? texts.toolsRuntime : tool.version
        return HStack(spacing: 10) {
            icon(row.state)
            Text(tool.name + (detail.isEmpty ? "" : " · " + detail))
                .svFont(12.5, running || isFailed ? .semibold : .regular)
                .foregroundStyle(isFailed ? SV.redText : running || row.state == .done ? SV.text : SV.text2)
                .lineLimit(1)
            Spacer(minLength: 8)
            if running, tool.kind == .download, row.total > 0 {
                SVBar(Double(row.bytes) / Double(row.total)).frame(width: 90)
            }
            if isFailed { StatusChip(texts.stopped, tone: .red) }
            if tool.megabytes > 0 {
                Text("\(tool.megabytes) MB")
                    .svFont(SVFont.smallNumbers).foregroundStyle(SV.text3)
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 33)
        .background(running ? SV.soft : isFailed ? SV.redSoft : .clear)
    }

    @ViewBuilder
    private func icon(_ state: ToolProgress.State) -> some View {
        switch state {
        case .done:
            Image(systemName: "checkmark").svFont(9, .bold).foregroundStyle(SV.greenText)
                .frame(width: 18, height: 18).background(Circle().fill(SV.greenBg))
                .overlay(Circle().strokeBorder(SV.greenLine))
        case .running:
            Spinner(size: 16).frame(width: 18, height: 18)
        case .failed:
            Image(systemName: "xmark").svFont(8, .bold).foregroundStyle(SV.redText)
                .frame(width: 18, height: 18).overlay(Circle().strokeBorder(SV.redLine))
        case .waiting:
            Circle().strokeBorder(SV.glassLine).frame(width: 18, height: 18)
        }
    }
}
