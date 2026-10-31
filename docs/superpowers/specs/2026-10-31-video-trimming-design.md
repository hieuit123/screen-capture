# Video trimming

## Goal

Cut the start and/or end off a recording, QuickTime-style, from the post-recording card or History. The trimmed
video replaces the original; the original goes to the Trash so it can be recovered.

## Approach

Use AVKit's built-in trimming UI (`AVPlayerView.canBeginTrimming` / `beginTrimming(completionHandler:)`) and
export with `AVAssetExportSession` using `AVAssetExportPresetPassthrough` + `timeRange` — no re-encode, so it's
fast and lossless. (Rejected: custom timeline UI — much more work; re-encoding export — slower, lossy.)

## Components

### `Services/VideoTrimmer.swift` (new)

`enum VideoTrimmer { static func trim(_ url: URL, to range: CMTimeRange) async throws }`

1. `AVURLAsset(url:)`; `AVAssetExportSession(asset:presetName: AVAssetExportPresetPassthrough)`;
   `outputFileType` from the extension (`.mp4` / `.mov`, via `VideoContainer`); `timeRange = range`.
2. Export to `StorageManager.temporaryURL(for: url)` (hidden `.UUID.ext` sibling — never shown in History)
   with `try await session.export(to:as:)`.
3. Copy the original's `.creationDate` to the new file (keeps the History position).
4. `FileManager.trashItem(at: url)`, then `moveItem(temp → url)`.
5. On any failure: delete the temp file, leave the original untouched, rethrow
   (`TrimError.exportFailed(String)` / `.nothingToTrim`, `LocalizedError`).
A range equal to the full duration returns without doing anything.

### `App/TrimWindowController.swift` (new)

`@MainActor final class TrimWindowController: NSWindowController, NSWindowDelegate`

- Window (titled "Trim — <name>", ~900×600, resizable) whose content view is an `AVPlayerView`
  (`controlsStyle = .inline`) with `AVPlayer(url:)`.
- On show: wait for the item to be ready (`canBeginTrimming`), then `beginTrimming`.
  - `.okButton`: read `player.currentItem.reversePlaybackEndTime` / `forwardPlaybackEndTime` as the range,
    pause, show a spinner overlay/“Saving…” title, `await VideoTrimmer.trim`, then `onFinish(url)` and close.
    On error: `NSAlert(error:)` sheet, stay open so the user can retry or cancel.
  - `.cancelButton`: close.
- `present()` / `onClose` like the other window controllers (activation-policy handling).

### Wiring

- `AppDelegate.openTrimmer(url:)`: one controller per URL (reuse if open), `onFinish` → `model.history.reload()`
  and a toast "Recording trimmed"; `onClose` → remove + `updateActivationPolicySoon()`.
- `PostCaptureView`: new `trim: (() -> Void)?` → "Trim" button for recordings (where "Edit" shows for screenshots);
  `PostCapturePanelController.show(…, trim:)`; `AppDelegate.showPostCapture` passes it for recordings.
- `HistoryView`: `onTrim: (CaptureItem) -> Void`; context menu "Trim…" for recordings; passed through
  `HistoryWindowController` like `onEdit` / `onCopyText` / `onPin`.
- `ThumbnailCache`: durations are cached by URL; drop the entry for the trimmed URL (`invalidate(url)`) so the
  badge updates. Thumbnails are keyed by modification date, so they refresh on their own.

## Out of scope

Auto-opening the trimmer after recording, GIF export, cropping, removing a middle section, keyboard-only trimming.

## Validation

- Harness: write a 6 s test clip with `AVAssetWriter`, `VideoTrimmer.trim(url, 1s–3s)`, assert the new duration
  ≈ 2 s (±0.1), the original is in the Trash, the creation date is preserved, and a failing export leaves the
  original in place.
- Release build; manual check from the card and History (trim UI, cancel, replace, History refresh).

## Implementation plan

1. `VideoTrimmer` + harness test (TDD-style: write the harness first, see it fail, implement).
2. `ThumbnailCache.invalidate(_:)`.
3. `TrimWindowController`.
4. `AppDelegate.openTrimmer` + post-capture card `trim` + History `onTrim`.
5. Release build, manual check, update README and `.architecture/` (CODEMAP, CHANGE-GUIDE, FLOWS, graph).
