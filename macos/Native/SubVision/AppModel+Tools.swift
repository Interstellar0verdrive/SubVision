// SPDX-License-Identifier: MIT
// The tools: the first-launch window's decisions (D12), the warm-up after a
// macOS update, Download Again, Homebrew's or "A folder of mine…" ffmpeg of
// Settings › Tools, the lists of Settings › Lists.

import AppKit
import SVShell
import UniformTypeIdentifiers

/// "Use my own ffmpeg" (Settings › Tools, O5b): the path chosen and what the engine made of it.
struct CustomFFmpeg: Equatable {
    var path: String
    var version: String?
    var ffprobeVersion: String?
    /// The engine's `bad_tool` message, when it does not start.
    var error: String?
    /// ffprobe is not next to it (design note 20).
    var ffprobeMissing = false

    /// `ffmpeg`'s folder, or the folder chosen.
    var folder: URL {
        let url = URL(fileURLWithPath: path)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue { return url }
        return url.deletingLastPathComponent()
    }
}

/// ffmpeg and ffprobe in Homebrew's folder (design note 54).
struct HomebrewFFmpeg: Equatable, Sendable {
    var folder: String
    var version: String
    var ffmpegPath: String { (folder as NSString).appendingPathComponent("ffmpeg") }
}

extension AppModel {
    /// After `tools.status`: the window for what's missing, the preparation on
    /// the first launch or after a macOS update (T4), and the Vision check (T3).
    func decideTools(_ status: ToolsStatusReply) {
        let buildChanged = defaults.string(forKey: DefaultsKey.warmupBuild) != Self.macOSBuild
        tools.warmupLanguages = [ocrLanguage]
        tools.decide(status, runTasks: tools.runtimePending || buildChanged)
        if hello?.vision == false, tools.showsWindow {
            // The warm-up would never answer: the row fails now, with the reason (API.md 29).
            tools.progress(ToolProgress(key: AppConfig.warmupKey, state: .failed, error: "vision"))
        }
    }

    /// `tools.progress` outside the tools window: Settings › Tools › Download Again.
    func toolProgress(_ p: ToolProgress) {
        guard !tools.showsWindow, redownload != nil || p.state == .running else { return }
        var done: Int64 = 0, total: Int64 = 0
        let sizes = AppConfig.downloadKeys.map { _ in AppConfig.ffmpegMB * 1_000_000 }
        total = sizes.reduce(0, +)
        let index = AppConfig.downloadKeys.firstIndex(of: p.key) ?? 0
        done = sizes.prefix(index).reduce(0, +) + (p.state == .done ? sizes[index] : min(p.bytes ?? 0, sizes[index]))
        redownload = (done, total)
    }

    /// Settings › Tools › Download Again: ffmpeg and ffprobe, checked again.
    func redownloadTools() {
        guard redownload == nil else { return }
        redownload = (0, Int64(AppConfig.downloadKeys.count) * AppConfig.ffmpegMB * 1_000_000)
        Task {
            do {
                let reply = try await engine.toolsInstall(AppConfig.downloadKeys)
                if !reply.started { redownload = nil }
            } catch {
                log.error("tools.install: \(error)")
                redownload = nil
            }
        }
    }

    /// The saved "my own" ffmpeg, told to the engine after every `hello`.
    func applyCustomFFmpeg() async {
        guard let custom = customFFmpeg else { return }
        await useOwnFFmpeg(custom.path)
    }

    /// Settings › Tools › A folder of mine…: a folder with both `ffmpeg` and `ffprobe` (design note 54).
    func chooseOwnFFmpeg() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.message = t("app.settings.ffmpeg_panel")
        panel.prompt = t("app.settings.ffmpeg_panel_btn")
        let start = customFFmpeg?.folder.path
            ?? Self.homebrewFolders.first { FileManager.default.fileExists(atPath: $0) } ?? NSHomeDirectory()
        panel.directoryURL = URL(fileURLWithPath: start)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let missing = ["ffmpeg", "ffprobe"].filter {
            !FileManager.default.isExecutableFile(atPath: url.appendingPathComponent($0).path)
        }
        if !missing.isEmpty {
            // Told now, and nothing changes: the tools in use stay as they were.
            Alerts.error(self, title: t("app.settings.ffmpeg_missing_title"),
                         text: t("app.settings.ffmpeg_missing_text", ["folder": url.path, "tools": missing.joined(separator: " · ")]))
            return
        }
        Task { await useOwnFFmpeg(url.appendingPathComponent("ffmpeg").path) }
    }

    /// Where Homebrew puts its tools (Apple silicon, then Intel).
    nonisolated static let homebrewFolders = ["/opt/homebrew/bin", "/usr/local/bin"]

    /// Homebrew's ffmpeg, when its folder has ffprobe too: a ready item of the menu.
    func findHomebrewFFmpeg() {
        Task.detached(priority: .utility) {
            var found: HomebrewFFmpeg?
            for folder in Self.homebrewFolders {
                let dir = URL(fileURLWithPath: folder)
                let ffmpeg = dir.appendingPathComponent("ffmpeg"), ffprobe = dir.appendingPathComponent("ffprobe")
                guard FileManager.default.isExecutableFile(atPath: ffmpeg.path),
                      FileManager.default.isExecutableFile(atPath: ffprobe.path),
                      let version = Self.toolVersion(ffmpeg) else { continue }
                found = HomebrewFFmpeg(folder: folder, version: version)
                break
            }
            await MainActor.run { [found] in self.homebrewFFmpeg = found }
        }
    }

    /// Settings › Tools › "Homebrew · 8.0 (/opt/homebrew/bin)".
    func useHomebrewFFmpeg(_ brew: HomebrewFFmpeg) {
        Task { await useOwnFFmpeg(brew.ffmpegPath) }
    }

    func useOwnFFmpeg(_ path: String) async {
        var custom = CustomFFmpeg(path: path)
        customFFmpeg = custom
        defaults.set(path, forKey: DefaultsKey.customFFmpeg)
        do {
            let reply = try await engine.toolsUse(ffmpeg: path)
            custom.version = reply.ffmpeg?.version
        } catch {
            custom.error = (error as? EngineError).flatMap { if case .remote(_, let m, _) = $0 { m } else { nil } } ?? String(describing: error)
            log.error("tools.use \(path): \(error)")
        }
        let probe = custom.folder.appendingPathComponent("ffprobe")
        if FileManager.default.isExecutableFile(atPath: probe.path) {
            custom.ffprobeVersion = Self.toolVersion(probe)
        } else {
            custom.ffprobeMissing = true
        }
        customFFmpeg = custom
        toolsStatus = try? await engine.toolsStatus()
    }

    /// Back to the downloaded ones.
    func useBundledFFmpeg() {
        customFFmpeg = nil
        defaults.removeObject(forKey: DefaultsKey.customFFmpeg)
        Task {
            _ = try? await engine.toolsUse(ffmpeg: nil)
            toolsStatus = try? await engine.toolsStatus()
        }
    }

    /// "9.0.2" from `<tool> -version` (the engine does the same for ffmpeg).
    nonisolated static func toolVersion(_ binary: URL) -> String? {
        let p = Process()
        p.executableURL = binary
        p.arguments = ["-hide_banner", "-version"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let line = String(data: data, encoding: .utf8)?.split(separator: "\n").first else { return nil }
        let parts = line.split(separator: " ")
        guard parts.count >= 3, parts[1] == "version" else { return nil }
        return String(parts[2].split(separator: "-").first ?? parts[2])
    }

    // MARK: - Lists (Settings › Lists)

    func refreshLists() {
        Task { lists = try? await engine.listsStatus() }
    }

    /// Edit…: the file in the system's text editor.
    func editList(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func showListInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// Import…: a text file, then O8c asks whether to replace or append.
    func importList(kind: String) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, .text]
        panel.message = t("app.settings.import")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let current = kind == "ignore" ? lists?.ignore : lists?.corrections
        let choice = Alerts.importList(self, name: url.lastPathComponent, existing: current?.count ?? 0)
        guard let choice else { return }
        Task {
            var source = url
            if choice == .append, let currentPath = current?.path {
                // The engine replaces the list: the appended file is built here.
                let old = (try? String(contentsOfFile: currentPath, encoding: .utf8)) ?? ""
                let new = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                let merged = old.hasSuffix("\n") || old.isEmpty ? old + new : old + "\n" + new
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("subvision-import-\(UUID().uuidString).txt")
                do { try merged.write(to: tmp, atomically: true, encoding: .utf8) } catch { log.error("import: \(error)"); return }
                source = tmp
            }
            do {
                lists = try await engine.listsImport(kind: kind, path: source.path)
            } catch {
                log.error("lists.import \(kind): \(error)")
                Alerts.error(self, title: t("app.settings.import"), text: String(describing: error))
            }
        }
    }
}
