// SPDX-License-Identifier: MIT
// Adapted from the AnimeUp native app (AnimeUpKit/Sources/Engine/Sidecar.swift),
// by the same author. SubVision does not depend on AnimeUp. Changed here: one
// reader thread delivers the lines and the exit status in order (no
// readability handler plus a separate exit source).

import Darwin
import Foundation

/// One run of `<launcher> serve`: spawned with posix_spawn in its own process
/// group, stdin/stdout as pipes, stderr appended to a log file.
///
/// The process group matters: the launcher is a bash script that execs
/// Python, and Python starts helpers (ffmpeg, ffprobe). Stopping signals the
/// whole group, so nothing is left behind.
///
/// Everything the sidecar says comes out of `messages`, in order: every
/// complete stdout line, then `.exited(status)` once, then the stream ends.
final class Sidecar: @unchecked Sendable {
    enum Message: Sendable {
        case line(Data)
        /// The exit code, or minus the signal number when killed by a signal.
        case exited(Int32)
    }

    let pid: pid_t
    let messages: AsyncStream<Message>
    private let input: FileHandle
    private let lock = NSLock()
    private var exited = false

    init(configuration: EngineConfiguration) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: configuration.logFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        Self.rotate(configuration.logFile)
        if !fm.fileExists(atPath: configuration.logFile.path) {
            fm.createFile(atPath: configuration.logFile.path, contents: nil)
        }
        guard fm.isExecutableFile(atPath: configuration.launcher.path) else {
            throw EngineError.launcherMissing(configuration.launcher.path)
        }

        var stdinPipe: [Int32] = [0, 0]
        var stdoutPipe: [Int32] = [0, 0]
        guard pipe(&stdinPipe) == 0, pipe(&stdoutPipe) == 0 else { throw EngineError.spawnFailed(errno) }
        let logFD = open(configuration.logFile.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard logFD >= 0 else { throw EngineError.spawnFailed(errno) }

        var actions: posix_spawn_file_actions_t? = nil
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, stdinPipe[0], 0)
        posix_spawn_file_actions_adddup2(&actions, stdoutPipe[1], 1)
        posix_spawn_file_actions_adddup2(&actions, logFD, 2)
        posix_spawn_file_actions_addchdir(&actions, configuration.stateFolder.path)

        var attributes: posix_spawnattr_t? = nil
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setpgroup(&attributes, 0)
        // CLOEXEC_DEFAULT: only the three descriptors above reach the child,
        // nothing else the app has open.
        // SETSIGMASK with an empty mask: the thread that spawns may block
        // signals (Swift concurrency threads do), and a blocked SIGTERM would
        // be inherited by every helper the engine starts: Stop would do nothing.
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT
                                                    | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
        var noMask = sigset_t()
        sigemptyset(&noMask)
        posix_spawnattr_setsigmask(&attributes, &noMask)
        var defaults = sigset_t()
        sigemptyset(&defaults)
        sigaddset(&defaults, SIGPIPE)
        sigaddset(&defaults, SIGINT)
        sigaddset(&defaults, SIGTERM)
        posix_spawnattr_setsigdefault(&attributes, &defaults)

        try fm.createDirectory(at: configuration.stateFolder, withIntermediateDirectories: true)
        let argv: [String] = [configuration.launcher.path, "serve"]
        let env = configuration.environment().map { "\($0.key)=\($0.value)" }
        var cArgv = argv.map { strdup($0) } + [nil]
        var cEnv = env.map { strdup($0) } + [nil]
        defer {
            cArgv.forEach { free($0) }
            cEnv.forEach { free($0) }
        }
        var child: pid_t = 0
        let status = posix_spawn(&child, configuration.launcher.path, &actions, &attributes, &cArgv, &cEnv)
        close(stdinPipe[0]); close(stdoutPipe[1]); close(logFD)
        guard status == 0 else {
            close(stdinPipe[1]); close(stdoutPipe[0])
            throw EngineError.spawnFailed(status)
        }
        pid = child
        // A dead engine must give EPIPE, not kill the app with SIGPIPE.
        _ = fcntl(stdinPipe[1], F_SETNOSIGPIPE, 1)
        input = FileHandle(fileDescriptor: stdinPipe[1], closeOnDealloc: true)

        let (stream, sink) = AsyncStream<Message>.makeStream(bufferingPolicy: .unbounded)
        messages = stream
        let outputFD = stdoutPipe[0]
        let reader = Thread { [self] in
            Self.readLoop(fd: outputFD, pid: child, sink: sink)
            self.markExited()
            sink.yield(.exited(Self.waitStatus(pid: child)))
            sink.finish()
        }
        reader.name = "SVEngine.sidecar.reader"
        reader.start()
    }

    /// Blocking reads until EOF, one line per message (empty lines dropped).
    private static func readLoop(fd: Int32, pid: pid_t, sink: AsyncStream<Message>.Continuation) {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 65_536)
        while true {
            let n = read(fd, &chunk, chunk.count)
            if n > 0 {
                buffer.append(chunk, count: n)
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let line = buffer[buffer.startIndex..<nl]
                    if !line.isEmpty { sink.yield(.line(Data(line))) }
                    buffer.removeSubrange(buffer.startIndex...nl)
                }
            } else if n == 0 || errno != EINTR {
                break
            }
        }
        close(fd)
    }

    /// Reaps the child: exit code, or minus the signal number.
    private static func waitStatus(pid: pid_t) -> Int32 {
        var raw: Int32 = 0
        while waitpid(pid, &raw, 0) < 0 && errno == EINTR {}
        let signal = raw & 0x7f
        return signal == 0 ? (raw >> 8) & 0xff : -signal
    }

    /// Keeps two files of ~5 MB: `engine.log` and `engine.1.log`.
    static func rotate(_ log: URL, limit: Int = 5_000_000) {
        let fm = FileManager.default
        guard let size = (try? fm.attributesOfItem(atPath: log.path))?[.size] as? Int, size > limit else { return }
        let old = log.deletingPathExtension().appendingPathExtension("1.log")
        try? fm.removeItem(at: old)
        try? fm.moveItem(at: log, to: old)
    }

    private func markExited() {
        lock.lock(); exited = true; lock.unlock()
    }

    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return !exited
    }

    func send(_ line: Data) throws {
        var data = line
        data.append(0x0A)
        do {
            try input.write(contentsOf: data)
        } catch {
            throw EngineError.notRunning
        }
    }

    /// Closes stdin (the engine exits on EOF), then signals the group.
    func stop(grace: TimeInterval = 2) {
        try? input.close()
        let pid = self.pid
        DispatchQueue.global().asyncAfter(deadline: .now() + grace) { [weak self] in
            guard let self, self.isRunning else { return }
            kill(-pid, SIGTERM)
            DispatchQueue.global().asyncAfter(deadline: .now() + grace) { [weak self] in
                guard let self, self.isRunning else { return }
                kill(-pid, SIGKILL)
            }
        }
    }

    /// Immediately: for the app quitting.
    func terminateNow() {
        try? input.close()
        kill(-pid, SIGTERM)
    }
}
