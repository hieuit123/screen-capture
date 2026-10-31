import AppKit
import Carbon.HIToolbox

/// A global keyboard shortcut (key code + modifiers) with a display label.
struct Shortcut: Codable, Equatable, Hashable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt
    var key: String

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var carbonModifiers: UInt32 {
        var result = 0
        if flags.contains(.command) { result |= cmdKey }
        if flags.contains(.option) { result |= optionKey }
        if flags.contains(.control) { result |= controlKey }
        if flags.contains(.shift) { result |= shiftKey }
        return UInt32(result)
    }

    var displayString: String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + key
    }

    init(keyCode: Int, modifiers: NSEvent.ModifierFlags, key: String) {
        self.keyCode = UInt32(keyCode)
        self.modifiers = modifiers.intersection([.command, .option, .control, .shift]).rawValue
        self.key = key
    }

    /// Builds a shortcut from a key press. Requires ⌘, ⌃ or ⌥ unless the key is a function key.
    init?(event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let code = Int(event.keyCode)
        let special = Self.specialKeys[code]
        let isFunctionKey = special?.hasPrefix("F") == true && special!.count > 1
        guard !mods.intersection([.command, .option, .control]).isEmpty || isFunctionKey else { return nil }
        guard let label = special ?? event.charactersIgnoringModifiers?.uppercased(), !label.isEmpty,
              label.rangeOfCharacter(from: .controlCharacters) == nil
        else { return nil }
        self.init(keyCode: code, modifiers: mods, key: label)
    }

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18",
        kVK_F19: "F19", kVK_F20: "F20",
    ]
}

enum ShortcutAction: String, CaseIterable, Identifiable, Sendable {
    case screenshot, quickScreenshot, areaScreenshot, fullPageScreenshot, captureText, toggleRecording

    var id: String { rawValue }

    var title: String {
        switch self {
        case .screenshot: "Take Screenshot"
        case .quickScreenshot: "Quick Screenshot"
        case .areaScreenshot: "Capture Area"
        case .fullPageScreenshot: "Full-Page Screenshot (Chrome)"
        case .captureText: "Capture Text (OCR)"
        case .toggleRecording: "Start / Stop Recording"
        }
    }

    var detail: String {
        switch self {
        case .screenshot: "Uses the source selected in the menu (screen, window, app or area)."
        case .quickScreenshot: "Instantly captures the screen under the mouse, copies it and saves it. No editor."
        case .areaScreenshot: "Always lets you drag out an area, then opens the editor."
        case .fullPageScreenshot: "Scrolls the active Chrome tab and captures the whole web page as one image."
        case .captureText: "Drag over an area to copy the text in it. Nothing is saved."
        case .toggleRecording: "Starts recording with the current options, or stops it."
        }
    }

    var defaultShortcut: Shortcut {
        let mods: NSEvent.ModifierFlags = [.control, .option, .command]
        switch self {
        case .screenshot: return Shortcut(keyCode: kVK_ANSI_S, modifiers: mods, key: "S")
        case .quickScreenshot: return Shortcut(keyCode: kVK_ANSI_D, modifiers: mods, key: "D")
        case .areaScreenshot: return Shortcut(keyCode: kVK_ANSI_A, modifiers: mods, key: "A")
        case .fullPageScreenshot: return Shortcut(keyCode: kVK_ANSI_F, modifiers: mods, key: "F")
        case .captureText: return Shortcut(keyCode: kVK_ANSI_T, modifiers: mods, key: "T")
        case .toggleRecording: return Shortcut(keyCode: kVK_ANSI_R, modifiers: mods, key: "R")
        }
    }
}
