# Architecture

## 1. Layers & ownership

| Layer | Folder | Role | Isolation |
|-------|--------|------|-----------|
| Entry | `main.swift` | Creates `NSApplication`, `AppDelegate`, `.accessory` policy, runs loop | MainActor |
| Shell | `App/AppDelegate.swift` | Status item, popover, context menu, main menu, hot-key wiring, owns all window controllers. Implements `AppUI` | `@MainActor` |
| Coordinator | `App/AppModel.swift` | Capture state machine (`Phase`), orchestrates services, decides post-capture UI. Talks to the shell **only via `weak var ui: AppUI`** | `@MainActor @Observable` |
| Windows | `App/WindowControllers.swift` | `HistoryWindowController`, `EditorWindowController`, `SettingsWindowController`, `QuickCaptureToastController`, `PostCapturePanelController`, `NSApplication.forceActivate()` | `@MainActor` |
| Models | `Models/` | Option enums, `CaptureItem`, `AreaSelection`, `SettingsStore`, `Shortcut`/`ShortcutAction` | value types + `@MainActor` store |
| Services | `Services/` | Capture, recording, file system, hot keys, thumbnails | mixed (see §4) |
| Editor | `Editor/` | Annotation editor: document model, renderer, SwiftUI view | `@MainActor` |
| Views | `Views/` | SwiftUI: menu panel, history, settings, post-capture card, shared bits | SwiftUI |

### Ownership (who creates/holds whom)

- `AppDelegate` **owns** `AppModel`, `NSStatusItem`, `NSPopover(MenuView)`, `HistoryWindowController?`,
  `SettingsWindowController?`, `[EditorWindowController]`, `PostCapturePanelController`, `QuickCaptureToastController`,
  `PinManager` (floating pins), `[TrimWindowController]`.
- `AppModel` **owns** `SettingsStore`, `ShareableContentStore`, `HistoryStore`, `AreaSelector`,
  `RecordingFrameOverlay`, current `ScreenRecorder?`.
- `EditorWindowController` **owns** one `EditorDocument` and hosts `EditorView`.
- Singletons: `HotKeyManager.shared`, `ThumbnailCache.shared`. Stateless enums: `StorageManager`,
  `ScreenshotService`, `CaptureTargetResolver`, `FullPageCapture`, `EditorRenderer`, `MainMenu`, `EditorZoom`.

## 2. Key abstractions

- **`AppUI` protocol** (AppModel.swift:7) — the model→shell boundary: `dismissPopover`, `phaseDidChange`,
  `showPostCapture`, `openEditor(url:image:beautify:)`, `showQuickCaptureToast`, `showTextToast`, `pin`, `openHistory`, `showError`,
  `isPopoverShown`. New UI side effects go here and are implemented in `AppDelegate`.
- **`AppModel.Phase`**: `idle → preparing → recording(since:) → finishing → idle`. Screenshots are allowed while
  recording (they only set `preparing` if started from idle). `didSet` calls `ui.phaseDidChange()`
  (status-bar icon + 1 s timer).
- **`CaptureTarget`** (CaptureTargetResolver.swift:4): `SCContentFilter` + optional `sourceRect` (area crop, points,
  top-left origin) + `nativePixelSize` + optional `AreaSelection`. Built by `CaptureTargetResolver.resolve`
  (and ad hoc by `FullPageCapture`), consumed by `ScreenshotService.capture` and `ScreenRecorder.start`.
- **`RecordingOptions`** (ScreenRecorder.swift:4): snapshot of settings for one recording; computes
  `outputSize` (scaled, even, clamped H.264 ≤4096×2304, HEVC ≤8K) and `bitrate` (2–240 Mbps).
- **Editor model:** `Annotation { id, shape: AnnotationShape, color, lineWidth, filled, fontSize, borderColor }`.
  `AnnotationShape` = rectangle/ellipse/line/arrow/pencil/highlighter/text/pixelate/blackout/counter.
  `BeautifySettings` (Codable, persisted as the default style) → `CanvasLayout` (canvas size, image rect, corner, shadow).
- **Errors:** `CaptureError`, `RecorderError`, `FullPageError`, all `LocalizedError`. `AppModel` surfaces
  `error.localizedDescription` via `ui.showError`, which adds "Open System Settings" when the message contains
  "System Settings" (pane picked by "Microphone"/"Automation" substrings).

## 3. Persistence & files

- **Settings:** `SettingsStore`. Each property writes to `UserDefaults.standard` in `didSet`; keys are in the private
  `enum Keys` (versioned: `shortcuts.v1`, `beautifyStyle.v1`; `shortcuts.seenActions` migrates newly added actions).
  Changing `shortcuts` fires `onShortcutsChanged` → `AppDelegate.registerHotKeys()`.
- **Output files:** `StorageManager` → `~/Documents/ScreenCapture/{videos,images}`, named
  `"Recording|Screenshot yyyy-MM-dd 'at' HH.mm.ss[ (n)].ext"`. Recordings are written to a hidden
  `.UUID.ext` sibling and moved into place when finished.
- **History:** `HistoryStore` scans both folders off-main (`Task.detached`), sorted by creation date, and watches
  them with `DispatchSource` file-system events (debounced 250 ms). No database.
- Editor saves overwrite the original file (format from its extension) unless "Save As" is used.

## 4. Concurrency model

- Almost everything is `@MainActor` (Swift 6 strict concurrency, `-swift-version 6`).
- `ScreenRecorder` is `@unchecked Sendable`; **all writer state is confined to its serial `queue`**, which is also
  the SCStream sample-handler queue, so there are no locks. Frames are dropped when the encoder is busy.
  On stop, the last frame is re-stamped at "now" so static endings aren't cut short.
- Image encoding (`ScreenshotService.write`, `nonisolated`) and folder scans run in `Task.detached`.
- Carbon hot-key, Dispatch and Timer callbacks hop back with `MainActor.assumeIsolated`.
- `AreaSelector.selectArea` bridges the AppKit overlay to async via `CheckedContinuation`.

## 5. Invariants / gotchas

- **Preview == export:** `EditorRenderer` draws annotations for both the live `Canvas` (via `withCGContext`) and the
  exported `CGImage`. Contexts are **y-down**; export flips the context first. Don't draw annotations anywhere else.
- **Annotation coordinates are image pixels**, not view points. `AnnotationLayer` converts with `p / scale`;
  `EditorDocument.viewScale` keeps hit tolerances constant on screen; `unit = max(1, longSide/1600)` scales
  stroke/text sizes.
- **Undo** is snapshot-based (`image`, `pixelated`, `annotations`, max 100). Call `pushUndo()` *before* mutating.
  Crop replaces `image` and offsets every annotation.
- **Auto-Beautify:** clipboard/disk get `EditorRenderer.render(..., beautify: style.applied)`, but the editor gets the
  **raw** image with Beautify enabled so it stays editable. Editor style changes write back to
  `settings.beautifyStyle` via `onBeautifyChanged`.
- **Own app is excluded** from display/area captures (`excludingApplications: ownApps`); overlays use
  `sharingType = .none`. Short sleeps (120–180 ms) let the popover/overlay disappear before capturing.
- **Area selection must not steal key focus (screenshots):** making the overlay key makes the frontmost app resign key,
  which closes its popups (Chrome dropdowns, menus). `.screenshot` overlays are non-key; Esc comes from a temporary
  Carbon hotkey (no Input Monitoring needed) that is unregistered in `finish`. `.recording` overlays stay key.
- **Activation policy:** `.accessory` by default; `.regular` (Dock icon) while History/Settings/Editor windows are
  visible (`updateActivationPolicySoon`). Use `NSApp.forceActivate()` so windows get key focus after a global hot key.
- **Hot keys:** Carbon `RegisterEventHotKey` (no Accessibility permission). `suspend()/resume()` while recording a
  new shortcut in Settings. Registration failures are exposed via `HotKeyManager.failedActions`.
- **Full-page capture:** AppleScript `execute javascript` in Chromium browsers. Injects a magenta 12 CSS-px marker
  to locate the viewport inside the window capture, scrolls either the document or the largest inner scroll
  container, hides fixed/sticky elements after the first slice, stitches up to 32,000 px, and always runs
  `Scripts.restore` (`defer`).
- **Permissions:** screen recording (`CGPreflight/RequestScreenCaptureAccess`), microphone (requested at record
  start), Automation (AppleScript error -1743 → `FullPageError.automationDenied`). Ad-hoc signing means
  permissions reset after a rebuild.

## 6. Build & tooling

- `Package.swift`: tools 6.2, `.macOS(.v26)`, one `executableTarget`, links `AVKit`.
- `scripts/build_app.sh`: runs `swiftc -swift-version 6 -wmo` over all sources (not SwiftPM), bundles
  `Resources/Info.plist`, renders the icon once via `scripts/make_icon.swift`, then `codesign`
  (ad hoc unless `SIGN_IDENTITY` is set).
- `scripts/make_dmg.sh`: builds (unless `SKIP_BUILD=1`), then `hdiutil` creates a DMG named after the plist version.
- Validation = compile with `./scripts/build_app.sh` (or `swift build`). No unit tests or linters are configured.
