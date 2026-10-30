# Stacked capture previews

## Goal

After screenshot 1 its preview stays visible when screenshot 2 is taken; both previews stack instead of the
newer one replacing the older. Applies to the post-capture card (bottom-right) and the Quick Screenshot /
editor toast (bottom-center). At most 3 per stack; a 4th closes the oldest.

## Design

New `@MainActor final class FloatingPanelStack` in `App/WindowControllers.swift`:

- Config: `anchor` (`.bottomTrailing` = card, `.bottomCenter` = toast), `spacing = 10`, `maxCount = 3`,
  `dismissDelay` (card 8 s, toast 2.4 s), `hoverDismissDelay` (card 8 s, toast 1.2 s), `entryOffset`
  (card slides in from the right, toast rises 12 pt), `margin` (card 16, toast 40 from the bottom).
- `push(panel: NSPanel, screen: NSScreen) -> UUID` — adds an entry, closes the oldest entries on the same
  screen beyond `maxCount`, lays out, fades/slides the new panel in, schedules its dismissal.
- `setHovered(_ id:, _ hovering:)` — hovering pauses that entry's timer; leaving reschedules with
  `hoverDismissDelay`.
- `close(_ id:, animated:)` — fades out, removes the entry, animates the remaining entries into place.
- Layout per screen: newest at the bottom (`visibleFrame.minY + margin`), older entries above it, each
  `panel.frame.height + spacing` higher; x from the anchor. Entries on other screens are untouched.

`PostCapturePanelController` and `QuickCaptureToastController` keep their `show(...)` signatures; they build
the panel + SwiftUI view as today and hand it to their own stack. Close/click/hover callbacks target that
entry's id. `AppDelegate` and the SwiftUI views don't change.

## Out of scope

Compact cards, "close all", settings for the max count, stacking editor windows.

## Validation

Release build via `./scripts/build_app.sh`; manually take 4 screenshots quickly (with "Open editor after
screenshot" off) and 4 Quick Screenshots: 3 previews visible, oldest dropped, hover pauses, closing reflows.
