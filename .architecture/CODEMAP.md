# Code Map

Paths are relative to `Sources/ScreenCapture/`. `Lnn` = line anchor (v1.4.6). LOC in parentheses.

## Entry

### `main.swift` (11)
Creates `NSApplication`, sets `AppDelegate`, `.accessory` activation policy, runs the app.

## App/

### `App/AppDelegate.swift` (359) — AppKit shell, implements `AppUI`
- `final class AppDelegate: NSApplicationDelegate, AppUI` L5
  - `applicationDidFinishLaunching` L17: ensure folders, `model.ui = self`, main menu, status item, popover,
    hot keys, `history.start()`.
  - `applicationShouldTerminate` L33: stops an active recording before quitting.
  - Status item: `setupStatusItem` L44, `statusItemClicked` L54 (right-click/⌃-click → menu, recording → stop,
    else popover), `updateStatusItem` L66 (red stop icon + timer while recording).
  - `showContextMenu` L91 + `item(_:shortcut:action:)` L115 + `@objc menu*` actions L125–136.
  - `setupPopover` L141 (hosts `MenuView`), `togglePopover` L156 (refreshes content).
  - `registerHotKeys` L173: `HotKeyManager.shared.configure` → `AppModel` actions.
  - `open(_ CaptureItem)` L186, `openSettings` L195, `updateActivationPolicySoon` L206.
  - **AppUI impl:** `dismissPopover`, `phaseDidChange` (status timer), `showPostCapture`, `isPopoverShown`,
    `showQuickCaptureToast`, `openEditor(url:image:beautify:)` L252 (dedupes per URL, wires `onSaved`,
    `onBeautifyChanged`, `onFinish` → toast, `onClose`), `openHistory` L284, `showError` L297 (NSAlert +
    System Settings deep link).
- `enum MainMenu` L317: minimal App/File/Edit/Window menus (⌘, ⌘W ⌘C ⌘V …).

### `App/AppModel.swift` (272) — coordinator
- `protocol AppUI` L7 (see ARCHITECTURE §2).
- `@Observable final class AppModel` L21
  - `enum Phase { idle, preparing, recording(since:), finishing }` L22.
  - Owns `settings`, `content`, `history`; private `recorder`, `pendingOutputURL`, `areaSelector`, `frameOverlay`.
  - `refreshContent` L49, `requestScreenPermission` L56, `fixSelections` L63 (keeps selected display/window/app valid).
  - Public actions: `performPrimaryAction` L77, `toggleRecording` L81, `takeScreenshot` L89,
    `quickScreenshot` L96, `captureArea` L145, `captureFullPage` L151, `captureText` (area → OCR, no file),
    `copyRecognizedText(from:displayID:)` (OCR → clipboard → `ui.showTextToast`; also used by History),
    `pinArea` (area → `ui.pin` at the area's global frame), `saveToScreenshots(_:)`.
  - `captureQuickScreenshot` L104 (resolve display under mouse → capture → `finalImage` → clipboard → sound →
    write → toast).
  - `finalImage(for:)` L134 (auto-Beautify via `EditorRenderer.render`), `shutterSound` L139.
  - `resolveTarget(source:mode:)` L161 (dismiss popover, optional `AreaSelector`, sleep, `CaptureTargetResolver`).
  - `startRecording` L173 (mic permission → target → `RecordingOptions` → `ScreenRecorder.start` → frame overlay),
    `stopRecording` L211.
  - `captureScreenshot(source:)` L228, `saveScreenshot(_ capture:)` L235 (shared save pipeline),
    `didSave(_:kind:image:)` L258 (open editor **or** post-capture panel).

### `App/WindowControllers.swift` (402)
- `HistoryWindowController` L5: hosts `HistoryView`; `show(kind:select:)` sets `HistoryViewState`.
- `EditorWindowController` L50: hosts `EditorView`; `present`, `finish` (close + `onFinish`), a local `keyDown`
  monitor (`deleteKeyMonitor`) that deletes the selected mark on Backspace/Delete regardless of SwiftUI focus,
  `windowShouldClose` L107 (Save / Don't Save / Cancel sheet when `isDirty`).
- `SettingsWindowController` L146: hosts `SettingsView`.
- `FloatingPanelStack` L181: stacks preview `NSPanel`s per screen (newest at bottom, max 3, oldest dropped),
  per-panel auto-dismiss timer paused on hover, animated reflow on close. API: `push(_:id:on:)`, `setHovered`, `close`.
- `QuickCaptureToastController` L317: bottom-center HUD (`QuickCaptureToastView`) on a stack, 2.4 s.
- `PostCapturePanelController` L356: bottom-right card (`PostCaptureView`) on a stack, 8 s.
- `extension NSApplication { forceActivate() }` L395.

### `App/PinWindows.swift` (361)
- `PinManager`: `pin(image:sourceURL:at:)`, `closeAll()`, `hasPins`, `defaultFrame(for:on:index:)` (60% cap, cascade).
  Owned by `AppDelegate` (save via `AppModel.saveToScreenshots`, edit via `openEditor`).
- `extension AreaSelection { globalFrame }` (top-left display points → global AppKit rect).
- `PinPanel` (private NSPanel): `sendEvent` handles scroll/pinch zoom and Esc.
- `PinController`: panel setup, `clamp` (aspect, ≥80 pt, ≤ screen), zoom, context menu (Copy, Save, Edit…,
  Opacity, Close, Close All Pins).
- `PinContentView` (private): layer-drawn image, drag to move (`performDrag`), aspect-locked edge resize, ✕ on hover.

### `App/TrimWindowController.swift` (104)
`TrimWindowController`: window with `AVPlayerView`; waits for `canBeginTrimming`, `await beginTrimming()`;
OK → range from `reversePlaybackEndTime`/`forwardPlaybackEndTime` → releases the player item →
`VideoTrimmer.trim` → `onFinish` + close; Cancel keeps the window as a player with a "Trim" overlay button (⌘T);
errors show a sheet and restart trimming. **All "open recording" actions route here** (card `open`, menu panel
`AppDelegate.open`, History `onOpenRecording`); History's "Open in Default App" is the only `NSWorkspace.open` path. Opened by
`AppDelegate.openTrimmer(url:)` (one per URL) from the post-recording card (`trim`) and History (`onTrim`).

## Models/

### `Models/Models.swift` (156)
Enums (all `CaseIterable, Identifiable, Sendable`, with `title`/`symbol`): `CaptureKind` (recording, screenshot) L4,
`CaptureSource` (display, window, application, area) L13, `FrameRate` L35, `VideoQuality` L42
(`resolutionScale`, `bitsPerPixel`), `VideoCodec` L77 (`avCodec`, `bitrateFactor`), `VideoContainer` L86,
`ImageFormat` L94 (`fileExtension`, `utType`), `FullPageQuality` L110 (`scale`).
Structs: `CaptureItem` L132 (url, kind, date, modified, size), `AreaSelection` L153 (displayID, rect in points).

### `Models/SettingsStore.swift` (134)
`@Observable SettingsStore` — every persisted preference (capture kind/source/target IDs, video options, audio,
image format, full-page quality, clipboard/post-capture/editor/sound toggles, `autoApplyBeautify`,
`beautifyStyle`, `shortcuts`, `lastActionKind`). `setShortcut(_:for:)` L51 (removes duplicates).
`init` L65 loads defaults + shortcut migration. `enum Keys` L107.

### `Models/Shortcut.swift` (95)
`struct Shortcut` (keyCode, modifiers, key; `carbonModifiers`, `displayString`, `init?(event:)`) L5.
`enum ShortcutAction` (screenshot, quickScreenshot, areaScreenshot, fullPageScreenshot, captureText, pinArea,
toggleRecording) L60 with `title`, `detail`, `defaultShortcut` (⌃⌥⌘ S/D/A/F/T/P/R).

## Services/

### `Services/CaptureTargetResolver.swift` (105)
`struct CaptureTarget` L4, `enum CaptureError` L14, `enum CaptureTargetResolver.resolve(source:settings:area:displayID:)` L35
→ builds an `SCContentFilter` per source (display excl. own app; desktop-independent window; app filter on the
display with most window coverage; area = display filter + `sourceRect`).

### `Services/ScreenshotService.swift` (38)
`capture(target:showsCursor:)` (SCScreenshotManager, sRGB, best resolution), `write(_:to:format:)` (ImageIO,
q=0.9 lossy, nonisolated), `copyToPasteboard`.

### `Services/ScreenRecorder.swift` (307)
- `struct RecordingOptions` L4: `outputSize(for:)`, `bitrate(for:)`.
- `enum RecorderError` L36.
- `final class ScreenRecorder: SCStreamOutput, SCStreamDelegate` L54: `start(target:options:outputURL:)` L70
  (420v YUV, BT.709, audio 48 kHz stereo, mic), `makeWriter` L132 (AVAssetWriter + video/system-audio/mic inputs),
  `stop(moveTo:)` L190, `finishWriting` L208 (re-stamp last frame, finalize, cleanup), stream callback L268
  (start session on first complete frame, drop if busy), `didStopWithError` → `onUnexpectedStop`.

### `Services/AreaSelector.swift` (470)
- `enum AreaSelectionMode { screenshot, recording }` L3.
- `AreaSelector.selectArea(mode:) async -> AreaSelection?` L17: one `OverlayPanel` per screen
  (`.screenSaver` level, non-activating).
- `private SelectionView: NSView` L82: mouse draw/move/resize with handles, Esc/Return, crosshair, size pill,
  confirm toolbar for recording mode (L291).
- `RecordingFrameOverlay` L428: red frame shown around the area while recording.

### `Services/FullPageCapture.swift` (265)
`enum FullPageError` L4. `FullPageCapture.capture(scale:)` L50: find browser → JS `prepare` (metrics + marker)
→ `findWindow` (match SCWindow by frame) → probe & `locateMarker` L111 → scroll/capture loop → `stitch` L176.
`runJavaScript` L196 (NSAppleScript). `enum Scripts` L209: `prepare`, `scroll(to:)`, `hideFixed`, `restore` (JS strings).

### `Services/ShareableContentStore.swift` (108)
`DisplayOption`, `WindowOption`, `AppOption`, `MicrophoneOption` structs; `@Observable ShareableContentStore.refresh()`
(SCShareableContent → filtered, sorted lists; mics via `AVCaptureDevice.DiscoverySession`); `icon(for:)` cache.
`extension NSScreen { displayID }` L104.

### `Services/HistoryStore.swift` (78)
`@Observable HistoryStore`: `recordings`, `screenshots`, `items(for:)`, `start()` (FS watchers), `reload()`,
`delete(_:)` (move to Trash), `scan(_:)` (allowed extensions per kind).

### `Services/StorageManager.swift` (45)
`rootURL`, `videosURL`, `imagesURL`, `folder(for:)`, `ensureFolders()`, `newFileURL(kind:fileExtension:)`,
`temporaryURL(for:)`.

### `Services/HotKeyManager.swift` (82)
`HotKeyManager.shared`: `configure(_:handler:)`, `suspend()`, `resume()`, `failedActions`; Carbon
`RegisterEventHotKey` with signature `'SCAP'`.

### `Services/BackgroundLibrary.swift` (64)
`@Observable BackgroundLibrary.shared`: Beautify background images copied to
`~/Library/Application Support/ScreenCapture/Backgrounds/<UUID>.<ext>`; `names`, `importImage(from:)`,
`remove(_:)`, `image(named:)` (NSCache).

### `Services/TextRecognizer.swift` (18)
`TextRecognizer.recognize(_ CGImage) async throws -> String` — Vision `RecognizeTextRequest` (accurate, auto language,
language correction), lines joined by `\n`, empty when no text.
`lines(in:) async throws -> [Line]` (`Line` = text + rect in image px, top-left origin) and
`line(at:in:tolerance:)` (line under/nearest a point) back the editor's double-click-to-copy.

### `Services/VideoTrimmer.swift` (53)
`VideoTrimmer.trim(_:to:)`: passthrough `AVAssetExportSession` (no re-encode) to a hidden temp sibling, copies
the creation date, trashes the original and moves the result into place; restores the original on failure.
Full-range = no-op. `TrimError`.

### `Services/ThumbnailCache.swift` (54)
`ThumbnailCache.shared`: QuickLook thumbnails in `NSCache` (limit 400, keyed by path+mtime+size), video `duration(for:)`, `invalidate(_:)` (after trimming).
`extension Double { durationString }`.

## Editor/

### `Editor/EditorDocument.swift` (1093) — editor model
- `enum EditorTool` L4 (select, text, arrow, blackout, rectangle, ellipse, line, pencil, highlighter, pixelate,
  counter, crop) with `key`/`numberKey` shortcuts and `uses*` capability flags.
- `StrokeSize` L84, `BorderStyle` L100, `TextSize` L113, `AnnotationShape` L125, `EditHandle` L140.
- `struct Annotation` L162: `offsetBy`, `bounds`, `frame`, `handles`, `point(of:)`, `handle(at:)`,
  `resized(_:to:uniform:)` L285, `hitTest` L339.
- Beautify: `GradientPreset` L371 (`all`), `AspectPreset` L389, `BackgroundKind` L411 (preset/solid/gradient/image),
  `RGBColor` L426 (hex, Codable), `GradientDirection` L440, `CustomGradient` L471, `ResolvedBackground` L478,
  `BeautifySettings` L484 (custom `init(from:)` for old saved styles; `resolvedBackground` falls back to preset 0
  when the image is missing), `CanvasLayout` L543.
- `@Observable EditorDocument` L576:
  - State: `image`, `pixelated`, `annotations`, `beautify`, `tool`, style props, `selectedID`, `draft`,
    `cropRect`, `textEditing`, `ocrHighlight`/`onTextCopied` (double-click OCR feedback), `isDirty`, undo/redo stacks, `viewScale`, `unit`, `layout`.
  - `init(image:fileURL:beautify:)` L657, `convenience init?(url:beautify:)` L666.
  - Style setters L675–724 (also update the selected annotation).
  - Undo: `pushUndo` L728, `undo`, `redo`, `restore`.
  - `tool` defaults to `.select` for every new document (never remembered between screenshots).
  - OCR: `prepareOCR` (lazy, cached per `image`; reset in `image.didSet`) and `copyText(at:)` — Select tool +
    double-click on empty space copies the nearest recognized line and flashes `ocrHighlight`.
  - Pointer: `begin(at:)` L769 (double-click text edit, handle resize, move, draw; Select + double-click empty = OCR), `update(to:constrained:)` L814,
    `end(at:)` L878 (commit draft, counters, text box), `annotation(at:)`, `handle(at:)`, `selectShapeTool`.
  - `commitTextEditing` L963, `deleteSelection`, `nudgeSelection`, `escape`, `applyCrop` L1009.
  - Output: `renderOutput` L1022, `save(to:rendered:)` L1027, `copyToPasteboard` L1038.
  - `makePixelated` L1064. Extensions: `ImageFormat.from(extension:)` L1078, `NSColor.hex` L1088.

### `Editor/EditorRenderer.swift` (310) — single source of truth for drawing
`render(image:pixelated:annotations:beautify:)` L9 (export: background, shadow, rounded clip, annotations),
`drawImage`, `drawBackground` L60 (gradient/solid/aspect-fill image), `aspectFillRect`, `drawGradient` (direction),
`draw(_ annotations:...)` L99, per-shape `draw` L107, text helpers
(`textAttributes`, `textPadding`, `textBoxSize`, `drawText`), `counterRadius`, `stroke` (border pass),
`drawArrow`, `smoothPath`.

### `Editor/EditorView.swift` (858) — SwiftUI editor
- `enum EditorFinishAction { copied, saved }` L3.
- `struct EditorView` L7: StyleBar + EditorCanvas + ZoomBar, toolbar (undo/redo, ToolPicker, Copy/Save/Inspector),
  inspector `BeautifyPanel`, `onCopyCommand` (⌘C), `copy`/`save`/`saveAs`/`finishOrFlash` (closes via `onFinish`
  when `settings.closeEditorAfterCopyOrSave`).
- `ToolPicker` L143, `StyleBar` L180 (palette, stroke, border, fill, text size).
- `EditorCanvas` L306: fit/zoom scale, ScrollView, pinch `MagnifyGesture`, key handling `handleKey` L379
  (delete, esc, return=apply crop, arrows=nudge, tool keys, `4` cycles shapes). Delete also works through the
  window-level monitor in `EditorWindowController`; `refocusCanvas()` (in `AnnotationLayer`) re-takes focus after text/gestures.
- `AnnotationLayer` L415: SwiftUI `Canvas` → `EditorRenderer.draw`, selection handles, `DragGesture` →
  `doc.begin/update/end`, pointer styles, `cropOverlay`, inline `textEditor`.
- `EditorZoom` L584 (steps, clamp, maxZoom), `ZoomBar` L598.
- `BeautifyPanel` L650, `BeautifyStyleControls` L691 (reused by Settings; segmented Presets/Solid/Gradient/Image,
  `ColorPicker`s, imported-image tiles + "Choose Image…"), `BeautifyBackgroundView` L827 (SwiftUI twin of
  `drawBackground`, used by the canvas, Settings preview and tiles).

## Views/

### `Views/MenuView.swift` (515) — popover panel
`MenuView` L3 (header, `kindPicker`, `actionButton`, `fullPageButton`, footer). Private pieces:
`PermissionBanner` L174, `RecordingStatusView` L199, `SourcePicker` L234, `TargetPicker` L270
(display/window/app pickers from `ShareableContentStore`), `RecordingOptionsView` L332 (fps, quality, codec,
container, audio, mic, cursor; `qualitySummary`), `ScreenshotOptionsView` L401, `RecentStrip` L420,
`OptionRow`, `ToggleRow`, `View.optionCard()`.

### `Views/HistoryView.swift` (313)
`@Observable HistoryViewState` L6 (kind, selection, showInspector, searchText). `HistoryView` L13 (grid by date
sections, search, context menu, drag-out, share, delete). Free func `copy(_ CaptureItem)` L143. Private
`HistoryCard`, `InspectorView`, `PreviewPane` (AVKit player / image), `MetadataView`.

### `Views/SettingsView.swift` (274)
`SettingsView` tabs: `GeneralSettingsView` L23, `BeautifySettingsView` L100 (+`BeautifyPreview`),
`ShortcutSettingsView` L158 (shows `HotKeyManager.failedActions`), `ShortcutRecorder` L206 (suspends hot keys while
recording). `extension SettingsStore.shortcutBinding(for:)` L270.

### `Views/PostCaptureView.swift` (115)
`PostCaptureView` L4 (preview, Open/Finder/Copy/Edit, View History), `QuickCaptureToastView` L80.

### `Views/SharedViews.swift` (65)
`ThumbnailView` (async `ThumbnailCache`), `DurationBadge` (reloads when `version`/mtime changes), `ElapsedTimeText`.

## Non-source

| Path | Purpose |
|------|---------|
| `Package.swift` | SwiftPM manifest (macOS 26, links AVKit) |
| `Resources/Info.plist` | Bundle ID/version, `LSUIElement`, usage strings (screen, mic, documents, Apple Events) |
| `scripts/build_app.sh` | swiftc build → `.app` bundle → codesign |
| `scripts/make_dmg.sh` | DMG packaging via `hdiutil` |
| `scripts/make_icon.swift` | Renders the app iconset |
| `docs/` | User/install guide images |
| `.build/`, `build/` | Build outputs (committed; ignore) |
