# Editor starts in Select; double-click copies text (OCR)

## Goal

Each screenshot session starts with no drawing tool active. In that state, double-clicking a word selects it and dragging
extends the selection to more words, like Xnapper; the user copies with ⌘C.

## Problem

`EditorDocument.tool` defaulted to `.arrow`, so every new editor opened ready to draw an arrow, and a stray click
drew a mark. The same Select state is the natural place for quick text copy.

## Design

- `EditorDocument.tool` defaults to `.select`. A new document is created per screenshot, so nothing carries over.
- `TextRecognizer.words(in:)` splits each recognized line into words, each with its rect (image px, top-left
  origin, from `RecognizedText.boundingBox(for:)`) and line index. `nearestWord` finds the word under a point.
- In `begin(at:)`, with the Select tool and no mark/handle under the pointer, the click calls `prepareOCR()`
  (background Vision pass, cached; reset when `image` changes through crop or undo) and clears the selection.
  Double-click on a word selects it (`ocrSelection`, a word-index range). Pressing on a word and dragging extends
  the range to the nearest word under the pointer (reading order; a range spanning lines is joined with newlines).
- Selected words are highlighted in the canvas. **Nothing is copied automatically**: ⌘C (Edit › Copy) copies
  `selectedOCRText` as plain text and shows a "Text copied" toast; with no selection ⌘C still copies the image.
  Esc, a new click or changing tool clears the selection.
- Double-clicking a text mark still edits it; clicking marks still selects and moves them.

## Out of scope

Selecting with the keyboard, OCR on the beautified/extra-space area, changing the "Copy Text (OCR)" button.

## Validation

Debug build. Manual: take a screenshot, editor shows Select active; double-click a word (only it is highlighted), drag
across more words, ⌘C and paste to check the text; press 2 and draw an arrow; take another screenshot and Select is active again; double-click blank
area selects nothing.
