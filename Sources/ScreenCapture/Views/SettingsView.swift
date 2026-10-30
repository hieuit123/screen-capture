import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView(settings: settings)
            }
            Tab("Beautify", systemImage: "sparkles") {
                BeautifySettingsView(settings: settings)
            }
            Tab("Shortcuts", systemImage: "keyboard") {
                ShortcutSettingsView(settings: settings)
            }
        }
        .frame(width: 560, height: 580)
    }
}

private struct GeneralSettingsView: View {
    @Bindable var settings: SettingsStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("After Capture") {
                Toggle("Open the editor after taking a screenshot", isOn: $settings.openEditorAfterScreenshot)
                Toggle("Close the editor after copying (⌘C) or saving (⌘S)", isOn: $settings.closeEditorAfterCopyOrSave)
                Toggle("Show a preview card after capturing", isOn: $settings.showPostCapturePanel)
                Toggle("Copy screenshots to the clipboard", isOn: $settings.copyScreenshotToClipboard)
            }
            Section {
                LabeledContent {
                    ShortcutRecorder(shortcut: settings.shortcutBinding(for: .quickScreenshot))
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Shortcut")
                        Text("Captures the screen under the mouse instantly, copies it to the clipboard and saves it to ScreenCapture/images. The editor is not opened.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle("Play shutter sound", isOn: $settings.playCaptureSound)
            } header: {
                Label("Quick Screenshot", systemImage: "bolt.fill")
            }

            Section("Screenshots") {
                Picker("Image format", selection: $settings.imageFormat) {
                    ForEach(ImageFormat.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Show the mouse cursor", isOn: $settings.showsCursor)
            }
            Section {
                Picker("Image quality", selection: $settings.fullPageQuality) {
                    ForEach(FullPageQuality.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Full-Page Screenshots (Chrome)")
            } footer: {
                Text("Lower quality makes smaller files and lets very long pages fit (up to 32,000 px tall). 100% keeps full Retina sharpness.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Storage") {
                LabeledContent("Save location") {
                    HStack {
                        Text("~/Documents/ScreenCapture")
                            .foregroundStyle(.secondary)
                        Button("Show in Finder") {
                            try? StorageManager.ensureFolders()
                            NSWorkspace.shared.open(StorageManager.rootURL)
                        }
                    }
                }
            }
            Section("System") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                        }
                    }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct BeautifySettingsView: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("Auto-apply Beautify to new screenshots", isOn: $settings.autoApplyBeautify)
                BeautifyPreview(style: settings.beautifyStyle)
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                    .opacity(settings.autoApplyBeautify ? 1 : 0.5)
            } footer: {
                Text("Applies to every new screenshot, including Quick Screenshots: the clipboard and saved file get the styled image, and the editor opens with Beautify on so you can still change or remove it. Changes you make in the editor become the new default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            BeautifyStyleControls(style: $settings.beautifyStyle)
        }
        .formStyle(.grouped)
    }
}

/// Miniature preview of a Beautify style with a mock window.
private struct BeautifyPreview: View {
    let style: BeautifySettings

    var body: some View {
        GeometryReader { geo in
            let mock = CGSize(width: 1600, height: 1000)
            let layout = CanvasLayout(imageSize: mock, beautify: style.applied)
            let scale = min(geo.size.width / layout.canvasSize.width, geo.size.height / layout.canvasSize.height)
            let image = CGRect(x: layout.imageRect.minX * scale, y: layout.imageRect.minY * scale,
                               width: layout.imageRect.width * scale, height: layout.imageRect.height * scale)
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: style.preset.colors.map { Color(nsColor: $0) },
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 0) {
                    HStack(spacing: 3) {
                        ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0).frame(width: 5, height: 5) }
                        Spacer()
                    }
                    .padding(5)
                    .background(Color(white: 0.92))
                    Color.white
                }
                .frame(width: image.width, height: image.height)
                .clipShape(.rect(cornerRadius: layout.cornerRadius * scale))
                .shadow(color: .black.opacity(style.shadow ? 0.35 : 0), radius: layout.shadowRadius * scale / 2,
                        y: layout.shadowRadius * scale * 0.4)
                .position(x: image.midX, y: image.midY)
            }
            .frame(width: layout.canvasSize.width * scale, height: layout.canvasSize.height * scale)
            .clipShape(.rect(cornerRadius: 6))
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

private struct ShortcutSettingsView: View {
    @Bindable var settings: SettingsStore
    private let hotKeys = HotKeyManager.shared

    var body: some View {
        Form {
            Section {
                ForEach(ShortcutAction.allCases) { action in
                    LabeledContent {
                        ShortcutRecorder(shortcut: binding(for: action))
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.title)
                            Text(action.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if hotKeys.failedActions.contains(action) {
                                Label("macOS refused this shortcut (it may be reserved). Choose a different one.",
                                      systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            } header: {
                Text("Global Shortcuts")
            } footer: {
                Text("Click a shortcut, then press the new key combination. It must include ⌘, ⌃ or ⌥ (function keys work alone). Press Delete to clear, Esc to cancel. Avoid combinations other apps already use, such as ⇧⌘3/4/5.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Restore Defaults") {
                    settings.shortcuts = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.defaultShortcut) })
                }
            }
        }
        .formStyle(.grouped)
    }

    private func binding(for action: ShortcutAction) -> Binding<Shortcut?> {
        settings.shortcutBinding(for: action)
    }
}

/// Click-to-record control for a global shortcut.
struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut?
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                isRecording ? stop() : start()
            } label: {
                Text(isRecording ? "Press keys…" : (shortcut?.displayString ?? "Record Shortcut"))
                    .font(.body.monospaced())
                    .frame(minWidth: 120)
                    .foregroundStyle(isRecording ? Color.accentColor : (shortcut == nil ? .secondary : .primary))
            }
            .buttonStyle(.bordered)

            if shortcut != nil, !isRecording {
                Button {
                    shortcut = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear shortcut")
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        guard monitor == nil else { return }
        isRecording = true
        HotKeyManager.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch Int(event.keyCode) {
            case 53:
                stop()
            case 51 where event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
                 117 where event.modifierFlags.intersection([.command, .option, .control]).isEmpty:
                shortcut = nil
                stop()
            default:
                if let recorded = Shortcut(event: event) {
                    shortcut = recorded
                    stop()
                } else {
                    NSSound.beep()
                }
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if isRecording {
            isRecording = false
            HotKeyManager.shared.resume()
        }
    }
}

extension SettingsStore {
    func shortcutBinding(for action: ShortcutAction) -> Binding<Shortcut?> {
        Binding { self.shortcuts[action] } set: { self.setShortcut($0, for: action) }
    }
}
