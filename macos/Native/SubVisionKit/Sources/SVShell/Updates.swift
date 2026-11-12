// SPDX-License-Identifier: MIT
// The update check of the native macOS app of AnimeUp (by the same author)
// went through its engine; here the app asks GitHub itself, so the engine
// needs no network code and the check works before the engine is up.

import AppKit
import Foundation
import SVDesign

/// The outcome of a check against the latest GitHub release.
public enum UpdateResult: Equatable, Sendable {
    /// A newer version, and the page to get it from.
    case available(version: String, url: URL)
    case upToDate
    case error(String)
}

public enum UpdateCheck {
    /// Reads `releaseAPIURL` (GitHub's `releases/latest`) and compares its tag
    /// with `currentVersion`. Tags may start with `v`; versions compare number
    /// by number (2.0.10 is newer than 2.0.9).
    public static func check(releaseAPIURL: URL, currentVersion: String, fallbackPage: URL,
                             session: URLSession = .shared) async -> UpdateResult {
        var request = URLRequest(url: releaseAPIURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return .error("HTTP \(http.statusCode)")
            }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = object["tag_name"] as? String else { return .error("no tag_name in the reply") }
            let latest = normalise(tag)
            let page = (object["html_url"] as? String).flatMap(URL.init(string:)) ?? fallbackPage
            return isNewer(latest, than: normalise(currentVersion)) ? .available(version: latest, url: page) : .upToDate
        } catch {
            return .error(String(describing: error))
        }
    }

    /// "v2.1.0" → "2.1.0".
    public static func normalise(_ tag: String) -> String {
        var s = tag.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        return s
    }

    /// Dotted numbers, missing parts count as 0; a suffix after `-` is ignored.
    public static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            v.split(separator: "-").first.map { $0.split(separator: ".").map { Int($0) ?? 0 } } ?? []
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }
}

/// The app menu's Check for Updates… and the sidebar footer: asks GitHub now and
/// always answers, in the app's own alert.
@MainActor
public func checkForUpdates(config: AppShellConfig, texts: ShellTexts = .english, session: URLSession = .shared,
                            busy: @escaping @MainActor (Bool) -> Void = { _ in }) {
    busy(true)
    Task {
        let result = await UpdateCheck.check(releaseAPIURL: config.releaseAPIURL, currentVersion: config.appVersion,
                                             fallbackPage: config.releasePageURL, session: session)
        busy(false)
        switch result {
        case .available(let version, let url):
            let alert = SVAlert(icon: "update", tone: .accent,
                                title: ShellTexts.fill(texts.updateAvailable, ["app": config.appName, "version": version]),
                                text: texts.updateAvailableText)
            alert.button(texts.updateDownload, role: .primary)
            alert.button(texts.updateLater, cancel: true)
            if alert.runModal() == 0 { NSWorkspace.shared.open(url) }
        case .upToDate:
            let alert = SVAlert(icon: "info", tone: .accent,
                                title: ShellTexts.fill(texts.upToDate, ["app": config.appName, "version": config.appVersion]),
                                text: texts.upToDateText)
            alert.button(texts.ok, role: .primary)
            alert.runModal()
        case .error(let message):
            AppLog.shared.error("update check failed: \(message)")
            let alert = SVAlert(icon: "error", tone: .red, title: texts.updateErrorTitle, text: texts.updateErrorText)
            alert.button(texts.ok, role: .primary)
            alert.runModal()
        }
    }
}
