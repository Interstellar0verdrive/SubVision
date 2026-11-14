// SPDX-License-Identifier: MIT
// Copied and adapted from the design system of the native macOS app of AnimeUp
// (AnimeUpKit/DesignSystem/SettingsKit.swift, version 2.1), by the same author.

import SwiftUI

/// A snapping slider: a few fixed values; dots mark them, the knob snaps
/// to the nearest, and the value under it lights up. With `ticks` (the
/// parameters panel, design board C2-P1) the values are small ticks under the
/// track instead, with no dots and no labels. With `defaultValue`, while the
/// value differs from it a thin grey tick marks where the default is; a click
/// on it goes back there (C3-10, board I2).
public struct SnapSlider<Value: Hashable>: View {
    var values: [Value]
    var label: (Value) -> String
    @Binding var selection: Value
    var width: CGFloat
    var ticks: Bool
    var defaultValue: Value?
    var defaultHelp: String
    @Environment(\.isEnabled) private var enabled
    @State private var dragging: Int?

    public init(values: [Value], selection: Binding<Value>, width: CGFloat = 250, ticks: Bool = false,
                defaultValue: Value? = nil, defaultHelp: String = "", label: @escaping (Value) -> String) {
        self.values = values
        self._selection = selection
        self.width = width
        self.ticks = ticks
        self.defaultValue = defaultValue
        self.defaultHelp = defaultHelp
        self.label = label
    }

    /// The ticks variant: no labels.
    public init(values: [Value], selection: Binding<Value>, width: CGFloat, defaultValue: Value? = nil, defaultHelp: String = "") {
        self.init(values: values, selection: selection, width: width, ticks: true,
                  defaultValue: defaultValue, defaultHelp: defaultHelp) { _ in "" }
    }

    /// The default's stop, while the value is elsewhere.
    private var defaultIndex: Int? {
        guard let defaultValue, defaultValue != selection, dragging == nil else { return nil }
        return values.firstIndex(of: defaultValue)
    }

    private var index: Int { dragging ?? values.firstIndex(of: selection) ?? 0 }

    public var body: some View {
        let steps = max(1, values.count - 1)
        let usable = width - 16
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .leading) {
                if let d = defaultIndex {
                    DefaultTick(help: defaultHelp)
                        .offset(x: 8 + usable * CGFloat(d) / CGFloat(steps) - DefaultTick.hitWidth / 2)
                }
                if ticks {
                    // 1×4 pt ticks just under the track (3 pt below it), at the knob's stops (C2-P1).
                    ForEach(values.indices, id: \.self) { i in
                        Rectangle().fill(SV.text3)
                            .frame(width: 1, height: 4)
                            .offset(x: 8 + usable * CGFloat(i) / CGFloat(steps) - 0.5, y: 7)
                    }
                }
                // With ticks the track takes the whole width and its fill reaches the knob's
                // centre, as the continuous slider's (C2-P1); with dots it runs from dot to dot.
                Capsule().fill(SV.trackSoft).frame(height: 4).padding(.horizontal, ticks ? 0 : 8)
                Capsule().fill(SV.sysAccent)
                    .frame(width: usable * CGFloat(index) / CGFloat(steps) + (ticks ? 8 : 0), height: 4)
                    .padding(.leading, ticks ? 0 : 8)
                // 6 pt dots ringed in the surface colour.
                if !ticks {
                    ForEach(values.indices, id: \.self) { i in
                        Circle().fill(i <= index ? SV.sysAccent : SV.track)
                            .frame(width: 6, height: 6)
                            .overlay(Circle().stroke(SV.surface, lineWidth: 1.5).padding(-0.75))
                            .offset(x: 8 + usable * CGFloat(i) / CGFloat(steps) - 3)
                    }
                }
                Circle().fill(SV.knob)
                    .frame(width: 16, height: 16)
                    .shadow(color: SV.knobShadow, radius: 1.5, y: 1)
                    .offset(x: usable * CGFloat(index) / CGFloat(steps))
            }
            .frame(width: width, height: ticks ? 18 : 16)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    guard enabled else { return }
                    let f = min(max((g.location.x - 8) / usable, 0), 1)
                    dragging = Int((f * CGFloat(steps)).rounded())
                }
                .onEnded { _ in
                    if let d = dragging, values.indices.contains(d) { selection = values[d] }
                    dragging = nil
                })
            // Labels under the track's ends (not the control's): the first starts
            // at the first dot, the last ends at the last one, the rest are centred.
            if !ticks { labels }
        }
        .frame(width: width)
        .opacity(enabled ? 1 : 0.4)
        .animation(.easeOut(duration: 0.12), value: index)
    }

    private var labels: some View {
        let steps = max(1, values.count - 1)
        let usable = width - 16
        return ZStack(alignment: .leading) {
            ForEach(values.indices, id: \.self) { i in
                Text(label(values[i]))
                    .svFont(9.5, mono: true)
                    .foregroundStyle(i == index ? SV.text : SV.text3)
                    .fixedSize()
                    .frame(width: 60, alignment: i == 0 ? .leading : i == values.count - 1 ? .trailing : .center)
                    .offset(x: i == 0 ? 8 : i == values.count - 1 ? width - 8 - 60
                            : 8 + usable * CGFloat(i) / CGFloat(steps) - 30)
            }
        }
        .frame(width: width, height: 12, alignment: .leading)
    }
}

/// A group of settings rows: surface, 10 pt corners, hairlines between rows.
public struct SettingsGroup<Content: View>: View {
    var title: String?
    @ViewBuilder var content: () -> Content

    public init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    public var body: some View {
        // Label 6 pt above a border-box of rows.
        VStack(alignment: .leading, spacing: 6) {
            if let title { Text(title).svLabel().textCase(.uppercase).tracking(0.4).padding(.leading, 4) }
            Group(subviews: content()) { subviews in
                VStack(spacing: 0) {
                    ForEach(Array(subviews.enumerated()), id: \.offset) { index, sub in
                        if index > 0 { Rectangle().fill(SV.line).frame(height: 1) }
                        sub
                    }
                }
            }
            .svBox(RoundedRectangle(cornerRadius: SV.Radius.card), fill: SV.surface, line: SV.line)
        }
    }
}

/// One settings row: title, description, the default on a line of its own
/// (on every row that has one: the description's size and leading, tertiary, no icon — information,
/// not a control), and the control on the right.
public struct SettingsRow<Control: View>: View {
    var title: String
    var description: String?
    var defaultText: String?
    @ViewBuilder var control: () -> Control

    public init(_ title: String, description: String? = nil, defaultText: String? = nil,
                @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.description = description
        self.defaultText = defaultText
        self.control = control
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).svFont(13).foregroundStyle(SV.text)
                if let description {
                    Text(description).svFont(SVFont.small).foregroundStyle(SV.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let defaultText {
                    // The description's leading, no gap of its own: one block of text.
                    Text(defaultText).svFont(SVFont.small).foregroundStyle(SV.text3.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, -2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control()
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
    }
}

/// A capsule segmented control (System · Light · Dark).
public struct CapsuleSegments<Value: Hashable>: View {
    var options: [(Value, String)]
    @Binding var selection: Value

    public init(_ options: [(Value, String)], selection: Binding<Value>) {
        self.options = options
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let on = options[i].0 == selection
                Button { selection = options[i].0 } label: {
                    // The medium width held in place: choosing doesn't nudge the segments.
                    ZStack {
                        Text(options[i].1).svControlFont(12, .medium).hidden()
                        Text(options[i].1).svControlFont(12, on ? .medium : .regular)
                    }
                        .foregroundStyle(on ? SV.text : SV.text2)
                        .padding(.horizontal, 14).padding(.vertical, 3)
                        .background(Capsule().fill(on ? SV.segOn : .clear)
                            .shadow(color: on ? SV.segShadow : .clear, radius: 1, y: 1))
                        .contentShape(Capsule())
                        // The other segment lights up under the pointer, like every clickable surface.
                        .svHover(Capsule(), enabled: !on)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(SV.glass))
        .overlay(Capsule().strokeBorder(SV.glassLine))
    }
}

/// The continuous slider: 4 pt track, accent fill, white knob (16 pt, or 12
/// under a player). With `defaultValue`, while the value differs from it a thin
/// grey tick marks where the default is; a click on it goes back there (C3-10,
/// board I2).
public struct SVSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var knob: CGFloat
    var defaultValue: Double?
    var defaultHelp: String
    var onEditingChanged: (Bool) -> Void
    @Environment(\.isEnabled) private var enabled
    @State private var dragging = false
    /// The press began on the default's tick: the value stays on the default unless it becomes a drag.
    @State private var resetting = false

    public init(value: Binding<Double>, in range: ClosedRange<Double>, knob: CGFloat = 16,
                defaultValue: Double? = nil, defaultHelp: String = "",
                onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self._value = value
        self.range = range
        self.knob = knob
        self.defaultValue = defaultValue
        self.defaultHelp = defaultHelp
        self.onEditingChanged = onEditingChanged
    }

    /// The knob's centre for a value, on a track `w` wide.
    private func centre(_ v: Double, _ w: CGFloat) -> CGFloat {
        let span = max(range.upperBound - range.lowerBound, .ulpOfOne)
        let f = min(max((v - range.lowerBound) / span, 0), 1)
        return min(max(w * f, knob / 2), w - knob / 2)
    }

    public var body: some View {
        GeometryReader { g in
            let span = max(range.upperBound - range.lowerBound, .ulpOfOne)
            let f = min(max((value - range.lowerBound) / span, 0), 1)
            let w = g.size.width
            let tick = defaultValue.flatMap { d in abs(d - value) > span * 1e-6 && !dragging ? centre(d, w) : nil }
            ZStack(alignment: .leading) {
                if let tick {
                    DefaultTick(help: defaultHelp).offset(x: tick - DefaultTick.hitWidth / 2)
                }
                Capsule().fill(SV.trackSoft).frame(height: 4)
                Capsule().fill(SV.sysAccent).frame(width: max(0, w * f), height: 4)
                Circle().fill(SV.knob)
                    .frame(width: knob, height: knob)
                    .shadow(color: SV.knobShadow, radius: 1.5, y: 1)
                    .offset(x: min(max(w * f - knob / 2, 0), w - knob))
            }
            .frame(height: g.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { d in
                    guard enabled else { return }
                    // A click on the default's tick (not a drag) goes back to the default.
                    if !dragging, let defaultValue, abs(d.translation.width) < 3,
                       resetting || tick.map({ abs(d.startLocation.x - $0) <= DefaultTick.hitWidth / 2 }) == true {
                        if !resetting { resetting = true; onEditingChanged(true) }
                        value = defaultValue
                        return
                    }
                    if !dragging { dragging = true; if !resetting { onEditingChanged(true) } }
                    resetting = false
                    value = range.lowerBound + min(max(d.location.x / max(w, 1), 0), 1) * span
                }
                .onEnded { _ in
                    dragging = false
                    resetting = false
                    onEditingChanged(false)
                })
        }
        .frame(height: max(knob, 16))
        .opacity(enabled ? 1 : 0.4)
    }
}

/// The default's tick on a slider (`.slider .dt`, board I2): 2 × 14 pt, grey,
/// under the track, in a wider transparent strip that carries the tooltip.
struct DefaultTick: View {
    static let hitWidth: CGFloat = 10
    var help: String

    var body: some View {
        RoundedRectangle(cornerRadius: 1).fill(SV.defaultTick)
            .frame(width: 2, height: 14)
            .frame(width: Self.hitWidth, height: 16)
            .contentShape(Rectangle())
            .help(help)
            .accessibilityHidden(true)
    }
}
