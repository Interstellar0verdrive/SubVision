// SPDX-License-Identifier: MIT
// Copied and adapted from the native macOS app of AnimeUp (AnimeUp/AppModel+Run.swift,
// `notify`), by the same author: an identifier, a payload and a click handler added.

import Foundation
import UserNotifications

/// A user notification, after asking for permission the first time. Outside
/// a bundle (a bare executable) there is no notification centre: nothing is sent.
/// The same `identifier` replaces the previous one; `userInfo` comes back to
/// `ShellNotifications.onClick` (e.g. `["page": "process", "sheet": "summary"]`).
/// The app checks its own Settings switch before calling.
public func notify(title: String, body: String, identifier: String = UUID().uuidString,
                   userInfo: [String: String] = [:]) {
    guard Bundle.main.bundleIdentifier != nil else { return }
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
        guard granted else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = userInfo
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }
}

/// The click on one of the app's notifications: macOS brings the app forward,
/// `onClick` gets the notification's `userInfo` (open Process and the summary
/// sheet). Call `install()` once at launch, before the first notification.
@MainActor
public final class ShellNotifications: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = ShellNotifications()
    public var onClick: @MainActor ([String: String]) -> Void = { _ in }
    /// Show the banner while the app is in front too (off: the window says it already).
    public var presentWhileActive = false

    public func install() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().delegate = self
    }

    public nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                                   withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let payload = info.reduce(into: [String: String]()) { out, pair in
            if let k = pair.key as? String, let v = pair.value as? String { out[k] = v }
        }
        Task { @MainActor in
            ShellNotifications.shared.onClick(payload)
            completionHandler()
        }
    }

    public nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                                   withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in
            completionHandler(ShellNotifications.shared.presentWhileActive ? [.banner, .sound] : [])
        }
    }
}
