// SPDX-License-Identifier: MIT
// The review report window (boards R1–R3, D8 a): the app's title row with
// the file's name, Show in Finder and Open in Browser, the report in a
// WKWebView under it, the loading spinner, the note when the file is gone,
// and the toast after an export. One NSWindow per report, kept by
// `AppModel.report`; AppKit lists them in the Window menu by itself.

import AppKit
import SVShell
import SwiftUI
import WebKit

/// What the window shows, and the bridge behind it.
@MainActor
@Observable
final class ReportSession {
    enum Phase: Equatable {
        case loading
        case ready
        /// The file is not there (any more).
        case gone
        /// The file is there but is not a readable review report.
        case unreadable
    }

    let url: URL
    private(set) var phase: Phase = .loading
    private(set) var bridge: ReportBridge?
    /// The export just done (R2): the toast's name, until it fades.
    private(set) var toast: URL?
    /// The review state (`<name>.review.json`) could not be written: the
    /// yellow notice at the bottom, once per run of failures (closing it keeps
    /// it closed until a write goes through and another fails).
    private(set) var stateWarning = false
    @ObservationIgnored private var stateFailing = false
    /// The last export, for the debug commands.
    private(set) var lastExport: URL?
    unowned let model: AppModel
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    #if DEBUG
    /// Debug: the answer to "Choose where to save…" without the alert and the panel
    /// (`report-elsewhere <path>|cancel`); `.some(nil)` cancels.
    static var debugElsewhere: URL??
    #endif

    var name: String { url.lastPathComponent }
    /// "Revisione · _test-1.mkv": the window's title and its title row (C2 boards).
    var title: String { model.t("app.report.window_title", ["name": model.reviewName(for: url)]) }

    init(url: URL, model: AppModel) {
        self.url = url
        self.model = model
    }

    /// Reads the file and starts the load; the phase says what the window shows.
    func load() {
        phase = .loading
        guard FileManager.default.fileExists(atPath: url.path) else {
            phase = .gone
            return
        }
        guard let file = ReportFile(url: url) else {
            phase = .unreadable
            return
        }
        let bridge = ReportBridge(file: file, language: model.language, t: { [model] key, values in model.t(key, values) })
        bridge.onNavigationFinished = { [weak self] in self?.phase = .ready }
        bridge.onNavigationFailed = { [weak self] error in
            AppLog.shared.error("report load \(file.url.lastPathComponent): \(error)")
            self?.phase = FileManager.default.fileExists(atPath: file.url.path) ? .unreadable : .gone
        }
        bridge.onExport = { [weak self] outcome in
            guard let self else { return }
            if case .saved(let url) = outcome {
                lastExport = url
                showToast(url)
            }
        }
        bridge.askWhereToSave = { [weak self] name in self?.askWhereToSave(name) }
        bridge.onStateWrite = { [weak self] ok in self?.stateWritten(ok) }
        self.bridge = bridge
        model.log.info("report open \(file.url.lastPathComponent) (\(file.kind == .bridged ? "2.0" : "1.x"))")
        bridge.load()
    }

    /// The toast of R2, gone by itself after a few seconds.
    func showToast(_ url: URL) {
        toastTask?.cancel()
        toast = url
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    /// A write of the review state went through or not (the notice of `stateWarning`).
    private func stateWritten(_ ok: Bool) {
        if ok {
            stateFailing = false
            stateWarning = false
        } else if !stateFailing {
            stateFailing = true
            stateWarning = true
        }
    }

    func hideStateWarning() { stateWarning = false }

    func hideToast() {
        toastTask?.cancel()
        toast = nil
    }

    /// R3 right: the export could not be written next to the original.
    private func askWhereToSave(_ name: String) -> URL? {
        #if DEBUG
        if let answer = Self.debugElsewhere { return answer }
        #endif
        let a = SVAlert(icon: AlertIconName.error, tone: .red, title: model.t("app.report.save_failed"),
                        text: model.t("app.report.save_failed_text"))
        a.button(model.t("app.report.save_elsewhere"), role: .primary)
        a.button(model.t("app.common.cancel"))
        guard a.runModal() == 0 else { return nil }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [.init(filenameExtension: "srt") ?? .plainText]
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    func showInFinder() { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    func openInBrowser() { NSWorkspace.shared.open(url) }
}

/// The window's content: title row, page, toast.
struct ReportView: View {
    let session: ReportSession
    var close: () -> Void
    @Environment(\.svChrome) private var chrome
    @State private var lightsAnchor: CGRect?

    private var model: AppModel { session.model }

    var body: some View {
        VStack(spacing: 0) {
            titleRow
            Rectangle().fill(SV.line).frame(height: 1)
            page
        }
        .background(SV.bg)
        .ignoresSafeArea()
        .background(WindowChrome(anchor: lightsAnchor, minSize: ReportWindowController.minSize))
        .onPreferenceChange(TrafficLightsAnchor.self) { lightsAnchor = $0 }
        .frame(minWidth: ReportWindowController.minSize.width, minHeight: ReportWindowController.minSize.height)
    }

    /// 52 pt: the lights, the file's icon and name, the two buttons.
    private var titleRow: some View {
        HStack(spacing: 12) {
            TrafficLightsSlot()
            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .svFont(13)
                    .foregroundStyle(SV.text2)
                Text(verbatim: session.title)
                    .svFont(13, .semibold)
                    .foregroundStyle(SV.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.leading, 8)
            Spacer(minLength: 12)
            Button { session.showInFinder() } label: {
                Label(model.t("app.common.show_in_finder"), systemImage: "folder")
            }
            .svButton(.secondary, .small)
            .disabled(session.phase == .gone)
            Button { session.openInBrowser() } label: {
                Label(model.t("app.report.open_browser"), systemImage: "arrow.up.right")
            }
            .svButton(.secondary, .small)
            .disabled(session.phase == .gone)
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .frame(height: 52)
        .background(SV.raised)
    }

    private var page: some View {
        ZStack {
            switch session.phase {
            case .loading, .ready:
                if let bridge = session.bridge {
                    WebViewHost(webView: bridge.webView)
                        .opacity(session.phase == .ready ? 1 : 0)
                }
                if session.phase == .loading {
                    HStack(spacing: 10) {
                        Spinner(size: 16)
                        Text(model.t("app.report.loading")).svFont(12.5).foregroundStyle(SV.text2)
                    }
                }
            case .gone:
                NoteView(.red, title: model.t("app.report.gone", ["name": session.name]),
                         text: model.t("app.report.gone_text")) {
                    Button(model.t("app.common.close")) { close() }.svButton(.destructive, .small)
                }
                .frame(width: 520)
            case .unreadable:
                NoteView(.red, title: model.t("app.report.unreadable", ["name": session.name]),
                         text: model.t("app.report.unreadable_text")) {
                    Button(model.t("app.common.close")) { close() }.svButton(.destructive, .small)
                }
                .frame(width: 520)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                if session.stateWarning {
                    ReportToast(text: model.t("app.report.state_failed"), tone: .yellow, symbol: "exclamationmark.triangle",
                                closeHelp: model.t("app.common.dismiss")) { session.hideStateWarning() }
                        .help(model.t("app.report.state_failed_help", ["name": session.bridge?.file.stateURL.lastPathComponent ?? ""]))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if let toast = session.toast {
                    ReportToast(text: model.t("app.report.saved", ["name": toast.lastPathComponent]),
                                button: model.t("app.common.show_in_finder")) {
                        NSWorkspace.shared.activateFileViewerSelecting([toast])
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.bottom, 20)
        }
        .animation(.easeOut(duration: 0.25), value: session.toast)
        .animation(.easeOut(duration: 0.25), value: session.stateWarning)
    }
}

/// The pill at the bottom of the report window. R2: a green tick, the text
/// and Show in Finder. In yellow, with a close button: the notice that the
/// review state is not being saved.
struct ReportToast: View {
    var text: String
    var tone: SVTone = .green
    var symbol = "checkmark.circle"
    /// The text button on the right (R2), or nil for a small close button.
    var button: String?
    var closeHelp = ""
    var action: () -> Void

    init(text: String, button: String, action: @escaping () -> Void) {
        self.text = text
        self.button = button
        self.action = action
    }

    init(text: String, tone: SVTone, symbol: String, closeHelp: String, close: @escaping () -> Void) {
        self.text = text
        self.tone = tone
        self.symbol = symbol
        self.closeHelp = closeHelp
        self.action = close
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .svFont(14)
                .foregroundStyle(tone.text)
            Text(verbatim: text)
                .svFont(12.5)
                .foregroundStyle(SV.text)
                .lineLimit(1)
            if let button {
                Button(button, action: action).svButton(.secondary, .small)
            } else {
                Button(action: action) {
                    Image(systemName: "xmark").svFont(10, .semibold).foregroundStyle(SV.text2)
                        .frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(closeHelp)
                .accessibilityLabel(closeHelp)
            }
        }
        .padding(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 8))
        .background(Capsule().fill(SV.alert))
        .overlay(Capsule().strokeBorder(button == nil ? tone.line : SV.glassLine, lineWidth: 1))
        .shadow(color: SV.shadow.opacity(0.4), radius: 16, y: 12)
    }
}

/// The bridge's WKWebView, owned by the bridge, in the view tree.
struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ view: WKWebView, context: Context) {}
}

/// One window per report. `isReleasedWhenClosed` is off: the model's
/// `ReportState` keeps the controller until the window closes.
@MainActor
final class ReportWindowController: NSWindowController, NSWindowDelegate {
    static let defaultSize = CGSize(width: 1100, height: 780)
    static let minSize = CGSize(width: 720, height: 520)
    static let frameName = "report"

    let session: ReportSession
    var onClose: () -> Void = {}

    init(session: ReportSession, cascadeFrom other: NSWindow?) {
        self.session = session
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.defaultSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        super.init(window: window)
        window.isReleasedWhenClosed = false
        window.title = session.title
        window.identifier = NSUserInterfaceItemIdentifier("report")
        window.minSize = Self.minSize
        window.delegate = self
        window.contentView = NSHostingView(rootView: ReportView(session: session, close: { [weak self] in self?.close() }))
        // The size and place of the last report window; a second one steps aside.
        if !window.setFrameUsingName(Self.frameName) { window.center() }
        window.setFrameAutosaveName(Self.frameName)
        if let other {
            window.setFrameTopLeftPoint(window.cascadeTopLeft(from: NSPoint(x: other.frame.minX, y: other.frame.maxY)))
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        session.load()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        session.hideToast()
        session.bridge?.detach()
        onClose()
    }

    #if DEBUG
    /// A PNG of the window: the frame from `cacheDisplay` (where the
    /// WKWebView, drawn out of process, comes out blank) with the web
    /// view's own `takeSnapshot` drawn over its place, and the toast, which
    /// lies over the web view, rendered again on top.
    func capture(to path: String) async -> Bool {
        guard let window, let root = window.contentView?.superview ?? window.contentView,
              let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { return false }
        root.cacheDisplay(in: root.bounds, to: rep)
        let webImage = session.phase == .ready ? try? await session.bridge?.webView.takeSnapshot(configuration: nil) : nil
        let image = NSImage(size: root.bounds.size)
        image.lockFocus()
        rep.draw(in: root.bounds)
        if let webImage, let webView = session.bridge?.webView {
            let frame = webView.convert(webView.bounds, to: root)
            webImage.draw(in: frame)
            if let toast = session.toast {
                let model = session.model
                let view = ReportToast(text: model.t("app.report.saved", ["name": toast.lastPathComponent]),
                                       button: model.t("app.common.show_in_finder"), action: {})
                    .padding(24)
                    .environment(\.colorScheme, ShellTheme.scheme)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                if let pill = renderer.nsImage {
                    let size = pill.size
                    pill.draw(in: NSRect(x: frame.midX - size.width / 2, y: frame.minY + 20 - 24, width: size.width, height: size.height))
                }
            }
        }
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let out = NSBitmapImageRep(data: tiff),
              let png = out.representation(using: .png, properties: [:]) else { return false }
        do {
            try FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: URL(fileURLWithPath: path))
            AppLog.shared.info("snapshot \(path)")
            return true
        } catch {
            AppLog.shared.error("snapshot \(path) failed: \(error)")
            return false
        }
    }
    #endif
}
