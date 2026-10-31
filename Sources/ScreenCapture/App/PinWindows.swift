import AppKit

/// Floating, always-on-top screenshots ("pins").
@MainActor
final class PinManager {
    private var pins: [PinController] = []
    /// Saves an image to the screenshots folder and returns its URL.
    private let saveImage: (CGImage) async throws -> URL
    private let openEditor: (URL) -> Void
    private let showError: (String) -> Void

    init(saveImage: @escaping (CGImage) async throws -> URL, openEditor: @escaping (URL) -> Void,
         showError: @escaping (String) -> Void) {
        self.saveImage = saveImage
        self.openEditor = openEditor
        self.showError = showError
    }

    var hasPins: Bool { !pins.isEmpty }

    /// `frame` (global AppKit coordinates) places the pin exactly; otherwise it's centred on the main screen.
    func pin(image: CGImage, sourceURL: URL?, at frame: NSRect?) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let target = frame ?? Self.defaultFrame(for: image, on: screen, index: pins.count)
        let controller = PinController(image: image, sourceURL: sourceURL, frame: target, manager: self)
        pins.append(controller)
        controller.show()
    }

    func closeAll() {
        pins.forEach { $0.close() }
    }

    fileprivate func didClose(_ controller: PinController) {
        pins.removeAll { $0 === controller }
    }

    fileprivate func save(_ image: CGImage) async throws -> URL { try await saveImage(image) }
    fileprivate func edit(_ url: URL) { openEditor(url) }
    fileprivate func report(_ message: String) { showError(message) }

    /// Image at screen resolution, shrunk to fit 60% of the visible frame, cascaded by `index`.
    static func defaultFrame(for image: CGImage, on screen: NSScreen, index: Int) -> NSRect {
        let visible = screen.visibleFrame
        let scale = screen.backingScaleFactor
        var size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let fit = min(1, visible.width * 0.6 / size.width, visible.height * 0.6 / size.height)
        size = CGSize(width: size.width * fit, height: size.height * fit)
        size = PinController.clamp(size, aspect: size.width / max(size.height, 1), on: screen)
        let offset = CGFloat(index % 8) * 24
        return NSRect(x: visible.midX - size.width / 2 + offset, y: visible.midY - size.height / 2 - offset,
                      width: size.width, height: size.height)
    }
}

extension AreaSelection {
    /// The selection in global AppKit coordinates (bottom-left origin).
    @MainActor
    var globalFrame: NSRect? {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else { return nil }
        return NSRect(x: screen.frame.minX + rect.minX, y: screen.frame.maxY - rect.maxY,
                      width: rect.width, height: rect.height)
    }
}

/// Borderless panel that can take key focus (for Esc) without activating the app.
private final class PinPanel: NSPanel {
    var onZoom: ((CGFloat) -> Void)?
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .scrollWheel:
            let delta = event.scrollingDeltaY
            guard delta != 0 else { break }
            let step = event.hasPreciseScrollingDeltas ? delta * 0.01 : (delta > 0 ? 0.1 : -0.1)
            onZoom?(1 + max(-0.5, min(0.5, step)))
            return
        case .magnify:
            onZoom?(1 + event.magnification)
            return
        case .keyDown where event.keyCode == 53: // Esc
            onEscape?()
            return
        default:
            break
        }
        super.sendEvent(event)
    }
}

@MainActor
final class PinController: NSObject, NSWindowDelegate {
    private let image: CGImage
    private var sourceURL: URL?
    private let panel: PinPanel
    private weak var manager: PinManager?
    private var aspect: CGFloat { CGFloat(image.width) / CGFloat(max(image.height, 1)) }

    fileprivate init(image: CGImage, sourceURL: URL?, frame: NSRect, manager: PinManager) {
        self.image = image
        self.sourceURL = sourceURL
        self.manager = manager
        panel = PinPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        super.init()

        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self

        let content = PinContentView(image: image)
        content.onClose = { [weak self] in self?.close() }
        content.menuProvider = { [weak self] in self?.makeMenu() }
        content.onResize = { [weak self] frame in self?.setFrame(frame) }
        content.aspect = aspect
        panel.contentView = content
        panel.onZoom = { [weak self] factor in self?.zoom(by: factor) }
        panel.onEscape = { [weak self] in self?.close() }
    }

    func show() {
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
    }

    func close() {
        panel.close()
    }

    func windowWillClose(_ notification: Notification) {
        manager?.didClose(self)
    }

    // MARK: Geometry

    /// Keeps the aspect ratio, at least 80 pt on the short side and no larger than the screen.
    static func clamp(_ size: CGSize, aspect: CGFloat, on screen: NSScreen?) -> CGSize {
        let visible = (screen ?? NSScreen.main)?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        var width = size.width
        let minWidth = aspect >= 1 ? 80 * aspect : 80
        width = max(width, minWidth)
        width = min(width, visible.width, visible.height * aspect)
        return CGSize(width: width.rounded(), height: (width / aspect).rounded())
    }

    private func zoom(by factor: CGFloat) {
        let frame = panel.frame
        let size = Self.clamp(CGSize(width: frame.width * factor, height: frame.height * factor),
                              aspect: aspect, on: panel.screen)
        setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                        width: size.width, height: size.height))
    }

    private func setFrame(_ frame: NSRect) {
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    // MARK: Menu

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Copy", #selector(copyImage)))
        menu.addItem(item(sourceURL == nil ? "Save to Screenshots" : "Save a Copy to Screenshots", #selector(saveImage)))
        menu.addItem(item("Edit…", #selector(editImage)))
        let opacity = NSMenuItem(title: "Opacity", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for percent in [100, 80, 60, 40] {
            let entry = item("\(percent)%", #selector(setOpacity(_:)))
            entry.tag = percent
            entry.state = Int((panel.alphaValue * 100).rounded()) == percent ? .on : .off
            submenu.addItem(entry)
        }
        opacity.submenu = submenu
        menu.addItem(opacity)
        menu.addItem(.separator())
        menu.addItem(item("Close", #selector(closePin)))
        menu.addItem(item("Close All Pins", #selector(closeAllPins)))
        return menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func copyImage() { ScreenshotService.copyToPasteboard(image) }
    @objc private func setOpacity(_ sender: NSMenuItem) { panel.alphaValue = CGFloat(sender.tag) / 100 }
    @objc private func closePin() { close() }
    @objc private func closeAllPins() { manager?.closeAll() }

    @objc private func saveImage() {
        Task {
            do {
                let url = try await manager?.save(image)
                if sourceURL == nil { sourceURL = url }
            } catch {
                manager?.report("Couldn't save the pinned image: \(error.localizedDescription)")
            }
        }
    }

    @objc private func editImage() {
        Task {
            do {
                if sourceURL == nil { sourceURL = try await manager?.save(image) }
                if let sourceURL { manager?.edit(sourceURL) }
            } catch {
                manager?.report("Couldn't save the pinned image: \(error.localizedDescription)")
            }
        }
    }
}

/// Shows the image; drag to move, drag an edge to resize (aspect kept), ✕ on hover, right-click menu.
private final class PinContentView: NSView {
    private enum Edge { case left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight }

    var onClose: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?
    var onResize: ((NSRect) -> Void)?
    var aspect: CGFloat = 1

    private let closeButton = NSButton()
    private var resizing: (edge: Edge, startFrame: NSRect, startMouse: CGPoint)?
    private static let edgeWidth: CGFloat = 8

    init(image: CGImage) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contents = image
        layer?.contentsGravity = .resize
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.black.withAlphaComponent(0.25).cgColor

        closeButton.bezelStyle = .circular
        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .semibold)
                .applying(.init(paletteColors: [.white, NSColor.black.withAlphaComponent(0.6)])))
        closeButton.target = self
        closeButton.action = #selector(closePressed)
        closeButton.isHidden = true
        closeButton.toolTip = "Close (Esc)"
        addSubview(closeButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        closeButton.frame = NSRect(x: 6, y: bounds.height - 26, width: 20, height: 20)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { closeButton.isHidden = false }
    override func mouseExited(with event: NSEvent) { closeButton.isHidden = true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    @objc private func closePressed() { onClose?() }

    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() }

    override func resetCursorRects() {
        let e = Self.edgeWidth
        let b = bounds
        addCursorRect(NSRect(x: 0, y: e, width: e, height: b.height - 2 * e), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: b.width - e, y: e, width: e, height: b.height - 2 * e), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: e, y: 0, width: b.width - 2 * e, height: e), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: e, y: b.height - e, width: b.width - 2 * e, height: e), cursor: .resizeUpDown)
        for corner in [NSRect(x: 0, y: 0, width: e, height: e), NSRect(x: b.width - e, y: 0, width: e, height: e),
                       NSRect(x: 0, y: b.height - e, width: e, height: e),
                       NSRect(x: b.width - e, y: b.height - e, width: e, height: e)] {
            addCursorRect(corner, cursor: .crosshair)
        }
    }

    private func edge(at point: CGPoint) -> Edge? {
        let e = Self.edgeWidth
        let left = point.x < e, right = point.x > bounds.width - e
        let bottom = point.y < e, top = point.y > bounds.height - e
        switch (left, right, top, bottom) {
        case (true, _, true, _): return .topLeft
        case (_, true, true, _): return .topRight
        case (true, _, _, true): return .bottomLeft
        case (_, true, _, true): return .bottomRight
        case (true, _, _, _): return .left
        case (_, true, _, _): return .right
        case (_, _, true, _): return .top
        case (_, _, _, true): return .bottom
        default: return nil
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        if let edge = edge(at: convert(event.locationInWindow, from: nil)) {
            resizing = (edge, window.frame, NSEvent.mouseLocation)
        } else {
            window.performDrag(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let (edge, start, mouse) = resizing else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - mouse.x, dy = now.y - mouse.y
        let widthFromX: CGFloat? = switch edge {
        case .right, .topRight, .bottomRight: start.width + dx
        case .left, .topLeft, .bottomLeft: start.width - dx
        default: nil
        }
        let widthFromY: CGFloat? = switch edge {
        case .top, .topLeft, .topRight: (start.height + dy) * aspect
        case .bottom, .bottomLeft, .bottomRight: (start.height - dy) * aspect
        default: nil
        }
        let proposed = [widthFromX, widthFromY].compactMap { $0 }.max() ?? start.width
        let size = PinController.clamp(CGSize(width: proposed, height: proposed / aspect), aspect: aspect,
                                       on: window?.screen)
        let x: CGFloat = switch edge {
        case .left, .topLeft, .bottomLeft: start.maxX - size.width
        case .top, .bottom: start.midX - size.width / 2
        default: start.minX
        }
        let y: CGFloat = switch edge {
        case .bottom, .bottomLeft, .bottomRight: start.maxY - size.height
        case .left, .right: start.midY - size.height / 2
        default: start.minY
        }
        onResize?(NSRect(x: x, y: y, width: size.width, height: size.height))
    }

    override func mouseUp(with event: NSEvent) {
        resizing = nil
        window?.invalidateCursorRects(for: self)
    }
}
