// SPDX-License-Identifier: MIT
// Everything the windows show, fed by the engine. Adapted from the AppModel
// of the native macOS app of AnimeUp (by the same author): here the frame,
// the tools window and the engine client come from SVShell, the settings
// live in UserDefaults, and one task consumes the engine's events in order.

import AppKit
import Observation
import SVShell
import SwiftUI

/// The pages, segments of the top bar (design note 80, C3 navigation N-A): Video (the list, the parameters, Start),
/// Review (the videos processed), then Sub fix among the tools. Preview is a page over
/// the list of Video (`PreviewPage.swift`). `process` keeps its raw value: the notifications
/// and the QA scenarios name the pages by it.
enum Tab: String, CaseIterable, Identifiable {
    case process, review, fix
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .process: "captions.bubble"
        case .review: "doc.text.magnifyingglass"
        case .fix: "text.badge.checkmark"
        }
    }
}

/// The batch as the batch bar, the Dock and the quit alert see it, filled
/// from the `batch.*` events.
struct BatchActivity: Equatable {
    var running = false
    /// 1-based index of the file in progress, and the batch size.
    var index = 0
    var total = 0
    var name = ""
    /// The batch's fraction, for the batch bar and the Dock.
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
    /// The main window's width (the parameters retract below 1100 pt, C3-03).
    var mainWindowWidth: CGFloat = 1360 {
        didSet {
            // Narrowed past the threshold: the panel retracts (N1); the top bar's button brings it.
            let chrome = config.chrome
            if chrome.inspectorOverlays(windowWidth: mainWindowWidth), !chrome.inspectorOverlays(windowWidth: oldValue) {
                inspectorOpen = false
            }
        }
    }
    /// The parameters laid over the page of a narrow window (N2). In a wide window the
    /// panel is always beside the page and this does not matter (C3-03); a window that
    /// becomes narrow starts with the panel retracted (N1).
    var inspectorOpen = false
    /// The page in front has a title band with its back button (the report in Review, Preview;
    /// The key of View › Back as the menu shows it: SwiftUI adapts "[" to the keyboard
    /// ("ò" on an Italian one), and the title band's help must name the same key.
    var backKey: String {
        let items = NSApp?.mainMenu?.items.compactMap(\.submenu).flatMap(\.items) ?? []
        let key = items.first { $0.title == t("app.menu.back") }?.keyEquivalent ?? ""
        return key.isEmpty ? "[" : key
    }
    /// C3-07, C3-09): View › Back (⌘[) runs it. The page sets it when it shows the band and
    /// clears it when it goes, and builds its band with `TitleBand(shortcut: false)`.
    @ObservationIgnored var backAction: (@MainActor () -> Void)? {
        didSet { canGoBack = backAction != nil; backGeneration &+= 1 }
    }
    var canGoBack = false
    /// Goes up at every change of `backAction`: a page that set it clears it on its way out
    /// only if no other page has set its own since (their onAppear and onDisappear interleave).
    @ObservationIgnored var backGeneration = 0
    /// Goes up by one to open the inspector's language menu (O7's "Choose the Language").
    var languageMenuRequest = 0
    var checkingUpdates = false
    /// A newer release GitHub told about (the top bar's chip, Settings › Updates).
    var updateAvailable: (version: String, url: URL)?
    var lastUpdateResult: UpdateResult?
    var lastUpdateCheck: Date?

    // Process (F4.4)
    var videos: [VideoItem] = []
    /// The row of Video the keyboard's ring is on (C3-02: no selection any more): ↑ ↓ move it,
    /// the menus' Review, Show in Finder, Open Log and Remove act on it.
    var focusedRow: UUID?
    /// The thin ring shows only when the focus came from the keyboard (↑ ↓), as in macOS lists:
    /// after a click the row keeps just its left bar (the owner's note on E3).
    var focusRingVisible = false
    /// Seconds of work per second of video learned from the files done (`WorkEstimate`), nil before the first.
    var estimateRate: Double? { didSet { defaults.set(estimateRate, forKey: Self.estimateRateKey) } }
    /// A change opens that row's ⋯ menu, as a click does (the debug commands and the menu captures).
    var rowMenuRequest: (id: UUID, count: Int)?
    /// The rows probed again this launch for their codecs (once each).
    @ObservationIgnored var codecProbed: Set<UUID> = []
    /// The row of the Review page last opened (⌘R on the list opens it again).
    var reviewSelection: UUID?
    /// Items dropped that are not videos: the yellow note over the list, until closed.
    var skippedItems: [String] = []
    var batch = BatchActivity()
    /// The batch in progress as the rows see it (F5.1, `AppModel+Run.swift`).
    var run = BatchRun()
    /// O1 or O2 while it is up (`AppModel+Run.swift`).
    @ObservationIgnored var stopAlert: StopAlert?
    /// O3 while it is up, and its answer "Quit and Stop" (the next quit goes through).
    @ObservationIgnored var quitAlert: SVAlertPresentation?
    @ObservationIgnored var quitConfirmed = false
    /// The video Preview shows (F5.2), chosen from the list.
    var previewVideoID: UUID? { didSet { defaults.set(previewVideoID?.uuidString, forKey: DefaultsKey.previewVideo) } }
    /// The SRT Sub fix works on (F5.3).
    var fixPath: URL?
    // One property per page (F5.2–5.4), each with its own `AppModel+X.swift`.
    var preview = PreviewState()
    /// The five frames of each video for the to-do drawers (`AppModel+VideoFrames.swift`).
    var videoFrames = VideoFramesState()
    var fix = FixState()
    var report = ReportState()

    // Settings
    var lists: ListsStatus?
    var toolsStatus: ToolsStatusReply?
    /// Settings › Tools › Download Again, while it runs: bytes done of total.
    var redownload: (done: Int64, total: Int64)?
    var customFFmpeg: CustomFFmpeg?
    /// Homebrew's ffmpeg and ffprobe, when both are there (Settings › Tools, design note 54).
    var homebrewFFmpeg: HomebrewFFmpeg?

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
        previewVideoID = defaults.string(forKey: DefaultsKey.previewVideo).flatMap(UUID.init)
        estimateRate = defaults.object(forKey: Self.estimateRateKey) as? Double
        AppLog.shared = AppLog(subsystem: config.logSubsystem, file: configuration.stateFolder.appendingPathComponent("records/app.log"))
        log.info("SubVision \(config.appVersion) · code \(configuration.codeFolder.path) · state \(configuration.stateFolder.path)")
        readUpdateDefaults()
        registerSubtitleLanguageDefault()
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
        // The first-launch window's rows too (its texts come from `texts`).
        tools.relabel(AppConfig.tools { [localizer] in localizer.t($0, $1) })
        defaults.set(localizer.language, forKey: DefaultsKey.language)
        followLanguage(localizer.language)
        // The report open follows too (design note 72).
        report.session?.bridge?.setLanguage(localizer.language)
    }

    /// macOS names its own menu items (About, Services, Hide…) in the app's
    /// language from the next launch on: the app's choice, not only the system's.
    func followLanguage(_ code: String) {
        if defaults.stringArray(forKey: "AppleLanguages")?.first != code {
            defaults.set([code], forKey: "AppleLanguages")
        }
    }

    var theme: String {
        get { access(keyPath: \.theme); return defaults.string(forKey: DefaultsKey.theme) ?? "system" }
        set {
            withMutation(keyPath: \.theme) {
                defaults.set(newValue, forKey: DefaultsKey.theme)
                ShellTheme.apply(newValue)
            }
        }
    }

    var notifications: Bool {
        get { access(keyPath: \.notifications); return defaults.object(forKey: DefaultsKey.notifications) as? Bool ?? true }
        set { withMutation(keyPath: \.notifications) { defaults.set(newValue, forKey: DefaultsKey.notifications) } }
    }

    var dockProgress: Bool {
        get { access(keyPath: \.dockProgress); return defaults.object(forKey: DefaultsKey.dockProgress) as? Bool ?? true }
        set {
            withMutation(keyPath: \.dockProgress) {
                defaults.set(newValue, forKey: DefaultsKey.dockProgress)
                updateDock()
            }
        }
    }

    var autoCheckUpdates: Bool {
        get { access(keyPath: \.autoCheckUpdates); return defaults.object(forKey: DefaultsKey.autoCheckUpdates) as? Bool ?? true }
        set { withMutation(keyPath: \.autoCheckUpdates) { defaults.set(newValue, forKey: DefaultsKey.autoCheckUpdates) } }
    }

    var includeSubfolders: Bool {
        get { access(keyPath: \.includeSubfolders); return defaults.object(forKey: DefaultsKey.includeSubfolders) as? Bool ?? true }
        set { withMutation(keyPath: \.includeSubfolders) { defaults.set(newValue, forKey: DefaultsKey.includeSubfolders) } }
    }

    /// The OCR language of the inspector (`OcrParams.langHint`); the warm-up prepares it.
    var ocrLanguage: String {
        get { defaults.string(forKey: DefaultsKey.ocrLanguage) ?? subtitleLanguageDefault }
        set { withMutation(keyPath: \.ocrLanguage) { defaults.set(newValue, forKey: DefaultsKey.ocrLanguage) } }
    }

    /// The default subtitle language (Settings › General, proposal P1): the user's pick,
    /// else the language of macOS when Vision reads it, else English. It is registered as
    /// the default of the OCR language key, so the parameters panel, "↺ Predefinito",
    /// "Ripristina" and the "changed" colour all measure against it.
    var subtitleLanguageDefault: String {
        get {
            access(keyPath: \.subtitleLanguageDefault)
            return defaults.string(forKey: DefaultsKey.subtitleLanguageDefault) ?? Self.systemSubtitleLanguage(among: hello?.languages)
        }
        set {
            withMutation(keyPath: \.subtitleLanguageDefault) {
                defaults.set(newValue, forKey: DefaultsKey.subtitleLanguageDefault)
                registerSubtitleLanguageDefault()
            }
        }
    }

    func registerSubtitleLanguageDefault() {
        defaults.register(defaults: [DefaultsKey.ocrLanguage: subtitleLanguageDefault])
    }

    /// The Vision code for the first macOS language that Vision reads: among the engine's
    /// list once it has said it, else from the usual codes of Vision; English otherwise.
    static func systemSubtitleLanguage(among languages: [String]?, preferred: [String] = Locale.preferredLanguages) -> String {
        let usual = ["en": "en-US", "it": "it-IT", "fr": "fr-FR", "de": "de-DE", "es": "es-ES", "pt": "pt-BR",
                     "ja": "ja-JP", "ko": "ko-KR", "zh": "zh-Hans", "ru": "ru-RU", "uk": "uk-UA", "th": "th-TH",
                     "vi": "vi-VT", "ar": "ar-SA", "tr": "tr-TR", "id": "id-ID", "cs": "cs-CZ", "da": "da-DK",
                     "nl": "nl-NL", "no": "no-NO", "nb": "nb-NO", "nn": "nn-NO", "ms": "ms-MY", "pl": "pl-PL",
                     "ro": "ro-RO", "sv": "sv-SE"]
        func parts(_ c: String) -> [String] { c.split(whereSeparator: { $0 == "-" || $0 == "_" }).map { $0.lowercased() } }
        for pref in preferred {
            let p = parts(pref)
            guard let base = p.first else { continue }
            guard let list = languages, !list.isEmpty else {
                if let code = usual[base] { return code }
                continue
            }
            // Same language and script or region first (zh-Hant-TW → zh-Hant), then the usual code, then any variant.
            let same = list.filter { parts($0).first == base }
            if let hit = same.first(where: { p.count > 1 && parts($0).dropFirst().contains(p[1]) }) { return hit }
            if let code = usual[base], let hit = same.first(where: { $0.caseInsensitiveCompare(code) == .orderedSame }) { return hit }
            if let hit = same.first { return hit }
        }
        if let list = languages, !list.isEmpty, !list.contains(where: { $0.caseInsensitiveCompare("en-US") == .orderedSame }) {
            return list.first { parts($0).first == "en" } ?? "en-US"
        }
        return "en-US"
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
            // A file's notification opens its report on Review.
            if let id = info["video"].flatMap(UUID.init) { self.openReviewFromNotification(id) }
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
        registerSubtitleLanguageDefault()
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
        // The drawers' frames of the videos already in the list (from the engine's cache when it has them).
        queueVideoFrames(videos.map(\.id))
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
                // ffmpeg is there now: the drawers' frames that could not be taken without it.
                if done.ok { queueVideoFrames(videos.map(\.id)) }
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

    /// The top bar's button and ⌥⌘I, in a narrow window only (N1, N2).
    func toggleInspector() {
        guard inspectorOverlays else { return }
        inspectorOpen.toggle()
    }

    /// The main window is narrow enough for the parameters to lie over the page (below 1100 pt):
    /// only then they can be shown and hidden (C3-03, N1, N2).
    var inspectorOverlays: Bool { config.chrome.inspectorOverlays(windowWidth: mainWindowWidth) }

    /// View › Video, Review, Sub fix (⌘1–⌘3): the main window, on that page.
    func showPage(_ page: Tab) {
        tab = page
        reopenMainWindow()
    }

    /// What Review (⌘R) opens: the row last opened on Review, else the row with the focus on Video.
    var reviewTarget: VideoItem? {
        tab == .review ? selectedReview : (tab == .process ? focusedVideo : nil)
    }

    /// O7's "Choose the Language": Process with the inspector open on the OCR
    /// group, and the language menu opened once the inspector has slid in.
    func showLanguageMenu() {
        tab = .process
        defaults.set("read", forKey: "inspector.tab")
        // Beside a wide page the panel is always there; over a narrow one it slides in first.
        let wasOpen = inspectorOpen || !inspectorOverlays
        if inspectorOverlays { inspectorOpen = true }
        Task {
            try? await Task.sleep(for: .milliseconds(wasOpen ? 150 : 500))
            guard inspectorOpen || !inspectorOverlays, tab == .process, !batch.running else { return }
            languageMenuRequest += 1
        }
    }

    /// The red button closed the window; the batch goes on (O4, the first time).
    func windowClosed() {
        guard batch.running, !defaults.bool(forKey: DefaultsKey.closeNoticeOff) else { return }
        // After the close has gone through: the alert must not hang on the window that is going.
        DispatchQueue.main.async { Alerts.closeNotice(self) }
    }

    /// ⌘Q: with a batch running, O3 asks first. True cancels this quit: O3 is not modal,
    /// and its "Quit and Stop" quits again, then without asking.
    func shouldBlockQuit() -> Bool {
        guard batch.running, !quitConfirmed else { return false }
        if let open = quitAlert, open.isOpen {
            open.focus()
            return true
        }
        quitAlert = Alerts.confirmQuit(self) { [weak self] quit in
            guard let self else { return }
            quitAlert = nil
            guard quit else { return }
            quitConfirmed = true
            quitApp()
        }
        return true
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
            items.append(.label(t("app.sidebar.batch_line", ["i": batch.index, "n": batch.total, "name": batch.name])))
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

    /// SubVision › About SubVision: the version, the line about the app, the GitHub mark and link (C3-01, O9).
    func showAbout() {
        showAboutPanel(repositoryURL: config.repositoryURL, credits: t("app.menu.about_credits"), mark: NSImage(named: "GitHubMark"))
    }

    /// SubVision › SubVision on GitHub ↗.
    func openRepository() { NSWorkspace.shared.open(config.repositoryURL) }

    // MARK: - Batch (the rest is in AppModel+Run, F5.1)

    /// Process (⌘↩, the bottom bar): the checked rows (C3-02).
    var canStart: Bool { canRun && !checkedVideos.isEmpty }

    /// The engine could take a batch now.
    var canRun: Bool { status == .ready && !batch.running && hello?.vision == true }

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

    /// Remembers a check's outcome (Settings › Updates, the top bar's chip).
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

    /// SubVision › Check for Updates…: the shell's alert, then the record.
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
