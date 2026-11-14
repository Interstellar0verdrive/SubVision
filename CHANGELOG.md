# Changelog

All notable changes to SubVision. The full story of each release is on its
[release page](https://github.com/Interstellar0verdrive/SubVision/releases).

## [2.0.0] - <!-- TODO: release date -->

SubVision becomes a native macOS app (SwiftUI), with the Python engine running
inside it. Requires macOS 26 and an Apple Silicon Mac.

### Added

- Native app with three pages, **Video**, **Review** and **Sub fix**, and a
  separate **Preview** window; light and dark appearance; English and Italian,
  switchable on the fly; menus, keyboard shortcuts, macOS notifications and
  progress on the Dock icon.
- First-launch window that downloads uv and Python 3.13, FFmpeg and FFprobe
  9.0.2 (about 107 MB, pinned releases checked by SHA256, with resume) and
  prepares Vision's models once per macOS version. Everything lives in
  `~/Library/Application Support/SubVision`.
- Video page: drop files or folders (subfolders included), list kept between
  launches, per-file steps for each band with progress, time left and speed,
  outcome kept on each row, **Process Again**, end-of-batch sheet.
- **Stop the current file** and **Stop All**: a stopped file never leaves a
  half-written SRT. Closing the window doesn't stop the batch; ⌘Q asks first.
- **Parameters** panel in three tabs (Reading, Bands, Lines), kept between
  launches, with explanations, defaults, **Restore** and undo.
- OCR language chosen from the languages Vision reads on the Mac; an
  unsupported language is caught before the batch starts.
- Preview window: bands dragged on the frame, 20 frames with text found by
  zone (dialogue and signs flagged separately), **Try OCR** on both bands
  side by side, results kept per frame.
- Review page and an in-app window for the review report: **Save reviewed
  SRT** writes next to the original; edits are saved in `<video>.review.json`;
  1.x reports open too.
- Sub fix with drop or Open…, the values shared with Video on the same page,
  usable during a batch.
- Settings in four tabs (General, Tools, Lists, Updates): your own FFmpeg
  (Homebrew or a folder), `ignore.txt` and `corrections.txt` with Edit…,
  Import… and the starter lists, automatic update check at most once a day.
- Command line `subvision extract | fix | preview` for the same engine.

### Changed

- The review report is `<video>.review.html` (was `.revisione.html`), the
  reviewed SRT `<video>-reviewed-<date>.srt` (was `-revisionato-`), the
  corrections list `corrections.txt` (was `correzioni.txt`). The report
  carries both languages and follows the app's.
- Videos stay where they are; outputs still go next to each video, and an
  existing SRT is never overwritten.

### Removed

- The Streamlit interface, `run.command`, `requirements.txt` and the
  `./videos` folder.
- Support for macOS 10.15–15 and Intel Macs (1.0.0 remains available).
- The free-text OCR language field, "Clear /tmp" and `.ui_prefs.json`.
- The `import ocr_core` headless one-liner, replaced by the command line.

## [1.0.0] - 2026-10-19

First public release: hardsub extraction to SRT with Apple Vision and LiveText
(multiple readings with voting, timing refined at the native frame rate, signs
band with `{\an8}`, interactive review report, balanced line wrapping), with a
bilingual Streamlit interface (Process, Preview, Sub fix), a daily update
check and the Sintel demo.

[2.0.0]: https://github.com/Interstellar0verdrive/SubVision/releases/tag/v2.0.0
[1.0.0]: https://github.com/Interstellar0verdrive/SubVision/releases/tag/v1.0.0
