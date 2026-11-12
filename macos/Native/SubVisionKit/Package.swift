// swift-tools-version: 6.2
// SPDX-License-Identifier: MIT
// SubVisionKit: the parts of the SubVision app that don't need the app target.
//   SVEngine        the sidecar client: spawns `subvision serve`, speaks JSON lines
//   SVDesign        colour tokens (light and dark), type styles, buttons, chrome
//   SVLocalization  the localiser: JSON catalogues per language, live switching
//   SVShell         the app frame: window, settings, tools setup, log, Dock, debug
import PackageDescription

let package = Package(
    name: "SubVisionKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SVEngine", targets: ["SVEngine"]),
        .library(name: "SVDesign", targets: ["SVDesign"]),
        .library(name: "SVLocalization", targets: ["SVLocalization"]),
        .library(name: "SVShell", targets: ["SVShell"]),
    ],
    targets: [
        .target(name: "SVEngine"),
        .target(name: "SVDesign"),
        .target(name: "SVLocalization"),
        .target(name: "SVShell", dependencies: ["SVEngine", "SVDesign", "SVLocalization"]),
        .testTarget(name: "SVEngineTests", dependencies: ["SVEngine"], resources: [.copy("Fixtures")]),
        .testTarget(name: "SVDesignTests", dependencies: ["SVDesign"]),
        .testTarget(name: "SVLocalizationTests", dependencies: ["SVLocalization"]),
        .testTarget(name: "SVShellTests", dependencies: ["SVShell"]),
    ],
    swiftLanguageModes: [.v5]
)
