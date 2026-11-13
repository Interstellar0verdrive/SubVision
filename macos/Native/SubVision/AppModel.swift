// SPDX-License-Identifier: MIT
// Everything the windows show, fed by the engine. Adapted from the AppModel
// of the native macOS app of AnimeUp (by the same author): here the frame,
// the tools window and the engine client come from SVShell, the settings
// live in UserDefaults, and one task consumes the engine's events in order.

import AppKit
import Observation
import SVShell
import SwiftUI

enum Tab: String, CaseIterable, Identifiable {
    case process, preview, fix
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .process: "captions.bubble"
        case .preview: "viewfinder"
        case .fix: "text.badge.checkmark"
        }
    }
}

/// The batch as the sidebar, the Dock and the quit alert see it. F5.1 fills
/// it from `batch.*` events; in F4 nothing runs.
struct BatchActivity: Equatable {
    var running = false
    /// 1-based index of the file in progress, and the batch size.
    var index = 0
    var total = 0
    var name = ""
    /// The batch's fraction, for the sidebar card and the Dock.
    var fraction: Double?
    /// "Ends around 14:20", when there is an estimate.
    var endsAround: String?
}

@MainActor
@Observable
final class AppModel {
    let configuration: EngineConfiguration
    let engine: EngineClient
    let localizer: Localizer
    let config: AppShellConfig
    let tools: ToolsSetupState
    /// The shell's own texts, from the catalogues; rebuilt on a language change.
    var texts: ShellTexts

    var status: EngineStatus = .starting
    var hello: EngineHello?
    var tab: Tab = .process
    /// The sidebar as the person set it from View, in a wide window; nil keeps it shown.
    var sidebarChoice: Bool?
    /// The window is narrower than `SVChrome.collapseBelow`: no sidebar, the top bar instead.
    var sidebarNarrow = false
    var sidebarShown = true
    var inspectorOpen: Bool { didSet { defaults.set(inspectorOpen, forKey: DefaultsKey.inspectorOpen) } }
    var checkingUpdates = false
    /// A newer release GitHub told about (the sidebar card, Settings › Updates).
    var updateAvailable: (version: String, url: URL)?
    var lastUpdateResult: UpdateResult?
    var lastUpdateCheck: Date?

    // Process (F4.4)
    var videos: [VideoItem] = []
    var selection: Set<UUID> = []
    /// Items dropped that are not videos: the yellow note over the list, until closed.
    var skippedItems: [String] = []
    var batch = BatchActivity()
    /// The batch in progress as the rows see it (F5.1, `AppModel+Run.swift`).
    var run = BatchRun()
    /// O1 or O2 while it is up (`AppModel+Run.swift`).
    @ObservationIgnored var stopAlert: StopAlert?
    /// The video Preview shows (F5.2), chosen from the list.
    var previewVideoID: UUID? { didSet { defaults.set(previewVideoID?.uuidString, forKey: DefaultsKey.previewVideo) } }
    /// The SRT Sub fix works on (F5.3).
    var fixPath: URL?
    // One property per page (F5.2–5.4), each with its own `AppModel+X.swift`.
    var preview = PreviewState()
    var fix = FixState()
    var report = ReportState()

    // Settings
    var lists: ListsStatus?
    var toolsStatus: ToolsStatusReply?
    /// Settings › Tools › Download Again, while it runs: bytes done of total.
    var redownload: (done: Int64, total: Int64)?
    var customFFmpeg: CustomFFmpeg?

    @ObservationIgnored let defaults = UserDefaults.standard
    @ObservationIgnored var reopenMainWindow: @MainActor () -> Void = {}
    @ObservationIgnored private var started = false
    @ObservationIgnored var log: AppLog { AppLog.shared }

    init() {
        #if DEBUG
        let debug = true
        #else
        let debug = false
        #endif
        configuration = EngineConfiguration.standard(debug: debug)
        let defaults = UserDefaults.standard
        localizer = Localizer(bundle: .main, subdirectory: "locales", languages: ["en", "it"])
        localizer.setLanguage(defaults.string(forKey: DefaultsKey.language) ?? localizer.systemLanguage())
        texts = ShellTexts(localizer)
        config = AppConfig.shell(localizer: localizer)
        engine = EngineClient(configuration: configuration)
        tools = ToolsSetupState(tools: config.tools, engine: engine)
        inspectorOpen = defaults.bool(forKey: DefaultsKey.inspectorOpen)
        previewVideoID = defaults.string(forKey: DefaultsKey.previewVideo).flatMap(UUID.init)
        AppLog.shared = AppLog(subsystem: config.logSubsystem, file: configuration.stateFolder.appendingPathComponent("records/app.log"))
        log.info("SubVision \(config.appVersion) · code \(configuration.codeFolder.path) · state \(configuration.stateFolder.path)")
        readUpdateDefaults()
        customFFmpeg = defaults.string(forKey: DefaultsKey.customFFmpeg).map { CustomFFmpeg(path: $0) }
        loadVideos()
        tools.onFinished = { [weak self] in
            guard let self else { return }
            WindowSizer.toMain(config)
        }
    }

    func t(_ key: String, _ values: [String: Any] = [:]) -> String { localizer.t(key, values) }
    func tn(_ key: String, _ n: Int, _ values: [String: Any] = [:]) -> String { localizer.tn(key, n, values) }

    /// Pieces joined as the boards do: "3 video · 1 fallito".
    func join(_ parts: [String]) -> String { parts.joined(separator: t("app.common.list_separator")) }

    // MARK: - Settings (UserDefaults)

    var language: String { localizer.language }

    func setLanguage(_ code: String) {
        localizer.setLanguage(code)
        texts = ShellTexts(localizer)
        defaults.set(localizer.language, forKey: DefaultsKey.language)
        followLanguage(localizer.language)
    }

    /// macOS names its own menu items (About, Services, Hide…) in the app's
    /// language from the next launch on: the app's choice, not only the system's.
    func followLanguage(_ code: String) {
        if defaults.stringArray(forKey: "AppleLanguages")?.first != code {
            defaults.set([code], forKey: "AppleLanguages")
        }
    }

    var theme: String {
        get { defaults.string(forKey: DefaultsKey.theme) ?? "system" }
        set {
            withMutation(keyPath: \.theme) {
                defaults.set(newValue, forKey: DefaultsKey.theme)
                ShellTheme.apply(newValue)
            }
        }
    }

    var notifications: Bool {
        get { defaults.object(forKey: DefaultsKey.notifications) as? Bool ?? true }
        set { withMutation(keyPath: \.notifications) { defaults.set(newValue, forKey: DefaultsKey.notifications) } }
    }

    var dockProgress: Bool {
        get { defaults.object(forKey: DefaultsKey.dockProgress) as? Bool ?? true }
        set {
            withMutation(keyPath: \.dockProgress) {
                defaults.set(newValue, forKey: DefaultsKey.dockProgress)
                updateDock()
            }
        }
    }

    var autoCheckUpdates: Bool {
        get { defaults.object(forKey: DefaultsKey.autoCheckUpdates) as? Bool ?? true }
        set { withMutation(keyPath: \.autoCheckUpdates) { defaults.set(newValue, forKey: DefaultsKey.autoCheckUpdates) } }
    }

    var includeSubfolders: Bool {
        get { defaults.object(forKey: DefaultsKey.includeSubfolders) as? Bool ?? true }
        set { withMutation(keyPath: \.includeSubfolders) { defaults.set(newValue, forKey: DefaultsKey.includeSubfolders) } }
    }

    /// The OCR language of the inspector (`OcrParams.langHint`); the warm-up prepares it.
    var ocrLanguage: String {
        get { defaults.string(forKey: DefaultsKey.ocrLanguage) ?? OcrParams().langHint }
        set { withMutation(keyPath: \.ocrLanguage) { defaults.set(newValue, forKey: DefaultsKey.ocrLanguage) } }
    }

    // MARK: - Engine

    func start() {
        guard !started else { return }
        started = true
        ShellNotifications.shared.install()
        ShellNotifications.shared.onClick = { [weak self] info in
            guard let self else { return }
            reopenMainWindow()
            if let page = info["page"], let tab = Tab(rawValue: page) { self.tab = tab }
        }
        tools.warmupLanguages = [ocrLanguage]
        tools.prepareIfFirstLaunch(stateFolder: configuration.stateFolder)
        Task { await listen() }
        Task { await launch() }
    }

    private func launch() async {
        status = .starting
        do {
            try await engine.start()
        } catch {
            log.error("engine start failed: \(error)")
            status = .failed(String(describing: error))
            return
        }
        await load(firstRun: true)
    }

    func retry() {
        Task {
            await engine.stop()
            try? await Task.sleep(for: .milliseconds(300))
            await launch()
        }
    }

    /// `hello` and the first requests. The retry policy of API.md 27: on the
    /// very first launch the launcher downloads uv and Python before the
    /// engine reads a line, so a second 90 s wait is granted; later launches
    /// fail at once, with Try Again.
    func load(firstRun: Bool) async {
        let h: EngineHello
        var attempts = tools.runtimePending ? 2 : 1
        while true {
            do {
                h = try await engine.hello()
                break
            } catch EngineError.timedOut(let method) {
                attempts -= 1
                log.error("\(method) timed out, attempts left \(attempts)")
                if attempts <= 0 {
                    status = .failed(String(describing: EngineError.timedOut(method)))
                    return
                }
            } catch EngineError.engineExited {
                // A crash while loading: the restart's `engine.started` loads again.
                log.error("engine stopped before hello")
                return
            } catch {
                log.error("hello failed: \(error)")
                status = .failed(String(describing: error))
                return
            }
        }
        hello = h
        log.info("engine \(h.engine) \(h.version) protocol \(h.protocol) · python \(h.python ?? "?") · pid \(h.pid ?? 0) · vision \(h.vision) · livetext \(h.livetext) · \(h.languages.count) languages")
        if !h.isCompatible {
            status = .failed("engine protocol \(h.protocol), app protocol \(EngineProtocol.version)")
            return
        }
        tools.runtimeReady()
        await applyCustomFFmpeg()
        do {
            let ts = try await engine.toolsStatus()
            toolsStatus = ts
            decideTools(ts)
        } catch {
            log.error("tools.status: \(error)")
            status = .failed(String(describing: error))
            return
        }
        lists = try? await engine.listsStatus()
        status = .ready
        await refreshVideos()
        if firstRun { autoCheckUpdatesIfDue() }
    }

    /// The one consumer of the engine's events, in order: the tools window
    /// first, then the typed message.
    private func listen() async {
        for await event in engine.events {
            tools.apply(event)
            let message: EngineMessage
            do {
                message = try event.message()
            } catch {
                log.error("event \(event.name) has the wrong shape: \(error)")
                continue
            }
            switch message {
            case .engineStarted(let pid):
                log.info("engine started, pid \(pid)")
                if await engine.restarts > 0 {
                    log.info("engine restarted: loading again")
                    await load(firstRun: false)
                }
            case .engineExited(let code):
                log.info("engine exited with status \(code)")
            case .engineGaveUp:
                status = .gaveUp
            case .ready:
                break
            case .toolsProgress(let p):
                toolProgress(p)
            case .toolsDone(let done):
                toolsStatus = done.status
                redownload = nil
                if !done.ok { log.error("tools.install did not finish") }
            case .warmupDone(let w):
                log.info("warmup done in \(w.seconds) s for \(w.languages)")
                if hello?.vision == true { defaults.set(Self.macOSBuild, forKey: DefaultsKey.warmupBuild) }
            case .batchFileStarted, .batchStep, .batchFileDone, .batchFileFailed, .batchFileStopped, .batchDone:
                handleBatch(message, name: event.name)
            case .previewProgress, .previewDone, .previewStopped, .previewFailed:
                handlePreview(message, name: event.name)
            case .other(let name):
                log.debug("event \(name) (unknown)")
            }
        }
    }

    /// The build of macOS (`kern.osversion`, e.g. 26B123): Vision's cache is per build (S5).
    static var macOSBuild: String {
        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("kern.osversion", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    // MARK: - Window and app

    func showLog() { openLogInConsole(configuration.logFile.path) }
    func showAppLog() { openLogInConsole(configuration.stateFolder.appendingPathComponent("records/app.log").path) }

    /// View › Show/Hide Sidebar and the top bar's button; a narrow window has no sidebar.
    func toggleSidebar() {
        guard !sidebarNarrow else { return }
        sidebarChoice = !sidebarShown
    }

    func toggleInspector() { inspectorOpen.toggle() }

    /// The red button closed the window; the batch goes on (O4, the first time).
    func windowClosed() {
        guard batch.running, !defaults.bool(forKey: DefaultsKey.closeNoticeOff) else { return }
        // After the close has gone through: the alert must not hang on the window that is going.
        DispatchQueue.main.async { Alerts.closeNotice(self) }
    }

    /// ⌘Q: with a batch running, O3 asks first. True cancels the quit.
    func shouldBlockQuit() -> Bool {
        guard batch.running else { return false }
        return !Alerts.confirmQuit(self)
    }

    /// A sheet that is up (the end-of-batch summary, F5.1) keeps AppKit from
    /// terminating: it is closed first, unseen, so it comes back at the next launch.
    func quitApp() {
        let sheetOpen = run.showSummary
        run.showSummary = false
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        DispatchQueue.main.asyncAfter(deadline: .now() + (sheetOpen ? 0.35 : 0)) { NSApp.terminate(nil) }
    }

    /// The Dock icon's menu (O10): the file in progress, Stop All, Show SubVision.
    func dockMenu() -> [DockMenuEntry] {
        var items: [DockMenuEntry] = []
        if batch.running {
            items.append(.item(t("app.sidebar.batch_line", ["i": batch.index, "n": batch.total, "name": batch.name])) {})
            items.append(.item(t("app.common.stop_all")) { [weak self] in self?.stopAll() })
            items.append(.separator)
        }
        items.append(.item(t("app.menu.dock.show")) { [weak self] in self?.reopenMainWindow() })
        return items
    }

    func updateDock() {
        if batch.running, dockProgress {
            DockProgress.update(config, fraction: batch.fraction ?? 0, badge: batch.total > 0 ? "\(batch.total - batch.index + 1)" : nil)
        } else {
            DockProgress.clear()
        }
    }

    func showAbout() {
        showAboutPanel(repositoryURL: config.repositoryURL, credits: t("app.menu.about_credits"))
    }

    // MARK: - Batch (the rest is in AppModel+Run, F5.1)

    var canStart: Bool {
        status == .ready && !batch.running && hello?.vision == true && !readyVideos.isEmpty
    }

    // MARK: - Updates

    private func readUpdateDefaults() {
        let when = defaults.double(forKey: DefaultsKey.lastUpdateCheck)
        lastUpdateCheck = when > 0 ? Date(timeIntervalSince1970: when) : nil
        if let saved = defaults.string(forKey: DefaultsKey.lastUpdateResult) {
            if saved == "ok" {
                lastUpdateResult = .upToDate
            } else if saved.hasPrefix("available:"), case let parts = saved.dropFirst("available:".count).split(separator: "|", maxSplits: 1),
                      parts.count == 2, let url = URL(string: String(parts[1])) {
                let version = String(parts[0])
                lastUpdateResult = .available(version: version, url: url)
                if UpdateCheck.isNewer(version, than: UpdateCheck.normalise(config.appVersion)) { updateAvailable = (version, url) }
            } else if saved.hasPrefix("error:") {
                lastUpdateResult = .error(String(saved.dropFirst("error:".count)))
            }
        }
    }

    /// Remembers a check's outcome (Settings › Updates, the sidebar card).
    func record(_ result: UpdateResult) {
        lastUpdateResult = result
        lastUpdateCheck = Date()
        defaults.set(Date().timeIntervalSince1970, forKey: DefaultsKey.lastUpdateCheck)
        switch result {
        case .upToDate:
            defaults.set("ok", forKey: DefaultsKey.lastUpdateResult)
            updateAvailable = nil
        case .available(let version, let url):
            defaults.set("available:\(version)|\(url.absoluteString)", forKey: DefaultsKey.lastUpdateResult)
            updateAvailable = (version, url)
        case .error(let message):
            defaults.set("error:\(message)", forKey: DefaultsKey.lastUpdateResult)
        }
    }

    /// SubVision › Check for Updates… and the sidebar footer: the shell's alert, then the record.
    func checkForUpdates() {
        guard !checkingUpdates else { return }
        checkingUpdates = true
        Task {
            let result = await UpdateCheck.check(releaseAPIURL: config.releaseAPIURL, currentVersion: config.appVersion,
                                                 fallbackPage: config.releasePageURL)
            checkingUpdates = false
            record(result)
            Alerts.updateResult(self, result)
        }
    }

    /// Settings › Updates › Check Now: no alert, the box shows the outcome.
    func checkForUpdatesQuietly() async {
        guard !checkingUpdates else { return }
        checkingUpdates = true
        let result = await UpdateCheck.check(releaseAPIURL: config.releaseAPIURL, currentVersion: config.appVersion,
                                             fallbackPage: config.releasePageURL)
        checkingUpdates = false
        record(result)
    }

    /// At launch, at most once a day, in the background (Settings › Updates).
    private func autoCheckUpdatesIfDue() {
        guard autoCheckUpdates else { return }
        if let last = lastUpdateCheck, Date().timeIntervalSince(last) < 24 * 3600 { return }
        Task { await checkForUpdatesQuietly() }
    }
}
