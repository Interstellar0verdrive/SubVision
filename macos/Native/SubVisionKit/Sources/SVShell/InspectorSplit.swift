// SPDX-License-Identifier: MIT
// The parameters panel's place on the Video and Preview pages (design boards
// C2-V1, N1, N2, design note 50, C3-03): always beside the page in a window of
// 1100 pt or more, where it never closes; over it from the right below that.

import AppKit
import SVDesign
import SwiftUI

extension EnvironmentValues {
    /// True for a parameters panel laid over the page of a narrow window (N2); beside
    /// the page it cannot be closed. The panel has no × of its own: the top bar's
    /// panel button closes it.
    @Entry public var svInspectorOverlaid = false
}

/// A page with the parameters panel on its right, `SVChrome.inspectorWidth` wide.
/// In a window of `SVChrome.inspectorOverlayBelow` or more (read from
/// `svWindowWidth`, which `MainSplit` sets) the panel is always there and
/// `isOpen` does not matter. In a narrower window the panel covers the page
/// with a shadow while `isOpen`, and closes with the top bar's panel button
/// (the app's), Esc or a click outside it (`svInspectorOverlaid`). The panel's look (background, header,
/// sections) is the app's.
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
            // The page takes the room left and never more: a page whose content asks for more
            // than the window would widen the split past the window's right edge, and the panel,
            // beside it or laid over it from the trailing edge, would be cut off there.
            page()
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            if !overlays {
                pane
            }
        }
        .overlay {
            if isOpen && overlays {
                ZStack(alignment: .trailing) {
                    // A click outside the panel closes it.
                    Color.clear.contentShape(Rectangle()).onTapGesture { isOpen = false }
                    pane
                        .environment(\.svInspectorOverlaid, true)
                        // C2-N1: the shadow falls on the page, to the left.
                        .shadow(color: SV.shadow.opacity(0.35), radius: 20, x: -16)
                        .background { EscapeCatcher { isOpen = false } }
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
            .background(SV.surface)
            .overlay(alignment: .leading) { Rectangle().fill(SV.line).frame(width: 1) }
    }
}

/// Esc closes the laid-over panel wherever the focus is in its window (the
/// panel rarely holds it, so `onExitCommand` alone would miss the key). Not
/// while a sheet is up, and not in another window.
private struct EscapeCatcher: NSViewRepresentable {
    var action: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.action = action
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) { view.action = action }

    final class CatcherView: NSView {
        var action: (() -> Void)?
        private var monitor: Any?

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.window, event.window === window, window.attachedSheet == nil,
                      event.keyCode == 53, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty
                else { return event }
                self.action?()
                return nil
            }
        }
    }
}
