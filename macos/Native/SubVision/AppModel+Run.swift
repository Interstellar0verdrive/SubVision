// SPDX-License-Identifier: MIT
// The batch (F5.1): `batch.start`, the rows' steps and outcomes, Stop and
// Stop All, the end-of-batch sheet and the notifications. The stubs below
// keep the app building until F5.1 fills them.

import SVShell

extension AppModel {
    func startBatch() { log.info("batch.start: not yet (\(readyVideos.count) ready)") }
    func stopCurrentFile() {}
    func stopAll() {}

    /// The `batch.*` events, from the one consumer in `AppModel.listen()`.
    func handleBatch(_ message: EngineMessage, name: String) {
        log.debug("event \(name)")
    }
}
