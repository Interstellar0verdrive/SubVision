// SPDX-License-Identifier: MIT
// The empty states of the three pages (design boards E0, A0, F0): three
// numbered step cards and a drop area that fills the rest of the page.

import SVShell
import SwiftUI

/// A page's title and intro, the actions on the right at the title's level.
struct PageTop<Trailing: View>: View {
    var title: String
    /// nil in a narrow window: the title alone (board N1).
    var intro: String?
    @ViewBuilder var trailing: () -> Trailing
    /// The intro wraps at the width of the boards' two lines.
    static var introWidth: CGFloat { 640 }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).svPageTitle()
                if let intro {
                    Text(intro).svBody().fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: Self.introWidth, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) { trailing() }
                .padding(.top, 2)
        }
    }
}

/// One of the three step cards: number, title, text (E0, A0).
struct StepCard: View {
    var number: Int
    var title: String
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(number)").svFont(12, .bold).foregroundStyle(SV.primaryText)
                .frame(width: 22, height: 22)
                .background(Circle().fill(SV.soft))
                .overlay(Circle().strokeBorder(SV.softLine))
                .padding(.bottom, 10)
            Text(title).svFont(13.5, .semibold).foregroundStyle(SV.text)
                .padding(.bottom, 6)
            Text(text).svSmall().fixedSize(horizontal: false, vertical: true)
        }
        // All three cards as tall as the tallest (board E0).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .svBox(RoundedRectangle(cornerRadius: SV.Radius.card), fill: SV.surface, line: SV.line,
               padding: EdgeInsets(vertical: 16, horizontal: 18))
    }
}

/// The big drop area of an empty page: a symbol, a title, "or" and the Open
/// button with its shortcut, a line under. The dashed frame of the design.
struct DropArea: View {
    var symbol: String
    var title: String
    var orText: String?
    var buttonTitle: String
    var shortcut: String
    var footnote: String?
    var footnoteMono = false
    var onOpen: () -> Void
    var onDrop: ([URL]) -> Void
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).svFont(40, .light).foregroundStyle(targeted ? SV.primaryText : SV.text3)
                .frame(height: 48)
                .padding(.bottom, 2)
            Text(title).svFont(14, .semibold).foregroundStyle(targeted ? SV.primaryText : SV.text)
            HStack(spacing: 6) {
                if let orText { Text(orText).svFont(13).foregroundStyle(SV.text2) }
                Button(action: onOpen) {
                    HStack(spacing: 6) {
                        Text(buttonTitle)
                        Text(shortcut).svFont(10, mono: true).opacity(0.7)
                    }
                }
                .svButton(.primary, .regular)
            }
            if let footnote {
                if footnoteMono {
                    Text(footnote).svFont(11, mono: true).foregroundStyle(SV.text3)
                } else {
                    Text(footnote).svSmall().multilineTextAlignment(.center)
                        .frame(maxWidth: 560).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .svDropFrame(targeted: targeted)
        .fileDrop(isTargeted: $targeted, action: onDrop)
    }
}

/// E0: Process with no videos.
struct ProcessEmptyView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(1...3, id: \.self) { n in
                    StepCard(number: n, title: model.t("app.process.empty.step\(n)"), text: model.t("app.process.empty.step\(n)_text"))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6)
            DropArea(symbol: "film", title: model.t("app.process.empty.drop"), orText: model.t("app.process.empty.or_open"),
                     buttonTitle: model.t("app.process.open"), shortcut: "⌘O",
                     footnote: model.t("app.process.empty.formats"), footnoteMono: true,
                     onOpen: { model.openVideos() }, onDrop: { model.add($0) })
                .padding(.top, 18)
        }
    }
}

/// A0: Preview with no videos in Process.
struct PreviewEmptyView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.svPageTop) private var top

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageTop(title: model.t("app.preview.title"), intro: model.t("app.preview.intro")) { EmptyView() }
                .padding(.bottom, 18)
            HStack(alignment: .top, spacing: 16) {
                ForEach(1...3, id: \.self) { n in
                    StepCard(number: n, title: model.t("app.preview.empty_\(n)"), text: model.t("app.preview.empty_\(n)_text"))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            DropArea(symbol: "viewfinder", title: model.t("app.preview.empty_title"),
                     orText: model.t("app.process.empty.drop") + model.t("app.common.list_separator") + model.t("app.process.empty.or_open"),
                     buttonTitle: model.t("app.process.open"), shortcut: "⌘O",
                     footnote: model.t("app.preview.empty_drop_text"),
                     onOpen: { model.openVideos() }, onDrop: { model.add($0) })
                .padding(.top, 18)
        }
        .padding(.horizontal, 28)
        .padding(.top, top)
        .padding(.bottom, 28)
    }
}

/// F0: Sub fix with no SRT.
struct FixEmptyView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.svPageTop) private var top

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageTop(title: model.t("app.fix.title"), intro: model.t("app.fix.intro")) {
                Button { openSRT() } label: {
                    HStack(spacing: 6) {
                        Label(model.t("app.fix.open"), systemImage: "doc")
                        Text("⇧⌘O").svFont(10, mono: true).foregroundStyle(SV.text3)
                    }
                }
                .svButton(.secondary, .regular)
            }
            .padding(.bottom, 18)
            DropArea(symbol: "text.badge.checkmark", title: model.t("app.fix.drop"), orText: model.t("app.process.empty.or_open"),
                     buttonTitle: model.t("app.fix.open"), shortcut: "⇧⌘O",
                     footnote: model.t("app.fix.why"),
                     onOpen: { openSRT() }, onDrop: { receive($0) })
        }
        .padding(.horizontal, 28)
        .padding(.top, top)
        .padding(.bottom, 28)
    }

    /// F5.3 takes these over: here the chosen file is only remembered.
    private func openSRT() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "srt") ?? .plainText]
        panel.message = model.t("app.menu.open_panel_srt")
        if panel.runModal() == .OK, let url = panel.url { model.fixPath = url }
    }

    private func receive(_ urls: [URL]) {
        if let srt = VideoScan.videos(in: urls, extensions: ["srt"], recursive: false).first { model.fixPath = srt }
    }
}
