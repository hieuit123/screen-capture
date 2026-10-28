# ScreenCapture

A simple menu bar app for taking **screenshots** and **screen recordings** on your Mac. You can mark up your screenshots with arrows, text, and blur, then save or copy them.

Requires **macOS 26 (Tahoe) or later**.

---

## Contents

1. [Install](#1-install)
2. [First launch: allow permissions](#2-first-launch-allow-permissions)
3. [Take a screenshot](#3-take-a-screenshot)
4. [Record your screen](#4-record-your-screen)
5. [Edit a screenshot](#5-edit-a-screenshot)
6. [Set up keyboard shortcuts](#6-set-up-keyboard-shortcuts)
7. [Find your files (History)](#7-find-your-files-history)
8. [Settings](#8-settings)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. Install

1. Open `ScreenCapture-<version>.dmg`.
2. Drag **ScreenCapture** into the **Applications** folder.
3. Open **ScreenCapture** from Applications.

The app runs in the **menu bar** at the top of the screen, not in the Dock. Look for its icon near the clock.

- **Left-click** the icon to open the capture panel.
- **Right-click** the icon for a quick menu with all actions, history, settings, and **Quit**.

> **Tip:** To start the app automatically, turn on **Settings › General › Launch at login**.

---

## 2. First launch: allow permissions

macOS will ask for a few permissions the first time you capture:

| Permission                          | Needed for                  | Required?                          |
| ----------------------------------- | --------------------------- | ---------------------------------- |
| **Screen & System Audio Recording** | Any screenshot or recording | Yes                                |
| **Documents folder**                | Saving your files           | Yes                                |
| **Microphone**                      | Recording your voice        | Only if you turn on the microphone |

If you see an **orange banner** in the panel:

1. Click **Grant Access**.
2. In System Settings, turn on **ScreenCapture**.
3. Quit and reopen ScreenCapture if capturing still doesn't work.

---

## 3. Take a screenshot

### Option A: from the panel

1. Click the menu bar icon.
2. Choose **Screenshot** mode.
3. Pick a source:
   - **Screen**: the whole display
   - **Window**: one window
   - **App**: all windows of one app
   - **Area**: a part of the screen you drag out
4. Click the capture button.

### Option B: with a shortcut (fastest)

| Shortcut | What it does                                                     |
| -------- | ---------------------------------------------------------------- |
| `⌃⌥⌘S`   | Take a screenshot                                                |
| `⌃⌥⌘A`   | Capture an area you select                                       |
| `⌃⌥⌘D`   | **Quick Screenshot**: grabs the screen under the mouse instantly |

`⌃` = Control, `⌥` = Option, `⌘` = Command. You can change these shortcuts; see [section 6](#6-set-up-keyboard-shortcuts).

### Selecting an area

- **Drag** to draw a box. The capture happens when you release the mouse.
- **Click once** (without dragging) to capture the whole screen.
- Press **Esc** to cancel.

### Quick Screenshot

`⌃⌥⌘D` captures the screen the mouse is on, **copies it to the clipboard**, and saves it. Paste it anywhere with `⌘V`. A small notice appears; **click it to open the editor**.

### After a screenshot

By default the **editor** opens so you can mark up the image (see [section 5](#5-edit-a-screenshot)). A preview card also appears with these buttons:

- **Edit**: open the editor
- **Open**: open the file
- **Finder**: show the file in Finder
- **Copy**: copy it to the clipboard
- **View Screenshot History**: see all your screenshots

You can drag the thumbnail straight into another app, such as an email or chat.

---

## 4. Record your screen

1. Click the menu bar icon and choose **Recording** mode.
2. Pick a source: **Screen**, **Window**, **App**, or **Area**.
3. (Optional) Adjust the options:
   - **Frame rate**: 30 fps is good for most uses. Choose 60 fps for smooth motion.
   - **Quality**: Low, Medium, High, or Best. Higher quality makes bigger files.
   - **System audio**: records sound from your Mac.
   - **Microphone**: records your voice. Choose which mic to use.
   - **Show cursor**: shows or hides the mouse pointer.
4. Click **Start Recording**, or press `⌃⌥⌘R`.

**For an Area recording:** drag a box, then move it or resize it using the handles. Click **Start Recording** or press **Return** when ready. Press **Esc** to cancel.

**To stop recording**, do either of these:

- Click the **red stop icon** with the timer in the menu bar.
- Press `⌃⌥⌘R` again.

---

## 5. Edit a screenshot

The editor opens automatically after a screenshot. You can also open it by:

- clicking **Edit** on the preview card, or
- double-clicking a screenshot in **Screenshot History**.

### Tools

Click a tool in the toolbar, or press its letter key:

| Key | Tool            | Use it to…                                             |
| --- | --------------- | ------------------------------------------------------ |
| `V` | **Select**      | Click a shape to select, move, or delete it            |
| `C` | **Crop**        | Drag to choose the area to keep, then press **Return** |
| `R` | **Rectangle**   | Draw a box around something                            |
| `O` | **Ellipse**     | Draw a circle or oval                                  |
| `L` | **Line**        | Draw a straight line                                   |
| `A` | **Arrow**       | Point at something                                     |
| `P` | **Pencil**      | Draw freehand                                          |
| `H` | **Highlighter** | Highlight text, like a marker pen                      |
| `T` | **Text**        | Click and type a label                                 |
| `B` | **Pixelate**    | Hide private info (passwords, emails, faces)           |
| `N` | **Step number** | Add numbered markers 1, 2, 3… for step-by-step guides  |

### Style

Use the style bar to change:

- **Color**: 9 preset colors, or pick your own
- **Stroke**: Thin, Medium, or Thick
- **Text size**: S, M, or L
- **Fill**: fill rectangles, ovals, and text backgrounds with color

### Handy tips

- Hold **Shift** while drawing to make perfect squares and circles, or to snap lines to 45°.
- Use the **arrow keys** to nudge a selected shape by 1 pixel. Hold **Shift** to move 10 pixels.
- Press **Delete** to remove the selected shape.
- Press **Esc** to deselect.
- `⌘Z` undoes and `⇧⌘Z` redoes.

### Beautify (make it look nice)

Turn on **Beautify** in the right sidebar to place your screenshot on a colored background. This is good for sharing on social media or in documents. You can adjust:

- **Background**: choose a gradient (Grape, Sunset, Ocean, Mint, and more)
- **Padding**: the space around the image
- **Corner radius**: how rounded the corners are
- **Shadow**
- **Aspect ratio**: Auto, 16:9, 4:3, or 1:1

### Save or share

| Action             | Shortcut | What it does                                             |
| ------------------ | -------- | -------------------------------------------------------- |
| **Copy**           | `⇧⌘C`    | Copies the edited image so you can paste it anywhere     |
| **Save**           | `⌘S`     | Replaces the original file with your edits               |
| **Save As**        |          | Saves a new file and lets you choose the name and format |
| **Show in Finder** |          | Opens the folder containing the file                     |

---

## 6. Set up keyboard shortcuts

Shortcuts work everywhere, even when ScreenCapture isn't in front.

### Default shortcuts

| Action                 | Default |
| ---------------------- | ------- |
| Take Screenshot        | `⌃⌥⌘S`  |
| Quick Screenshot       | `⌃⌥⌘D`  |
| Capture Area           | `⌃⌥⌘A`  |
| Start / Stop Recording | `⌃⌥⌘R`  |

### Change a shortcut

1. Open **Settings**. Click the gear button in the panel, right-click the menu bar icon and choose **Settings…**, or press `⌘,` while the panel is open.
2. Go to the **Shortcuts** tab.
3. Click the shortcut button next to the action. It changes to **Press keys…**.
4. Press your new key combination, for example `⌃⌥⌘1`.
   - It must include at least one of **⌘ Command**, **⌃ Control**, or **⌥ Option**. Function keys such as `F5` work on their own.
5. That's it. The new shortcut works immediately.

### Other options

- **Cancel** while recording a shortcut: press **Esc**.
- **Remove a shortcut:** click the **ⓧ** next to it, or press **Delete** while the button shows _Press keys…_.
- **Reset everything:** click **Restore Defaults**.
- If you choose a shortcut that another action already uses, it moves to the new action automatically.

> **Orange warning?** macOS or another app is already using that combination. Pick a different one. Avoid `⇧⌘3`, `⇧⌘4`, and `⇧⌘5`, which macOS uses for its own screenshots.

---

## 7. Find your files (History)

All files are saved automatically to:

- Screenshots: `~/Documents/ScreenCapture/images`
- Recordings: `~/Documents/ScreenCapture/videos`

To browse them, right-click the menu bar icon and choose **Screenshot History…** or **Recording History…**.

In the History window you can:

- Switch between **Recordings** and **Screenshots** at the top.
- **Search** by file name.
- **Double-click** a screenshot to edit it, or a video to play it.
- **Right-click** an item to Edit, Open, Show in Finder, Copy, Share, or Move to Trash.
- **Drag** an item into another app.

---

## 8. Settings

**General tab**

| Setting                                          | What it does                                                     |
| ------------------------------------------------ | ---------------------------------------------------------------- |
| Open the editor after taking a screenshot        | Opens the editor automatically after each capture                |
| Show a preview card after capturing              | Shows the small card with Open / Finder / Copy                   |
| Copy screenshots to the clipboard                | Copies every screenshot automatically so you can paste with `⌘V` |
| Quick Screenshot › Shortcut / Play shutter sound | Sets up the instant-capture shortcut and its sound               |
| Image format                                     | PNG (best quality), JPEG (smaller), or HEIC (smallest)           |
| Show the mouse cursor                            | Includes the pointer in screenshots                              |
| Save location › Show in Finder                   | Opens the ScreenCapture folder                                   |
| Launch at login                                  | Starts the app when you log in                                   |

**Shortcuts tab:** see [section 6](#6-set-up-keyboard-shortcuts).

---

## 9. Troubleshooting

| Problem                                   | Fix                                                                                                                              |
| ----------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| Screenshots are black or capture fails    | Turn on ScreenCapture in _System Settings › Privacy & Security › Screen & System Audio Recording_, then quit and reopen the app. |
| A shortcut doesn't work                   | Another app may be using it. Choose a different one in **Settings › Shortcuts**.                                                 |
| No sound in recording                     | Turn on **System audio** or **Microphone** before you start, and check the microphone permission.                                |
| I can't find the app                      | It lives in the menu bar, not the Dock. If you can't see it, the menu bar may be full; try closing other menu bar apps.          |
| Permission stopped working after updating | Turn ScreenCapture off and on again in _Screen & System Audio Recording_.                                                        |

---

# For developers

Built with ScreenCaptureKit, hardware-encoded AVFoundation, and SwiftUI with Liquid Glass.

## Performance notes

- Frames go from ScreenCaptureKit straight to the hardware encoder in YUV 4:2:0 (`420v`). There's no colour conversion or copying.
- All writer work runs on one serial queue, with no locks. If the encoder is busy, frames are dropped rather than blocking capture.
- Idle frames are skipped, and when the screen is static at the end, the last frame is re-stamped at stop time so the clip isn't cut short.
- Output size is clamped to encoder limits: H.264 up to 4096×2304, HEVC up to 8K.
- Recordings are written to a hidden temporary file and renamed when finished, so incomplete files never show up in History.
- Thumbnails come from QuickLook and are cached in a bounded `NSCache`. Folder scans run off the main thread and are triggered by file-system events.

## Build & run

Xcode isn't required; the Command Line Tools are enough.

```bash
./scripts/build_app.sh          # release build -> build/ScreenCapture.app
open build/ScreenCapture.app
```

Options: `CONFIG=debug ./scripts/build_app.sh`, or set `SIGN_IDENTITY="Apple Development: …"` to sign with your own certificate. You can also open `Package.swift` in Xcode.

### DMG installer

```bash
./scripts/make_dmg.sh               # builds the app, then build/ScreenCapture-<version>.dmg
SKIP_BUILD=1 ./scripts/make_dmg.sh  # package the existing build/ScreenCapture.app
```

The disk image contains the app and an `Applications` shortcut, so you can drag to install.

### Permissions

On first use, macOS asks for:

1. **Screen & System Audio Recording.** Required. If the panel shows the orange banner, click **Grant Access** and enable ScreenCapture. If capture still fails, relaunch the app.
2. **Documents folder.** Needed to save files.
3. **Microphone.** Only if you enable it.

> The default build is ad-hoc signed. macOS ties permissions to the code signature, so after a rebuild you may need to re-enable ScreenCapture under _System Settings › Privacy & Security › Screen & System Audio Recording_. Signing with a real identity (`SIGN_IDENTITY`) avoids this.

## Project layout

```
Sources/ScreenCapture/
  App/        main entry, AppDelegate (status item, popover, menus), AppModel (coordinator), window controllers
  Models/     option enums and the persisted SettingsStore
  Services/   ScreenRecorder (SCStream → AVAssetWriter), ScreenshotService, CaptureTargetResolver,
              AreaSelector, ShareableContentStore, HistoryStore, ThumbnailCache, HotKeyManager, StorageManager
  Views/      MenuView (panel), HistoryView, PostCaptureView, shared views
Resources/Info.plist
scripts/build_app.sh, scripts/make_icon.swift
```
