import Carbon.HIToolbox
import Observation

/// System-wide keyboard shortcuts via Carbon (works without Accessibility permission).
@MainActor
@Observable
final class HotKeyManager {
    static let shared = HotKeyManager()

    /// Actions whose shortcut could not be registered (usually taken by another app).
    private(set) var failedActions: Set<ShortcutAction> = []

    @ObservationIgnored private var bindings: [(ShortcutAction, Shortcut)] = []
    @ObservationIgnored private var handler: ((ShortcutAction) -> Void)?
    @ObservationIgnored private var refs: [EventHotKeyRef] = []
    @ObservationIgnored private var idToAction: [UInt32: ShortcutAction] = [:]
    @ObservationIgnored private var isSuspended = false
    @ObservationIgnored private var handlerInstalled = false

    func configure(_ shortcuts: [ShortcutAction: Shortcut], handler: @escaping (ShortcutAction) -> Void) {
        self.handler = handler
        bindings = ShortcutAction.allCases.compactMap { action in shortcuts[action].map { (action, $0) } }
        if !isSuspended { apply() }
    }

    /// Temporarily releases all shortcuts, e.g. while the user records a new one.
    func suspend() {
        isSuspended = true
        unregisterAll()
    }

    func resume() {
        isSuspended = false
        apply()
    }

    private func apply() {
        installHandlerIfNeeded()
        unregisterAll()
        var failed: Set<ShortcutAction> = []
        for (index, (action, shortcut)) in bindings.enumerated() {
            let id = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x5343_4150), id: id) // 'SCAP'
            let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, hotKeyID,
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
                idToAction[id] = action
            } else {
                failed.insert(action)
            }
        }
        if failed != failedActions { failedActions = failed }
    }

    private func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        idToAction.removeAll()
    }

    fileprivate func handle(id: UInt32) {
        guard !isSuspended, let action = idToAction[id] else { return }
        handler?(action)
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return status }
            let id = hotKeyID.id
            MainActor.assumeIsolated { HotKeyManager.shared.handle(id: id) }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
