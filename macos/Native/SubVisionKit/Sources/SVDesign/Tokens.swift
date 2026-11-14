// SPDX-License-Identifier: MIT
// Copied and adapted from the design system of the native macOS app of AnimeUp
// (AnimeUpKit/DesignSystem/Tokens.swift, version 2.1), by the same author.
// SubVision keeps both appearances: every token carries its dark and its light
// value, the light one designed rather than inverted (secondary and coloured
// texts above WCAG AA, softer shadows, pastel reds).

import AppKit
import SwiftUI

extension Color {
    /// A colour that follows the appearance: `dark` in Dark Mode, `light` otherwise.
    public init(dark: String, light: String) {
        let darkColor = NSColor(css: dark)
        let lightColor = NSColor(css: light)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua, .vibrantDark, .vibrantLight])
            let isDark = match == .darkAqua || match == .vibrantDark
            return isDark ? darkColor : lightColor
        })
    }
}

extension NSColor {
    /// `#RRGGBB` or `rgba(r,g,b,a)`; anything else is magenta, so it shows.
    public convenience init(css: String) {
        let s = css.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#"), s.count == 7, let v = UInt32(s.dropFirst(), radix: 16) {
            self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                      blue: CGFloat(v & 0xFF) / 255, alpha: 1)
            return
        }
        if s.hasPrefix("rgba("), s.hasSuffix(")") {
            let parts = s.dropFirst(5).dropLast().split(separator: ",").map {
                Double($0.trimmingCharacters(in: .whitespaces)) ?? 0
            }
            if parts.count == 4 {
                self.init(srgbRed: parts[0] / 255, green: parts[1] / 255, blue: parts[2] / 255, alpha: parts[3])
                return
            }
        }
        self.init(srgbRed: 1, green: 0, blue: 1, alpha: 1)
    }
}

/// The colour tokens of SubVision, each with its dark and its light value.
public enum SV {
    // Surfaces, back to front
    public static let desk = Color(dark: "#2A2D33", light: "#D9DDE3")
    public static let bg = Color(dark: "#101113", light: "#F6F7F9")
    public static let side = Color(dark: "rgba(30,33,38,.78)", light: "rgba(236,238,241,.82)")
    public static let surface = Color(dark: "#16181B", light: "#FFFFFF")
    public static let raised = Color(dark: "#1C1F23", light: "#EEF0F2")
    /// Sheets. Light: a step below white, so the white cards inside read as cards.
    public static let sheet = Color(dark: "#22252A", light: "#F3F4F6")
    /// The app's own alerts (`SVAlert`).
    public static let alert = Color(dark: "#26292E", light: "#F6F7F9")
    public static let surfaceHover = Color(dark: "#1C1F23", light: "#F3F4F6")
    public static let inset = Color(dark: "rgba(0,0,0,.25)", light: "rgba(0,0,0,.04)")
    public static let control = Color(dark: "#1C1F23", light: "#FFFFFF")
    public static let glass = Color(dark: "rgba(255,255,255,.07)", light: "rgba(0,0,0,.04)")
    public static let glassHover = Color(dark: "rgba(255,255,255,.11)", light: "rgba(0,0,0,.07)")
    public static let glassPress = Color(dark: "rgba(255,255,255,.15)", light: "rgba(0,0,0,.11)")
    public static let glassLine = Color(dark: "rgba(255,255,255,.10)", light: "rgba(0,0,0,.12)")
    public static let line = Color(dark: "#26292E", light: "#E1E4E8")
    public static let boxLine = Color(dark: "rgba(255,255,255,.22)", light: "rgba(0,0,0,.25)")
    /// The line between the head of a running row and its steps (white 12 % in dark).
    public static let detailLine = Color(dark: "rgba(255,255,255,.12)", light: "rgba(0,0,0,.10)")

    // Text
    public static let text = Color(dark: "#E8EAED", light: "#16181B")
    public static let text2 = Color(dark: "#9BA1A9", light: "#5C626A")
    public static let text3 = Color(dark: "#80868E", light: "#656B73")
    public static let textCode = Color(dark: "#C6CBD2", light: "#3A3F46")

    // Accent
    /// Light: hue 244°, white on it at 4.97 : 1, the hover lighter at 4.51, pressed 5.81.
    public static let primary = Color(dark: "#2AC9DE", light: "#0275B6")
    public static let primaryHover = Color(dark: "#4FD5E7", light: "#067CC1")
    public static let primaryPress = Color(dark: "#1FB0C4", light: "#056AA5")
    public static let onPrimary = Color(dark: "#06252A", light: "#FFFFFF")
    public static let primaryText = Color(dark: "#2AC9DE", light: "#206CA1")
    public static let focus = Color(dark: "rgba(42,201,222,.5)", light: "rgba(39,147,219,.45)")
    /// The keyboard's ring on a list row: neutral, so the row's left bar stays its only colour.
    public static let rowFocus = Color(dark: "rgba(255,255,255,.28)", light: "rgba(0,0,0,.24)")
    public static let sel = Color(dark: "rgba(42,201,222,.16)", light: "rgba(39,147,219,.14)")
    /// A selected row of a list: a softer `sel`, so the rows under it still read (design note 58).
    public static let selSoft = Color(dark: "rgba(42,201,222,.10)", light: "rgba(39,147,219,.09)")
    /// The system's controls (switches, slider fills, the highlight of the menus): the deep cyan of the
    /// `AccentColor` asset in dark, so white reads on it (4.9 : 1, design note 53); the app's own
    /// components keep `primary`. Light: the same blue as `primary`.
    public static let sysAccent = Color(dark: "#0E7C8C", light: "#0275B6")
    public static let soft = Color(dark: "rgba(42,201,222,.07)", light: "rgba(39,147,219,.07)")
    public static let softLine = Color(dark: "rgba(42,201,222,.28)", light: "rgba(39,147,219,.28)")
    public static let track = Color(dark: "#2A2E34", light: "#DADDE2")
    public static let trackSoft = Color(dark: "rgba(255,255,255,.14)", light: "rgba(0,0,0,.10)")

    // Status
    public static let green = Color(dark: "#3DD68C", light: "#12A150")
    public static let greenText = Color(dark: "#7FE3AC", light: "#146C3E")
    public static let greenBg = Color(dark: "rgba(18,161,80,.12)", light: "#E6F5EC")
    public static let greenLine = Color(dark: "rgba(61,214,140,.35)", light: "rgba(18,161,80,.35)")
    public static let greenTint = Color(dark: "rgba(61,214,140,.16)", light: "rgba(18,161,80,.14)")
    public static let yellow = Color(dark: "#F2B84B", light: "#F5B400")
    public static let yellowHover = Color(dark: "#F5C76E", light: "#FFC21F")
    public static let yellowText = Color(dark: "#F5CB78", light: "#7F5300")
    public static let yellowBg = Color(dark: "#2A2110", light: "#FFF0C4")
    public static let yellowLine = Color(dark: "rgba(242,184,75,.45)", light: "rgba(245,180,0,.45)")
    public static let yellowTint = Color(dark: "rgba(242,184,75,.16)", light: "rgba(245,180,0,.22)")
    public static let onYellow = Color(dark: "#2A1C00", light: "#2A1C00")
    /// The notice button (Install update, Download…) sits inside a yellow note: ochre with dark ink
    /// in dark; in light white with yellow text on a yellow line (6.7 : 1), so it stands out from the note.
    public static let noticeFill = Color(dark: "#F2B84B", light: "#FFFFFF")
    public static let noticeHover = Color(dark: "#F5C76E", light: "#FFFAEB")
    public static let noticePress = Color(dark: "#F2B84B", light: "#FFF0C4")
    public static let onNotice = Color(dark: "#2A1C00", light: "#7F5300")
    public static let noticeLine = Color(dark: "rgba(242,184,75,0)", light: "rgba(245,180,0,.45)")
    /// White on red reaches 5.0 : 1, hover 4.6, pressed 6.1; the same red in both appearances.
    public static let red = Color(dark: "#CD3725", light: "#CD3725")
    public static let redHover = Color(dark: "#D83A27", light: "#D83A27")
    public static let redPress = Color(dark: "#B63121", light: "#B63121")
    /// The ink on the solid red button: white in both appearances.
    public static let onRed = Color(dark: "#FFFFFF", light: "#FFFFFF")
    public static let redText = Color(dark: "#F59B9B", light: "#B42323")
    public static let redBg = Color(dark: "rgba(242,109,109,.10)", light: "#FDECEA")
    public static let redBgPress = Color(dark: "rgba(242,109,109,.17)", light: "#FADAD6")
    public static let redLine = Color(dark: "rgba(242,109,109,.55)", light: "rgba(217,64,46,.45)")
    public static let redSoft = Color(dark: "rgba(242,109,109,.07)", light: "rgba(205,55,37,.10)")
    public static let redTint = Color(dark: "rgba(242,109,109,.16)", light: "rgba(217,64,46,.12)")

    /// A value different from its default (design note 81, boards C3-10, DS1): a warning,
    /// never an error, so never red, and not the accent either. Yellow in dark (10.6 : 1 on
    /// the panel), amber in light (4.9 : 1 on white, 4.5 : 1 on the window's background).
    public static let modified = Color(dark: "#E8C547", light: "#AB5E00")
    public static let modifiedTint = Color(dark: "rgba(232,197,71,.16)", light: "rgba(171,94,0,.12)")
    /// A file the person stopped (boards E3, E5, DS3): its own colour, lilac, so it reads as a
    /// state of its own, apart from done (green), warnings (yellow), errors (red) and the accent.
    public static let stopped = Color(dark: "#A99BFF", light: "#6650C8")
    public static let stoppedBg = Color(dark: "rgba(169,155,255,.14)", light: "rgba(102,80,200,.10)")
    public static let stoppedLine = Color(dark: "rgba(169,155,255,.45)", light: "rgba(102,80,200,.40)")
    /// The tick of a slider's default value (C3-10, board I2): grey, under the track.
    public static let defaultTick = Color(dark: "#80868E", light: "#656B73")

    /// Drop areas (design notes 38 and 40): a 2 pt dash strong enough to read in
    /// both appearances, and faint diagonal stripes inside (14 pt on, 14 pt off).
    public static let dropLine = Color(dark: "rgba(255,255,255,.40)", light: "rgba(0,0,0,.40)")
    public static let dropHatch = Color(dark: "rgba(255,255,255,.035)", light: "rgba(0,0,0,.03)")

    public static let chipBg = Color(dark: "#1C1F23", light: "#EEF0F2")
    public static let chipLine = Color(dark: "rgba(255,255,255,.10)", light: "rgba(0,0,0,.08)")
    public static let segOn = Color(dark: "#3A3E44", light: "#FFFFFF")
    public static let segShadow = Color(dark: "rgba(0,0,0,.4)", light: "rgba(0,0,0,.15)")
    /// The count capsule on the selected (accent) sidebar tab.
    public static let chipOnAccent = Color(dark: "rgba(0,0,0,.18)", light: "rgba(0,0,0,.08)")
    /// Shadows: multiply with `.opacity(x)` where a design says `rgba(0,0,0,x)`.
    /// Light: half strength, a cool ink instead of black.
    public static let shadow = Color(dark: "#000000", light: "rgba(16,24,40,.5)")
    /// The knob of a slider and its shadow: white on a short black shadow in both
    /// appearances, so the knob reads as the one solid thing on the track.
    public static let knob = Color(dark: "#FFFFFF", light: "#FFFFFF")
    public static let knobShadow = Color(dark: "rgba(0,0,0,.45)", light: "rgba(0,0,0,.45)")

    /// Corners: nested shapes get a smaller radius than their container.
    public enum Radius {
        public static let icon: CGFloat = 6
        public static let field: CGFloat = 8
        public static let card: CGFloat = 10
        public static let sidebar: CGFloat = 16
        public static let window: CGFloat = 22
    }
}

/// The text styles: SF Pro and SF Mono, whole points.
public enum SVFont {
    /// Page title · 24 bold, −1 % tracking (use `.svPageTitle()` for the tracking).
    public static let pageTitle = SVTextStyle(24, .bold)
    /// Section title · 15 semibold (card titles).
    public static let sectionTitle = SVTextStyle(15, .semibold)
    /// File name · 12 medium.
    public static let fileName = SVTextStyle(12, .medium)
    /// Body · 13 regular, line height 1.5.
    public static let body = SVTextStyle(13, leading: 1.5)
    /// Callout · 12 regular.
    public static let callout = SVTextStyle(12)
    /// Small paragraph · 12 regular, line height 1.45.
    public static let small = SVTextStyle(12, leading: 1.45)
    /// Label · 11 semibold, tertiary.
    public static let label = SVTextStyle(11, .semibold)
    /// Numbers · 12 mono.
    public static let numbers = SVTextStyle(12, mono: true)
    /// Small numbers · 11 mono.
    public static let smallNumbers = SVTextStyle(11, mono: true)
}

extension View {
    public func svPageTitle() -> some View {
        svFont(SVFont.pageTitle).tracking(-0.24).foregroundStyle(SV.text)
    }

    /// Body text with the 1.5 line height.
    public func svBody(_ color: Color = SV.text2) -> some View {
        svFont(SVFont.body).foregroundStyle(color)
    }

    /// The small paragraph style of the cards (12, line height 1.45).
    public func svSmall(_ color: Color = SV.text2) -> some View {
        svFont(SVFont.small).foregroundStyle(color)
    }

    public func svLabel(_ color: Color = SV.text3) -> some View {
        svFont(SVFont.label).foregroundStyle(color)
    }
}
