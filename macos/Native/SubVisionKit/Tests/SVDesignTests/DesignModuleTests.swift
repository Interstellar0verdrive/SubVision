// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI
import Testing
@testable import SVDesign

@Test func cssColours() {
    let hex = NSColor(css: "#2AC9DE").usingColorSpace(.sRGB)!
    #expect(abs(hex.redComponent - 42 / 255) < 0.002)
    #expect(abs(hex.greenComponent - 201 / 255) < 0.002)
    #expect(abs(hex.blueComponent - 222 / 255) < 0.002)
    #expect(hex.alphaComponent == 1)
    let rgba = NSColor(css: "rgba(16,24,40,.5)").usingColorSpace(.sRGB)!
    #expect(abs(rgba.redComponent - 16 / 255) < 0.002)
    #expect(abs(rgba.alphaComponent - 0.5) < 0.002)
    // Anything else is magenta, so it shows.
    let bad = NSColor(css: "oops").usingColorSpace(.sRGB)!
    #expect(bad.redComponent == 1 && bad.greenComponent == 0 && bad.blueComponent == 1)
}

@Test func lineHeights() {
    #expect(SVType.normalLineHeight(13, mono: false) == 15)
    #expect(SVType.normalLineHeight(12, mono: true) == 14)
    #expect(SVType.normalLineHeight(40, mono: false) == 47)   // off the table: the factor
    #expect(SVFont.body.lineHeight == 19.5)
    #expect(abs(SVFont.small.lineHeight - 17.4) < 0.001)
}

@Test func chromeDefaults() {
    let chrome = SVChrome.default
    #expect(chrome.sidebarWidth == 236 && chrome.collapseBelow == 1240)
    #expect(chrome.minWindow == CGSize(width: 720, height: 640))
    let narrow = SVChrome(sidebarWidth: 200, collapseBelow: 1000)
    #expect(narrow.sidebarWidth == 200 && narrow.page.top == 28)
}

@Test func alertIconFallsBackToSymbol() {
    // The test bundle has no asset catalog: every name comes back as a symbol.
    #expect(AlertIconSource.default.image("stop-file") != nil)
    #expect(AlertIconSource.default.image("no-such-icon") != nil)
    #expect(AlertIconSource.symbols.image("error") != nil)
    let none = AlertIconSource { _ in nil }
    #expect(none.image("info") == nil)
}

/// The tokens change with the appearance: one PNG per scheme, a background
/// pixel light in light and dark in dark.
@MainActor
@Test(arguments: [ColorScheme.light, ColorScheme.dark])
func galleryRenders(scheme: ColorScheme) throws {
    let dir = galleryDirectory()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let path = dir.appendingPathComponent(scheme == .dark ? "dark.png" : "light.png")
    let image = try #require(renderGallery(scheme: scheme))
    let cg = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
    let png = try #require(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
    try png.write(to: path)
    let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
    #expect((attributes[.size] as? Int ?? 0) > 50_000)
    let rep = try #require(NSBitmapImageRep(data: try Data(contentsOf: path)))
    #expect(rep.pixelsWide >= Int(SVDesignGallery.width) * 2)
    #expect(rep.pixelsHigh > 1000)
    // The page's own background, in the corner of the padding.
    let pixel = try #require(rep.colorAt(x: 6, y: 6)?.usingColorSpace(.sRGB))
    let luminance = 0.2126 * pixel.redComponent + 0.7152 * pixel.greenComponent + 0.0722 * pixel.blueComponent
    if scheme == .dark {
        #expect(luminance < 0.15, "dark background, got \(pixel)")
    } else {
        #expect(luminance > 0.85, "light background, got \(pixel)")
    }
}

@MainActor
private func renderGallery(scheme: ColorScheme) -> NSImage? {
    let renderer = ImageRenderer(content: SVDesignGallery().environment(\.colorScheme, scheme))
    renderer.scale = 2
    return renderer.nsImage
}

private func galleryDirectory() -> URL {
    if let dir = ProcessInfo.processInfo.environment["SVDESIGN_GALLERY_DIR"], !dir.isEmpty {
        return URL(fileURLWithPath: dir)
    }
    return URL(fileURLWithPath: "/private/tmp/claude-503/-Users-albertoangeli--claude-spares-spare-AKF5Ex/f95acff4-3b10-4790-bb56-d271ac0eb05c/scratchpad/svdesign-gallery")
}
