// SPDX-License-Identifier: MIT
// Debug only: the commands of the F6 design snapshots (design/snapshot/f6),
// reached through `DebugQA` (`SUBVISION_COMMANDS=<file>`) for the boards that
// had no path yet: the engine page (T5), the banner and the disk note (E7),
// the alerts over the window (O1–O8), the menus (O9, I2), the Dock (O10), the
// Settings window (ST1–ST5) and the design gallery (DS1–DS4).
//
//   engine-status starting|gaveup|ready|failed <text>   the page in place of the tabs (T5), fed by hand
//   vision on|off                  hello.vision as the engine said it (E7: the red banner, Start off)
//   disk-free <GB>|off             the free space the disk note reads (E7: under 10 GB the yellow note)
//   batch-fake on|off              batch.running with "file 2 of 3" (the menus, the Dock, ST5); no engine involved
//   capture-all <path>             the main window with the alerts over it (its child windows), in each scheme
//   capture-window main|settings|alert|<number> <path>   one window alone (cacheDisplay), in each scheme
//   windows                        the visible windows: number, class, title, frame
//   activate [main|settings|alert] the app active and that window key (switches in the accent)
//   settings-tab general|tools|lists|updates   the Settings window's tab, as a click on its toolbar item
//   settings-feed redownload <MB> <MB> | own <path> <error> | update ok|available <version>|error | clear
//   alert-show quit|close|novideos <folder>|already <path>|import|update   O3, O4, O8a–d over the main window
//   alerts-close                   every alert panel up, as with Esc
//   menu-shot <menu index>|dock|lang <path>   opens that menu and `screencapture`s its window while it is open
//   dock-tile <path>               the Dock tile's view with the batch's bar (O10), at 2x
//   compose <out> <light|dark> <columns> <png>[,<png>…]   pictures on a grid, on the page's background
//   gallery <path>                 the SVDesign gallery (DS1–DS4), in each scheme

#if DEBUG
import AppKit
import SVShell
import SwiftUI

@MainActor
enum DebugCapture {
    /// The free space the disk note of Process reads instead of the disk's (`disk-free`).
    static var freeGB: Double?

    static func run(_ command: String, _ argument: String, _ model: AppModel) async -> String? {
        let args = argument.split(separator: " ").map(String.init)
        let schemes = SVShell.DebugSnapshot.schemes(model.config)
        switch command {
        case "engine-status":
            switch args.first ?? "" {
            case "starting": model.status = .starting
            case "gaveup": model.status = .gaveUp
            case "ready": model.status = .ready
            case "failed": model.status = .failed(args.dropFirst().joined(separator: " "))
            default: return "usage: engine-status starting|gaveup|ready|failed <text>"
            }
            return "ok · \(model.status)"
        case "vision":
            guard model.hello != nil else { return "no hello" }
            model.hello?.vision = argument == "on"
            return "ok · vision \(model.hello?.vision ?? false) · canStart \(model.canStart)"
        case "disk-free":
            freeGB = argument == "off" ? nil : Double(argument)
            // The note is computed in the body: a write the page observes redraws it.
            model.skippedItems = model.skippedItems
            return "ok · free \(freeGB.map { "\($0)" } ?? "real")"
        case "batch-fake":
            if argument == "on" {
                model.batch = BatchActivity(running: true, index: 2, total: 3, name: model.videos.count > 1 ? model.videos[1].name : "Show S01E05 [1080p].mkv",
                                            fraction: 0.47, endsAround: AppModel.clockTime(Date().addingTimeInterval(3600)))
            } else {
                model.batch = BatchActivity()
            }
            model.updateDock()
            return "ok · running \(model.batch.running)"
        case "capture-all":
            return await captureAll(model, argument, schemes: schemes).joined(separator: " ")
        case "capture-window":
            guard args.count == 2 else { return "usage: capture-window main|settings|alert|<number> <path>" }
            guard let window = window(args[0], model) else { return "no window" }
            return await captureWindow(window, args[1], schemes: schemes).joined(separator: " ")
        case "activate":
            // The switches and the selected rows draw in the accent only in the active app's key window.
            NSApp.activate(ignoringOtherApps: true)
            (window(argument.isEmpty ? "main" : argument, model))?.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(500))
            return "ok · active \(NSApp.isActive) · key \(NSApp.keyWindow?.title ?? "-")"
        case "windows":
            return NSApp.windows.filter(\.isVisible).map {
                "\($0.windowNumber) \(type(of: $0)) «\($0.title)» \(Int($0.frame.minX)),\(Int($0.frame.minY)) \(Int($0.frame.width))x\(Int($0.frame.height))"
            }.joined(separator: " | ")
        case "settings-tab":
            return settingsTab(argument, model)
        case "settings-feed":
            return settingsFeed(args, model)
        case "alert-show":
            return showAlert(args, model)
        case "alerts-close":
            let panels = alertPanels()
            panels.forEach { $0.cancelOperation(nil) }
            return "closed \(panels.count)"
        case "menu-shot":
            guard args.count == 2 else { return "usage: menu-shot <index>|dock|lang <path>" }
            return await menuShot(args[0], args[1], model)
        case "dock-tile":
            return dockTile(argument, model)
        case "compose":
            guard args.count == 4, let columns = Int(args[2]) else { return "usage: compose <out> <light|dark> <columns> <png,…>" }
            return compose(args[0], dark: args[1] == "dark", columns: columns, args[3].split(separator: ",").map(String.init))
        case "gallery":
            return SVShell.DebugSnapshot.render(SVDesignGallery(), width: SVDesignGallery.width, schemes: schemes, argument)
                .joined(separator: " ")
        default:
            return nil
        }
    }

    // MARK: - Windows

    private static func window(_ which: String, _ model: AppModel) -> NSWindow? {
        let main = WindowSizer.main(model.config)
        switch which {
        case "main": return main
        case "settings": return settingsWindow(model)
        case "alert": return alertPanels().last
        default: return Int(which).flatMap { NSApp.window(withWindowNumber: $0) }
        }
    }

    private static func settingsWindow(_ model: AppModel) -> NSWindow? {
        let main = WindowSizer.main(model.config)
        return NSApp.windows.first { $0.isVisible && $0 !== main && $0.toolbar != nil && !(String(describing: type(of: $0)).contains("Report")) }
    }

    /// The panels of `SVAlert.present` (SVDesign's `AlertWindow`) that are up.
    private static func alertPanels() -> [NSWindow] {
        NSApp.windows.filter { $0.isVisible && String(describing: type(of: $0)) == "AlertWindow" }
    }

    /// A window's frame view (title bar and toolbar included) as `cacheDisplay` draws it.
    private static func bitmap(_ window: NSWindow) -> NSBitmapImageRep? {
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    private static func write(_ rep: NSBitmapImageRep, _ path: String) -> Bool {
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: URL(fileURLWithPath: path))
            return true
        } catch {
            return false
        }
    }

    /// Once per scheme: the app's appearance switched, everything redrawn, `body` run, the appearance put back.
    private static func perScheme(_ path: String, _ schemes: [ColorScheme], _ windows: () -> [NSWindow],
                                  _ body: (String) -> Bool) async -> [String] {
        let saved = NSApp.appearance
        defer { NSApp.appearance = saved }
        var written: [String] = []
        for scheme in schemes {
            NSApp.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            for w in windows() { w.displayIfNeeded() }
            try? await Task.sleep(for: .milliseconds(500))
            let p = schemes.count > 1 ? SVShell.DebugSnapshot.path(path, scheme) : path
            if body(p) { written.append(p) }
        }
        return written
    }

    private static func captureWindow(_ window: NSWindow, _ path: String, schemes: [ColorScheme]) async -> [String] {
        await perScheme(path, schemes, { [window] }) { p in
            guard let rep = bitmap(window) else { return false }
            return write(rep, p)
        }
    }

    /// The main window, and each alert panel over it drawn where it is on screen.
    private static func captureAll(_ model: AppModel, _ path: String, schemes: [ColorScheme]) async -> [String] {
        guard let main = WindowSizer.main(model.config) else { return [] }
        // The alerts and the sheet hanging on the main window (the end-of-batch sheet, C2-V5).
        let panels = { alertPanels() + [main.attachedSheet].compactMap { $0 } }
        return await perScheme(path, schemes, { [main] + panels() }) { p in
            guard let base = bitmap(main) else { return false }
            guard let context = NSGraphicsContext(bitmapImageRep: base) else { return false }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            for panel in panels() {
                guard let rep = bitmap(panel) else { continue }
                let f = panel.frame, m = main.frame
                let image = NSImage(size: f.size)
                image.addRepresentation(rep)
                image.draw(in: NSRect(x: f.minX - m.minX, y: f.minY - m.minY, width: f.width, height: f.height),
                           from: .zero, operation: .sourceOver, fraction: 1)
            }
            context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()
            return write(base, p)
        }
    }

    // MARK: - Settings (ST1–ST5)

    /// A click on the toolbar item of that tab (the SwiftUI TabView of the Settings scene).
    private static func settingsTab(_ name: String, _ model: AppModel) -> String {
        guard let window = settingsWindow(model), let toolbar = window.toolbar else { return "no settings window" }
        let title = model.t("app.settings.tab.\(name)")
        guard let item = toolbar.items.first(where: { $0.label == title }) else {
            return "no item «\(title)» in " + toolbar.items.map(\.label).joined(separator: "|")
        }
        if let action = item.action { NSApp.sendAction(action, to: item.target, from: item) }
        toolbar.selectedItemIdentifier = item.itemIdentifier
        return "ok · \(window.title)"
    }

    private static func settingsFeed(_ args: [String], _ model: AppModel) -> String {
        switch args.first ?? "" {
        case "redownload":
            guard args.count == 3, let done = Int64(args[1]), let total = Int64(args[2]) else { return "bad args" }
            model.redownload = (done * 1_000_000, total * 1_000_000)
        case "own":
            guard args.count >= 3 else { return "bad args" }
            // In memory only: `customFFmpeg` is saved by `chooseOwnFFmpeg`, not here.
            model.customFFmpeg = CustomFFmpeg(path: args[1], error: args.dropFirst(2).joined(separator: " "))
        case "update":
            switch args.count > 1 ? args[1] : "" {
            case "ok":
                model.lastUpdateResult = .upToDate
                model.updateAvailable = nil
            case "available":
                let version = args.count > 2 ? args[2] : "2.0.1"
                model.lastUpdateResult = .available(version: version, url: AppConfig.releasesURL)
                model.updateAvailable = (version, AppConfig.releasesURL)
            case "error":
                model.lastUpdateResult = .error("timed out")
                model.updateAvailable = nil
            default: return "bad args"
            }
        case "clear":
            model.redownload = nil
            model.customFFmpeg = model.defaults.string(forKey: DefaultsKey.customFFmpeg).map { CustomFFmpeg(path: $0) }
            model.lastUpdateResult = .upToDate
            model.updateAvailable = nil
        default:
            return "usage: settings-feed redownload|own|update|clear"
        }
        return "ok"
    }

    // MARK: - Alerts (O3, O4, O8)

    /// The non-modal ones through the app's own functions; O3 and O8c run modal
    /// in the app (a modal loop would stop the commands), so they are built here
    /// as `Alerts` builds them and presented without the loop: the same card.
    private static func showAlert(_ args: [String], _ model: AppModel) -> String {
        switch args.first ?? "" {
        case "quit":
            let b = model.batch
            let a = SVAlert(icon: AlertIconName.quit, tone: .yellow, title: model.t("app.alerts.quit_title"),
                            text: model.t("app.alerts.quit_text", ["name": b.name, "i": b.index, "n": b.total]))
            a.button(model.t("app.alerts.quit_btn"), role: .primary)
            a.button(model.t("app.common.cancel"))
            a.present(over: WindowSizer.main(model.config)) { _ in }
        case "close":
            Alerts.closeNotice(model)
        case "novideos":
            guard args.count > 1 else { return "usage: alert-show novideos <empty folder>" }
            // The real path: a folder without videos dropped on the list (subfolders not searched).
            model.add([URL(fileURLWithPath: args[1])], subfolders: false)
        case "already":
            guard args.count > 1 else { return "usage: alert-show already <paths>" }
            model.add(args[1].split(separator: ",").map { URL(fileURLWithPath: String($0)) })
        case "import":
            let a = SVAlert(icon: AlertIconName.info, tone: .accent, title: model.t("app.alerts.import_title", ["name": "corrections.txt"]),
                            text: model.tn("app.alerts.import_text", 4))
            a.button(model.t("app.alerts.import_add"), role: .primary)
            a.button(model.t("app.alerts.import_replace"))
            a.button(model.t("app.common.cancel"))
            a.present(over: WindowSizer.main(model.config)) { _ in }
        case "update":
            Alerts.updateResult(model, .available(version: "2.0.1", url: AppConfig.releasesURL))
        default:
            return "usage: alert-show quit|close|novideos <folder>|already <paths>|import|update"
        }
        return "ok · \(alertPanels().count) alert(s) up"
    }

    // MARK: - Menus (O9, O10, I2)

    /// Our windows on screen: the menus (layer 101, kCGPopUpMenuWindowLevel) and the others, with their bounds.
    private static func ownWindows() -> (menus: [(CGWindowID, CGRect)], others: [CGRect]) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        var menus: [(CGWindowID, CGRect)] = [], others: [CGRect] = []
        for info in list where (info[kCGWindowOwnerPID as String] as? Int32) == pid {
            guard let id = info[kCGWindowNumber as String] as? Int,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dict as CFDictionary) else { continue }
            if (info[kCGWindowLayer as String] as? Int) == Int(CGWindowLevelForKey(.popUpMenuWindow)) {
                menus.append((CGWindowID(id), rect))
            } else {
                others.append(rect)
            }
        }
        return (menus, others)
    }

    /// `screencapture -l` of a menu gives the menu together with the window it
    /// opened over (their union), and the menu's window is wider than the menu
    /// (room for its shadow): the menu is cut out of it, 16 pt around it.
    private static func cropToMenu(_ path: String, menu: CGRect, size: NSSize, others: [CGRect]) {
        guard let image = NSImage(contentsOfFile: path), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let scale = 2.0, pad = 16.0
        let union = others.filter { $0.intersects(menu) }.reduce(menu) { $0.union($1) }
        guard abs(Double(cg.width) - union.width * scale) < 4 else { return }
        let visible = CGRect(x: menu.midX - size.width / 2 - pad, y: menu.midY - size.height / 2 - pad,
                             width: size.width + pad * 2, height: size.height + pad * 2).intersection(menu)
        let crop = CGRect(x: (visible.minX - union.minX) * scale, y: (visible.minY - union.minY) * scale,
                          width: visible.width * scale, height: visible.height * scale)
        guard let cut = cg.cropping(to: crop) else { return }
        _ = write(NSBitmapImageRep(cgImage: cut), path)
    }

    /// Opens the menu, and while AppKit tracks it a timer in the common modes
    /// runs `screencapture -l` on its window (the menu is drawn by the window
    /// server: `cacheDisplay` cannot reach it), then closes it.
    private static func menuShot(_ which: String, _ path: String, _ model: AppModel) async -> String {
        var result = "no menu window"
        var ticks = 0
        nonisolated(unsafe) var opened: NSMenu?   // read and written on the main thread only (the timer runs there)
        let shoot = {
            let (menus, others) = ownWindows()
            guard !menus.isEmpty else { return }
            var written: [String] = []
            for (i, (id, rect)) in menus.enumerated() {
                let p = menus.count > 1 ? path.replacingOccurrences(of: ".png", with: "-\(i + 1).png") : path
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                task.arguments = ["-x", "-o", "-l\(id)", p]
                try? task.run()
                task.waitUntilExit()
                guard task.terminationStatus == 0 else { continue }
                cropToMenu(p, menu: rect, size: (opened ?? PopupMenuTracking.open)?.size ?? rect.size, others: others)
                written.append(p)
            }
            result = written.isEmpty ? "screencapture failed" : written.joined(separator: " ")
        }
        let timer = Timer(timeInterval: 0.1, repeats: true) { t in
            MainActor.assumeIsolated {
                ticks += 1
                let tracking = opened != nil || PopupMenuTracking.open != nil
                if tracking, ticks >= 7, result == "no menu window" {
                    shoot()
                    if let opened { opened.cancelTracking() } else { PopupMenuTracking.cancel() }
                    t.invalidate()
                } else if ticks > 80 {
                    opened?.cancelTracking()
                    PopupMenuTracking.cancel()
                    t.invalidate()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        guard let main = WindowSizer.main(model.config), let content = main.contentView else { timer.invalidate(); return "no window" }
        switch which {
        case "lang":
            // The inspector's language menu, opened the way O7's button opens it.
            model.showLanguageMenu()
            _ = await DebugQA.wait(9) { !timer.isValid }
            return result
        case "dock":
            guard let menu = NSApp.delegate?.applicationDockMenu?(NSApp) else { timer.invalidate(); return "no dock menu" }
            opened = menu
            menu.popUp(positioning: nil, at: NSPoint(x: content.bounds.midX, y: content.bounds.midY), in: content)
        default:
            guard let index = Int(which), let items = NSApp.mainMenu?.items, items.indices.contains(index),
                  let menu = items[index].submenu else { timer.invalidate(); return "no such menu" }
            opened = menu
            // Each menu under its own title, as if the menu bar were inside the window.
            menu.popUp(positioning: nil, at: NSPoint(x: 40 + CGFloat(index) * 30, y: content.isFlipped ? 40 : content.bounds.maxY - 40), in: content)
        }
        timer.invalidate()
        return "\(items(opened)) · \(result)"
    }

    private static func items(_ menu: NSMenu?) -> String {
        guard let menu else { return "-" }
        return "\(menu.title): " + menu.items.filter { !$0.isSeparatorItem }.map { ($0.isEnabled ? "" : "(off)") + $0.title }.joined(separator: "|")
    }

    /// The Dock tile's own view (the bar the app draws; the badge is the Dock's) at 2x.
    private static func dockTile(_ path: String, _ model: AppModel) -> String {
        let view = NSApp.dockTile.contentView ?? {
            DockProgress.update(model.config, fraction: 0.47, badge: "2")
            return NSApp.dockTile.contentView
        }()
        guard let view else { return "no dock view" }
        view.frame = NSRect(x: 0, y: 0, width: 128, height: 128)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 256, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        return write(rep, path) ? path : "write failed"
    }

    // MARK: - Pictures

    /// PNGs on a grid (row by row), 24 pt apart, on the page's background of that appearance.
    private static func compose(_ out: String, dark: Bool, columns: Int, _ inputs: [String]) -> String {
        let images = inputs.compactMap { NSImage(contentsOfFile: $0) }
        guard !images.isEmpty else { return "no images" }
        // The PNGs are 2x: their size in points is half their pixels.
        let sizes = images.map { img -> NSSize in
            let rep = img.representations.first
            return NSSize(width: CGFloat(rep?.pixelsWide ?? 0) / 2, height: CGFloat(rep?.pixelsHigh ?? 0) / 2)
        }
        let gap: CGFloat = 24, pad: CGFloat = 24
        let rows = stride(from: 0, to: images.count, by: columns).map { Array($0..<min($0 + columns, images.count)) }
        let colWidth = (0..<columns).map { c in rows.compactMap { $0.count > c ? sizes[$0[c]].width : nil }.max() ?? 0 }
        let rowHeight = rows.map { r in r.map { sizes[$0].height }.max() ?? 0 }
        let width = colWidth.reduce(0, +) + gap * CGFloat(columns - 1) + pad * 2
        let height = rowHeight.reduce(0, +) + gap * CGFloat(rows.count - 1) + pad * 2
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * 2), pixelsHigh: Int(height * 2), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return "no bitmap" }
        // In points before the context exists: the drawing below is in points, at 2x.
        rep.size = NSSize(width: width, height: height)
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return "no context" }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        appearance.performAsCurrentDrawingAppearance {
            NSColor(SV.bg).setFill()
            NSRect(x: 0, y: 0, width: width, height: height).fill()
        }
        var y = height - pad
        for (r, row) in rows.enumerated() {
            var x = pad
            for (c, i) in row.enumerated() {
                let s = sizes[i]
                images[i].draw(in: NSRect(x: x, y: y - s.height, width: s.width, height: s.height), from: .zero, operation: .sourceOver, fraction: 1)
                x += colWidth[c] + gap
            }
            y -= rowHeight[r] + gap
        }
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return write(rep, out) ? out : "write failed"
    }
}
#endif
