// SPDX-License-Identifier: MIT
// A page with one of everything in the design system, for the tests (rendered
// in light and in dark), the design boards and the app's debug snapshots.
// AppKit-backed pieces (the popup menu, the cursor) draw as placeholders in
// ImageRenderer; that is expected.

import SwiftUI

/// Every component of `SVDesign` on one page, on `SV.bg`.
public struct SVDesignGallery: View {
    @State private var appearance = "system"
    @State private var fps = 6
    @State private var level = 0.4
    public static let width: CGFloat = 1260

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            PageHeader("Design gallery",
                       "Every piece of SVDesign on one page, in the appearance it was rendered in.",
                       "Colours, text styles, buttons, boxes, notes, settings rows, chips and bars.") {
                Button("Process", systemImage: "play.fill") {}.svButton(.primary)
            }
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 24) {
                    text
                    buttons
                    chips
                    bars
                }
                .frame(width: 560, alignment: .leading)
                VStack(alignment: .leading, spacing: 24) {
                    notes
                    settings
                    cards
                }
                .frame(width: 560, alignment: .leading)
            }
            HStack(alignment: .top, spacing: 24) {
                alerts
                navigation
            }
        }
        .padding(28)
        .frame(width: Self.width, alignment: .topLeading)
        .background(SV.bg)
    }

    private var text: some View {
        Card {
            CardTitle("Text styles", symbol: "textformat")
            Text("Page title · 24 bold").svPageTitle()
            Text("Section title · 15 semibold").svFont(SVFont.sectionTitle).foregroundStyle(SV.text)
            Text("File name · 12 medium").svFont(SVFont.fileName).foregroundStyle(SV.text)
            Text("Body · 13 regular on 1.5, secondary. Lorem ipsum dolor sit amet, consectetur adipiscing elit.")
                .svBody().fixedSize(horizontal: false, vertical: true)
            Text("Small paragraph · 12 regular on 1.45, secondary.").svSmall()
            Text("Callout · 12 regular, tertiary").svFont(SVFont.callout).foregroundStyle(SV.text3)
            Text("LABEL · 11 SEMIBOLD").svLabel()
            Text("Numbers · 12 mono 00:12:34.567").svFont(SVFont.numbers).foregroundStyle(SV.textCode)
            Text("small numbers · 11 mono").svFont(SVFont.smallNumbers).foregroundStyle(SV.textCode)
            HStack(spacing: 12) {
                Text("primary text").svFont(13).foregroundStyle(SV.primaryText)
                Text("green text").svFont(13).foregroundStyle(SV.greenText)
                Text("yellow text").svFont(13).foregroundStyle(SV.yellowText)
                Text("red text").svFont(13).foregroundStyle(SV.redText)
            }
            BalancedParagraph("A balanced paragraph takes the narrowest width that keeps its number of lines, so no lone word is left on the last one.",
                              style: SVFont.small).foregroundStyle(SV.text2)
            UnderlineLink("Open the user guide", symbol: "book") {}
        }
    }

    private var buttons: some View {
        Card {
            CardTitle("Buttons", symbol: "button.horizontal")
            HStack(spacing: 8) {
                Button("Primary", systemImage: "play.fill") {}.svButton(.primary)
                Button("Secondary") {}.svButton(.secondary)
                Button("Destructive") {}.svButton(.destructive)
                Button("Delete") {}.svButton(.destructiveSolid)
                Button("Notice") {}.svButton(.notice)
                Button("Plain") {}.svButton(.plain)
            }
            HStack(spacing: 8) {
                Button("Large", systemImage: "checkmark") {}.svButton(.primary, .large)
                Button("Regular", systemImage: "checkmark") {}.svButton(.secondary, .regular)
                Button("Small", systemImage: "checkmark") {}.svButton(.secondary, .small)
                Button("Disabled") {}.svButton(.primary).disabled(true)
                Button("Disabled") {}.svButton(.secondary).disabled(true)
                Button {} label: { Label("Settings", systemImage: "gearshape") }
                    .buttonStyle(SVButtonStyle(.secondary, iconOnly: true))
                ChromeIconButton("gearshape", help: "Settings") {}
            }
            HStack(spacing: 8) {
                Button("Tinted green", systemImage: "arrow.clockwise") {}.buttonStyle(SVTintedButtonStyle(.green))
                Button("Tinted yellow") {}.buttonStyle(SVTintedButtonStyle(.yellow))
                Button("Tinted red") {}.buttonStyle(SVTintedButtonStyle(.red))
                Button("Tinted accent") {}.buttonStyle(SVTintedButtonStyle(.accent))
            }
            HStack(spacing: 12) {
                CapsuleSegments([("system", "System"), ("light", "Light"), ("dark", "Dark")], selection: $appearance)
                SVMiniSegments([
                    .init(Image(systemName: "arrow.up.left.and.arrow.down.right"), help: "Fit", selected: true) {},
                    .init(Text("1:1"), help: "Actual size", selected: false) {},
                ], segmentWidth: 36)
                }
                HStack(spacing: 12) {
                TopBarSegments {
                    TopBarSegment(symbol: "play.rectangle", title: "Process", selected: true, busy: true, count: 3) {}
                    TopBarSegment(symbol: "eye", title: "Preview", selected: false) {}
                    TopBarSegment(symbol: "wrench.and.screwdriver", title: "Sub fix", selected: false) {}
                }
            }
        }
    }

    private var chips: some View {
        Card {
            CardTitle("Chips, dots and links", symbol: "tag")
            HStack(spacing: 8) {
                StatusChip("queued")
                StatusChip("running", tone: .accent, symbol: "play.fill")
                StatusChip("done", tone: .green, symbol: "checkmark")
                StatusChip("warning", tone: .yellow, symbol: "exclamationmark.triangle.fill")
                StatusChip("failed", tone: .red, symbol: "xmark")
            }
            HStack(spacing: 16) {
                StatusLink("Tools ready", tone: .green) {}
                StatusLink("Checking…", tone: .accent, busy: true) {}
                StatusLink("ffmpeg missing", tone: .red) {}
                HStack(spacing: 6) { StatusDot(.neutral); StatusDot(.accent); StatusDot(.green); StatusDot(.yellow); StatusDot(.red) }
            }
            PathField("/Users/someone/Movies/Series/episode-01-hardsub.mp4")
            ValueStrip([
                .init(symbol: "film", value: "1920 × 1080", label: "Frame"),
                .init(symbol: "clock", value: "24:12", label: "Length"),
                .init(symbol: "speedometer", value: "6 fps", label: "Sampling"),
            ])
        }
    }

    private var bars: some View {
        Card {
            CardTitle("Progress and sliders", symbol: "slider.horizontal.3")
            SVBar(0.62)
            SVBar(0.35, height: 6, fill: SV.green)
            HStack(spacing: 10) { Spinner(); Spinner(size: 10); Text("Spinner").svSmall() }
            SnapSlider(values: [2, 4, 6, 8, 12], selection: $fps) { "\($0) fps" }
            SVSlider(value: $level, in: 0...1, defaultValue: 0.3, defaultHelp: "Default: 0.30").frame(width: 250)
            HStack(spacing: 10) {
                SegmentedProgressBar(weights: [55, 55, 63], fraction: 0.47).frame(width: 280)
                Text("47 %").svFont(SVFont.smallNumbers).foregroundStyle(SV.text2)
            }
            HStack(spacing: 8) {
                Circle().fill(SV.modified).frame(width: 6, height: 6)
                Text("1 value differs from the default").svFont(11.5).foregroundStyle(SV.modified)
            }
        }
    }

    private var notes: some View {
        Card {
            CardTitle("Notes", symbol: "info.circle")
            NoteView(.neutral, title: "A neutral note", text: "Something to know, in the chip colours.")
            NoteView(.accent, text: "An accent note with a tinted button inside.") {
                Button("Show") {}.buttonStyle(SVTintedButtonStyle(.accent))
            }
            NoteView(.green, title: "Done", text: "12 subtitles written next to the video.", footnote: "extract 0:41 · ocr 1:12 · refine 0:08") { EmptyView() }
            NoteView(.yellow, title: "2 warnings", text: "Two segments were too short to read.", bullets: ["00:12:03 too short", "00:40:11 noise"]) {
                Button("Install update") {}.svButton(.notice, .small)
            }
            NoteView(.red, title: "ffmpeg not found", text: "The tools were not set up.", strong: "Set them up now?") {
                Button("Retry") {}.buttonStyle(SVTintedButtonStyle(.red))
            }
        }
    }

    private var settings: some View {
        SettingsGroup("General") {
            SettingsRow("Appearance", description: "System follows macOS; the change applies at once.") {
                CapsuleSegments([("system", "System"), ("light", "Light"), ("dark", "Dark")], selection: $appearance)
            }
            SettingsRow("Sampling", description: "Frames read per second of video.", defaultText: "Default: 6 fps") {
                SnapSlider(values: [2, 4, 6, 8, 12], selection: $fps, width: 200) { "\($0)" }
            }
            SettingsRow("Working folder") {
                PathField("~/Library/Application Support/SubVision/tmp", height: 26).frame(width: 220)
            }
        }
    }

    private var cards: some View {
        Card {
            CardTitle("Steps and drop zone", symbol: "list.number") {
                StatusChip("3 steps", tone: .accent)
            }
            NumberedSteps([
                .init(title: "Extract", detail: "Frames are read from the subtitle band.", done: true),
                .init(title: "Group", detail: "Frames that look alike become one line."),
                .init(title: "OCR", detail: "Each line is read with Vision."),
            ])
            DropZone(title: "Drop videos here", buttonTitle: "Choose…", primary: false, axis: .horizontal,
                     text: "MP4, MKV and MOV with burned-in subtitles.", onOpen: {}, onDrop: { _ in })
                .frame(height: 140)
        }
    }

    private var alerts: some View {
        HStack(alignment: .top, spacing: 24) {
            SVAlertCard(alert: Self.alert(icon: "info", tone: .accent, title: "Update available",
                                          text: "SubVision 2.1 is out.\nInstall it now or later.",
                                          buttons: [("Install", .primary), ("Later", .secondary)]))
            SVAlertCard(alert: Self.alert(icon: "stop-file", tone: .yellow, title: "Stop this file?",
                                          text: "What is done so far is kept.",
                                          buttons: [("Stop", .secondary), ("Keep going", .secondary)], checkbox: "Don't ask again"))
            SVAlertCard(alert: Self.alert(icon: "discard", tone: .red, title: "Discard the revised SRT?",
                                          text: "The edits cannot be recovered.",
                                          buttons: [("Discard", .destructiveSolid), ("Cancel", .secondary)]))
        }
        .padding(.vertical, 40).padding(.horizontal, 24)
    }

    /// The top bar's segments, the title band, the checkboxes (C3, DS4).
    private var navigation: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                TrafficLightsSlot()
                TopBarSegments {
                    TopBarSegment(symbol: "captions.bubble", title: "Video", selected: true, busy: true) {}
                    TopBarSegment(symbol: "doc.text.magnifyingglass", title: "Review", selected: false) {}
                    TopBarSegment(symbol: "text.badge.checkmark", title: "Sub fix", selected: false) {}
                }
                ChromeIconButton("sidebar.right", help: "Parameters", on: true) {}
                ChromeIconButton("gearshape", help: "Settings") {}
            }
            TitleBand(prefix: "Review of", name: "episode-01.mkv", subtitle: "16 lines · processed today",
                      backHelp: "Back to the list · ⌘[", back: {}) {
                Button("Show in Finder") {}.svButton(.secondary, .small)
            }
            .frame(width: 560)
            HStack(spacing: 14) {
                HeaderCheckbox(.off, help: "None") {}
                HeaderCheckbox(.mixed, help: "Some") {}
                HeaderCheckbox(.on, help: "All") {}
                SVCheckbox(isOn: true) {}.disabled(true)
            }
        }
        .padding(.vertical, 40)
    }

    private static func alert(icon: String, tone: SVTone, title: String, text: String,
                              buttons: [(String, SVButtonRole)], checkbox: String? = nil) -> SVAlert {
        let alert = SVAlert(icon: icon, tone: tone, title: title, text: text)
        for (title, role) in buttons { alert.button(title, role: role) }
        alert.checkbox = checkbox
        return alert
    }
}
