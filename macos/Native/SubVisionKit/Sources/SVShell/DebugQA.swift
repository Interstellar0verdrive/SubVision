// SPDX-License-Identifier: MIT
// Copied and adapted from the native macOS app of AnimeUp (AnimeUp/DebugQA.swift,
// `watchCommands`), by the same author: the commands themselves are the app's,
// through a handler.

import Foundation

@MainActor
public enum DebugQA {
    /// `<PREFIX>COMMANDS=<file>`: the app reads that file every half second, runs
    /// each line through `handler` and empties it; what happened goes to `<file>.out`
    /// (one line per command: the command, a tab, the reply). Lets the dev app be
    /// driven from the shell, without menus, panels or the screen.
    public static func watchCommands(_ file: URL, interval: Duration = .milliseconds(500),
                                     handler: @escaping @MainActor (String) async -> String) -> Task<Void, Never> {
        let out = file.appendingPathExtension("out")
        return Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let text = try? String(contentsOf: file, encoding: .utf8), !text.isEmpty else { continue }
                try? "".write(to: file, atomically: true, encoding: .utf8)
                for line in text.split(separator: "\n").map(String.init) where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    let reply = await handler(line)
                    AppLog.shared.info("QA: command \(line) → \(reply)")
                    let entry = "\(line)\t\(reply)\n"
                    if let h = try? FileHandle(forWritingTo: out) { h.seekToEndOfFile(); h.write(Data(entry.utf8)); try? h.close() }
                    else { try? entry.write(to: out, atomically: true, encoding: .utf8) }
                }
            }
        }
    }

    /// Starts watching when `<PREFIX>COMMANDS` is set.
    @discardableResult
    public static func watchIfAsked(_ config: AppShellConfig, env: [String: String] = ProcessInfo.processInfo.environment,
                                    handler: @escaping @MainActor (String) async -> String) -> Task<Void, Never>? {
        guard let file = config.environment("COMMANDS", env) else { return nil }
        return watchCommands(URL(fileURLWithPath: file), handler: handler)
    }

    /// Polls `condition` every half second, up to `seconds`; true if it came true.
    public static func wait(_ seconds: Double, _ condition: @MainActor () -> Bool) async -> Bool {
        var left = seconds
        while left > 0 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(500))
            left -= 0.5
        }
        return condition()
    }
}
