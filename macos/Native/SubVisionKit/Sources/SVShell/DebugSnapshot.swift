// SPDX-License-Identifier: MIT
// Copied and adapted from the native macOS app of AnimeUp (AnimeUp/DebugSnapshot.swift,
// the rendering helpers), by the same author. The scenarios stayed in the app;
// here are the renderers, the window capture and the environment variables,
// with the prefix as a parameter and both appearances on request.
//
// ImageRenderer draws AppKit-backed controls (menus, sliders, links) as
// placeholders: these pictures check layout and colour, the real window the rest.

import AppKit
import SVDesign
import SwiftUI

@MainActor
public enum DebugSnapshot {
    /// `<PREFIX>SNAPSHOT=/path/shot`: the prefix of the PNGs, when snapshots are asked for.
    public static func base(_ config: AppShellConfig, env: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        config.environment("SNAPSHOT", env)
    }

    /// `<PREFIX>SNAPSHOT_SCHEME=light|dark|both`: the appearances to render in;
    /// unset, the app's own appearance.
    public static func schemes(_ config: AppShellConfig, env: [String: String] = ProcessInfo.processInfo.environment) -> [ColorScheme] {
        switch config.environment("SNAPSHOT_SCHEME", env) {
        case "light": [.light]
        case "dark": [.dark]
        case "both": [.light, .dark]
        default: [ShellTheme.scheme]
        }
    }

    /// `path` with `-light` / `-dark` before the extension.
    public static func path(_ path: String, _ scheme: ColorScheme) -> String {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().path
        return "\(stem)-\(scheme == .dark ? "dark" : "light").\(ext)"
    }

    /// Renders `view` at `width` (height to fit) and writes a PNG at scale 2.
    @discardableResult
    public static func render<V: View>(_ view: V, width: CGFloat, height: CGFloat? = nil, scheme: ColorScheme,
                                       _ path: String) -> Bool {
        let content = view.frame(width: width, height: height).environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        return write(renderer.nsImage, to: path)
    }

    /// One PNG per scheme, named `path(_:_:)`; the paths written.
    @discardableResult
    public static func render<V: View>(_ view: V, width: CGFloat, height: CGFloat? = nil, schemes: [ColorScheme],
                                       _ path: String) -> [String] {
        schemes.compactMap { scheme in
            let p = schemes.count > 1 ? self.path(path, scheme) : path
            return render(view, width: width, height: height, scheme: scheme, p) ? p : nil
        }
    }

    /// Sidebar and page side by side at the window size, on `bg`.
    @discardableResult
    public static func renderComposite<S: View, P: View>(sidebar: S, page: P, size: CGSize, chrome: SVChrome = .default,
                                                         schemes: [ColorScheme], _ path: String) -> [String] {
        let view = HStack(spacing: 0) {
            sidebar
                .frame(width: chrome.sidebarWidth)
                .frame(maxHeight: .infinity)
                .padding([.leading, .vertical], chrome.sidebarInset)
            page.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(SV.bg)
        .environment(\.svChrome, chrome)
        return render(view, width: size.width, height: size.height, schemes: schemes, path)
    }

    /// The main window as it is on screen (no Screen Recording permission needed).
    @discardableResult
    public static func capture(_ config: AppShellConfig, _ path: String) -> Bool {
        guard let window = WindowSizer.main(config) ?? NSApp.windows.first(where: \.isVisible),
              let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            AppLog.shared.info("snapshot \(path)")
            return true
        } catch {
            return false
        }
    }

    /// The real window once per scheme (light and dark from `schemes(_:)`):
    /// the app's appearance is switched, the window redrawn and captured,
    /// then the appearance put back. One scheme keeps `path` as it is.
    @discardableResult
    public static func capture(_ config: AppShellConfig, schemes: [ColorScheme], _ path: String,
                               settle: Duration = .milliseconds(400)) async -> [String] {
        let saved = NSApp.appearance
        defer { NSApp.appearance = saved }
        var written: [String] = []
        for scheme in schemes {
            NSApp.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            WindowSizer.main(config)?.displayIfNeeded()
            try? await Task.sleep(for: settle)
            let p = schemes.count > 1 ? self.path(path, scheme) : path
            if capture(config, p) { written.append(p) }
        }
        return written
    }

    private static func write(_ image: NSImage?, to path: String) -> Bool {
        guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return false }
        do {
            try FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try png.write(to: URL(fileURLWithPath: path))
            AppLog.shared.info("snapshot \(path)")
            return true
        } catch {
            AppLog.shared.error("snapshot \(path) failed: \(error)")
            return false
        }
    }
}
