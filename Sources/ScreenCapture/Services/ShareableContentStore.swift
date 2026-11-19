import AppKit
import AVFoundation
import Observation
import ScreenCaptureKit

struct DisplayOption: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
    let pointSize: CGSize
    let scale: CGFloat

    var pixelSize: CGSize { CGSize(width: pointSize.width * scale, height: pointSize.height * scale) }
}

struct WindowOption: Identifiable, Hashable {
    let id: CGWindowID
    let title: String
    let appName: String
    let pid: pid_t
}

struct AppOption: Identifiable, Hashable {
    let id: String
    let name: String
    let pid: pid_t
}

struct MicrophoneOption: Identifiable, Hashable {
    let id: String
    let name: String
}

/// Lightweight, UI-friendly snapshot of what can be captured.
@MainActor
@Observable
final class ShareableContentStore {
    private(set) var displays: [DisplayOption] = []
    private(set) var windows: [WindowOption] = []
    private(set) var apps: [AppOption] = []
    private(set) var microphones: [MicrophoneOption] = []
    private(set) var isLoading = false

    @ObservationIgnored private var iconCache: [pid_t: NSImage] = [:]

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        refreshMicrophones()
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else {
            return
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier

        displays = content.displays.map { display in
            let screen = NSScreen.screens.first { $0.displayID == display.displayID }
            return DisplayOption(
                id: display.displayID,
                name: screen?.localizedName ?? "Display \(display.displayID)",
                pointSize: display.frame.size,
                scale: screen?.backingScaleFactor ?? 2
            )
        }

        windows = content.windows
            .filter { window in
                guard let app = window.owningApplication else { return false }
                if app.processID == ownPID && !CaptureTargetResolver.capturableOwnWindowNumbers().contains(window.windowID) { return false }
                return window.isOnScreen && window.windowLayer == 0
                    && window.frame.width >= 80 && window.frame.height >= 60
            }
            .map { window in
                let appName = window.owningApplication?.applicationName ?? "Unknown"
                let title = (window.title?.isEmpty == false ? window.title! : appName)
                return WindowOption(id: window.windowID, title: title, appName: appName,
                                    pid: window.owningApplication?.processID ?? 0)
            }
            .sorted { ($0.appName, $0.title) < ($1.appName, $1.title) }

        let pidsWithWindows = Set(windows.map(\.pid))
        apps = content.applications
            .filter { pidsWithWindows.contains($0.processID) && !$0.bundleIdentifier.isEmpty }
            .map { AppOption(id: $0.bundleIdentifier, name: $0.applicationName, pid: $0.processID) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func icon(for pid: pid_t) -> NSImage? {
        if let cached = iconCache[pid] { return cached }
        let icon = NSRunningApplication(processIdentifier: pid)?.icon
        if let icon {
            icon.size = NSSize(width: 16, height: 16)
            iconCache[pid] = icon
        }
        return icon
    }

    private func refreshMicrophones() {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
        microphones = session.devices.map { MicrophoneOption(id: $0.uniqueID, name: $0.localizedName) }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
