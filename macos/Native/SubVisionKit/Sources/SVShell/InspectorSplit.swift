// SPDX-License-Identifier: MIT
// The parameters inspector's place on the Process and Preview pages (design
// inventory §0 and §3, boards I1 and N2): beside the page in a window of
// 1000 pt or more, over it from the right below that.

import SVDesign
import SwiftUI

/// A page with the inspector on its right, `SVChrome.inspectorWidth` wide.
/// In a window narrower than `SVChrome.inspectorOverlayBelow` (read from
/// `svWindowWidth`, which `MainSplit` sets) the inspector covers the page with
/// a shadow and closes with Esc or a click outside it. The inspector's look
/// (background, header, groups) is the app's.
public struct InspectorSplit<Page: View, Inspector: View>: View {
    @Binding var isOpen: Bool
    @ViewBuilder var page: () -> Page
    @ViewBuilder var inspector: () -> Inspector
    @Environment(\.svChrome) private var chrome
    @Environment(\.svWindowWidth) private var windowWidth

    public init(isOpen: Binding<Bool>, @ViewBuilder page: @escaping () -> Page,
                @ViewBuilder inspector: @escaping () -> Inspector) {
        self._isOpen = isOpen
        self.page = page
        self.inspector = inspector
    }

    public var body: some View {
        let overlays = chrome.inspectorOverlays(windowWidth: windowWidth)
        HStack(spacing: 0) {
            page().frame(maxWidth: .infinity, maxHeight: .infinity)
            if isOpen && !overlays {
                pane.transition(.move(edge: .trailing))
            }
        }
        .overlay {
            if isOpen && overlays {
                ZStack(alignment: .trailing) {
                    // A click outside the inspector closes it.
                    Color.clear.contentShape(Rectangle()).onTapGesture { isOpen = false }
                    pane
                        .background(SV.bg)
                        .shadow(color: SV.shadow.opacity(0.35), radius: 12, x: -4)
                        .onExitCommand { isOpen = false }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: isOpen)
    }

    private var pane: some View {
        inspector()
            .frame(width: chrome.inspectorWidth)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .leading) { Rectangle().fill(SV.line).frame(width: 1) }
    }
}
