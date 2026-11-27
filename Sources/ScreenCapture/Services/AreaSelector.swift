import AppKit
import Carbon.HIToolbox

enum AreaSelectionMode {
    /// Capture as soon as the mouse is released (like ⌘⇧4).
    case screenshot
    /// Let the user adjust the frame, then confirm with "Start Recording".
    case recording
}

/// Full-screen overlay that lets the user pick a capture rectangle on any display.
@MainActor
final class AreaSelector {
    private var panels: [NSPanel] = []
    private var views: [SelectionView] = []
    private var continuation: CheckedContinuation<AreaSelection?, Never>?
    private var escapeHotKey: EventHotKeyRef?
    private static var escapeHandlerInstalled = false
    private static weak var activeSelector: AreaSelector?

    private func registerEscape() {
        if !Self.escapeHandlerInstalled {
            Self.escapeHandlerInstalled = true
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                               nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                // Other hotkeys are handled by HotKeyManager.
                guard status == noErr, hotKeyID.signature == OSType(0x5343_4553) else { return OSStatus(eventNotHandledErr) }
                MainActor.assumeIsolated { AreaSelector.activeSelector?.finish(nil) }
                return noErr
            }, 1, &spec, nil, nil)
        }
        Self.activeSelector = self
        RegisterEventHotKey(UInt32(kVK_Escape), 0, EventHotKeyID(signature: OSType(0x5343_4553), id: 1), // 'SCES'
                            GetApplicationEventTarget(), 0, &escapeHotKey)
    }

    private func unregisterEscape() {
        if let escapeHotKey { UnregisterEventHotKey(escapeHotKey) }
        escapeHotKey = nil
    }

    func selectArea(mode: AreaSelectionMode) async -> AreaSelection? {
        guard continuation == nil else { return nil }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            present(mode: mode)
        }
    }

    private func present(mode: AreaSelectionMode) {
        for screen in NSScreen.screens {
            guard let displayID = screen.displayID else { continue }
            // A non-activating panel can become key (to receive Esc/Return) even while another app is active.
            let panel = OverlayPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
            // Note: setting isFloatingPanel resets the level, so it must come before `level`.
            // Taking key focus makes the frontmost app resign key, which closes its open popups (e.g. a Chrome dropdown).
            // Screenshot selection therefore stays non-key; recording needs key focus for its toolbar and shortcuts.
            panel.allowsKey = mode == .recording
            panel.isFloatingPanel = true
            panel.level = .screenSaver
            panel.becomesKeyOnlyIfNeeded = false
            panel.hidesOnDeactivate = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.sharingType = .none
            panel.acceptsMouseMovedEvents = true
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

            let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size), mode: mode,
                                     backingScale: screen.backingScaleFactor)
            view.onBegin = { [weak self, weak view] in
                self?.views.forEach { if $0 !== view { $0.clearSelection() } }
            }
            view.onComplete = { [weak self] rect in
                self?.finish(rect.map { AreaSelection(displayID: displayID, rect: $0) })
            }
            panel.contentView = view
            panel.setFrame(screen.frame, display: true)
            panel.orderFrontRegardless()
            panels.append(panel)
            views.append(view)
        }

        let mouse = NSEvent.mouseLocation
        let target = panels.first { NSMouseInRect(mouse, $0.frame, false) } ?? panels.first
        if mode == .recording {
            target?.makeKeyAndOrderFront(nil)
            if let view = target?.contentView { target?.makeFirstResponder(view) }
        } else {
            // Without key focus Esc would go to the other app, so claim it as a Carbon hotkey (no permission needed)
            // while the overlay is up. Right-click also cancels.
            registerEscape()
        }
        NSCursor.crosshair.set()
    }

    private func finish(_ selection: AreaSelection?) {
        guard continuation != nil else { return }
        unregisterEscape()
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        views.removeAll()
        NSCursor.arrow.set()
        continuation?.resume(returning: selection)
        continuation = nil
    }
}

private final class OverlayPanel: NSPanel {
    var allowsKey = true
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

private final class SelectionView: NSView {
    private enum Handle: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    }

    private enum Interaction {
        case none
        case creating(start: CGPoint)
        case moving(grab: CGPoint, original: CGRect)
        case resizing(handle: Handle, original: CGRect)
    }

    var onBegin: (() -> Void)?
    var onComplete: ((CGRect?) -> Void)?

    private let mode: AreaSelectionMode
    private let backingScale: CGFloat
    private var selection: CGRect?
    private var interaction: Interaction = .none
    private var mouse: CGPoint?
    private var toolbar: NSView?

    init(frame: CGRect, mode: AreaSelectionMode, backingScale: CGFloat) {
        self.mode = mode
        self.backingScale = backingScale
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    func clearSelection() {
        selection = nil
        removeToolbar()
        needsDisplay = true
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onComplete?(nil)                                   // Esc
        case 36, 76: if let selection { complete(selection) }      // Return / Enter
        default: super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onComplete?(nil)
    }

    // MARK: Mouse

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        mouse = point
        cursor(at: point).set()
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        mouse = nil
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        if mode == .screenshot { onComplete?(nil) } else { super.rightMouseDown(with: event) }
    }

    override func mouseDown(with event: NSEvent) {
        if mode == .recording { window?.makeKey() }
        let point = convert(event.locationInWindow, from: nil)

        if mode == .recording, let selection {
            if let handle = handle(at: point, in: selection) {
                interaction = .resizing(handle: handle, original: selection)
                removeToolbar()
                return
            }
            if selection.contains(point) {
                interaction = .moving(grab: point, original: selection)
                removeToolbar()
                NSCursor.closedHand.set()
                return
            }
        }

        onBegin?()
        removeToolbar()
        selection = nil
        interaction = .creating(start: point)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil).clamped(to: bounds)
        mouse = point

        switch interaction {
        case .none:
            return
        case .creating(let start):
            selection = CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
                               width: abs(point.x - start.x), height: abs(point.y - start.y))
        case .moving(let grab, let original):
            var origin = CGPoint(x: original.minX + point.x - grab.x, y: original.minY + point.y - grab.y)
            origin.x = min(max(origin.x, bounds.minX), bounds.maxX - original.width)
            origin.y = min(max(origin.y, bounds.minY), bounds.maxY - original.height)
            selection = CGRect(origin: origin, size: original.size)
        case .resizing(let handle, let original):
            selection = resize(original, handle: handle, to: point)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let finished = interaction
        interaction = .none

        switch finished {
        case .none:
            return
        case .creating:
            // A plain click (no meaningful drag) selects the whole display.
            if let rect = selection, rect.width >= 8, rect.height >= 8 {
                selection = rect.integral
            } else {
                selection = bounds
            }
            if mode == .screenshot, let selection {
                complete(selection)
                return
            }
        case .moving, .resizing:
            selection = selection?.integral
        }
        showToolbar()
        needsDisplay = true
    }

    private func complete(_ rect: CGRect) {
        removeToolbar()
        onComplete?(rect.integral.intersection(bounds))
    }

    // MARK: Geometry

    private func handlePoint(_ handle: Handle, in rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .top: CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .right: CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .left: CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    private func handle(at point: CGPoint, in rect: CGRect) -> Handle? {
        Handle.allCases.first { handle in
            let p = handlePoint(handle, in: rect)
            return abs(p.x - point.x) <= 8 && abs(p.y - point.y) <= 8
        }
    }

    private func resize(_ rect: CGRect, handle: Handle, to point: CGPoint) -> CGRect {
        var minX = rect.minX, minY = rect.minY, maxX = rect.maxX, maxY = rect.maxY
        switch handle {
        case .topLeft: minX = point.x; minY = point.y
        case .top: minY = point.y
        case .topRight: maxX = point.x; minY = point.y
        case .right: maxX = point.x
        case .bottomRight: maxX = point.x; maxY = point.y
        case .bottom: maxY = point.y
        case .bottomLeft: minX = point.x; maxY = point.y
        case .left: minX = point.x
        }
        let result = CGRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))
        return CGRect(x: result.minX, y: result.minY, width: max(result.width, 16), height: max(result.height, 16))
    }

    private func cursor(at point: CGPoint) -> NSCursor {
        guard mode == .recording, let selection else { return .crosshair }
        if let handle = handle(at: point, in: selection) {
            switch handle {
            case .topLeft: return .frameResize(position: .topLeft, directions: .all)
            case .top: return .frameResize(position: .top, directions: .all)
            case .topRight: return .frameResize(position: .topRight, directions: .all)
            case .right: return .frameResize(position: .right, directions: .all)
            case .bottomRight: return .frameResize(position: .bottomRight, directions: .all)
            case .bottom: return .frameResize(position: .bottom, directions: .all)
            case .bottomLeft: return .frameResize(position: .bottomLeft, directions: .all)
            case .left: return .frameResize(position: .left, directions: .all)
            }
        }
        return selection.contains(point) ? .openHand : .crosshair
    }

    // MARK: Confirm toolbar (recording mode)

    private func showToolbar() {
        guard mode == .recording, let selection else { return }
        removeToolbar()

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelPressed))
        cancel.controlSize = .large
        cancel.keyEquivalent = "\u{1b}"
        let record = NSButton(title: "Start Recording", image: NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: nil)!,
                              target: self, action: #selector(confirmPressed))
        record.controlSize = .large
        record.bezelColor = .systemRed
        record.keyEquivalent = "\r"
        record.imagePosition = .imageLeading

        let size = NSTextField(labelWithString: sizeLabel(for: selection))
        size.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        size.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [size, cancel, record])
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 8)

        let container = NSVisualEffectView()
        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 14
        container.layer?.masksToBounds = true
        container.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        let fitting = stack.fittingSize
        var origin = CGPoint(x: selection.midX - fitting.width / 2, y: selection.maxY + 12)
        if origin.y + fitting.height > bounds.maxY - 8 { origin.y = selection.maxY - fitting.height - 12 }
        origin.x = min(max(origin.x, bounds.minX + 8), bounds.maxX - fitting.width - 8)
        container.frame = CGRect(origin: origin, size: fitting)
        addSubview(container)
        toolbar = container
    }

    private func removeToolbar() {
        toolbar?.removeFromSuperview()
        toolbar = nil
    }

    @objc private func cancelPressed() { onComplete?(nil) }
    @objc private func confirmPressed() { if let selection { complete(selection) } }

    private func sizeLabel(for rect: CGRect) -> String {
        "\(Int((rect.width * backingScale).rounded())) × \(Int((rect.height * backingScale).rounded()))"
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.4).setFill()
        bounds.fill()

        guard let selection else {
            if let mouse { drawCrosshair(at: mouse) }
            drawPill(mode == .recording
                     ? "Drag to select the recording area  ·  Click for the whole screen  ·  Esc to cancel"
                     : "Drag to capture an area  ·  Click for the whole screen  ·  Esc to cancel",
                     center: CGPoint(x: bounds.midX, y: bounds.minY + 80))
            return
        }

        // Keep a tiny alpha so the window server still delivers mouse events inside the hole.
        NSColor(white: 1, alpha: 0.01).setFill()
        selection.fill(using: .copy)

        let border = NSBezierPath(rect: selection.insetBy(dx: -1, dy: -1))
        border.lineWidth = 2
        NSColor.systemRed.setStroke()
        border.stroke()

        var isCreating = false
        if case .creating = interaction { isCreating = true }
        if mode == .recording, !isCreating {
            for handle in Handle.allCases {
                let p = handlePoint(handle, in: selection)
                let knob = NSBezierPath(ovalIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10))
                NSColor.white.setFill()
                knob.fill()
                knob.lineWidth = 1.5
                NSColor.systemRed.setStroke()
                knob.stroke()
            }
        }

        let labelY = selection.minY - 18 > bounds.minY ? selection.minY - 18 : selection.minY + 18
        drawPill(sizeLabel(for: selection), center: CGPoint(x: selection.midX, y: labelY))
    }

    private func drawCrosshair(at point: CGPoint) {
        let path = NSBezierPath()
        path.move(to: CGPoint(x: bounds.minX, y: point.y))
        path.line(to: CGPoint(x: bounds.maxX, y: point.y))
        path.move(to: CGPoint(x: point.x, y: bounds.minY))
        path.line(to: CGPoint(x: point.x, y: bounds.maxY))
        path.lineWidth = 1
        NSColor.systemRed.withAlphaComponent(0.7).setStroke()
        path.stroke()

        let label = "\(Int(point.x * backingScale)), \(Int(point.y * backingScale))"
        drawPill(label, center: CGPoint(x: point.x + 50, y: point.y + 22))
    }

    private func drawPill(_ text: String, center: CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        let pill = CGRect(x: center.x - size.width / 2 - 9, y: center.y - size.height / 2 - 4,
                          width: size.width + 18, height: size.height + 8)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        string.draw(at: CGPoint(x: pill.minX + 9, y: pill.minY + 4))
    }
}

private extension CGPoint {
    func clamped(to rect: CGRect) -> CGPoint {
        CGPoint(x: min(max(x, rect.minX), rect.maxX), y: min(max(y, rect.minY), rect.maxY))
    }
}

/// Dashed frame drawn around an area while it is being recorded. Invisible to screen capture.
@MainActor
final class RecordingFrameOverlay {
    private var window: NSWindow?

    func show(for area: AreaSelection) {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == area.displayID }) else { return }
        // Skip the frame when recording the whole display: it would sit off-screen anyway.
        guard area.rect.size != screen.frame.size else { return }
        let inset: CGFloat = 4
        let rect = CGRect(
            x: screen.frame.minX + area.rect.minX - inset,
            y: screen.frame.maxY - area.rect.maxY - inset,
            width: area.rect.width + inset * 2,
            height: area.rect.height + inset * 2)

        let window = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.sharingType = .none
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = FrameView(frame: CGRect(origin: .zero, size: rect.size))
        window.orderFrontRegardless()
        self.window = window
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
    }

    private final class FrameView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(rect: bounds.insetBy(dx: 1.5, dy: 1.5))
            path.lineWidth = 2
            path.setLineDash([6, 4], count: 2, phase: 0)
            NSColor.systemRed.withAlphaComponent(0.9).setStroke()
            path.stroke()
        }
    }
}
