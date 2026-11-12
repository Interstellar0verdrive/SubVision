// SPDX-License-Identifier: MIT
// Copied and adapted from the design system of the native macOS app of AnimeUp
// (AnimeUpKit/DesignSystem/Box.swift, version 2.1), by the same author.
//
// The design draws every framed thing as a CSS `border-box`: a 1 pt line
// inside the box and the padding inside the line. So the content sits at
// line + padding from the edge, and a hugging box is 2 pt wider and taller
// than its padding alone. `svBox` is that box; every framed component uses it.

import SwiftUI

extension EdgeInsets {
    /// The same insets plus `amount` on every side.
    public func grown(by amount: CGFloat) -> EdgeInsets {
        EdgeInsets(top: top + amount, leading: leading + amount, bottom: bottom + amount, trailing: trailing + amount)
    }

    public init(vertical: CGFloat, horizontal: CGFloat) {
        self.init(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal)
    }
}

extension View {
    /// A CSS border-box: `padding` inside a `lineWidth` line, on `fill`.
    public func svBox<S: InsettableShape, F: ShapeStyle>(_ shape: S, fill: F, line: Color,
                                                         padding: EdgeInsets = EdgeInsets(),
                                                         lineWidth: CGFloat = 1) -> some View {
        self.padding(padding.grown(by: lineWidth))
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(line, lineWidth: lineWidth))
    }
}
