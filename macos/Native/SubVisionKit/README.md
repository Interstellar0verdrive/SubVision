# SubVisionKit

The local Swift package of the SubVision 2.0 macOS app: everything that doesn't need the app target itself. The app depends on it as a local package from `macos/Native/`; it is not published on its own.

## Modules

- `SVEngine`: the sidecar client, which spawns `subvision serve` and speaks the JSON-lines protocol (requests, replies, events, restart on crash).
- `SVDesign`: the design system, with colour tokens for both light and dark themes, type styles, buttons, boxes, alerts and the window chrome.
- `SVLocalization`: the localiser, with JSON catalogues per language and switching at run time.
- `SVShell`: the app frame, with window and settings scenes, tools setup at first launch, log, Dock progress, notifications and debug snapshots.

Working notes on the public API, in Italian: `API.md`.

## Build and test

```sh
cd macos/Native/SubVisionKit
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Requires macOS 26 and Xcode 27.

## Provenance

Several pieces were copied and adapted from the native macOS app of [AnimeUp](https://github.com/Interstellar0verdrive/AnimeUp), which I also wrote. The two projects stay separate: nothing here depends on AnimeUp, and the files that come from it say so in a comment.

## A note on how this was written

I wrote this code with AI assistance and tested it thoroughly, with me in the lead on every decision. Licensed under the MIT License, see `LICENSE`.
