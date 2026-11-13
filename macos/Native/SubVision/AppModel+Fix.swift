// SPDX-License-Identifier: MIT
// Sub fix (F5.3): the SRT chosen, the four options, `srt.fix` and its
// outcome. The stub below keeps the app building until F5.3 fills it.

import SVShell

/// Everything the Sub fix page shows; `AppModel.fix` holds it.
struct FixState {}

extension AppModel {
    var canRunFix: Bool { fixPath != nil && status == .ready }
    func runFix() { log.info("srt.fix: not yet") }
}
