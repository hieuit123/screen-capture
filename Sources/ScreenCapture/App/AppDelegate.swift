import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, AppUI {
    let model = AppModel()

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var historyController: HistoryWindowController?
    private var settingsController: SettingsWindowController?
    private var editorControllers: [EditorWindowController] = []
    private let postCapture = PostCapturePanelController()
    private let quickToast = QuickCaptureToastController()
    private var statusTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? StorageManager.ensureFolders()
        model.ui = self
        NSApp.mainMenu = MainMenu.make()
        setupStatusItem()
        setupPopover()
        registerHotKeys()
        model.settings.onShortcutsChanged = { [weak self] in self?.registerHotKeys() }
        model.history.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { togglePopover() }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.phase.isRecording else { return .terminateNow }
        Task {
            await model.stopRecording()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    // MARK: Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageLeading
        updateStatusItem()
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
            || NSApp.currentEvent?.modifierFlags.contains(.control) == true
        if isRightClick {
            showContextMenu()
        } else if model.phase.isRecording {
            Task { await model.stopRecording() }
        } else {
            togglePopover()
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        switch model.phase {
        case .recording(let since):
            let config = NSImage.SymbolConfiguration(paletteColors: [.white, .systemRed])
            let image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: "Stop recording")?
                .withSymbolConfiguration(config)
            image?.isTemplate = false
            button.image = image
            button.attributedTitle = NSAttributedString(
                string: " " + Date.now.timeIntervalSince(since).durationString,
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)])
            button.toolTip = "Click to stop recording (⌃⌥⌘R)"
        case .finishing:
            button.image = NSImage(systemSymbolName: "hourglass", accessibilityDescription: "Saving")
            button.title = ""
            button.toolTip = "Saving recording…"
        default:
            button.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "ScreenCapture")
            button.image?.isTemplate = true
            button.title = ""
            button.toolTip = "ScreenCapture"
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let recordTitle = model.phase.isRecording ? "Stop Recording" : "Start Recording"
        menu.addItem(item(recordTitle, shortcut: .toggleRecording, action: #selector(menuToggleRecording)))
        menu.addItem(item("Take Screenshot", shortcut: .screenshot, action: #selector(menuScreenshot)))
        menu.addItem(item("Quick Screenshot", shortcut: .quickScreenshot, action: #selector(menuQuickScreenshot)))
        menu.addItem(item("Capture Area", shortcut: .areaScreenshot, action: #selector(menuCaptureArea)))
        menu.addItem(.separator())
        menu.addItem(item("Recording History…", action: #selector(menuRecordingHistory)))
        menu.addItem(item("Screenshot History…", action: #selector(menuScreenshotHistory)))
        menu.addItem(item("Open Capture Folder", action: #selector(menuOpenFolder)))
        menu.addItem(.separator())
        let postCaptureItem = item("Show Preview After Capture", action: #selector(menuTogglePostCapture))
        postCaptureItem.state = model.settings.showPostCapturePanel ? .on : .off
        menu.addItem(postCaptureItem)
        menu.addItem(item("Settings…", action: #selector(menuSettings)))
        menu.addItem(.separator())
        menu.addItem(item("Quit ScreenCapture", action: #selector(menuQuit)))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func item(_ title: String, shortcut action: ShortcutAction? = nil, action selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        // Show the global shortcut next to the item (single-character keys only).
        if let action, let shortcut = model.settings.shortcuts[action], shortcut.key.count == 1 {
            item.keyEquivalent = shortcut.key.lowercased()
            item.keyEquivalentModifierMask = shortcut.flags
        }
        item.target = self
        return item
    }

    @objc private func menuToggleRecording() { model.toggleRecording() }
    @objc private func menuScreenshot() { model.takeScreenshot() }
    @objc private func menuCaptureArea() { model.captureArea() }
    @objc private func menuQuickScreenshot() { model.quickScreenshot() }
    @objc private func menuSettings() { openSettings() }
    @objc func showSettings(_ sender: Any?) { openSettings() }
    @objc private func menuRecordingHistory() { openHistory(.recording, select: nil) }
    @objc private func menuScreenshotHistory() { openHistory(.screenshot, select: nil) }
    @objc private func menuOpenFolder() { openCaptureFolder() }
    @objc private func menuTogglePostCapture() { model.settings.showPostCapturePanel.toggle() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    // MARK: Popover

    private func setupPopover() {
        let view = MenuView(
            model: model,
            openHistory: { [weak self] kind in self?.openHistory(kind, select: nil) },
            openItem: { [weak self] item in self?.open(item) },
            openSettings: { [weak self] in self?.openSettings() },
            openFolder: { [weak self] in self?.openCaptureFolder() },
            quit: { NSApp.terminate(nil) })
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = true
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            Task { await model.refreshContent() }
            NSApp.forceActivate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func openCaptureFolder() {
        dismissPopover()
        try? StorageManager.ensureFolders()
        NSWorkspace.shared.open(StorageManager.rootURL)
    }

    private func registerHotKeys() {
        HotKeyManager.shared.configure(model.settings.shortcuts) { [weak self] action in
            guard let model = self?.model else { return }
            switch action {
            case .screenshot: model.takeScreenshot()
            case .quickScreenshot: model.quickScreenshot()
            case .areaScreenshot: model.captureArea()
            case .toggleRecording: model.toggleRecording()
            }
        }
    }

    private func open(_ item: CaptureItem) {
        if item.kind == .screenshot {
            openEditor(url: item.url, image: nil, beautify: false)
        } else {
            dismissPopover()
            NSWorkspace.shared.open(item.url)
        }
    }

    private func openSettings() {
        dismissPopover()
        if settingsController == nil {
            let controller = SettingsWindowController(settings: model.settings)
            controller.onClose = { [weak self] in self?.updateActivationPolicySoon() }
            settingsController = controller
        }
        settingsController?.present()
    }

    /// Shows a Dock icon only while one of our windows is open.
    private func updateActivationPolicySoon() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let windows = [self.historyController?.window, self.settingsController?.window]
                + self.editorControllers.map(\.window)
            let anyVisible = windows.contains { $0?.isVisible == true }
            NSApp.setActivationPolicy(anyVisible ? .regular : .accessory)
        }
    }

    // MARK: AppUI

    func dismissPopover() {
        if popover.isShown { popover.performClose(nil) }
    }

    func phaseDidChange() {
        updateStatusItem()
        statusTimer?.invalidate()
        statusTimer = nil
        if model.phase.isRecording {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateStatusItem() }
            }
            RunLoop.main.add(timer, forMode: .common)
            statusTimer = timer
        }
    }

    func showPostCapture(_ item: CaptureItem) {
        let edit: (() -> Void)? = item.kind == .screenshot ? { [weak self] in self?.openEditor(url: item.url, image: nil, beautify: false) } : nil
        postCapture.show(item: item, openHistory: { [weak self] in
            self?.openHistory(item.kind, select: item.url)
        }, edit: edit)
    }

    var isPopoverShown: Bool { popover.isShown }

    func showQuickCaptureToast(url: URL, image: CGImage, thumbnail: CGImage, on displayID: CGDirectDisplayID) {
        let beautify = model.settings.autoApplyBeautify
        quickToast.show(image: thumbnail, title: "Copied to clipboard",
                        subtitle: "Saved to ScreenCapture/images · Click to edit", on: displayID) { [weak self] in
            self?.openEditor(url: url, image: image, beautify: beautify)
        }
    }

    func openEditor(url: URL, image: CGImage?, beautify: Bool) {
        dismissPopover()
        if let existing = editorControllers.first(where: { $0.editorDocument.fileURL == url }) {
            existing.present()
            return
        }
        var style = model.settings.beautifyStyle
        style.enabled = beautify
        let document = image.map { EditorDocument(image: $0, fileURL: url, beautify: style) }
            ?? EditorDocument(url: url, beautify: style)
        guard let document else {
            showError("Couldn't open \(url.lastPathComponent) for editing.")
            return
        }
        document.onSaved = { [weak self] _ in self?.model.history.reload() }
        document.onBeautifyChanged = { [weak self] newStyle in self?.model.settings.beautifyStyle = newStyle }
        let controller = EditorWindowController(document: document, settings: model.settings)
        controller.onFinish = { [weak self] action, image, displayID in
            let title = action == .copied ? "Copied to clipboard" : "Saved"
            let subtitle = action == .copied ? "Also saved to ScreenCapture/images · Click to edit" : "ScreenCapture/images · Click to edit"
            self?.quickToast.show(image: image, title: title, subtitle: subtitle, on: displayID ?? CGMainDisplayID()) {
                self?.openEditor(url: url, image: nil, beautify: false)
            }
        }
        controller.onClose = { [weak self] closed in
            self?.editorControllers.removeAll { $0 === closed }
            self?.updateActivationPolicySoon()
        }
        editorControllers.append(controller)
        controller.present()
    }

    func openHistory(_ kind: CaptureKind, select url: URL?) {
        dismissPopover()
        if historyController == nil {
            let controller = HistoryWindowController(history: model.history) { [weak self] item in
                self?.openEditor(url: item.url, image: nil, beautify: false)
            }
            controller.onClose = { [weak self] in self?.updateActivationPolicySoon() }
            historyController = controller
        }
        model.history.reload()
        historyController?.show(kind: kind, select: url)
    }

    func showError(_ message: String) {
        dismissPopover()
        NSApp.forceActivate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "ScreenCapture"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        if message.contains("System Settings") {
            alert.addButton(withTitle: "Open System Settings")
        }
        if alert.runModal() == .alertSecondButtonReturn {
            let pane = message.contains("Microphone") ? "Privacy_Microphone" : "Privacy_ScreenCapture"
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
        }
    }
}

/// Minimal main menu so standard shortcuts work while the History window is open.
enum MainMenu {
    @MainActor
    static func make() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About ScreenCapture", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide ScreenCapture", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit ScreenCapture", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu: appMenu, title: "ScreenCapture")

        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(submenu: fileMenu, title: "File")

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenu: editMenu, title: "Edit")

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        main.addItem(submenu: windowMenu, title: "Window")
        NSApp.windowsMenu = windowMenu

        return main
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
