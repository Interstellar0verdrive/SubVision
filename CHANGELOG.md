# Changelog

All notable changes to SubVision. The full story of each release is on its
[release page](https://github.com/Interstellar0verdrive/SubVision/releases).

## [2.0.0] - <!-- TODO: release date -->

SubVision becomes a native macOS app (SwiftUI), with the Python engine running
inside it. Requires macOS 26 and an Apple Silicon Mac.

### Added

- Native app in one window with three pages, **Video**, **Review** and
  **Sub fix**, as tabs in the top bar (⌘1 ⌘2 ⌘3); the Preview opens inside
  the Video page and the review report inside the Review page. Light and dark
  appearance; English and Italian, switchable on the fly; menus, keyboard
  shortcuts, macOS notifications and progress on the Dock icon. The window
  opens at least 1360 × 860 pt; below 1100 pt the Parameters panel retracts
  to a button and opens over the page.
- First-launch window that downloads uv and Python 3.13, FFmpeg and FFprobe
  9.0.2 (about 107 MB, pinned releases checked by SHA256, with resume) and
  prepares Vision's models once per macOS version. Everything lives in
  `~/Library/Application Support/SubVision`.
- Video page: drop files or folders (subfolders included), list kept between
  launches, one checkbox per row for what to process (new videos come in
  checked, a finished one can be checked again and **will be redone**), a
  bottom button that says what it does (**Process 2 videos**, ⌘↩) with an
  estimate, rows that open with a click (time of each step, result and files
  for a finished video; what is known, what it will read, the estimate and
  five frames for one still to process), one main action per row (Preview,
  Review, Retry, Stop) and a ⋯ menu equal to the right-click menu, and
  keyboard navigation (↑ ↓, Space, → ←, ⌫, ⌘Z).
- Per-file steps for each band with progress, time left and speed; a batch
  bar at the bottom of every page, with one segment per file weighted by
  duration, the expected end and **Stop All**; an end-of-batch sheet over
  whatever page is open, failed files included.
- **Stop the current file** and **Stop All**: a stopped file never leaves a
  half-written SRT. **Retry** runs a failed or stopped file at once, or
  queues it after the running batch. Closing the window doesn't stop the
  batch; ⌘Q asks first.
- **Parameters** panel in three tabs (Reading, Bands, Lines), always open
  beside the page and locked during a batch, kept between launches, with
  explanations, values that differ from the default in their own colour, the
  default marked on each slider, **Restore** and undo.
- OCR language chosen from the languages Vision reads on the Mac; an
  unsupported language is caught before the batch starts.
- Preview inside the Video page (⌘Y, back with ⌘[, video above and below
  with ⌘↑ ⌘↓): bands dragged on the frame, 20 frames with text found by
  itself by zone (dialogue and signs flagged separately, an interrupted search
  resumes), **Try OCR** on both bands side by side, results kept per frame
  and marked when the parameters changed after the test.
- Review page listing the processed videos, with the review report opening
  inside it: a report bar that stays at the top (**Save reviewed SRT**, ⌘S,
  writes next to the original; **Reset all…** asks first), the duration of
  each line, alternative readings with the differing words highlighted,
  **Original**, a per-line "It's a sign" box, a legend fixed at the bottom,
  gaps without subtitles over the threshold of the Lines tab, lines added by
  hand. Every Review in the app opens it there. Edits are saved in
  `<video>.review.json`; 1.x reports open too.
- Sub fix with drop or Choose SRT…, the values shared with Video on the
  same page, usable during a batch.
- Settings in four tabs (General, Tools, Lists, Updates): your own FFmpeg
  (Homebrew or a folder), `ignore.txt` and `corrections.txt` with Edit…,
  Import… and the starter lists, automatic update check at most once a day,
  with a capsule in the tab bar when a new version is out. Version, update
  check and GitHub link in the SubVision menu.
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
