import ScreenCaptureKit

/// A ready-to-use ScreenCaptureKit filter plus geometry for the selected source.
struct CaptureTarget: @unchecked Sendable {
    let filter: SCContentFilter
    /// Crop rectangle in display points (top-left origin), only for area captures.
    let sourceRect: CGRect?
    /// Size of the captured content in native pixels.
    let nativePixelSize: CGSize
    /// Area rect in global coordinates, used to draw the recording frame.
    let areaSelection: AreaSelection?
}

enum CaptureError: LocalizedError {
    case noDisplay
    case windowNotFound
    case appNotFound
    case cancelled
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .noDisplay: "No display is available to capture."
        case .windowNotFound: "The selected window is no longer available. Choose another window."
        case .appNotFound: "The selected app has no visible windows. Choose another app."
        case .cancelled: "Capture cancelled."
        case .permissionDenied:
            "ScreenCapture needs Screen Recording permission. Enable it in System Settings › Privacy & Security › Screen & System Audio Recording, then try again."
        }
    }
}

@MainActor
enum CaptureTargetResolver {
    /// Window numbers of our own windows that may appear in captures (open editors), so an edited screenshot can itself be captured.
    static var capturableOwnWindowNumbers: () -> Set<CGWindowID> = { [] }

    static func resolve(source: CaptureSource, settings: SettingsStore, area: AreaSelection?,
                        displayID displayOverride: CGDirectDisplayID? = nil) async throws -> CaptureTarget {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw CaptureError.permissionDenied
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownApps = content.applications.filter { $0.processID == ownPID }
        let capturable = capturableOwnWindowNumbers()
        let ownEditorWindows = content.windows.filter { $0.owningApplication?.processID == ownPID && capturable.contains($0.windowID) }

        func display(id: CGDirectDisplayID) -> SCDisplay? {
            content.displays.first { $0.displayID == id }
                ?? content.displays.first { $0.displayID == CGMainDisplayID() }
                ?? content.displays.first
        }

        func pixelSize(_ filter: SCContentFilter, _ rect: CGRect? = nil) -> CGSize {
            let scale = CGFloat(filter.pointPixelScale)
            let size = rect?.size ?? filter.contentRect.size
            return CGSize(width: size.width * scale, height: size.height * scale)
        }

        switch source {
        case .display:
            guard let display = display(id: displayOverride ?? settings.displayID) else { throw CaptureError.noDisplay }
            let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: ownEditorWindows)
            return CaptureTarget(filter: filter, sourceRect: nil, nativePixelSize: pixelSize(filter), areaSelection: nil)

        case .window:
            guard let window = content.windows.first(where: { $0.windowID == settings.windowID }) else {
                throw CaptureError.windowNotFound
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            return CaptureTarget(filter: filter, sourceRect: nil, nativePixelSize: pixelSize(filter), areaSelection: nil)

        case .application:
            guard let app = content.applications.first(where: { $0.bundleIdentifier == settings.appBundleID }) else {
                throw CaptureError.appNotFound
            }
            let appWindows = content.windows.filter {
                $0.owningApplication?.processID == app.processID && $0.isOnScreen && $0.windowLayer == 0
            }
            guard !appWindows.isEmpty else { throw CaptureError.appNotFound }
            // Record on the display that shows the largest share of the app's windows.
            let best = content.displays.max { lhs, rhs in
                coverage(of: appWindows, on: lhs) < coverage(of: appWindows, on: rhs)
            }
            guard let target = best ?? display(id: settings.displayID) else { throw CaptureError.noDisplay }
            let filter = SCContentFilter(display: target, including: [app], exceptingWindows: [])
            return CaptureTarget(filter: filter, sourceRect: nil, nativePixelSize: pixelSize(filter), areaSelection: nil)

        case .area:
            guard let area else { throw CaptureError.cancelled }
            guard let display = content.displays.first(where: { $0.displayID == area.displayID }) else {
                throw CaptureError.noDisplay
            }
            let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: ownEditorWindows)
            return CaptureTarget(filter: filter, sourceRect: area.rect,
                                 nativePixelSize: pixelSize(filter, area.rect), areaSelection: area)
        }
    }

    private static func coverage(of windows: [SCWindow], on display: SCDisplay) -> CGFloat {
        windows.reduce(0) { total, window in
            let overlap = window.frame.intersection(display.frame)
            return total + (overlap.isNull ? 0 : overlap.width * overlap.height)
        }
    }
}
