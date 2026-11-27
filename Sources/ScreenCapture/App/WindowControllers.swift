import AppKit
import SwiftUI

@MainActor
final class HistoryWindowController: NSWindowController, NSWindowDelegate {
    let state = HistoryViewState()
    var onClose: (() -> Void)?

    init(history: HistoryStore, onEdit: @escaping (CaptureItem) -> Void, onCopyText: @escaping (CaptureItem) -> Void,
         onPin: @escaping (CaptureItem) -> Void, onTrim: @escaping (CaptureItem) -> Void,
         onOpenRecording: @escaping (CaptureItem) -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "History"
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false

        let hosting = NSHostingController(rootView: HistoryView(history: history, state: state, onEdit: onEdit,
                                                                onCopyText: onCopyText, onPin: onPin, onTrim: onTrim,
                                                                onOpenRecording: onOpenRecording))
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
    /// Pin the edited image (with the document's file URL).
    var onPin: ((CGImage, URL) -> Void)?
    private var deleteKeyMonitor: Any?

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
        } onPin: { image in
            weakSelf?.onPin?(image, document.fileURL)
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

        // Backspace/Delete removes the selected mark even when SwiftUI focus is not on the canvas
        // (e.g. after typing text or clicking the side panel). Text fields keep their normal Backspace.
        deleteKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, event.window === window, window.isKeyWindow,
                  event.keyCode == 51 || event.keyCode == 117,
                  event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
                  !(window.firstResponder is NSText),
                  self.editorDocument.textEditing == nil, self.editorDocument.selectedID != nil else { return event }
            self.editorDocument.deleteSelection()
            return nil
        }
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
        if let deleteKeyMonitor { NSEvent.removeMonitor(deleteKeyMonitor) }
        deleteKeyMonitor = nil
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

/// Keeps floating preview panels stacked in a column on each screen, newest at the bottom.
/// Each panel has its own auto-dismiss timer, paused while the pointer is over it.
@MainActor
final class FloatingPanelStack {
    enum Anchor { case bottomTrailing, bottomCenter }

    struct Style {
        var anchor: Anchor
        /// Distance from the bottom (and trailing edge for `.bottomTrailing`) of the visible frame.
        var margin: CGFloat
        var spacing: CGFloat = 10
        var maxCount = 3
        var dismissDelay: Duration
        var hoverDismissDelay: Duration
        /// Where a new panel starts before sliding into place.
        var entryOffset: CGSize
        var fadeInDuration: TimeInterval
        var fadeOutDuration: TimeInterval
    }

    private final class Entry {
        let id: UUID
        let panel: NSPanel
        let displayID: CGDirectDisplayID?
        var dismissTask: Task<Void, Never>?
        var isHovered = false

        init(id: UUID, panel: NSPanel, displayID: CGDirectDisplayID?) {
            self.id = id
            self.panel = panel
            self.displayID = displayID
        }
    }

    private let style: Style
    /// Oldest first.
    private var entries: [Entry] = []

    init(style: Style) {
        self.style = style
    }

    func push(_ panel: NSPanel, id: UUID, on screen: NSScreen) {
        let entry = Entry(id: id, panel: panel, displayID: screen.displayID)
        entries.append(entry)
        let sameScreen = entries.filter { $0.displayID == entry.displayID }
        for old in sameScreen.dropLast(style.maxCount) {
            close(old.id, animated: true, relayout: false)
        }

        let targets = layout(for: entry.displayID)
        let finalFrame = targets[id] ?? panel.frame
        panel.setFrame(finalFrame.offsetBy(dx: style.entryOffset.width, dy: style.entryOffset.height), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = style.fadeInDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(finalFrame, display: true)
            panel.animator().alphaValue = 1
            for other in entries where other !== entry {
                if let frame = targets[other.id] { other.panel.animator().setFrame(frame, display: true) }
            }
        }
        scheduleDismiss(entry, after: style.dismissDelay)
    }

    func setHovered(_ id: UUID, _ hovering: Bool) {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        entry.isHovered = hovering
        if hovering {
            entry.dismissTask?.cancel()
        } else {
            scheduleDismiss(entry, after: style.hoverDismissDelay)
        }
    }

    func close(_ id: UUID, animated: Bool = true) {
        close(id, animated: animated, relayout: true)
    }

    private func close(_ id: UUID, animated: Bool, relayout: Bool) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries.remove(at: index)
        entry.dismissTask?.cancel()
        let panel = entry.panel
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = style.fadeOutDuration
                panel.animator().alphaValue = 0
            } completionHandler: {
                MainActor.assumeIsolated { panel.orderOut(nil) }
            }
        } else {
            panel.orderOut(nil)
        }
        guard relayout else { return }
        let targets = layout(for: entry.displayID)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for other in entries {
                if let frame = targets[other.id] { other.panel.animator().setFrame(frame, display: true) }
            }
        }
    }

    /// Target frames for the panels on one screen: newest at the bottom, older ones above.
    private func layout(for displayID: CGDirectDisplayID?) -> [UUID: NSRect] {
        let screen = NSScreen.screens.first { $0.displayID == displayID } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        var y = visible.minY + style.margin
        var frames: [UUID: NSRect] = [:]
        for entry in entries.reversed() where entry.displayID == displayID {
            let size = entry.panel.frame.size
            let x = switch style.anchor {
            case .bottomTrailing: visible.maxX - size.width - style.margin
            case .bottomCenter: visible.midX - size.width / 2
            }
            frames[entry.id] = NSRect(x: x, y: y, width: size.width, height: size.height)
            y += size.height + style.spacing
        }
        return frames
    }

    private func scheduleDismiss(_ entry: Entry, after delay: Duration) {
        entry.dismissTask?.cancel()
        let id = entry.id
        entry.dismissTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self,
                  let entry = self.entries.first(where: { $0.id == id }), !entry.isHovered else { return }
            self.close(id)
        }
    }
}

/// Brief HUD at the bottom of the captured screen after a Quick Screenshot. Several stack up.
@MainActor
final class QuickCaptureToastController {
    private let stack = FloatingPanelStack(style: .init(
        anchor: .bottomCenter, margin: 40, dismissDelay: .seconds(2.4), hoverDismissDelay: .seconds(1.2),
        entryOffset: CGSize(width: 0, height: -12), fadeInDuration: 0.22, fadeOutDuration: 0.25))

    func show(image: CGImage, title: String, subtitle: String, on displayID: CGDirectDisplayID,
              onClick: @escaping () -> Void) {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let id = UUID()
        let view = QuickCaptureToastView(
            image: NSImage(cgImage: image, size: .zero),
            title: title,
            subtitle: subtitle,
            onClick: { [weak self] in
                self?.stack.close(id)
                onClick()
            },
            onHoverChange: { [weak self] hovering in self?.stack.setHovered(id, hovering) })
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)

        let screen = NSScreen.screens.first { $0.displayID == displayID } ?? NSScreen.main ?? NSScreen.screens[0]
        stack.push(panel, id: id, on: screen)
    }
}

/// Non-activating floating panel in the bottom-right corner, like the system screenshot thumbnail.
/// Several stack up, newest at the bottom.
@MainActor
final class PostCapturePanelController {
    // The view has a transparent `outerMargin` around the card: the visible card sits 20 pt from the screen
    // edges, and stacked cards are 10 pt apart.
    private let stack = FloatingPanelStack(style: .init(
        anchor: .bottomTrailing, margin: 20 - PostCaptureView.outerMargin,
        spacing: 10 - 2 * PostCaptureView.outerMargin, dismissDelay: .seconds(8), hoverDismissDelay: .seconds(8),
        entryOffset: CGSize(width: 380, height: 0), fadeInDuration: 0.3, fadeOutDuration: 0.2))

    func show(item: CaptureItem, openHistory: @escaping () -> Void, edit: (() -> Void)?, trim: (() -> Void)?,
              pin: (() -> Void)?, open: @escaping () -> Void) {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The card draws its own rounded shadow; the window shadow would be rectangular.
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let id = UUID()
        let view = PostCaptureView(
            item: item,
            openHistory: { [weak self] in
                self?.stack.close(id)
                openHistory()
            },
            edit: edit.map { edit in { [weak self] in
                self?.stack.close(id)
                edit()
            } },
            trim: trim.map { trim in { [weak self] in
                self?.stack.close(id)
                trim()
            } },
            pin: pin.map { pin in { [weak self] in
                self?.stack.close(id)
                pin()
            } },
            open: { [weak self] in
                self?.stack.close(id)
                open()
            },
            close: { [weak self] in self?.stack.close(id) },
            onHoverChange: { [weak self] hovering in self?.stack.setHovered(id, hovering) })
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        stack.push(panel, id: id, on: screen)
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
