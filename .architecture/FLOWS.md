# Flows & Graphs (Mermaid)

## 1. File dependency graph

Arrow = "references a type declared in". Generated data: [graph.json](graph.json). Leaf models omitted from
some arrows for readability (almost every file uses `Models/Models.swift`).

```mermaid
flowchart LR
  subgraph Entry
    main[main.swift]
  end
  subgraph App
    AD[AppDelegate]
    AM[AppModel + AppUI]
    WC[WindowControllers]
  end
  subgraph Views
    MV[MenuView]
    HV[HistoryView]
    SV[SettingsView]
    PCV[PostCaptureView]
    SH[SharedViews]
  end
  subgraph Editor
    ED[EditorDocument]
    ER[EditorRenderer]
    EV[EditorView]
  end
  subgraph Models
    MO[Models]
    SS[SettingsStore]
    SC[Shortcut]
  end
  subgraph Services
    CTR[CaptureTargetResolver]
    SSv[ScreenshotService]
    SR[ScreenRecorder]
    AS[AreaSelector]
    FP[FullPageCapture]
    SCS[ShareableContentStore]
    HS[HistoryStore]
    SM[StorageManager]
    HK[HotKeyManager]
    TC[ThumbnailCache]
  end

  main --> AD
  AD --> AM & WC & MV & ED & HK & SM & SC
  AM --> SS & SCS & HS & AS & CTR & SSv & SR & FP & SM & ER
  WC --> EV & ED & HV & SV & PCV & HS & SS
  MV --> AM & SS & SCS & SR & SH
  HV --> HS & SM & TC & SH
  SV --> SS & HK & SC & EV & ED & SM
  PCV --> SH
  SH --> TC
  EV --> ED & ER & SS & SSv
  ED --> ER & SSv
  ER --> ED
  SS --> SC & ED
  CTR --> SS
  FP --> CTR & SSv
  SR --> CTR & SM
  SSv --> CTR
  HS --> SM
  HK --> SC
```

Notable couplings: `SettingsStore → EditorDocument` (persists `BeautifySettings`), `MenuView → ScreenRecorder`
(uses `RecordingOptions` to preview resolution/bitrate), `EditorDocument ↔ EditorRenderer` (mutual).

## 2. Startup

```mermaid
sequenceDiagram
  participant main
  participant AD as AppDelegate
  participant AM as AppModel
  participant HK as HotKeyManager
  participant HS as HistoryStore
  main->>AD: NSApplication.delegate = AppDelegate()  (.accessory)
  AD->>AD: StorageManager.ensureFolders()
  AD->>AM: model.ui = self
  AD->>AD: MainMenu.make(), setupStatusItem(), setupPopover(MenuView)
  AD->>HK: configure(settings.shortcuts, handler → AppModel actions)
  AD->>HS: start()  (scan + DispatchSource watchers)
```

## 3. Screenshot (button / ⌃⌥⌘S / ⌃⌥⌘A area)

```mermaid
sequenceDiagram
  participant UI as MenuView / HotKey / Menu
  participant AM as AppModel
  participant AS as AreaSelector
  participant CTR as CaptureTargetResolver
  participant SS as ScreenshotService
  participant ER as EditorRenderer
  participant SM as StorageManager
  participant AD as AppDelegate (AppUI)
  UI->>AM: takeScreenshot() / captureArea()
  AM->>AM: saveScreenshot { ... }  phase=.preparing (if idle)
  AM->>AD: dismissPopover()
  opt source == .area
    AM->>AS: selectArea(mode: .screenshot) (await continuation)
    AS-->>AM: AreaSelection? (nil → CaptureError.cancelled)
  end
  AM->>CTR: resolve(source, settings, area) → CaptureTarget
  AM->>SS: capture(target, showsCursor) → CGImage
  AM->>SM: newFileURL(.screenshot, ext)
  AM->>ER: finalImage(): render(beautify.applied) if autoApplyBeautify
  opt copyScreenshotToClipboard
    AM->>SS: copyToPasteboard(output)
  end
  AM->>SS: write(output, url, format)  (Task.detached)
  AM->>AM: didSave → settings.lastActionKind, history.reload()
  alt openEditorAfterScreenshot
    AM->>AD: openEditor(url, rawImage, beautify: autoApplyBeautify)
  else showPostCapturePanel
    AM->>AD: showPostCapture(CaptureItem)
  end
```

## 4. Quick Screenshot (⌃⌥⌘D)

`AppModel.quickScreenshot` → display under mouse → `CaptureTargetResolver.resolve(.display, displayID:)` →
`ScreenshotService.capture` → `finalImage` → **always** copy to clipboard → shutter sound (optional) → write →
`history.reload()` → `ui.showQuickCaptureToast` (click → `openEditor`). No editor/post-capture panel.

## 5. Full-page Chrome screenshot (⌃⌥⌘F)

```mermaid
sequenceDiagram
  participant AM as AppModel
  participant FP as FullPageCapture
  participant Chrome as Chrome (AppleScript JS)
  participant SCK as ScreenCaptureKit
  AM->>FP: capture(scale: fullPageQuality.scale)  (inside saveScreenshot)
  FP->>FP: findBrowser() (frontmost or running Chromium)
  FP->>Chrome: Scripts.prepare → Metrics JSON (+ magenta marker, choose scroll element)
  FP->>SCK: findWindow(pid, metrics) → SCWindow
  FP->>SCK: probe capture → locateMarker → viewport region
  loop until bottom or 32,000 px
    FP->>Chrome: Scripts.scroll(to: y) → PageState
    FP->>SCK: ScreenshotService.capture → crop region
    Note over FP,Chrome: after 1st slice → Scripts.hideFixed
  end
  FP->>FP: stitch(frames, scale) → CGImage
  FP->>Chrome: Scripts.restore (defer)
  FP-->>AM: CGImage → same save pipeline as §3
```

## 6. Recording (⌃⌥⌘R / status item)

```mermaid
sequenceDiagram
  participant AM as AppModel
  participant AS as AreaSelector
  participant CTR as CaptureTargetResolver
  participant SR as ScreenRecorder
  participant Q as recorder queue
  participant AD as AppDelegate
  AM->>AM: toggleRecording() → startRecording(), phase=.preparing
  AM->>AM: request mic access (if captureMicrophone)
  AM->>AS: selectArea(.recording) (if source == .area, confirm toolbar)
  AM->>CTR: resolve → CaptureTarget
  AM->>SR: start(target, RecordingOptions, url)
  SR->>SR: makeWriter(temp .UUID file) + SCStream(420v, audio, mic)
  SR->>Q: addStreamOutput(sampleHandlerQueue: queue), startCapture()
  AM->>AM: frameOverlay.show(area), phase=.recording(since:)
  AM->>AD: phaseDidChange() → red stop icon + timer
  loop frames
    Q->>Q: stream(didOutputSampleBuffer) → append (drop if busy)
  end
  AM->>SR: stopRecording() → phase=.finishing → stop(moveTo: url)
  SR->>Q: finishWriting (re-stamp last frame, endSession, finish)
  SR-->>AM: url (temp moved to final)
  AM->>AM: phase=.idle → didSave(.recording) → showPostCapture
  Note over SR,AM: SCStream didStopWithError → onUnexpectedStop → stopRecording()
```

## 7. Editor lifecycle

```mermaid
sequenceDiagram
  participant AD as AppDelegate
  participant EWC as EditorWindowController
  participant EV as EditorView/AnnotationLayer
  participant ED as EditorDocument
  participant ER as EditorRenderer
  AD->>ED: EditorDocument(image|url, beautify: settings.beautifyStyle(enabled?))
  AD->>EWC: init(document, settings), onFinish → toast, onClose → remove
  EV->>ED: DragGesture → begin/update/end(at: imagePoint)
  ED->>ED: pushUndo(), mutate annotations / draft / crop / textEditing
  EV->>ER: Canvas.withCGContext → draw(visibleAnnotations)
  EV->>ED: ⌘C/⌘S → renderOutput() → ER.render(...)
  ED->>ED: save(): ScreenshotService.write (detached) → onSaved → history.reload()
  ED-->>AD: onBeautifyChanged → settings.beautifyStyle
  EV-->>EWC: onFinish(action, image) (if closeEditorAfterCopyOrSave)
  EWC->>EWC: windowShouldClose → Save/Don't Save/Cancel if isDirty
```

## 8. Hot keys & settings change

`SettingsView/ShortcutRecorder` → `HotKeyManager.suspend()` while capturing a key → `settings.setShortcut` →
`SettingsStore.shortcuts.didSet` → `onShortcutsChanged` → `AppDelegate.registerHotKeys()` →
`HotKeyManager.configure` → Carbon `RegisterEventHotKey` (failures → `failedActions`, shown in Settings).
