import SwiftUI

struct MenuView: View {
    let model: AppModel
    let openHistory: (CaptureKind) -> Void
    let openItem: (CaptureItem) -> Void
    let openSettings: () -> Void
    let openFolder: () -> Void
    let quit: () -> Void

    @Namespace private var kindNamespace

    var body: some View {
        @Bindable var settings = model.settings

        VStack(alignment: .leading, spacing: 14) {
            header

            if !model.hasScreenPermission {
                PermissionBanner { model.requestScreenPermission() }
            }

            if case .recording(let since) = model.phase {
                RecordingStatusView(since: since) { Task { await model.stopRecording() } }
            } else {
                kindPicker(selection: $settings.kind)
                SourcePicker(selection: $settings.source)
                TargetPicker(model: model)
                Group {
                    if settings.kind == .recording {
                        RecordingOptionsView(settings: settings, content: model.content)
                    } else {
                        ScreenshotOptionsView(settings: settings)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                actionButton
                if settings.kind == .screenshot {
                    fullPageButton
                }
            }

            RecentStrip(kind: settings.kind, items: Array(model.history.items(for: settings.kind).prefix(4)),
                        open: openItem) {
                openHistory(settings.kind)
            }

            footer
        }
        .padding(16)
        .frame(width: 360)
        .animation(.snappy(duration: 0.25), value: settings.kind)
        .animation(.snappy(duration: 0.25), value: settings.source)
        .task { await model.refreshContent() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "record.circle.fill")
                .font(.title2)
                .foregroundStyle(.red.gradient)
            VStack(alignment: .leading, spacing: 0) {
                Text("ScreenCapture").font(.headline)
                Text("Record and capture your screen")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await model.refreshContent() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .help("Refresh screens, windows and apps")
            Button(action: openSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .help("Settings and shortcuts")
        }
    }

    private func kindPicker(selection: Binding<CaptureKind>) -> some View {
        HStack(spacing: 4) {
            ForEach(CaptureKind.allCases) { kind in
                let isSelected = selection.wrappedValue == kind
                Button {
                    selection.wrappedValue = kind
                } label: {
                    Label(kind.title, systemImage: kind.symbol)
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(.background)
                            .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                            .matchedGeometryEffect(id: "kind", in: kindNamespace)
                    }
                }
            }
        }
        .padding(3)
        .background(.quaternary.opacity(0.7), in: .capsule)
    }

    private var actionButton: some View {
        let isRecording = model.settings.kind == .recording
        let shortcut = model.settings.shortcuts[isRecording ? .toggleRecording : .screenshot]?.displayString ?? ""
        return Button {
            model.performPrimaryAction()
        } label: {
            HStack {
                Image(systemName: isRecording ? "record.circle" : "camera.fill")
                Text(isRecording ? "Start Recording" : "Take Screenshot")
                Spacer()
                Text(shortcut)
                    .font(.caption.monospaced())
                    .opacity(0.75)
            }
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.glassProminent)
        .tint(isRecording ? .red : .accentColor)
        .controlSize(.large)
        .disabled(model.phase.isBusy)
        .keyboardShortcut(.defaultAction)
    }

    private var fullPageButton: some View {
        Button {
            model.captureFullPage()
        } label: {
            HStack {
                Image(systemName: "doc.richtext")
                Text("Full Web Page (Chrome)")
                Spacer()
                Text(model.settings.shortcuts[.fullPageScreenshot]?.displayString ?? "")
                    .font(.caption.monospaced())
                    .opacity(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
        }
        .buttonStyle(.glass)
        .disabled(model.phase.isBusy)
        .help("Scrolls the active Chrome tab and captures the whole page")
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("History", systemImage: "clock.arrow.circlepath") { openHistory(model.settings.lastActionKind) }
            Button("Folder", systemImage: "folder") { openFolder() }
            Spacer()
            Button("Quit", systemImage: "power") { quit() }
        }
        .buttonStyle(.glass)
        .controlSize(.small)
    }
}

// MARK: - Pieces

private struct PermissionBanner: View {
    let request: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("Screen Recording permission needed").font(.callout.weight(.semibold))
                Text("Allow ScreenCapture in System Settings, then reopen this menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Grant Access", action: request)
                    .buttonStyle(.glassProminent)
                    .tint(.orange)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 12))
    }
}

private struct RecordingStatusView: View {
    let since: Date
    let stop: () -> Void
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                    .opacity(pulse ? 0.3 : 1)
                    .animation(.easeInOut(duration: 0.8).repeatForever(), value: pulse)
                Text("Recording")
                    .font(.headline)
                Spacer()
                ElapsedTimeText(since: since)
                    .font(.title3.weight(.semibold))
            }
            Button(action: stop) {
                Label("Stop Recording", systemImage: "stop.fill")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .tint(.red)
            .controlSize(.large)
        }
        .padding(12)
        .background(.red.opacity(0.08), in: .rect(cornerRadius: 14))
        .onAppear { pulse = true }
    }
}

private struct SourcePicker: View {
    @Binding var selection: CaptureSource

    var body: some View {
        HStack(spacing: 8) {
            ForEach(CaptureSource.allCases) { source in
                let isSelected = selection == source
                Button {
                    selection = source
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: source.symbol)
                            .font(.title3)
                            .frame(height: 22)
                        Text(source.title)
                            .font(.caption.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .contentShape(.rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isSelected ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1.5)
                )
            }
        }
    }
}

private struct TargetPicker: View {
    let model: AppModel

    var body: some View {
        @Bindable var settings = model.settings
        let content = model.content

        Group {
            switch settings.source {
            case .display:
                OptionRow(icon: "display", title: "Display") {
                    Picker("Display", selection: $settings.displayID) {
                        ForEach(content.displays) { display in
                            Text("\(display.name) — \(Int(display.pixelSize.width))×\(Int(display.pixelSize.height))")
                                .tag(display.id)
                        }
                    }
                }
            case .window:
                OptionRow(icon: "macwindow", title: "Window") {
                    Picker("Window", selection: $settings.windowID) {
                        if content.windows.isEmpty { Text("No windows").tag(settings.windowID) }
                        ForEach(content.windows) { window in
                            Label {
                                Text(window.title == window.appName ? window.appName : "\(window.appName) — \(window.title)")
                            } icon: {
                                if let icon = content.icon(for: window.pid) { Image(nsImage: icon) }
                            }
                            .tag(window.id)
                        }
                    }
                }
            case .application:
                OptionRow(icon: "app.badge", title: "App") {
                    Picker("App", selection: $settings.appBundleID) {
                        if content.apps.isEmpty { Text("No apps").tag(settings.appBundleID) }
                        ForEach(content.apps) { app in
                            Label {
                                Text(app.name)
                            } icon: {
                                if let icon = content.icon(for: app.pid) { Image(nsImage: icon) }
                            }
                            .tag(app.id)
                        }
                    }
                }
            case .area:
                HStack(spacing: 8) {
                    Image(systemName: "hand.draw")
                        .foregroundStyle(.secondary)
                    Text("Drag to select an area after you press the button. Click once to capture a whole screen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 4)
            }
        }
        .labelsHidden()
    }
}

private struct RecordingOptionsView: View {
    @Bindable var settings: SettingsStore
    let content: ShareableContentStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            OptionRow(icon: "speedometer", title: "Frame rate") {
                Picker("Frame rate", selection: $settings.frameRate) {
                    ForEach(FrameRate.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            OptionRow(icon: "sparkles.tv", title: "Quality") {
                Picker("Quality", selection: $settings.quality) {
                    ForEach(VideoQuality.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Text(qualitySummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 28)

            OptionRow(icon: "film", title: "Format") {
                HStack(spacing: 6) {
                    Picker("Codec", selection: $settings.codec) {
                        ForEach(VideoCodec.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Container", selection: $settings.container) {
                        ForEach(VideoContainer.allCases) { Text($0.title).tag($0) }
                    }
                    .frame(width: 76)
                }
            }

            Divider().padding(.vertical, 2)

            ToggleRow(icon: "speaker.wave.2.fill", title: "System audio", isOn: $settings.captureSystemAudio)
            ToggleRow(icon: "mic.fill", title: "Microphone", isOn: $settings.captureMicrophone)
            if settings.captureMicrophone {
                Picker("Microphone", selection: $settings.microphoneID) {
                    Text("System Default").tag("")
                    ForEach(content.microphones) { Text($0.name).tag($0.id) }
                }
                .labelsHidden()
                .controlSize(.small)
                .padding(.leading, 28)
            }
            ToggleRow(icon: "cursorarrow", title: "Show cursor", isOn: $settings.showsCursor)
        }
        .optionCard()
    }

    private var qualitySummary: String {
        let options = RecordingOptions(
            frameRate: settings.frameRate.rawValue, quality: settings.quality, codec: settings.codec,
            container: settings.container, showsCursor: true, captureSystemAudio: false,
            captureMicrophone: false, microphoneID: nil)
        guard settings.source == .display,
              let display = content.displays.first(where: { $0.id == settings.displayID }) else {
            return settings.quality.detail
        }
        let size = options.outputSize(for: display.pixelSize)
        let mbps = Double(options.bitrate(for: size)) / 1_000_000
        return "\(Int(size.width))×\(Int(size.height)) @ \(settings.frameRate.rawValue) fps · ≈\(Int(mbps.rounded())) Mbps"
    }
}

private struct ScreenshotOptionsView: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            OptionRow(icon: "photo", title: "Format") {
                Picker("Format", selection: $settings.imageFormat) {
                    ForEach(ImageFormat.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Divider().padding(.vertical, 2)
            ToggleRow(icon: "cursorarrow", title: "Show cursor", isOn: $settings.showsCursor)
            ToggleRow(icon: "doc.on.clipboard", title: "Also copy to clipboard", isOn: $settings.copyScreenshotToClipboard)
        }
        .optionCard()
    }
}

private struct RecentStrip: View {
    let kind: CaptureKind
    let items: [CaptureItem]
    let open: (CaptureItem) -> Void
    let showAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent \(kind.historyTitle)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Show All", action: showAll)
                    .buttonStyle(.link)
                    .font(.caption)
            }
            if items.isEmpty {
                Text("Nothing yet. Your \(kind.historyTitle.lowercased()) will appear here.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        Button {
                            open(item)
                        } label: {
                            ThumbnailView(url: item.url, version: item.modified, maxPixel: 160)
                                .frame(width: 74, height: 46)
                                .clipShape(.rect(cornerRadius: 8))
                                .overlay(alignment: .bottomTrailing) {
                                    if kind == .recording {
                                        DurationBadge(url: item.url).scaleEffect(0.85).padding(2)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .help(item.name)
                        .draggable(item.url)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

private struct OptionRow<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            Text(title)
                .frame(width: 74, alignment: .leading)
            content
                .labelsHidden()
                .frame(maxWidth: .infinity)
        }
        .font(.callout)
        .controlSize(.small)
    }
}

private struct ToggleRow: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            Text(title)
            Spacer()
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .font(.callout)
    }
}

private extension View {
    func optionCard() -> some View {
        padding(12)
            .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 14))
    }
}
