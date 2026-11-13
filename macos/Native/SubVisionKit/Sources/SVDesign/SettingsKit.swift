// SPDX-License-Identifier: MIT
// Copied and adapted from the design system of the native macOS app of AnimeUp
// (AnimeUpKit/DesignSystem/SettingsKit.swift, version 2.1), by the same author.

import SwiftUI

/// A snapping slider: a few fixed values; dots mark them, the knob snaps
/// to the nearest, and the value under it lights up.
public struct SnapSlider<Value: Hashable>: View {
    var values: [Value]
    var label: (Value) -> String
    @Binding var selection: Value
    var width: CGFloat
    @Environment(\.isEnabled) private var enabled
    @State private var dragging: Int?

    public init(values: [Value], selection: Binding<Value>, width: CGFloat = 250,
                label: @escaping (Value) -> String) {
        self.values = values
        self._selection = selection
        self.width = width
        self.label = label
    }

    private var index: Int { dragging ?? values.firstIndex(of: selection) ?? 0 }

    public var body: some View {
        let steps = max(1, values.count - 1)
        let usable = width - 16
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .leading) {
                Capsule().fill(SV.trackSoft).frame(height: 4).padding(.horizontal, 8)
                Capsule().fill(SV.primary)
                    .frame(width: usable * CGFloat(index) / CGFloat(steps), height: 4)
                    .padding(.leading, 8)
                // 6 pt dots ringed in the surface colour.
                ForEach(values.indices, id: \.self) { i in
                    Circle().fill(i <= index ? SV.primary : SV.track)
                        .frame(width: 6, height: 6)
                        .overlay(Circle().stroke(SV.surface, lineWidth: 1.5).padding(-0.75))
                        .offset(x: 8 + usable * CGFloat(i) / CGFloat(steps) - 3)
                }
                Circle().fill(SV.knob)
                    .frame(width: 16, height: 16)
                    .shadow(color: SV.knobShadow, radius: 1.5, y: 1)
                    .offset(x: usable * CGFloat(index) / CGFloat(steps))
            }
            .frame(width: width, height: 16)
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
            ZStack(alignment: .leading) {
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
        .frame(width: width)
        .opacity(enabled ? 1 : 0.4)
        .animation(.easeOut(duration: 0.12), value: index)
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
/// under a player).
public struct SVSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var knob: CGFloat
    var onEditingChanged: (Bool) -> Void
    @Environment(\.isEnabled) private var enabled
    @State private var dragging = false

    public init(value: Binding<Double>, in range: ClosedRange<Double>, knob: CGFloat = 16,
                onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self._value = value
        self.range = range
        self.knob = knob
        self.onEditingChanged = onEditingChanged
    }

    public var body: some View {
        GeometryReader { g in
            let span = max(range.upperBound - range.lowerBound, .ulpOfOne)
            let f = min(max((value - range.lowerBound) / span, 0), 1)
            let w = g.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(SV.trackSoft).frame(height: 4)
                Capsule().fill(SV.primary).frame(width: max(0, w * f), height: 4)
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
                    if !dragging { dragging = true; onEditingChanged(true) }
                    value = range.lowerBound + min(max(d.location.x / max(w, 1), 0), 1) * span
                }
                .onEnded { _ in dragging = false; onEditingChanged(false) })
        }
        .frame(height: max(knob, 16))
        .opacity(enabled ? 1 : 0.4)
    }
}
