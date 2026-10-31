import AppKit
import AVFoundation
import Observation

/// UI hooks the model uses to drive AppKit windows.
@MainActor
protocol AppUI: AnyObject {
    func dismissPopover()
    func phaseDidChange()
    func showPostCapture(_ item: CaptureItem)
    /// `beautify`: start with the default Beautify style switched on (for fresh, un-beautified captures).
    func openEditor(url: URL, image: CGImage?, beautify: Bool)
    func showQuickCaptureToast(url: URL, image: CGImage, thumbnail: CGImage, on displayID: CGDirectDisplayID)
    /// Confirms an OCR copy. `text` is empty when nothing was recognized.
    func showTextToast(thumbnail: CGImage, text: String, on displayID: CGDirectDisplayID)
    /// Floats the image on top of other windows. `frame` (global coordinates) places it exactly.
    func pin(image: CGImage, sourceURL: URL?, at frame: NSRect?)
    var isPopoverShown: Bool { get }
    func openHistory(_ kind: CaptureKind, select url: URL?)
    func showError(_ message: String)
}

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case idle
        case preparing
        case recording(since: Date)
        case finishing

        var isRecording: Bool { if case .recording = self { true } else { false } }
        var isBusy: Bool { self != .idle }
    }

    let settings = SettingsStore()
    let content = ShareableContentStore()
    let history = HistoryStore()

    private(set) var phase: Phase = .idle {
        didSet { ui?.phaseDidChange() }
    }
    private(set) var hasScreenPermission = CGPreflightScreenCaptureAccess()

    @ObservationIgnored weak var ui: AppUI?
    @ObservationIgnored private var recorder: ScreenRecorder?
    @ObservationIgnored private var pendingOutputURL: URL?
    @ObservationIgnored private let areaSelector = AreaSelector()
    @ObservationIgnored private let frameOverlay = RecordingFrameOverlay()

    // MARK: Content

    func refreshContent() async {
        hasScreenPermission = CGPreflightScreenCaptureAccess()
        guard hasScreenPermission else { return }
        await content.refresh()
        fixSelections()
    }

    func requestScreenPermission() {
        if !CGRequestScreenCaptureAccess() {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
        hasScreenPermission = CGPreflightScreenCaptureAccess()
    }

    private func fixSelections() {
        if !content.displays.contains(where: { $0.id == settings.displayID }) {
            settings.displayID = content.displays.first { $0.id == CGMainDisplayID() }?.id ?? content.displays.first?.id ?? 0
        }
        if !content.windows.contains(where: { $0.id == settings.windowID }), let first = content.windows.first {
            settings.windowID = first.id
        }
        if !content.apps.contains(where: { $0.id == settings.appBundleID }), let first = content.apps.first {
            settings.appBundleID = first.id
        }
    }

    // MARK: Actions

    func performPrimaryAction() {
        settings.kind == .recording ? toggleRecording() : takeScreenshot()
    }

    func toggleRecording() {
        switch phase {
        case .idle: Task { await startRecording() }
        case .recording: Task { await stopRecording() }
        default: break
        }
    }

    func takeScreenshot() {
        guard phase == .idle || phase.isRecording else { return }
        let source = settings.source
        Task { await captureScreenshot(source: source) }
    }

    /// Instantly captures the display under the mouse, copies it and saves it. No editor, no area selection.
    func quickScreenshot() {
        guard phase == .idle || phase.isRecording else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let displayID = screen?.displayID else { return }
        Task { await captureQuickScreenshot(displayID: displayID) }
    }

    private func captureQuickScreenshot(displayID: CGDirectDisplayID) async {
        let wasIdle = phase == .idle
        if wasIdle { phase = .preparing }
        defer { if wasIdle { phase = .idle } }

        do {
            if ui?.isPopoverShown == true {
                ui?.dismissPopover()
                try? await Task.sleep(for: .milliseconds(180))
            }
            let target = try await CaptureTargetResolver.resolve(source: .display, settings: settings, area: nil, displayID: displayID)
            let image = try await ScreenshotService.capture(target: target, showsCursor: settings.showsCursor)
            let output = finalImage(for: image)
            ScreenshotService.copyToPasteboard(output)
            if settings.playCaptureSound { Self.shutterSound?.play() }

            let format = settings.imageFormat
            let url = try StorageManager.newFileURL(kind: .screenshot, fileExtension: format.fileExtension)
            try await Task.detached(priority: .userInitiated) {
                try ScreenshotService.write(output, to: url, format: format)
            }.value
            settings.lastActionKind = .screenshot
            history.reload()
            ui?.showQuickCaptureToast(url: url, image: image, thumbnail: output, on: displayID)
        } catch {
            ui?.showError(error.localizedDescription)
        }
    }

    /// The image that goes to the clipboard and disk: beautified when auto-apply is on.
    private func finalImage(for image: CGImage) -> CGImage {
        guard settings.autoApplyBeautify else { return image }
        return EditorRenderer.render(image: image, pixelated: nil, annotations: [], beautify: settings.beautifyStyle.applied) ?? image
    }

    private static let shutterSound: NSSound? = {
        let path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
        return NSSound(contentsOfFile: path, byReference: true) ?? NSSound(named: "Tink")
    }()

    /// Screenshot of a dragged area, regardless of the source selected in the menu.
    func captureArea() {
        guard phase == .idle || phase.isRecording else { return }
        Task { await captureScreenshot(source: .area) }
    }

    /// Scrolls the active Chrome tab and saves the whole web page as one screenshot.
    func captureFullPage() {
        guard phase == .idle || phase.isRecording else { return }
        Task {
            await saveScreenshot {
                ui?.dismissPopover()
                return try await FullPageCapture.capture(scale: settings.fullPageQuality.scale)
            }
        }
    }

    /// Drag an area and copy the text in it (OCR). Nothing is saved.
    func captureText() {
        guard phase == .idle || phase.isRecording else { return }
        Task {
            let wasIdle = phase == .idle
            if wasIdle { phase = .preparing }
            defer { if wasIdle { phase = .idle } }
            do {
                let target = try await resolveTarget(source: .area, mode: .screenshot)
                let image = try await ScreenshotService.capture(target: target, showsCursor: false)
                await copyRecognizedText(from: image, displayID: target.areaSelection?.displayID ?? CGMainDisplayID())
            } catch CaptureError.cancelled {
                return
            } catch {
                ui?.showError(error.localizedDescription)
            }
        }
    }

    /// Drag an area and pin it on screen, exactly where it was. Nothing is saved.
    func pinArea() {
        guard phase == .idle || phase.isRecording else { return }
        Task {
            let wasIdle = phase == .idle
            if wasIdle { phase = .preparing }
            defer { if wasIdle { phase = .idle } }
            do {
                let target = try await resolveTarget(source: .area, mode: .screenshot)
                let image = try await ScreenshotService.capture(target: target, showsCursor: false)
                ui?.pin(image: image, sourceURL: nil, at: target.areaSelection?.globalFrame)
            } catch CaptureError.cancelled {
                return
            } catch {
                ui?.showError(error.localizedDescription)
            }
        }
    }

    /// Writes an image to the screenshots folder (current format) and returns its URL.
    func saveToScreenshots(_ image: CGImage) async throws -> URL {
        let format = settings.imageFormat
        let url = try StorageManager.newFileURL(kind: .screenshot, fileExtension: format.fileExtension)
        try await Task.detached(priority: .userInitiated) {
            try ScreenshotService.write(image, to: url, format: format)
        }.value
        settings.lastActionKind = .screenshot
        history.reload()
        return url
    }

    /// Recognizes the text in the image, copies it and confirms with a toast.
    func copyRecognizedText(from image: CGImage, displayID: CGDirectDisplayID) async {
        do {
            let text = try await TextRecognizer.recognize(image)
            if !text.isEmpty {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            ui?.showTextToast(thumbnail: image, text: text, on: displayID)
        } catch {
            ui?.showError("Couldn't recognize text: \(error.localizedDescription)")
        }
    }

    private func resolveTarget(source: CaptureSource, mode: AreaSelectionMode) async throws -> CaptureTarget {
        ui?.dismissPopover()
        var area: AreaSelection?
        if source == .area {
            area = await areaSelector.selectArea(mode: mode)
            guard area != nil else { throw CaptureError.cancelled }
        }
        // Let the popover / selection overlay disappear from the screen before capturing.
        try? await Task.sleep(for: .milliseconds(source == .area ? 120 : 180))
        return try await CaptureTargetResolver.resolve(source: source, settings: settings, area: area)
    }

    private func startRecording() async {
        guard phase == .idle else { return }
        phase = .preparing

        do {
            if settings.captureMicrophone, !(await AVCaptureDevice.requestAccess(for: .audio)) {
                throw RecorderError.cannotCreateWriter("Microphone access was denied. Enable it in System Settings › Privacy & Security › Microphone.")
            }
            let target = try await resolveTarget(source: settings.source, mode: .recording)
            let options = RecordingOptions(
                frameRate: settings.frameRate.rawValue,
                quality: settings.quality,
                codec: settings.codec,
                container: settings.container,
                showsCursor: settings.showsCursor,
                captureSystemAudio: settings.captureSystemAudio,
                captureMicrophone: settings.captureMicrophone,
                microphoneID: settings.microphoneID.isEmpty ? nil : settings.microphoneID)
            let url = try StorageManager.newFileURL(kind: .recording, fileExtension: settings.container.rawValue)

            let recorder = ScreenRecorder()
            recorder.onUnexpectedStop = { [weak self] _ in
                Task { @MainActor in await self?.stopRecording() }
            }
            try await recorder.start(target: target, options: options, outputURL: url)

            self.recorder = recorder
            pendingOutputURL = url
            if let area = target.areaSelection { frameOverlay.show(for: area) }
            phase = .recording(since: .now)
        } catch CaptureError.cancelled {
            phase = .idle
        } catch {
            phase = .idle
            ui?.showError(error.localizedDescription)
        }
    }

    func stopRecording() async {
        guard phase.isRecording, let recorder, let url = pendingOutputURL else { return }
        phase = .finishing
        frameOverlay.hide()
        self.recorder = nil
        pendingOutputURL = nil

        do {
            let saved = try await recorder.stop(moveTo: url)
            phase = .idle
            didSave(saved, kind: .recording, image: nil)
        } catch {
            phase = .idle
            ui?.showError(error.localizedDescription)
        }
    }

    private func captureScreenshot(source: CaptureSource) async {
        await saveScreenshot {
            let target = try await resolveTarget(source: source, mode: .screenshot)
            return try await ScreenshotService.capture(target: target, showsCursor: settings.showsCursor)
        }
    }

    private func saveScreenshot(_ capture: () async throws -> CGImage) async {
        let wasIdle = phase == .idle
        if wasIdle { phase = .preparing }
        defer { if wasIdle { phase = .idle } }

        do {
            let image = try await capture()
            let format = settings.imageFormat
            let url = try StorageManager.newFileURL(kind: .screenshot, fileExtension: format.fileExtension)

            let output = finalImage(for: image)
            if settings.copyScreenshotToClipboard { ScreenshotService.copyToPasteboard(output) }
            try await Task.detached(priority: .userInitiated) {
                try ScreenshotService.write(output, to: url, format: format)
            }.value
            didSave(url, kind: .screenshot, image: image)
        } catch CaptureError.cancelled {
            return
        } catch {
            ui?.showError(error.localizedDescription)
        }
    }

    private func didSave(_ url: URL, kind: CaptureKind, image: CGImage?) {
        settings.lastActionKind = kind
        history.reload()
        if kind == .screenshot, settings.openEditorAfterScreenshot {
            // The editor gets the raw capture; Beautify stays editable on top of it.
            ui?.openEditor(url: url, image: image, beautify: settings.autoApplyBeautify)
            return
        }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
        let item = CaptureItem(url: url, kind: kind, date: .now, size: size)
        if settings.showPostCapturePanel {
            ui?.showPostCapture(item)
        }
    }
}
