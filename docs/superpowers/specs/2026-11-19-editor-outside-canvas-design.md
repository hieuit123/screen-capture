# Edit outside the screenshot, multi-line text, capture the editor

## Goal

Let users place marks and text outside the screenshot (over the Beautify background or extra blank space), make text
input roomier and multi-line, and allow screenshotting an editor window that is open.

## Design

Edit outside the screenshot (`Editor/EditorDocument.swift`, `EditorRenderer.swift`, `EditorView.swift`):

- `enum ExtraSpace` (none / S / M / L) and `doc.extraSpace` (session-only; changing it marks the document dirty).
- `CanvasLayout(imageSize:beautify:extraSpace:)` computes the canvas and `imageRect`; extra space is added around the
  image (on top of Beautify padding). `renderOutput` passes `extraSpace` to the renderer.
- `EditorRenderer.render(... extraSpace:)`: fills white when extra space is on without Beautify; annotations are drawn
  unclipped to the whole canvas; pixelate stays clipped to the image rect.
- `AnnotationLayer` spans the whole canvas and takes an `origin`; points are converted with `imagePoint` and offset by
  `layout.imageRect.origin`, so annotation coordinates remain in image space (they can be negative or exceed the image).
- Inspector: new "Canvas › Extra space" segmented picker.

Text input:

- The inline editor is a `TextEditor` sized from `EditorRenderer.textBoxSize` (min 12 em wide, 3 lines tall) so it grows
  with the content and matches the finished mark. Return commits; Shift+Return inserts a newline; Esc discards.
- No translucent backing for plain text; filled text keeps its colour backing. Rendered text uses a two-pass outline
  (stroke, then fill) instead of a blurred shadow. A trailing newline is measured as an extra line.
- A cancelled drag no longer leaves `isDragging` set (`@GestureState` reset), so the next click is not swallowed.

Capturing the editor (`Services/CaptureTargetResolver.swift`, `ShareableContentStore.swift`, `App/AppDelegate.swift`):

- `CaptureTargetResolver.capturableOwnWindowNumbers` (set by `AppDelegate` to the visible editor windows). The resolver
  passes those windows as `exceptingWindows` when excluding the app's own windows for display/area captures, and the
  window picker no longer filters them out. Popovers, selection overlays and pins stay excluded.

## Out of scope

Persisting `extraSpace`, choosing the extra-space colour, resizing the text box by dragging while editing, capturing
pins.

## Validation

Release/debug build; render checks of a sample image with extra space and text (preview and export match); manual
check of Shift+Return, text move after commit, and an area capture over an open editor.
