// SPDX-License-Identifier: MIT
// Copied and adapted from the native macOS app of AnimeUp (AnimeUp/AppModel+Run.swift,
// `notify`), by the same author.

import Foundation
import UserNotifications

/// A user notification, after asking for permission the first time. Outside
/// a bundle (a bare executable) there is no notification centre: nothing is sent.
public func notify(title: String, body: String) {
    guard Bundle.main.bundleIdentifier != nil else { return }
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
        guard granted else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
