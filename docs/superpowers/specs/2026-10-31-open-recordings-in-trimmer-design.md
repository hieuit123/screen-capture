# Open recordings in the trim window

## Goal

Every "open a recording" action opens the built-in trim window instead of the macOS default player.

## Design

- `AppDelegate.openRecording(url:)` → `openTrimmer(url:)`. Used by:
  - post-capture card: thumbnail click and "Open" (new `openRecording` closure on `PostCaptureView`, passed by
    `PostCapturePanelController.show`);
  - History: double-click, context menu "Open", inspector "Open" (new `onOpenRecording` on `HistoryView`,
    `InspectorView`, passed through `HistoryWindowController`);
  - menu panel recent strip (already routed through `AppDelegate.open(_:)`).
  Screenshots are unchanged (editor / default actions).
- History context menu for recordings: "Open", "Trim…", and "Open in Default App" (`NSWorkspace.open`).
- `TrimWindowController`:
  - still starts in trim mode;
  - Cancel keeps the window open as a player instead of closing;
  - a "Trim" button (top-right of the video, ⌘T) re-enters trim mode; hidden while trimming or saving;
  - OK still trims, replaces the file and closes.

## Validation

Release build; harness: cancel keeps the window visible with the Trim button shown, the button restarts
trimming; manual check of all entry points.
