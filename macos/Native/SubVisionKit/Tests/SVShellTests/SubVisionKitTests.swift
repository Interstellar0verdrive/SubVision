// SPDX-License-Identifier: MIT
import Testing
@testable import SVShell

@Test func versionAndModules() {
    #expect(SubVisionKit.version == "0.1.0")
    #expect(SubVisionKit.modules == ["SVEngine", "SVDesign", "SVLocalization", "SVShell"])
}
