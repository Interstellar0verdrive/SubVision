// SPDX-License-Identifier: MIT
// Copied and adapted from the native macOS app of AnimeUp (AnimeUp/MainView.swift,
// `EngineStatusView`), by the same author: the status, texts and actions are parameters.

import SVDesign
import SwiftUI

/// Where the engine stands, as the app's model tracks it.
public enum EngineStatus: Equatable, Sendable {
    case starting
    case ready
    case failed(String)
    case gaveUp
}

/// The engine is starting, or didn't: shown in place of the page.
public struct EngineStatusView: View {
    var status: EngineStatus
    var texts: ShellTexts
    var retry: () -> Void
    var showLog: () -> Void

    public init(status: EngineStatus, texts: ShellTexts = .english,
                retry: @escaping () -> Void, showLog: @escaping () -> Void) {
        self.status = status
        self.texts = texts
        self.retry = retry
        self.showLog = showLog
    }

    public var body: some View {
        VStack(spacing: 14) {
            switch status {
            case .starting:
                Spinner(size: 22)
                Text(texts.engineStarting).svBody(SV.text)
                Text(texts.engineFirst).svSmall()
            case .failed(let error):
                NoteView(.red, title: texts.engineFailed, text: error) {
                    Button(texts.retry, action: retry).buttonStyle(SVTintedButtonStyle(.red))
                    Button(texts.showLog, action: showLog).buttonStyle(SVTintedButtonStyle(.red))
                }
                .frame(maxWidth: 560)
            case .gaveUp:
                NoteView(.red, title: texts.engineFailed, text: texts.engineGaveUp) {
                    Button(texts.showLog, action: showLog).buttonStyle(SVTintedButtonStyle(.red))
                }
                .frame(maxWidth: 560)
            case .ready:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
