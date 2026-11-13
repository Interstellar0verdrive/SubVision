// SPDX-License-Identifier: MIT
// Preview (F5.2): `preview.frames` with its progress and stop, the frames
// found, the band handles and Try OCR. The stub below keeps the app building
// until F5.2 fills it.

import SVShell

/// Everything the Preview page shows; `AppModel.preview` holds it.
struct PreviewState {}

extension AppModel {
    /// The `preview.*` events, from the one consumer in `AppModel.listen()`.
    func handlePreview(_ message: EngineMessage, name: String) {
        log.debug("event \(name)")
    }
}
