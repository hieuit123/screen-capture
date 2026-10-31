# Capture Text (OCR)

## Goal

Copy text from the screen or from screenshots, like CleanShot's "Capture Text": a global shortcut to OCR a
dragged area, a "Copy Text" action in the editor, and in History.

## Design

- `Services/TextRecognizer.swift`: `enum TextRecognizer { static func recognize(_ image: CGImage) async throws -> String }`
  using the Swift Vision API `RecognizeTextRequest` — `.accurate`, `automaticallyDetectsLanguage = true`,
  `usesLanguageCorrection = true`. Each observation's top candidate, in Vision's reading order, joined by "\n".
  Whitespace-only results count as "no text".
- `AppModel.copyRecognizedText(from image: CGImage, displayID:)`: OCR → `NSPasteboard` string → toast via
  `AppUI.showTextToast(thumbnail:text:on:)` (title "Text copied", subtitle = first line; or "No text found").
  OCR errors go to `ui.showError`.
- `ShortcutAction.captureText` ("Capture Text (OCR)", default ⌃⌥⌘T) — existing users get it via the
  `shortcuts.seenActions` migration unless the combination is taken. `AppDelegate.registerHotKeys` and the
  status item context menu call `AppModel.captureText()`: area selection (screenshot mode) → capture →
  `copyRecognizedText`. No file is saved. Allowed while idle or recording, like other screenshots.
- Editor: "Copy Text" button in the inspector's Export section; OCRs `doc.image` (the current, possibly cropped,
  image without annotations) and flashes "Text copied" / "No text found".
- History: context-menu "Copy Text" for screenshots. `HistoryView` gets `onCopyText: (CaptureItem) -> Void`,
  passed from `AppDelegate` through `HistoryWindowController`; `AppDelegate` loads the file and calls
  `AppModel.copyRecognizedText`.

## Out of scope

Language settings, saving the OCR'd area, QR/barcode reading, OCR in recordings.

## Validation

Release build; a harness that renders English and Vietnamese text into a `CGImage` and checks
`TextRecognizer.recognize` returns it; manual check of shortcut, editor and History entry points.
