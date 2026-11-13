// SPDX-License-Identifier: MIT
// Review (design note 80, board C2-R1): the videos processed, with what is
// left to check. Filled in by the C2 design round.

import SVShell
import SwiftUI

extension AppModel {
    /// The videos of the list with an outcome to review: done or without subtitles.
    var reviewVideos: [VideoItem] { videos.filter { $0.state == .done || $0.state == .noSubs } }
}

struct ReviewPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        PlaceholderPage(title: model.t("app.review.title"), symbol: Tab.review.symbol, text: model.t("app.review.intro"))
    }
}
