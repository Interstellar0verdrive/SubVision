// SPDX-License-Identifier: MIT
// Copied and adapted from the design system of the native macOS app of AnimeUp
// (AnimeUpKit/DesignSystem/Buttons.swift, version 2.1), by the same author.

import SwiftUI

/// Six roles, three sizes. A button is chosen by what it does, never by
/// where it sits. All capsules; label weight 500 (primary and notice 600);
/// icon on the left with a 5 pt gap; the label sits 1 pt higher for optical
/// centring. Hover only lightens the same fill; disabled is 40 %.
public enum SVButtonRole: Sendable {
    /// The one way forward in a view (at most one per view).
    case primary
    /// Everything else.
    case secondary
    /// Ends or throws away work: outline only.
    case destructive
    /// Only inside a confirmation alert.
    case destructiveSolid
    /// Only inside a yellow note.
    case notice
    /// No fill or border until hover.
    case plain
}

public enum SVButtonSize: Sendable {
    /// 32 pt: alerts and dialogs.
    case large
    /// 28 pt: page headers, panels, Settings.
    case regular
    /// 24 pt: file rows and the sidebar.
    case small

    var height: CGFloat { switch self { case .large: 32; case .regular: 28; case .small: 24 } }
    var padding: CGFloat { switch self { case .large: 18; case .regular: 14; case .small: 10 } }
    var fontSize: CGFloat { switch self { case .large: 13; case .regular: 12.5; case .small: 12 } }
    var iconSize: CGFloat { switch self { case .large: 12; case .regular: 11; case .small: 10 } }
}

public struct SVButtonStyle: ButtonStyle {
    var role: SVButtonRole
    var size: SVButtonSize
    var fullWidth: Bool
    /// Icon-only: a circle as tall as the size.
    var iconOnly: Bool

    public init(_ role: SVButtonRole = .secondary, size: SVButtonSize = .regular,
                fullWidth: Bool = false, iconOnly: Bool = false) {
        self.role = role
        self.size = size
        self.fullWidth = fullWidth
        self.iconOnly = iconOnly
    }

    public func makeBody(configuration: Configuration) -> some View {
        SVButtonBody(configuration: configuration, role: role, size: size,
                     fullWidth: fullWidth, iconOnly: iconOnly)
    }
}

struct SVButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let role: SVButtonRole
    let size: SVButtonSize
    let fullWidth: Bool
    let iconOnly: Bool
    @State private var hover = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        configuration.label
            .labelStyle(SVLabelStyle(iconSize: size.iconSize, iconOnly: iconOnly))
            .svControlFont(size.fontSize, weight)
            .foregroundStyle(foreground)
            .lineLimit(1)
            // A button label never truncates: the row around it gives way instead.
            .fixedSize()
            .frame(width: iconOnly ? size.height - 2 : nil, height: size.height - 2)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .svBox(Capsule(), fill: fill, line: border,
                   padding: EdgeInsets(vertical: 0, horizontal: iconOnly ? 0 : (role == .plain ? 6 : size.padding)))
            .contentShape(Capsule())
            .opacity(enabled ? 1 : 0.4)
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.12), value: hover)
    }

    private var weight: Font.Weight {
        role == .primary || role == .notice ? .semibold : .medium
    }

    private var pressed: Bool { configuration.isPressed && enabled }
    private var hovering: Bool { hover && enabled }

    private var fill: Color {
        switch role {
        case .primary: pressed ? SV.primaryPress : hovering ? SV.primaryHover : SV.primary
        case .secondary: pressed ? SV.glassPress : hovering ? SV.glassHover : SV.glass
        case .destructive: pressed ? SV.redBgPress : hovering ? SV.redBg : .clear
        case .destructiveSolid: pressed ? SV.redPress : hovering ? SV.redHover : SV.red
        case .notice: pressed ? SV.noticePress : hovering ? SV.noticeHover : SV.noticeFill
        case .plain: pressed ? SV.glassPress : hovering ? SV.glass : .clear
        }
    }

    private var border: Color {
        switch role {
        case .secondary: SV.glassLine
        case .destructive: SV.redText
        case .notice: SV.noticeLine
        default: .clear
        }
    }

    private var foreground: Color {
        switch role {
        case .primary: SV.onPrimary
        case .secondary: SV.text
        case .destructive: SV.redText
        case .destructiveSolid: SV.onRed
        case .notice: SV.onNotice
        case .plain: SV.text2
        }
    }
}

/// Icon then title, 5 pt apart; the title nudged up 1 pt.
struct SVLabelStyle: LabelStyle {
    var iconSize: CGFloat
    var iconOnly: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.svFont(iconSize, .medium)
            if !iconOnly {
                configuration.title
            }
        }
    }
}

/// A tinted button that sits inside a note: background and line from
/// the note's status colour.
public struct SVTintedButtonStyle: ButtonStyle {
    var tone: SVTone
    var size: SVButtonSize

    public init(_ tone: SVTone, size: SVButtonSize = .small) {
        self.tone = tone
        self.size = size
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(SVLabelStyle(iconSize: size.iconSize, iconOnly: false))
            .svControlFont(size.fontSize, .medium)
            .foregroundStyle(tone.text)
            .frame(height: size.height - 2)
            .svBox(Capsule(), fill: tone.tint, line: tone.line, padding: EdgeInsets(vertical: 0, horizontal: size.padding))
            .svHover(Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Capsule())
    }
}

extension View {
    /// Shorthand: `.svButton(.primary, .regular)`.
    public func svButton(_ role: SVButtonRole, _ size: SVButtonSize = .regular,
                         fullWidth: Bool = false) -> some View {
        buttonStyle(SVButtonStyle(role, size: size, fullWidth: fullWidth))
    }
}
