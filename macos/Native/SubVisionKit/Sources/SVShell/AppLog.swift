// SPDX-License-Identifier: MIT
// Copied and adapted from the native macOS app of AnimeUp (AnimeUp/AppModel.swift,
// `AppLog`), by the same author: the subsystem and the file are parameters.

import Foundation
import OSLog

/// The app's log: the unified log plus `<state>/records/app.log` (one line per
/// entry), so it can be read without Console.
public struct AppLog: @unchecked Sendable {
    private let logger: Logger
    private let lock = NSLock()
    public var file: URL?

    public init(subsystem: String, category: String = "app", file: URL? = nil) {
        logger = Logger(subsystem: subsystem, category: category)
        self.file = file
    }

    public func info(_ s: String) { write("INFO", s); logger.info("\(s, privacy: .public)") }
    public func error(_ s: String) { write("ERROR", s); logger.error("\(s, privacy: .public)") }
    public func debug(_ s: String) { logger.debug("\(s, privacy: .public)") }

    private func write(_ level: String, _ s: String) {
        guard let file else { return }
        lock.lock(); defer { lock.unlock() }
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(level) \(s)\n"
        if let h = try? FileHandle(forWritingTo: file) {
            h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
        } else {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(line.utf8).write(to: file)
        }
    }

    /// The log the shell's own pieces write to; the app replaces it at launch.
    public nonisolated(unsafe) static var shared = AppLog(subsystem: "io.github.interstellar0verdrive.subvision")
}

/// Opens a log file in Console.
@MainActor
public func openLogInConsole(_ path: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    p.arguments = ["-a", "Console", path]
    try? p.run()
}
