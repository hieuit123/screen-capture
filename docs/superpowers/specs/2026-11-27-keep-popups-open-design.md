# Keep other apps' popups open while selecting an area

## Goal

Starting a screenshot area selection must not dismiss popups in the frontmost app (for example an open Chrome dropdown
or menu), so they can be captured.

## Problem

The selection overlay was made key (`makeKeyAndOrderFront`, `canBecomeKey = true`). Becoming key makes the frontmost
app resign key, and apps such as Chrome close their popups on resign.

## Design (`Services/AreaSelector.swift`)

- `OverlayPanel.allowsKey` is `true` only for `.recording`. In `.screenshot` mode the panels never become key, are not
  made key on present, and `SelectionView.mouseDown` no longer calls `makeKey()`. Mouse events still work because the
  panels are non-activating.
- Without key focus Esc would reach the other app, so `registerEscape()` registers Esc as a Carbon hotkey
  (`RegisterEventHotKey`, signature `SCES`, no Input Monitoring permission) while the overlay is shown, with its own
  `InstallEventHandler` that returns `eventNotHandledErr` for other hotkeys so `HotKeyManager` still gets its events.
  `finish(_:)` unregisters it and is idempotent (`guard continuation != nil`).
- Right-click cancels the selection in `.screenshot` mode (`SelectionView.rightMouseDown`).
- `.recording` mode keeps key focus for its toolbar and Esc/Return.

## Out of scope

Return-to-confirm in screenshot mode (selection already completes on mouse up), changing the recording flow.

## Validation

Debug build; manual check: open a Chrome dropdown, trigger area capture, dropdown stays open and is in the result;
Esc and right-click cancel; recording selection still accepts Esc/Return.
