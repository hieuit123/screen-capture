# Beautify: custom backgrounds (solid, gradient, image)

## Goal

Let users change the Beautify background beyond the 9 built-in gradient presets: a solid colour, a custom
two-colour gradient with a direction, or an image from a file. Works in the editor inspector and in
Settings › Beautify (both use `BeautifyStyleControls`), and the chosen style stays the remembered default.

## Model (`Editor/EditorDocument.swift`)

- `enum BackgroundKind: String, Codable, CaseIterable { preset, solid, gradient, image }` with `title`
  ("Presets", "Solid", "Gradient", "Image").
- `struct RGBColor: Codable, Equatable` — sRGB `hex: UInt32`; `nsColor`, `init(_ NSColor)`.
- `enum GradientDirection: String, Codable, CaseIterable { diagonalDown, horizontal, vertical, diagonalUp }`
  — start/end as unit points (top-left origin): ↘ (0,0)→(1,1), → (0,0.5)→(1,0.5), ↓ (0.5,0)→(0.5,1),
  ↗ (0,1)→(1,0); `symbol` for the picker.
- `struct CustomGradient: Codable, Equatable { from: RGBColor, to: RGBColor, direction: GradientDirection }`,
  default `#4A00E0 → #FF5F6D`, `.diagonalDown`.
- `BeautifySettings` gains `background: BackgroundKind = .preset`, `solidColor: RGBColor = #1E1E1E`,
  `gradient = CustomGradient()`, `imageName: String? = nil`. `presetID` is kept.
- Custom `init(from:)` using `decodeIfPresent` for every field so existing `beautifyStyle.v1` data still decodes
  (missing keys take defaults). Encoding uses the same key names.
- Each kind keeps its own value, so switching tabs never loses the previous choice.

## Image library (`Services/BackgroundLibrary.swift`, new, `@MainActor`)

- Folder: `~/Library/Application Support/ScreenCapture/Backgrounds/` (created on demand).
- `importImage(from url: URL) throws -> String` — validates that it decodes as an image, copies it to
  `<UUID>.<ext>`, returns the file name.
- `names: [String]` — imported files sorted by creation date (newest first); `remove(_ name:)` deletes the file.
- `image(named:) -> CGImage?` — decoded once and cached in `NSCache`.
- If the referenced image is missing or undecodable, rendering falls back to `GradientPreset.all[0]`.
- Removing an image that a style still references doesn't change the style; it renders the fallback.

## Rendering

- `EditorRenderer.drawBackground(_ style: BeautifySettings, in rect: CGRect, context:)` replaces the
  `drawGradient(beautify.preset.colors…)` call in `render`. Preset and custom gradient use `drawGradient` with
  direction-aware start/end points; solid fills; image draws aspect-fill (scale = max(w/iw, h/ih), centred,
  clipped) via `drawImage` (handles the y-down flip).
- New SwiftUI `BeautifyBackgroundView(style:)` (in `EditorView.swift`) with identical math: `LinearGradient`
  with matching unit points, `Color`, or `Image(decorative:).resizable().scaledToFill().clipped()`.
  Used by `EditorCanvas`, `BeautifyPreview` (Settings) and the tiles, so preview == export.

## UI (`BeautifyStyleControls`)

Section "Background":
1. Segmented `Picker` bound to `style.background`.
2. Per kind:
   - **Presets:** existing 3-column grid (sets `presetID`).
   - **Solid:** `ColorPicker("Colour", supportsOpacity: false)` bound to `solidColor`.
   - **Gradient:** two `ColorPicker`s (From / To) and a segmented direction picker.
   - **Image:** grid of imported tiles (selected = accent border; context menu "Remove"), plus a
     "Choose Image…" button → `NSOpenPanel` (`allowedContentTypes: [.image]`) → import → select.
     Import failure shows the inline caption "Couldn't use that image."
3. Any change also calls `onPickPreset` (turns Beautify on in the editor), as today.

## Out of scope

Transparent backgrounds, desktop wallpaper, blur, opacity, more presets, image tiling/fit modes.

## Validation

No test target exists. Build with `./scripts/build_app.sh`; manually check each kind in the editor, Settings
preview, saved file and clipboard, old-settings migration, and the missing-image fallback.
Update `.architecture/` (CODEMAP, CHANGE-GUIDE, graph.json) for the new file.
