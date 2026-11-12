// SPDX-License-Identifier: MIT
// Copied and adapted from the native macOS app of AnimeUp (AnimeUp/AppModel+Run.swift,
// `DockProgress` and `DockView`), by the same author: the fraction, the badge
// and the colours are parameters.

import AppKit
import SVDesign

/// A progress bar and a badge on the Dock icon while work runs.
@MainActor
public enum DockProgress {
    /// `fraction` nil clears the bar and the badge.
    public static func update(fraction: Double?, paused: Bool = false, badge: String? = nil,
                              colors: DockColors = .standard) {
        let tile = NSApp.dockTile
        guard let fraction else {
            if tile.contentView != nil || tile.badgeLabel != nil {
                tile.contentView = nil
                tile.badgeLabel = nil
                tile.display()
            }
            return
        }
        let view = (tile.contentView as? DockView) ?? DockView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
        view.fraction = fraction
        view.paused = paused
        view.colors = colors
        tile.contentView = view
        tile.badgeLabel = badge
        tile.display()
    }
}

public final class DockView: NSView {
    var fraction: Double = 0
    var paused = false
    var colors = DockColors.standard

    public override func draw(_ dirtyRect: NSRect) {
        NSApp.applicationIconImage.draw(in: bounds)
        let bar = NSRect(x: 14, y: 10, width: bounds.width - 28, height: 12)
        colors.track.setFill()
        NSBezierPath(roundedRect: bar, xRadius: 6, yRadius: 6).fill()
        let inner = bar.insetBy(dx: 2, dy: 2)
        var fill = inner
        fill.size.width = max(inner.height, inner.width * CGFloat(min(1, max(0, fraction))))
        (paused ? colors.paused : colors.running).setFill()
        NSBezierPath(roundedRect: fill, xRadius: 4, yRadius: 4).fill()
    }
}
