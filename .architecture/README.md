# .architecture — Agent/Developer Index

Pre-digested map of the ScreenCapture codebase. **Read these files before opening source** so you only open
the 1–3 Swift files that a task actually touches.

| File | Use it for |
|------|------------|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Layers, ownership, threading, persistence, invariants/gotchas |
| [CODEMAP.md](CODEMAP.md) | Every source file → types, key functions, line anchors |
| [FLOWS.md](FLOWS.md) | Mermaid dependency graph + sequence diagrams for each capture flow |
| [CHANGE-GUIDE.md](CHANGE-GUIDE.md) | "I want to change X → edit these files" lookup |
| [graph.json](graph.json) | Machine-readable nodes/edges (file → file dependencies, with the types that link them) |
| [gen_graph.py](gen_graph.py) | Regenerates `graph.json`: `python3 .architecture/gen_graph.py` |

## 30-second summary

- **What:** macOS 26+ menu-bar app (`LSUIElement`) for screen recording + screenshots + annotation editor.
- **Stack:** Swift 6.2, SwiftPM single executable target, AppKit shell + SwiftUI views, ScreenCaptureKit,
  AVFoundation (AVAssetWriter), CoreGraphics, Carbon hot keys, AppleScript (Chrome full-page). No 3rd-party deps.
- **No tests**, no Xcode project. Build: `./scripts/build_app.sh` → `build/ScreenCapture.app`
  (`CONFIG=debug` for debug). DMG: `./scripts/make_dmg.sh`. Version lives in `Resources/Info.plist`
  (`CFBundleShortVersionString`, currently 1.5.1).
- **Source root:** `Sources/ScreenCapture/` (26 files, ~6.7k LOC). Biggest: `Editor/EditorDocument.swift` (1093),
  `Editor/EditorView.swift` (858), `Views/MenuView.swift` (515), `Services/AreaSelector.swift` (470).

## Layer cheat-sheet

```
main.swift ─► AppDelegate (AppKit shell, implements AppUI) ─► AppModel (coordinator, @Observable)
                  │                                              │
                  ├─ WindowControllers (History/Editor/Settings,  ├─ SettingsStore (UserDefaults)
                  │   toast + post-capture panels)               ├─ ShareableContentStore (SCShareableContent)
                  └─ Views (SwiftUI)                             ├─ HistoryStore (folder scan + FS watch)
                                                                 └─ Services: CaptureTargetResolver, ScreenshotService,
                                                                    ScreenRecorder, AreaSelector, FullPageCapture,
                                                                    BackgroundLibrary, StorageManager, HotKeyManager, ThumbnailCache
Editor:  EditorDocument (model, undo, hit-testing) ─► EditorRenderer (CoreGraphics, shared preview+export)
```

## Ignore when exploring

`.build/`, `build/` (compiled app + DMGs, committed binaries), `docs/*.png|svg` (user guides), `.DS_Store`.

## Keeping this folder current

When you add/rename a file, type, or flow, update `CODEMAP.md` + `graph.json` (and `FLOWS.md` if a flow changes).
Line numbers in CODEMAP are anchors as of v1.4.6 — use them as hints, then grep.
