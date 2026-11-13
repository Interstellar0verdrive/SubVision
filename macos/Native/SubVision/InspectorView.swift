// SPDX-License-Identifier: MIT
// The parameters inspector (design boards I1–I3, D5). F5.1 builds it; in F4
// the pane exists so ⌥⌘I and the button have somewhere to go.

import SVShell
import SwiftUI

struct InspectorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.t("app.inspector.title")).svFont(SVFont.sectionTitle).foregroundStyle(SV.text)
                Spacer()
                Button { model.toggleInspector() } label: {
                    Image(systemName: "xmark").svFont(11, .semibold).foregroundStyle(SV.text2)
                        .frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(model.t("app.inspector.close"))
            }
            Text(model.t("app.inspector.subtitle")).svSmall().fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 28)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SV.bg)
    }
}
