// SPDX-License-Identifier: MIT
// The two bands drawn over a whole frame (design board A3, note 4): the
// dialogue band anchored to the bottom, the signs band to the top, both
// centred, with a name tag and, when editable, the draggable handles (height
// on the inner edge, width on the sides, symmetric, whole percent points).
// The geometry is the engine's `core.band_box`; the values are the
// UserDefaults keys of `OcrKey`, the same the inspector shows.

import AppKit
import SVShell
import SwiftUI

/// The two bands the engine reads.
enum PreviewBand: String, CaseIterable, Sendable {
    case dialogue, signs

    var heightKey: String { self == .dialogue ? OcrKey.bottomKeepPct : OcrKey.topKeepPct }
    var widthKey: String { self == .dialogue ? OcrKey.keepWPct : OcrKey.topKeepWPct }
    var defaultHeight: Int { self == .dialogue ? ocrDefaults.bottomKeepPct : ocrDefaults.topKeepPct }
    var defaultWidth: Int { self == .dialogue ? ocrDefaults.keepWPct : ocrDefaults.topKeepWPct }

    /// The plan's limits: dialogue 5–80 × 50–100, signs 5–50 × 50–100.
    var heightRange: ClosedRange<Int> { self == .dialogue ? 5...80 : 5...50 }
    var widthRange: ClosedRange<Int> { 50...100 }

    /// Design note 4: green dialogue, blue signs, in both appearances (`tavole.css`).
    var color: Color { self == .dialogue ? BandColors.dialogue : BandColors.signs }
    var tagText: Color { self == .dialogue ? BandColors.dialogueTagText : BandColors.signsTagText }
    var tone: SVTone { self == .dialogue ? .green : .accent }
    var nameKey: String { self == .dialogue ? "app.preview.band_dlg" : "app.preview.band_sig" }
    var helpKey: String { self == .dialogue ? "app.preview.dlg_handle" : "app.preview.sig_handle" }
}

enum BandColors {
    static let dialogue = Color(dark: "#3DD68C", light: "#3DD68C")
    static let signs = Color(dark: "#4DA3FF", light: "#4DA3FF")
    static let dialogueTagText = Color(dark: "#06210F", light: "#06210F")
    static let signsTagText = Color(dark: "#04182E", light: "#04182E")
    static let dialogueFill = Color(dark: "rgba(61,214,140,.10)", light: "rgba(61,214,140,.10)")
    static let signsFill = Color(dark: "rgba(77,163,255,.10)", light: "rgba(77,163,255,.10)")
}

/// A drag in progress: the band and the values it is at (the label by the handle).
struct BandDrag: Equatable {
    var band: PreviewBand
    var height: Int
    var width: Int
}

/// Which handle is held.
enum BandHandle: String, CaseIterable {
    /// The inner edge: the top of the dialogue band, the bottom of the signs band.
    case height
    case left, right
}

/// The band values in UserDefaults, through the inspector's keys. Every write
/// clamps to the plan's limits and rounds to the percent point, so the
/// handles, the DebugQA commands and the inspector agree.
enum BandValues {
    static var defaults: UserDefaults { .standard }

    static func height(_ band: PreviewBand) -> Int { defaults.value(band.heightKey, or: band.defaultHeight) }
    static func width(_ band: PreviewBand) -> Int { defaults.value(band.widthKey, or: band.defaultWidth) }
    static var signsOn: Bool { defaults.value(OcrKey.topBand, or: ocrDefaults.topBand) }

    @discardableResult
    static func setHeight(_ value: Int, _ band: PreviewBand) -> Int {
        let v = clamp(value, band.heightRange)
        if height(band) != v { defaults.set(v, forKey: band.heightKey) }
        return v
    }

    @discardableResult
    static func setWidth(_ value: Int, _ band: PreviewBand) -> Int {
        let v = clamp(value, band.widthRange)
        if width(band) != v { defaults.set(v, forKey: band.widthKey) }
        return v
    }

    static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int { min(range.upperBound, max(range.lowerBound, value)) }
}

/// The engine's geometry (`core.band_box`) on a frame drawn at `size`, and
/// what a pointer at a point means for the handle held.
enum BandGeometry {
    static func rect(_ band: PreviewBand, height: Int, width: Int, in size: CGSize) -> CGRect {
        let w = size.width * CGFloat(width) / 100
        let h = size.height * CGFloat(height) / 100
        let x = (size.width - w) / 2
        let y = band == .dialogue ? size.height - h : 0
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// The height a pointer at `y` (from the frame's top) asks for.
    static func height(_ band: PreviewBand, pointerY y: CGFloat, in size: CGSize) -> Int {
        guard size.height > 0 else { return BandValues.height(band) }
        let fraction = band == .dialogue ? (size.height - y) / size.height : y / size.height
        return BandValues.clamp(Int((fraction * 100).rounded()), band.heightRange)
    }

    /// The width a pointer at `x` asks for: symmetric, so the distance from the centre counts.
    static func width(_ band: PreviewBand, pointerX x: CGFloat, in size: CGSize) -> Int {
        guard size.width > 0 else { return BandValues.width(band) }
        let fraction = abs(x - size.width / 2) * 2 / size.width
        return BandValues.clamp(Int((fraction * 100).rounded()), band.widthRange)
    }

    /// The one function a drag goes through, from the gesture and from the
    /// DebugQA command alike: the pointer's place in the frame becomes the
    /// band's value in UserDefaults. Returns the values the band has now.
    @discardableResult
    @MainActor
    static func apply(_ band: PreviewBand, _ handle: BandHandle, pointer: CGPoint, in size: CGSize) -> BandDrag {
        switch handle {
        case .height: BandValues.setHeight(height(band, pointerY: pointer.y, in: size), band)
        case .left, .right: BandValues.setWidth(width(band, pointerX: pointer.x, in: size), band)
        }
        return BandDrag(band: band, height: BandValues.height(band), width: BandValues.width(band))
    }
}

/// The bands over the frame: `size` is the frame's drawn size. With
/// `editable` the handles show and drag; `drag` is the one in progress (the
/// label with the values, A3).
struct BandOverlay: View {
    var size: CGSize
    var editable: Bool
    @Binding var drag: BandDrag?
    @Environment(AppModel.self) private var model
    @AppStorage(OcrKey.bottomKeepPct) private var bottomHeight = ocrDefaults.bottomKeepPct
    @AppStorage(OcrKey.keepWPct) private var bottomWidth = ocrDefaults.keepWPct
    @AppStorage(OcrKey.topBand) private var signsOn = ocrDefaults.topBand
    @AppStorage(OcrKey.topKeepPct) private var signsHeight = ocrDefaults.topKeepPct
    @AppStorage(OcrKey.topKeepWPct) private var signsWidth = ocrDefaults.topKeepWPct

    /// The tag sits 19 pt out from the band's outer edge (`tavole.css .tagb`).
    private static let tagOffset: CGFloat = 19

    var body: some View {
        ZStack(alignment: .topLeading) {
            if signsOn {
                band(.signs, height: signsHeight, width: signsWidth)
            }
            band(.dialogue, height: bottomHeight, width: bottomWidth)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .coordinateSpace(name: "frame")
    }

    private func band(_ band: PreviewBand, height: Int, width: Int) -> some View {
        let rect = BandGeometry.rect(band, height: height, width: width, in: size)
        let dragging = drag?.band == band
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 1)
                .fill(band == .dialogue ? BandColors.dialogueFill : BandColors.signsFill)
                .overlay {
                    Rectangle().strokeBorder(band.color, lineWidth: 2)
                }
                .overlay {
                    // The white ring of the band being dragged (`.band.drag`).
                    if dragging { Rectangle().stroke(.white.opacity(0.6), lineWidth: 1).padding(-1) }
                }
                .frame(width: rect.width, height: rect.height)
            tag(band)
                .offset(x: -2, y: band == .dialogue ? -Self.tagOffset : rect.height + Self.tagOffset - 17)
            if editable {
                handles(band, rect: rect)
            }
            if dragging, let drag {
                dragLabel(drag)
                    .offset(x: rect.width / 2 + 18, y: band == .dialogue ? -30 : rect.height + 30 - 21)
            }
        }
        .frame(width: rect.width, height: rect.height, alignment: .topLeading)
        .offset(x: rect.minX, y: rect.minY)
        .help(editable ? model.t(band.helpKey) : "")
    }

    /// "Dialogue" / "Signs" on the band's outer corner.
    private func tag(_ band: PreviewBand) -> some View {
        Text(model.t(band.nameKey)).svFont(10.5, .bold).foregroundStyle(band.tagText)
            .padding(.horizontal, 7).padding(.vertical, 1)
            .frame(height: 17)
            .background(RoundedRectangle(cornerRadius: 4).fill(band.color))
            .fixedSize()
    }

    /// "Height 31 % · Width 96 %" while dragging (`.dragtag`).
    private func dragLabel(_ drag: BandDrag) -> some View {
        Text(model.t("app.preview.drag", ["h": drag.height, "w": drag.width]))
            .svFont(11, mono: true).foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.78)))
            .fixedSize()
    }

    /// The three handles: height on the inner edge, width on both sides.
    @ViewBuilder
    private func handles(_ band: PreviewBand, rect: CGRect) -> some View {
        let innerY: CGFloat = band == .dialogue ? 0 : rect.height
        handle(band, .height)
            .position(x: rect.width / 2, y: innerY)
        handle(band, .left)
            .position(x: 0, y: rect.height / 2)
        handle(band, .right)
            .position(x: rect.width, y: rect.height / 2)
    }

    /// A 22 × 8 white pill (`.hdl`), turned for the sides; the pointer says which way it goes.
    private func handle(_ band: PreviewBand, _ which: BandHandle) -> some View {
        let vertical = which != .height
        return Capsule()
            .fill(.white)
            .frame(width: vertical ? 8 : 22, height: vertical ? 22 : 8)
            .overlay(Capsule().stroke(.black.opacity(0.45), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.5), radius: 1.5, y: 1)
            // A bigger target than the pill itself.
            .padding(6)
            .contentShape(Rectangle())
            .pointerStyle(vertical ? .columnResize : .rowResize)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("frame"))
                    .onChanged { value in
                        drag = BandGeometry.apply(band, which, pointer: value.location, in: size)
                    }
                    .onEnded { _ in drag = nil }
            )
    }
}
