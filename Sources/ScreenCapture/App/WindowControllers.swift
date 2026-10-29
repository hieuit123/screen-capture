import AppKit
import SwiftUI

@MainActor
final class HistoryWindowController: NSWindowController, NSWindowDelegate {
    let state = HistoryViewState()
    var onClose: (() -> Void)?

    init(history: HistoryStore, onEdit: @escaping (CaptureItem) -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "History"
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false

        let hosting = NSHostingController(rootView: HistoryView(history: history, state: state, onEdit: onEdit))
        hosting.sceneBridgingOptions = [.toolbars, .title]
        hosting.sizingOptions = [.minSize]
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 1040, height: 680))
        window.center()
        window.setFrameAutosaveName("ScreenCaptureHistory")

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(kind: CaptureKind, select url: URL?) {
        state.kind = kind
        state.searchText = ""
        state.selection = url.map { [$0] } ?? []
        NSApp.setActivationPolicy(.regular)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        NSApp.forceActivate()
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    let editorDocument: EditorDocument
    var onClose: ((EditorWindowController) -> Void)?
    /// Copy/Save finished and the window closed itself.
    var onFinish: ((EditorFinishAction, CGImage, CGDirectDisplayID?) -> Void)?

    init(document: EditorDocument, settings: SettingsStore) {
        self.editorDocument = document
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = document.fileURL.lastPathComponent
        window.representedURL = document.fileURL
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false

        weak var weakSelf: EditorWindowController?
        let view = EditorView(doc: document, settings: settings) {
            NSWorkspace.shared.activateFileViewerSelecting([document.fileURL])
        } onFinish: { action, image in
            weakSelf?.finish(action, image: image)
        }
        let hosting = NSHostingController(rootView: view)
        hosting.sceneBridgingOptions = [.toolbars]
        hosting.sizingOptions = [.minSize]
        window.contentViewController = hosting

        // Fit the window to the visible screen area.
        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let size = NSSize(width: min(1280, visible.width * 0.85), height: min(860, visible.height * 0.88))
        window.setContentSize(size)
        window.center()

        super.init(window: window)
        window.delegate = self
        weakSelf = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func present() {
        NSApp.setActivationPolicy(.regular)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        NSApp.forceActivate()
    }

    private func finish(_ action: EditorFinishAction, image: CGImage) {
        let displayID = window?.screen?.displayID
        // `close()` skips windowShouldClose: the work is already copied/saved.
        window?.close()
        onFinish?(action, image, displayID)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        editorDocument.commitTextEditing()
        guard editorDocument.isDirty else { return true }

        let alert = NSAlert()
        alert.messageText = "Save changes to “\(editorDocument.fileURL.lastPathComponent)”?"
        alert.informativeText = "Your annotations will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: sender) { [weak self] response in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch response {
                case .alertFirstButtonReturn:
                    Task {
                        do {
                            try await self.editorDocument.save()
                            sender.close()
                        } catch {
                            NSAlert(error: error).beginSheetModal(for: sender, completionHandler: nil)
                        }
                    }
                case .alertSecondButtonReturn:
                    sender.close()
                default:
                    break
                }
            }
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        onClose?(self)
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    init(settings: SettingsStore) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 580),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "ScreenCapture Settings"
        window.isReleasedWhenClosed = false
        let hosting = NSHostingController(rootView: SettingsView(settings: settings))
        hosting.sizingOptions = [.preferredContentSize]
        window.contentViewController = hosting
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func present() {
        NSApp.setActivationPolicy(.regular)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        NSApp.forceActivate()
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

/// Brief HUD at the bottom of the captured screen after a Quick Screenshot.
@MainActor
final class QuickCaptureToastController {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    private var isHovered = false

    func show(image: CGImage, title: String, subtitle: String, on displayID: CGDirectDisplayID,
              onClick: @escaping () -> Void) {
        close(animated: false)

        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let view = QuickCaptureToastView(
            image: NSImage(cgImage: image, size: .zero),
            title: title,
            subtitle: subtitle,
            onClick: { [weak self] in
                self?.close(animated: true)
                onClick()
            },
            onHoverChange: { [weak self] hovering in
                self?.isHovered = hovering
                if !hovering { self?.scheduleDismiss(after: .seconds(1.2)) }
            })
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hosting
        let size = hosting.fittingSize

        let screen = NSScreen.screens.first { $0.displayID == displayID } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let finalFrame = NSRect(x: visible.midX - size.width / 2, y: visible.minY + 40, width: size.width, height: size.height)
        panel.setFrame(finalFrame.offsetBy(dx: 0, dy: -12), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(finalFrame, display: true)
            panel.animator().alphaValue = 1
        }

        self.panel = panel
        scheduleDismiss(after: .seconds(2.4))
    }

    private func scheduleDismiss(after delay: Duration) {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, !self.isHovered else { return }
            self.close(animated: true)
        }
    }

    func close(animated: Bool) {
        dismissTask?.cancel()
        guard let panel else { return }
        self.panel = nil
        isHovered = false
        guard animated else {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        }
    }
}

/// Non-activating floating panel in the bottom-right corner, like the system screenshot thumbnail.
@MainActor
final class PostCapturePanelController {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    private var isHovered = false

    func show(item: CaptureItem, openHistory: @escaping () -> Void, edit: (() -> Void)?) {
        close(animated: false)

        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = PostCaptureView(
            item: item,
            openHistory: { [weak self] in
                self?.close(animated: true)
                openHistory()
            },
            edit: edit.map { edit in { [weak self] in
                self?.close(animated: true)
                edit()
            } },
            close: { [weak self] in self?.close(animated: true) },
            onHoverChange: { [weak self] hovering in
                self?.isHovered = hovering
                if !hovering { self?.scheduleDismiss() }
            })
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hosting
        let size = hosting.fittingSize

        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? .zero
        let finalFrame = NSRect(x: visible.maxX - size.width - 16, y: visible.minY + 16,
                                width: size.width, height: size.height)
        panel.setFrame(finalFrame.offsetBy(dx: size.width + 32, dy: 0), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(finalFrame, display: true)
            panel.animator().alphaValue = 1
        }

        self.panel = panel
        scheduleDismiss()
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, let self, !self.isHovered else { return }
            self.close(animated: true)
        }
    }

    func close(animated: Bool) {
        dismissTask?.cancel()
        guard let panel else { return }
        self.panel = nil
        isHovered = false
        guard animated else {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        }
    }
}

extension NSApplication {
    /// `activate()` is cooperative since macOS 14 and is ignored while another app is frontmost
    /// (e.g. after a global shortcut). Our windows would then show without keyboard focus, so ⌘S/⌘C
    /// would go to the previous app. The legacy call still activates reliably.
    func forceActivate() {
        activate(ignoringOtherApps: true)
    }
}
