# Delete the selected mark with Backspace

## Goal

Pressing Backspace (or Forward Delete) removes the selected mark in the editor, without having to use the Delete button.

## Problem

`EditorCanvas.handleKey` already handles `.delete`, but it relies on SwiftUI focus (`canvasFocused`). After inline text
editing or clicking the side panel, the flag can read `true` while the real first responder is elsewhere, so
`onKeyPress` never fires and Backspace does nothing.

## Design

- `EditorWindowController` installs an `NSEvent` local `keyDown` monitor (`deleteKeyMonitor`), removed in
  `windowWillClose`. It runs before SwiftUI sees the event.
- It acts only when: the event is for this window and the window is key; the key code is Backspace (51) or Forward
  Delete (117) with no ⌘/⌥/⌃; the first responder is not an `NSText` (text fields keep normal Backspace);
  `doc.textEditing == nil`; and a mark is selected. Then it calls `doc.deleteSelection()` (pushes undo) and consumes
  the event.
- `AnnotationLayer.refocusCanvas()` toggles `canvasFocused` (false, then true on the next run loop) after finishing or
  cancelling text and after canvas gestures, so tool keys and arrows also keep working.

## Out of scope

Deleting multiple marks, a confirmation prompt, Delete while a text field in the side panel has focus.

## Validation

Debug build; manual check: add text with `1`, press Enter, press Backspace (mark disappears, ⌘Z restores it); typing
in a colour hex field still deletes characters.
