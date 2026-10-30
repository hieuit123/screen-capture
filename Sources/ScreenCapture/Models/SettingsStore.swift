import Foundation
import Observation

@MainActor
@Observable
final class SettingsStore {
    @ObservationIgnored private let defaults = UserDefaults.standard

    var kind: CaptureKind { didSet { defaults.set(kind.rawValue, forKey: Keys.kind) } }
    var source: CaptureSource { didSet { defaults.set(source.rawValue, forKey: Keys.source) } }
    var displayID: UInt32 { didSet { defaults.set(Int(displayID), forKey: Keys.displayID) } }
    var windowID: UInt32 { didSet { defaults.set(Int(windowID), forKey: Keys.windowID) } }
    var appBundleID: String { didSet { defaults.set(appBundleID, forKey: Keys.appBundleID) } }

    var frameRate: FrameRate { didSet { defaults.set(frameRate.rawValue, forKey: Keys.frameRate) } }
    var quality: VideoQuality { didSet { defaults.set(quality.rawValue, forKey: Keys.quality) } }
    var codec: VideoCodec { didSet { defaults.set(codec.rawValue, forKey: Keys.codec) } }
    var container: VideoContainer { didSet { defaults.set(container.rawValue, forKey: Keys.container) } }
    var showsCursor: Bool { didSet { defaults.set(showsCursor, forKey: Keys.showsCursor) } }
    var captureSystemAudio: Bool { didSet { defaults.set(captureSystemAudio, forKey: Keys.systemAudio) } }
    var captureMicrophone: Bool { didSet { defaults.set(captureMicrophone, forKey: Keys.microphone) } }
    var microphoneID: String { didSet { defaults.set(microphoneID, forKey: Keys.microphoneID) } }

    var imageFormat: ImageFormat { didSet { defaults.set(imageFormat.rawValue, forKey: Keys.imageFormat) } }
    var fullPageQuality: FullPageQuality { didSet { defaults.set(fullPageQuality.rawValue, forKey: Keys.fullPageQuality) } }
    var copyScreenshotToClipboard: Bool { didSet { defaults.set(copyScreenshotToClipboard, forKey: Keys.copyToClipboard) } }
    var showPostCapturePanel: Bool { didSet { defaults.set(showPostCapturePanel, forKey: Keys.postCapture) } }
    var openEditorAfterScreenshot: Bool { didSet { defaults.set(openEditorAfterScreenshot, forKey: Keys.openEditor) } }
    var playCaptureSound: Bool { didSet { defaults.set(playCaptureSound, forKey: Keys.captureSound) } }
    var closeEditorAfterCopyOrSave: Bool { didSet { defaults.set(closeEditorAfterCopyOrSave, forKey: Keys.closeEditor) } }

    /// Apply the Beautify style to every new screenshot (clipboard, file and editor).
    var autoApplyBeautify: Bool { didSet { defaults.set(autoApplyBeautify, forKey: Keys.autoBeautify) } }
    /// Default Beautify style. Also updated when the style is changed in the editor.
    var beautifyStyle: BeautifySettings {
        didSet { defaults.set(try? JSONEncoder().encode(beautifyStyle), forKey: Keys.beautifyStyle) }
    }

    /// Global shortcuts. A missing entry means the shortcut is disabled.
    var shortcuts: [ShortcutAction: Shortcut] {
        didSet {
            let encoded = Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.key.rawValue, $0.value) })
            defaults.set(try? JSONEncoder().encode(encoded), forKey: Keys.shortcuts)
            defaults.set(ShortcutAction.allCases.map(\.rawValue), forKey: Keys.shortcutActionsSeen)
            onShortcutsChanged?()
        }
    }
    @ObservationIgnored var onShortcutsChanged: (() -> Void)?

    /// Assigns a shortcut, removing it from any other action so a combination maps to one action only.
    func setShortcut(_ shortcut: Shortcut?, for action: ShortcutAction) {
        var updated = shortcuts
        if let shortcut {
            for (other, existing) in updated where other != action && existing == shortcut {
                updated[other] = nil
            }
        }
        updated[action] = shortcut
        shortcuts = updated
    }

    /// The kind of the most recent capture, used to pick the default history tab.
    var lastActionKind: CaptureKind { didSet { defaults.set(lastActionKind.rawValue, forKey: Keys.lastAction) } }

    init() {
        let d = defaults
        kind = CaptureKind(rawValue: d.string(forKey: Keys.kind) ?? "") ?? .recording
        source = CaptureSource(rawValue: d.string(forKey: Keys.source) ?? "") ?? .display
        displayID = UInt32(d.integer(forKey: Keys.displayID))
        windowID = UInt32(d.integer(forKey: Keys.windowID))
        appBundleID = d.string(forKey: Keys.appBundleID) ?? ""
        frameRate = FrameRate(rawValue: d.object(forKey: Keys.frameRate) as? Int ?? 60) ?? .fps60
        quality = VideoQuality(rawValue: d.string(forKey: Keys.quality) ?? "") ?? .high
        codec = VideoCodec(rawValue: d.string(forKey: Keys.codec) ?? "") ?? .hevc
        container = VideoContainer(rawValue: d.string(forKey: Keys.container) ?? "") ?? .mp4
        showsCursor = d.object(forKey: Keys.showsCursor) as? Bool ?? true
        captureSystemAudio = d.object(forKey: Keys.systemAudio) as? Bool ?? false
        captureMicrophone = d.object(forKey: Keys.microphone) as? Bool ?? false
        microphoneID = d.string(forKey: Keys.microphoneID) ?? ""
        imageFormat = ImageFormat(rawValue: d.string(forKey: Keys.imageFormat) ?? "") ?? .png
        fullPageQuality = FullPageQuality(rawValue: d.string(forKey: Keys.fullPageQuality) ?? "") ?? .best
        copyScreenshotToClipboard = d.object(forKey: Keys.copyToClipboard) as? Bool ?? false
        showPostCapturePanel = d.object(forKey: Keys.postCapture) as? Bool ?? true
        openEditorAfterScreenshot = d.object(forKey: Keys.openEditor) as? Bool ?? true
        playCaptureSound = d.object(forKey: Keys.captureSound) as? Bool ?? true
        closeEditorAfterCopyOrSave = d.object(forKey: Keys.closeEditor) as? Bool ?? true
        autoApplyBeautify = d.object(forKey: Keys.autoBeautify) as? Bool ?? false
        beautifyStyle = d.data(forKey: Keys.beautifyStyle).flatMap { try? JSONDecoder().decode(BeautifySettings.self, from: $0) }
            ?? BeautifySettings()
        if let data = d.data(forKey: Keys.shortcuts),
           let stored = try? JSONDecoder().decode([String: Shortcut].self, from: data) {
            var loaded = Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in
                ShortcutAction(rawValue: key).map { ($0, value) }
            })
            // Actions added in a later version get their default, unless that combination is already taken.
            let seen = Set(d.stringArray(forKey: Keys.shortcutActionsSeen) ?? stored.keys.map { $0 })
            for action in ShortcutAction.allCases where !seen.contains(action.rawValue) && loaded[action] == nil {
                if !loaded.values.contains(action.defaultShortcut) { loaded[action] = action.defaultShortcut }
            }
            shortcuts = loaded
        } else {
            shortcuts = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.defaultShortcut) })
        }
        lastActionKind = CaptureKind(rawValue: d.string(forKey: Keys.lastAction) ?? "") ?? .recording
    }

    private enum Keys {
        static let kind = "kind"
        static let source = "source"
        static let displayID = "displayID"
        static let windowID = "windowID"
        static let appBundleID = "appBundleID"
        static let frameRate = "frameRate"
        static let quality = "quality"
        static let codec = "codec"
        static let container = "container"
        static let showsCursor = "showsCursor"
        static let systemAudio = "captureSystemAudio"
        static let microphone = "captureMicrophone"
        static let microphoneID = "microphoneID"
        static let imageFormat = "imageFormat"
        static let fullPageQuality = "fullPageQuality"
        static let copyToClipboard = "copyScreenshotToClipboard"
        static let postCapture = "showPostCapturePanel"
        static let lastAction = "lastActionKind"
        static let openEditor = "openEditorAfterScreenshot"
        static let shortcuts = "shortcuts.v1"
        static let shortcutActionsSeen = "shortcuts.seenActions"
        static let captureSound = "playCaptureSound"
        static let closeEditor = "closeEditorAfterCopyOrSave"
        static let autoBeautify = "autoApplyBeautify"
        static let beautifyStyle = "beautifyStyle.v1"
    }
}
