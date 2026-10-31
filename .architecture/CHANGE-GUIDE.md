# Change Guide — "where do I edit?"

| Task | Files (in order) | Notes |
|------|------------------|-------|
| Add a persisted setting | `Models/SettingsStore.swift` (property + `didSet` + `init` default + `Keys`), UI in `Views/SettingsView.swift` or `Views/MenuView.swift` | Read it where needed via `model.settings` |
| Add a capture option enum (codec, format…) | `Models/Models.swift`, `SettingsStore`, `MenuView` (`RecordingOptionsView`/`ScreenshotOptionsView`), consumer service | `RecordingOptions` in `ScreenRecorder.swift` for video |
| Add a global shortcut action | `Models/Shortcut.swift` (`ShortcutAction` case, title, detail, default), `AppDelegate.registerHotKeys` switch, optionally `showContextMenu` | Migration for existing users is automatic (`shortcuts.seenActions`) |
| Add a new capture source | `Models/Models.swift` (`CaptureSource`), `CaptureTargetResolver.resolve`, `MenuView` (`SourcePicker`/`TargetPicker`), `ShareableContentStore` if it needs a list | |
| Change screenshot save/clipboard/post-capture behaviour | `AppModel.saveScreenshot` / `didSave` / `finalImage` | Quick screenshot path is separate: `captureQuickScreenshot` |
| Change recording encoding / quality / audio | `Services/ScreenRecorder.swift` (`RecordingOptions`, `start`, `makeWriter`) | Keep writer state on `queue` only |
| Change area selection UX | `Services/AreaSelector.swift` (`SelectionView`) | Recording frame: `RecordingFrameOverlay` |
| Full-page capture bugs | `Services/FullPageCapture.swift` (`Scripts` JS, `locateMarker`, loop, `stitch`) | Always keep `Scripts.restore` in `defer` |
| OCR / Capture Text | `Services/TextRecognizer.swift`; flow `AppModel.captureText`/`copyRecognizedText`; editor `EditorView.copyText`; History `onCopyText` (AppDelegate → HistoryWindowController → HistoryView) | Toast via `AppUI.showTextToast` |
| Pins (floating screenshots) | `App/PinWindows.swift`; entry points `AppModel.pinArea`, `AppDelegate.pin/pinFile`, card `pin`, editor `onPin`, History `onPin` | Pin geometry is global AppKit coordinates (bottom-left) |
| File naming / folders | `Services/StorageManager.swift` | History file filters: `HistoryStore.scan` |
| History window UI | `Views/HistoryView.swift`, window in `App/WindowControllers.swift` | Thumbnails: `ThumbnailCache`, `SharedViews` |
| Menu bar panel UI | `Views/MenuView.swift`; status item/right-click menu in `App/AppDelegate.swift` | |
| Post-capture card / quick toast | `Views/PostCaptureView.swift` + controllers in `App/WindowControllers.swift` | Stacking/timers/max count: `FloatingPanelStack.Style` |
| New editor tool | `EditorDocument.swift`: `EditorTool` (+keys/flags), `AnnotationShape`, `Annotation` (bounds/handles/resize/hitTest/offset), `begin/update/end`, `newAnnotation`; draw in `EditorRenderer.draw(_ a:)`; button in `EditorView.ToolPicker` | Coordinates are image pixels; `pushUndo()` before mutation |
| Editor style controls (color, stroke…) | `EditorDocument` setters (L563+) + `EditorView.StyleBar` | |
| Beautify (backgrounds, padding, aspect) | `GradientPreset`/`BackgroundKind`/`BeautifySettings`/`CanvasLayout` in `EditorDocument.swift`; drawing in `EditorRenderer.drawBackground`/`render`; images in `Services/BackgroundLibrary.swift`; controls `BeautifyStyleControls` (EditorView) reused by `BeautifySettingsView` | Keep `BeautifyBackgroundView` in sync with `drawBackground`; new `BeautifySettings` fields need `decodeIfPresent` |
| Editor keyboard shortcuts | `EditorView.EditorCanvas.handleKey`, toolbar `keyboardShortcut`s, `EditorTool.key/numberKey` | |
| Editor zoom | `EditorZoom`, `ZoomBar`, `EditorCanvas` (pinch) | |
| Editor close/save prompts | `EditorWindowController.windowShouldClose`, `EditorView.finishOrFlash` | |
| Error messages / permission prompts | Error enums (`CaptureError`, `RecorderError`, `FullPageError`), `AppDelegate.showError` | Deep-link pane chosen from message text |
| App version / permissions strings | `Resources/Info.plist` | DMG name uses `CFBundleShortVersionString` |
| Build/sign/package | `scripts/build_app.sh`, `scripts/make_dmg.sh` | Build script compiles with `swiftc` directly |

## Verify a change

```bash
./scripts/build_app.sh            # compile + bundle (only automated check; no tests)
open build/ScreenCapture.app
```

After structural changes: `python3 .architecture/gen_graph.py` and update `CODEMAP.md`.
