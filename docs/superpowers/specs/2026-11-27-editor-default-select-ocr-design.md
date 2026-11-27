# Editor starts in Select; double-click copies text (OCR)

## Goal

Each screenshot session starts with no drawing tool active. In that state, double-clicking text in the image copies
it, like Xnapper.

## Problem

`EditorDocument.tool` defaulted to `.arrow`, so every new editor opened ready to draw an arrow, and a stray click
drew a mark. The same Select state is the natural place for quick text copy.

## Design

- `EditorDocument.tool` defaults to `.select`. A new document is created per screenshot, so nothing carries over.
- `TextRecognizer.lines(in:)` returns each recognized line with its rect (image px, top-left origin);
  `line(at:in:tolerance:)` picks the line containing the point, or the nearest within `6 * unit` px.
- In `begin(at:)`, with the Select tool and no mark/handle under the pointer, the first click calls `prepareOCR()`
  (background Vision pass, cached; reset when `image` changes through crop or undo). A double-click then calls
  `copyText(at:)`: waits for the cache if needed, copies the line to the pasteboard, sets `ocrHighlight`
  (accent box drawn in the canvas, cleared after ~0.9 s) and calls `onTextCopied` so the view shows a toast
  ("Text copied" / "No text here").
- Double-clicking a text mark still edits it; clicking marks still selects and moves them.

## Out of scope

Word-level or multi-line selection, OCR on the beautified/extra-space area, changing the "Copy Text (OCR)" button.

## Validation

Debug build. Manual: take a screenshot, editor shows Select active; double-click a word, line is pasted and
highlighted; press 2 and draw an arrow; take another screenshot and Select is active again; double-click blank
area shows "No text here".
