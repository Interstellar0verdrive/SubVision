// SPDX-License-Identifier: MIT
// The batch (F5.1, design boards E2–E6, O1, O2, O10): `batch.start`, the
// rows' steps and outcomes from the `batch.*` events, Stop and Stop All with
// their confirmations, `BatchActivity` for the sidebar and the Dock, the
// end-of-batch summary (kept until seen) and the notifications. Some of the
// shape (stop confirmations after the click, the summary seen or not) is
// adapted from the AppModel+Run of the native macOS app of AnimeUp (by the
// same author).

import AppKit
import SVShell

/// One step of the file in progress (`batch.file.started.steps[]`, then `batch.step`).
struct StepRun: Identifiable, Equatable {
    enum State: Equatable {
        case waiting, running, done
        /// The file failed or was stopped in this step.
        case aborted
        /// The steps after the aborted one.
        case notRun
    }

    var key: String
    var band: String
    /// Seconds, from the previous file of the batch.
    var estimate: Double?
    var state: State = .waiting
    var ratio = 0.0
    var count = 0
    var total = 0
    /// frames, targets or segments.
    var unit = "frames"
    var elapsed = 0.0
    var eta: Double?
    var rate: Double?
    /// Seconds it took, once done.
    var duration: Double?

    var id: String { "\(key):\(band)" }

    init(key: String, band: String, estimate: Double? = nil, state: State = .waiting) {
        self.key = key
        self.band = band
        self.estimate = estimate
        self.state = state
    }

    init(_ planned: PlannedStep) {
        self.init(key: planned.key, band: planned.band, estimate: planned.estimate)
    }
}

/// `batch.done`, kept in `<state>/records/batch-summary.json` until the
/// summary sheet (E6) has been seen: the notification's click or the next
/// launch reopen it.
struct BatchSummary: Codable, Equatable {
    var ids: [UUID]
    var done: Int
    var failed: Int
    var stopped: Int
    var skipped: Int
    var elapsed: Double
    var error: String?
    var when: Date
    var seen = false
}

/// The batch in progress as the rows see it; `AppModel.batch` is the short form.
struct BatchRun: Equatable {
    /// The videos of the batch in the engine's order (`idx`).
    var ids: [UUID] = []
    /// The steps of the file in progress.
    var steps: [StepRun] = []
    var fileStarted: Date?
    /// Seconds the previous file took, for "Ends around".
    var lastFileElapsed: Double?
    /// Stop All was asked: a batch stopped on purpose with nothing done shows no summary.
    var stoppedByUser = false
    var summary: BatchSummary?
    var showSummary = false
    /// Rows that never started and went back to ready when the batch was stopped: they say "ready" (E5).
    var readyAgain: Set<UUID> = []
    /// Finished rows opened to show their times and files (E3).
    var expanded: Set<UUID> = []
    /// The language and frames per second the batch started with: each file keeps them (Review).
    var lang: String?
    var fps: Double?
    var gapWarn: Double?

    /// The step the engine works on (or the first not started).
    var currentStep: StepRun? {
        steps.first { $0.state == .running } ?? steps.first { $0.state == .waiting }
    }

    /// The file's fraction: by estimate when every step has one (a step that had nothing
    /// to do in the previous file weighs 0), else one share each.
    var fileFraction: Double {
        guard !steps.isEmpty else { return 0 }
        let weights = steps.map { $0.estimate ?? 0 }
        let useWeights = steps.allSatisfy { $0.estimate != nil } && weights.reduce(0, +) > 0
        var total = 0.0, done = 0.0
        for (i, step) in steps.enumerated() {
            let w = useWeights ? weights[i] : 1
            total += w
            switch step.state {
            case .done: done += w
            case .running: done += w * min(max(step.ratio, 0), 1)
            default: break
            }
        }
        return total > 0 ? done / total : 0
    }

    /// Seconds left in this file, from the estimates (nil without them). The estimates
    /// are the times of the previous file: `scale` is this file's duration over that one's.
    func fileRemaining(scale: Double = 1) -> Double? {
        guard !steps.isEmpty, steps.allSatisfy({ $0.estimate != nil }) else { return nil }
        var left = 0.0
        for step in steps {
            let estimate = (step.estimate ?? 0) * scale
            switch step.state {
            case .waiting: left += estimate
            case .running:
                if let eta = step.eta { left += eta } else { left += max(0, estimate - step.elapsed) }
            default: break
            }
        }
        return left
    }
}

/// The stop confirmation that is up (O1 or O2): one at a time, not modal.
struct StopAlert {
    enum Kind: Equatable {
        /// O1, for the file at this index of the batch (`BatchRun.ids`).
        case file(idx: Int, name: String)
        /// O2.
        case all
    }

    var kind: Kind
    var presentation: SVAlertPresentation
}

extension AppModel {
    private var summaryFile: URL { configuration.stateFolder.appendingPathComponent("records/batch-summary.json") }

    // MARK: - Start

    /// Start (⌘↩): the ready rows go into the batch with the inspector's parameters.
    func startBatch() {
        guard canStart else { return }
        let ready = readyVideos
        let lang = ocrLanguage
        if let known = hello?.languages, !known.isEmpty, !known.contains(where: { $0.caseInsensitiveCompare(lang) == .orderedSame }) {
            Alerts.languageUnsupported(self, language: lang, count: known.count)
            return
        }
        let ids = ready.map(\.id)
        // The rows wait before the request: the first event can come back before the reply.
        for i in videos.indices where ids.contains(videos[i].id) {
            videos[i].resetOutcome()
            videos[i].state = .waiting
        }
        run = BatchRun(ids: ids)
        run.lang = lang
        run.fps = ocrParams.fps
        run.gapWarn = ocrParams.qcGapWarn
        batch = BatchActivity(running: true, index: 1, total: ids.count, name: ready.first?.name ?? "")
        selection = []
        saveVideos()
        updateDock()
        log.info("batch.start: \(ids.count) videos, \(ocrParams.langHint), fps \(ocrParams.fps)")
        Task {
            do {
                let reply = try await engine.batchStart(videos: ready.map(\.path), params: ocrParams,
                                                        useIgnore: useIgnore, useCorrections: useCorrections, lang: language)
                if !reply.started {
                    rollBackStart(ids)
                    log.error("batch.start refused: \(reply.reason ?? "?")")
                    Alerts.error(self, title: t("app.menu.start"), text: t(reply.isBusy ? "app.errors.busy" : "app.errors.unknown", ["detail": reply.reason ?? ""]))
                }
            } catch {
                rollBackStart(ids)
                log.error("batch.start failed: \(error)")
                // `bad_params` names the field refused; an engine that does not say it yet has it in the text.
                if let e = error as? EngineError, e.remoteCode == "bad_params",
                   e.remoteInfo?.field == "lang_hint" || (e.remoteInfo?.field == nil && String(describing: e).contains("lang_hint")) {
                    Alerts.languageUnsupported(self, language: lang, count: hello?.languages.count ?? 0)
                } else {
                    Alerts.error(self, title: t("app.menu.start"), text: engineErrorText(error))
                }
            }
        }
    }

    private func rollBackStart(_ ids: [UUID]) {
        for i in videos.indices where ids.contains(videos[i].id) && videos[i].state.inBatch { videos[i].state = .ready }
        run = BatchRun()
        batch = BatchActivity()
        closeStopAlert()
        saveVideos()
        updateDock()
    }

    /// An error of a request as the alerts and the notes say it: `app.errors.<code>`
    /// with the engine's own `detail`, `tool`, `path` and `line` (`RemoteErrorInfo`);
    /// what the caller knows fills the ones the engine left out.
    func engineErrorText(_ error: Error, tool: String = "", path: String = "") -> String {
        guard case .remote(let code, let message, let info)? = error as? EngineError else { return String(describing: error) }
        var detail = info.detail ?? info.reason ?? (message == code ? "" : message)
        if let field = info.field, let reason = info.reason, info.detail == nil { detail = "\(field): \(reason)" }
        let values: [String: Any] = ["detail": detail, "tool": info.tool ?? tool, "path": info.path ?? path,
                                     "line": info.line.map(String.init) ?? ""]
        if localizer.has("app.errors.\(code)") { return t("app.errors.\(code)", values) }
        return t("app.errors.unknown", ["detail": detail.isEmpty ? code : detail])
    }

    /// `app.errors.<code>` with what the message carries as `detail`.
    func engineErrorText(_ code: String, detail: String) -> String {
        let key = "app.errors.\(code)"
        guard localizer.has(key) else { return detail }
        let d = detail.split(separator: ":", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) } ?? detail
        return t(key, ["detail": d, "tool": "", "path": "", "line": ""])
    }

    // MARK: - Stop

    /// The video the batch works on.
    var runningVideo: VideoItem? { videos.first { $0.state == .running } }

    /// Stop on the row or ⌥⌘. (O1): the file stops, the batch goes on. The
    /// alert is not modal: the events keep coming under it, and the answer is
    /// for the file it names (its batch index goes with `batch.stop`).
    func stopCurrentFile() {
        guard batch.running, let video = runningVideo, let idx = run.ids.firstIndex(of: video.id) else { return }
        afterClick { [self] in askStop(.file(idx: idx, name: video.name)) }
    }

    /// Stop All (⌘., the sidebar card, the bottom bar, the Dock; O2).
    func stopAll() {
        guard batch.running else { return }
        afterClick { [self] in askStop(.all) }
    }

    /// O1 or O2, one at a time: with one up already, that one comes to the front.
    private func askStop(_ kind: StopAlert.Kind) {
        if let open = stopAlert, open.presentation.isOpen {
            open.presentation.focus()
            return
        }
        // The click was queued: the file may be over by now, or the batch.
        guard batch.running else { return }
        if case .file(let idx, _) = kind {
            guard let video = runningVideo, run.ids.firstIndex(of: video.id) == idx else { return }
        }
        let presentation = Alerts.confirmStop(self, kind) { [self] confirmed in
            stopAlert = nil
            guard confirmed else { return }
            switch kind {
            case .file(let idx, _): Task { await stop(all: false, file: idx) }
            case .all: Task { await stop(all: true) }
            }
        }
        stopAlert = StopAlert(kind: kind, presentation: presentation)
    }

    /// The file an open O1 names is over (or the batch, for O2 and O3 too): the alert goes by itself.
    private func closeStopAlert(file idx: Int? = nil) {
        if idx == nil, let quit = quitAlert {
            // Nothing left to stop: the quit question is moot (a new ⌘Q quits at once).
            quit.close()
            quitAlert = nil
        }
        guard let open = stopAlert else { return }
        if let idx {
            guard case .file(let asked, _) = open.kind, asked == idx else { return }
        }
        log.info("stop alert closed: \(idx.map { "file \($0) is over" } ?? "the batch is over")")
        open.presentation.close()
        stopAlert = nil
    }

    /// Without a confirmation (the quit alert said it already, the QA scenarios).
    /// `file` is the batch index the stop is meant for: when that file is not
    /// the one in progress any more the engine answers `not_running` and
    /// nothing stops. Returns the engine's answer, for the log and the QA.
    @discardableResult
    func stop(all: Bool, file: Int? = nil) async -> String {
        if all { run.stoppedByUser = true }
        do {
            let reply = try await engine.batchStop(all: all, file: file)
            let what = all ? "all" : file.map { "file \($0)" } ?? "file"
            let answer = reply.ok ? "ok" : (reply.reason ?? "refused")
            log.info("batch.stop \(what): \(answer)")
            return answer
        } catch {
            log.error("batch.stop failed: \(error)")
            return "error: \(error)"
        }
    }

    // MARK: - Events

    /// The `batch.*` events, from the one consumer in `AppModel.listen()`.
    /// What a failed row says after the step (E4): the sentence of a code the
    /// catalogue knows, else the engine's short text as it is. Never the
    /// "Something went wrong:" of `unknown`, never the exception's type name.
    func failureText(_ video: VideoItem) -> String {
        // A tool that exited with an error: the app's own sentence, in the language of now;
        // the complaint stays as the tool wrote it (11.3.4).
        if let program = video.failProgram, let status = video.failStatus {
            let sentence = t("app.errors.tool_exit", ["tool": program, "status": status])
            return video.failReason.map { "\(sentence): \($0)" } ?? sentence
        }
        if let code = video.errorCode, code != "unknown", localizer.has("app.errors.\(code)") {
            // The row takes the engine's short text; a long technical detail (a command line,
            // stderr) stays in the box under the steps.
            var short = video.failText ?? video.errorShort ?? ""
            if video.failText == nil, short.count > 60 || short.contains("\n") { short = "" }
            var sentence = t("app.errors.\(code)", ["detail": short, "tool": video.failTool ?? "",
                                                    "path": video.failPath ?? video.path, "line": video.failLine.map(String.init) ?? ""])
            if short.isEmpty { sentence = sentence.replacing(/\s*:\s*\.?\s*$/, with: ".") }
            return sentence
        }
        return video.errorShort ?? video.error ?? ""
    }

    func handleBatch(_ message: EngineMessage, name: String) {
        switch message {
        case .batchFileStarted(let f): fileStarted(f)
        case .batchStep(let s): step(s)
        case .batchFileDone(let d): fileDone(d)
        case .batchFileFailed(let f): fileFailed(f)
        case .batchFileStopped(let s): fileStopped(s)
        case .batchDone(let d): batchDone(d)
        default: log.debug("event \(name) ignored here")
        }
    }

    private func index(of idx: Int) -> Int? {
        guard run.ids.indices.contains(idx) else { return nil }
        let id = run.ids[idx]
        return videos.firstIndex { $0.id == id }
    }

    private func fileStarted(_ f: BatchFileStarted) {
        guard let i = index(of: f.idx) else { log.error("batch.file.started idx \(f.idx) unknown"); return }
        videos[i].state = .running
        videos[i].plan = f.steps.map(\.id)
        videos[i].srtPath = f.srt
        videos[i].logPath = f.log
        videos[i].reportPath = f.report
        run.steps = f.steps.map(StepRun.init)
        run.fileStarted = Date()
        batch.index = f.idx + 1
        batch.total = f.total
        batch.name = f.name
        refreshActivity()
        saveVideos()
    }

    private func step(_ s: BatchStep) {
        guard let k = run.steps.firstIndex(where: { $0.id == s.id }) else { return }
        // A step that reports means the ones before it are over (the engine's tracker does the same).
        for j in run.steps.indices where j < k && run.steps[j].state != .done {
            run.steps[j].state = .done
            run.steps[j].ratio = 1
            if run.steps[j].duration == nil { run.steps[j].duration = run.steps[j].elapsed }
        }
        run.steps[k].state = s.ratio >= 1 ? .done : .running
        run.steps[k].ratio = s.ratio
        run.steps[k].count = s.count
        run.steps[k].total = s.total
        run.steps[k].unit = s.unit
        run.steps[k].elapsed = s.elapsed
        run.steps[k].eta = s.eta
        run.steps[k].rate = s.rate
        if s.ratio >= 1 { run.steps[k].duration = s.elapsed }
        refreshActivity()
    }

    private func fileDone(_ d: BatchFileDone) {
        guard let i = index(of: d.idx) else { return }
        videos[i].state = d.empty ? .noSubs : .done
        videos[i].segments = d.segments
        videos[i].dropped = d.dropped
        videos[i].refined = d.refined
        videos[i].elapsed = d.elapsed
        videos[i].times = d.times
        videos[i].srtPath = d.srt
        videos[i].reportPath = d.report
        videos[i].logPath = d.log
        videos[i].finished = Date()
        videos[i].gaps = d.gaps
        videos[i].ocrLang = run.lang
        videos[i].ocrFPS = run.fps
        videos[i].gapWarn = run.gapWarn
        for j in run.steps.indices {
            run.steps[j].state = .done
            run.steps[j].ratio = 1
            if let t = d.times[run.steps[j].id] { run.steps[j].duration = t }
        }
        run.lastFileElapsed = d.elapsed
        refreshActivity()
        saveVideos()
        closeStopAlert(file: d.idx)
        let v = videos[i]
        notifyFile(v, body: d.empty ? t("app.notify.file_no_subs", ["name": v.name])
                   : tn("app.notify.file_done", d.segments, ["name": v.name]))
    }

    private func fileFailed(_ f: BatchFileFailed) {
        guard let i = index(of: f.idx) else { return }
        videos[i].state = .failed
        videos[i].error = f.error
        videos[i].failCode = f.code
        videos[i].failText = f.text
        videos[i].failDetail = f.detail
        videos[i].failTool = f.tool
        videos[i].failPath = f.path
        videos[i].failLine = f.line
        videos[i].failProgram = f.program
        videos[i].failStatus = f.status
        videos[i].failReason = f.reason
        if let log = f.log, !log.isEmpty { videos[i].logPath = log }
        videos[i].atStep = f.atStep ?? run.currentStep?.id
        videos[i].finished = Date()
        videos[i].times = stepTimes()
        abortSteps(at: videos[i].atStep)
        saveVideos()
        closeStopAlert(file: f.idx)
        let v = videos[i]
        log.error("file \(v.name) failed at \(v.atStep ?? "?"): \(f.error)")
        notifyFile(v, body: t("app.notify.file_failed", ["name": v.name, "step": stepLabel(v.atStep)]))
    }

    private func fileStopped(_ s: BatchFileStopped) {
        guard let i = index(of: s.idx) else { return }
        videos[i].state = .stopped
        videos[i].atStep = run.currentStep?.id
        videos[i].finished = Date()
        videos[i].times = stepTimes()
        abortSteps(at: videos[i].atStep)
        saveVideos()
        closeStopAlert(file: s.idx)
    }

    private func batchDone(_ d: BatchDone) {
        closeStopAlert()
        // Rows never started (Stop All) are ready again (E5).
        for i in videos.indices where videos[i].state.inBatch {
            videos[i].resetOutcome()
            run.readyAgain.insert(videos[i].id)
        }
        if let error = d.error { log.error("batch failed: \(error)") }
        log.info("batch.done: \(d.done) done, \(d.failed) failed, \(d.stopped) stopped, \(d.skipped) skipped in \(d.elapsed) s")
        let summary = BatchSummary(ids: run.ids, done: d.done, failed: d.failed, stopped: d.stopped, skipped: d.skipped,
                                   elapsed: d.elapsed, error: d.error, when: Date())
        run.summary = summary
        run.steps = []
        run.fileStarted = nil
        // Stopped on purpose with nothing done or failed: the rows say it already (as AnimeUp does).
        let worthASheet = d.done + d.failed > 0 || d.error != nil
        run.showSummary = worthASheet
        if worthASheet { saveSummary() } else { run.summary?.seen = true; removeSummary() }
        batch = BatchActivity()
        saveVideos()
        updateDock()
        if worthASheet { tab = .process }
        if let error = d.error {
            Alerts.error(self, title: t("app.notify.batch_done"), text: engineErrorText(error.split(separator: " ").first.map(String.init) ?? "unknown", detail: error))
        }
        if notifications {
            let readyCount = videos.filter { summary.ids.contains($0.id) && $0.state == .done }.count
            let warned = videos.filter { summary.ids.contains($0.id) && ($0.state == .noSubs || $0.state == .failed) }.count
            var parts = [tn("app.notify.batch_ready", readyCount)]
            if warned > 0 { parts.append(tn("app.notify.batch_warnings", warned)) }
            notify(title: t("app.notify.batch_done"), body: join(parts), identifier: "batch-done",
                   userInfo: ["page": Tab.process.rawValue, "sheet": "summary"])
        }
    }

    /// The step the file broke in turns red, the ones after it grey (E4, E5).
    private func abortSteps(at id: String?) {
        guard let k = run.steps.firstIndex(where: { $0.id == id }) else { return }
        for j in run.steps.indices {
            if j < k, run.steps[j].state != .done { run.steps[j].state = .done; run.steps[j].ratio = 1 }
            if j == k { run.steps[j].state = .aborted }
            if j > k { run.steps[j].state = .notRun }
        }
    }

    /// Seconds per step of the file in progress, for a row that failed or stopped.
    private func stepTimes() -> [String: Double] {
        var out: [String: Double] = [:]
        for s in run.steps where s.state == .done || s.state == .running {
            out[s.id] = s.duration ?? s.elapsed
        }
        return out
    }

    /// Each file of the batch weighs its duration (`BatchProgress`), in the engine's order.
    var batchWeights: [Double] {
        BatchProgress.weights(run.ids.map { id in videos.first { $0.id == id }?.duration })
    }

    /// Seconds each file of the batch took, by index: the ones done in this batch.
    private var batchMeasured: [Int: Double] {
        var out: [Int: Double] = [:]
        for (i, id) in run.ids.enumerated() {
            guard let v = videos.first(where: { $0.id == id }), v.state == .done || v.state == .noSubs,
                  let elapsed = v.elapsed else { continue }
            out[i] = elapsed
        }
        return out
    }

    /// Seconds of work per second of video, from the files done (nil before the first).
    var batchRate: Double? { BatchProgress.rate(weights: batchWeights, measured: batchMeasured) }

    /// About how long a waiting row will take: its duration at the rate of the files done.
    func waitingEstimate(_ video: VideoItem) -> Double? {
        guard let i = run.ids.firstIndex(of: video.id) else { return run.lastFileElapsed }
        let weights = batchWeights
        guard let rate = batchRate, weights.indices.contains(i) else { return run.lastFileElapsed }
        return rate * weights[i]
    }

    /// `BatchActivity` (sidebar, Dock, O3): the fraction and "Ends around", both by duration:
    /// a file twice as long weighs twice as much (`BatchProgress`).
    private func refreshActivity() {
        guard batch.running, batch.total > 0 else { return }
        let current = max(0, batch.index - 1)
        var weights = batchWeights
        if weights.count != batch.total { weights = Array(repeating: 1, count: batch.total) }
        batch.fraction = BatchProgress.fraction(weights: weights, current: current, fileFraction: run.fileFraction)
        let measured = batchMeasured
        // The step estimates come from the last file done: scaled to this file's duration.
        let source = measured.keys.filter { $0 < current }.max()
        let scale = source.map { weights[current] / weights[$0] } ?? 1
        let left = run.fileRemaining(scale: scale)
        // Nothing done yet: the step estimates, if any, stand for this file.
        let rate = BatchProgress.rate(weights: weights, measured: measured)
            ?? run.steps.compactMap(\.estimate).reduce(0, +) / weights[current]
        let remaining = BatchProgress.remaining(weights: weights, current: current, currentLeft: left, rate: rate)
        batch.endsAround = remaining.map { Self.clockTime(Date().addingTimeInterval($0)) }
        updateDock()
    }

    /// "14:20" in the app's language.
    static func clockTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }

    // MARK: - Labels (shared by the rows, the sheet and the notifications)

    /// "OCR ×3 · dialogue" from `key:band` (design note 18).
    func stepLabel(_ id: String?) -> String {
        guard let id else { return "" }
        let parts = id.split(separator: ":").map(String.init)
        let key = parts.first ?? id
        let band = parts.count > 1 ? parts[1] : ""
        let step = stepName(key)
        guard !band.isEmpty else { return step }
        return "\(step) · \(bandName(band, lower: true))"
    }

    /// The short label of a step (the OCR one with its variants).
    func stepName(_ key: String) -> String {
        switch key {
        case "ocr": t("app.steps.ocr", ["n": ocrParams.multiVariant ? 3 : 1])
        case "extract", "group", "refine": t("app.steps.\(key)")
        default: key
        }
    }

    func bandName(_ band: String, lower: Bool = false) -> String {
        let name = band == "top" ? "signs" : "dialogue"
        return t("app.steps.band.\(name)\(lower ? "_l" : "")")
    }

    /// "2 h 14 min · 48 min · 55 s" as the texts of the rows and the sheet want it.
    func durationLong(_ seconds: Double) -> String { durationText(seconds) }

    // MARK: - Summary (E6)

    func markSummarySeen() {
        run.showSummary = false
        guard run.summary != nil, run.summary?.seen == false else { return }
        run.summary?.seen = true
        removeSummary()
    }

    private func saveSummary() {
        guard let summary = run.summary else { return }
        do {
            try FileManager.default.createDirectory(at: summaryFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(summary).write(to: summaryFile, options: .atomic)
        } catch {
            log.error("batch-summary.json: \(error)")
        }
    }

    private func removeSummary() { try? FileManager.default.removeItem(at: summaryFile) }

    /// At launch: a summary never seen comes back with its sheet (the batch
    /// ended with the window closed, the app quit before the sheet was read).
    func loadSummary() {
        guard let data = try? Data(contentsOf: summaryFile),
              let summary = try? JSONDecoder().decode(BatchSummary.self, from: data), !summary.seen,
              Date().timeIntervalSince(summary.when) < 7 * 86400,
              videos.contains(where: { summary.ids.contains($0.id) && $0.state.isFinished }) else {
            removeSummary()
            return
        }
        run.summary = summary
        run.showSummary = true
    }

    /// The rows of the sheet: the batch's videos still in the list, in the batch's order.
    var summaryVideos: [VideoItem] {
        guard let summary = run.summary else { return [] }
        return summary.ids.compactMap { id in videos.first { $0.id == id && $0.state.isFinished } }
    }

    // MARK: - Outputs

    func openLog(_ video: VideoItem) {
        guard video.logExists else { return }
        openLogInConsole(video.outputLog.path)
    }

    func openSRT(_ video: VideoItem) {
        let url = video.outputSRT
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Show SRTs in Finder (the sheet): the SRTs of the batch, selected.
    func showSummarySRTs() {
        let urls = summaryVideos.filter { $0.state == .done }.map(\.outputSRT).filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// The finished row whose report Open Report (⌘R) opens: the one selected.
    var selectedFinished: VideoItem? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return videos.first { $0.id == id && $0.state.isFinished }
    }

    // MARK: - Notifications (design note 23)

    /// One per file only in a batch of several files, and only with the window behind.
    private func notifyFile(_ video: VideoItem, body: String) {
        guard notifications, batch.total > 1, !NSApp.isActive else { return }
        // A file done goes to Review (its row opened), one that failed to Video.
        let review = video.state == .done || video.state == .noSubs
        notify(title: t("app.notify.file_title"), body: body, identifier: "file-\(video.id.uuidString)",
               userInfo: review ? ["page": Tab.review.rawValue, "video": video.id.uuidString] : ["page": Tab.process.rawValue])
    }

    /// Alerts opened by a button wait for the click to finish (a modal loop
    /// inside the button's own gesture leaves AppKit tracking that click).
    private func afterClick(_ show: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async { show() }
    }
}
