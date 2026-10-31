# Pin screenshots

## Goal

Keep a screenshot floating on top of other windows (like CleanShot's Pin) for reference while working.

## Design

New file `App/PinWindows.swift`:

- `@MainActor final class PinManager` (owned by `AppDelegate`): `pin(image: CGImage, sourceURL: URL?, at frame: NSRect?)`,
  `closeAll()`, keeps `[PinController]`, removes a controller when its panel closes.
- `PinPanel: NSPanel` — borderless, `.nonactivatingPanel`, `.resizable`; `canBecomeKey = true` (Esc, scroll);
  `level = .floating`; `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`; `hasShadow`;
  `isMovableByWindowBackground`; `contentAspectRatio` = image size; `isReleasedWhenClosed = false`.
- `PinView` (SwiftUI): the image filling the panel; ✕ button in the top-left corner on hover; right-click menu:
  Copy, Save to Screenshots, Edit…, Opacity (100/80/60/40%), Close, Close All Pins.
- Size: image pixels / screen backing scale, scaled down to fit 60% of the screen's visible frame, minimum 80 pt
  on the short side. Position: `frame` when given (area pins sit exactly over the captured area), otherwise
  centred on the main screen, offset by 24 pt per open pin.
- Resize: edge drag (AppKit, aspect kept), scroll wheel / pinch zoom ±10% per step around the centre
  (clamped 80 pt – screen size). Esc closes.
- Save to Screenshots: `StorageManager.newFileURL` + `ScreenshotService.write` (settings image format),
  `history.reload()`, and the pin remembers the new URL. Edit…: opens `sourceURL` in the editor, saving first
  when there is none.

Entry points (`AppUI.pin(image:sourceURL:at:)` implemented by `AppDelegate`):

- Post-capture card: "Pin" button for screenshots (loads the file).
- Editor: "Pin" button in the inspector Export section; pins `doc.renderOutput()` with `sourceURL = doc.fileURL`.
- History: context menu "Pin" for screenshots (`onPin` passed like `onCopyText`).
- `ShortcutAction.pinArea` ("Pin Area", default ⌃⌥⌘P) + status-item menu item: `AppModel.pinArea()` →
  area selection → capture → pin at the area's global frame. Nothing is saved.

## Out of scope

Persisting pins across launches, click-through/lock mode, annotating on a pin.

## Validation

Release build; harness checks pin frame for area pins (global coordinate conversion) and size capping;
manual check of the entry points and interactions.
