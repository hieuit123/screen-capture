import SwiftUI

struct EditorView: View {
    @Bindable var doc: EditorDocument
    let showInFinder: () -> Void

    @State private var showInspector = true
    @State private var toast: String?
    @FocusState private var canvasFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            StyleBar(doc: doc)
            Divider()
            EditorCanvas(doc: doc, canvasFocused: $canvasFocused)
        }
        .frame(minWidth: 760, minHeight: 480)
        .toolbar { toolbarContent }
        .inspector(isPresented: $showInspector) {
            BeautifyPanel(doc: doc, copy: copy, save: save, saveAs: saveAs, showInFinder: showInFinder)
                .inspectorColumnWidth(min: 250, ideal: 280, max: 340)
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Label(toast, systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: toast)
        .onAppear { canvasFocused = true }
        // Edit › Copy (⌘C) copies the edited image. While typing, the text field handles ⌘C itself.
        .onCopyCommand {
            guard doc.textEditing == nil, let image = doc.renderOutput() else { return [] }
            flash("Copied to clipboard")
            return [NSItemProvider(object: NSImage(cgImage: image, size: .zero))]
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button("Undo", systemImage: "arrow.uturn.backward") { doc.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!doc.canUndo)
            Button("Redo", systemImage: "arrow.uturn.forward") { doc.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!doc.canRedo)
        }
        ToolbarItem(placement: .principal) {
            ToolPicker(doc: doc)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Copy", systemImage: "doc.on.doc") { copy() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .help("Copy image (⌘C)")
            Button("Save", systemImage: "square.and.arrow.down") { save() }
                .keyboardShortcut("s", modifiers: .command)
                .help("Save (⌘S)")
            Button("Inspector", systemImage: "sidebar.trailing") { showInspector.toggle() }
                .help("Show or hide the Beautify panel")
        }
    }

    private func copy() {
        doc.copyToPasteboard()
        flash("Copied to clipboard")
    }

    private func save() {
        Task {
            do {
                try await doc.save()
                flash("Saved")
            } catch {
                flash("Save failed: \(error.localizedDescription)")
            }
        }
    }

    private func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = ImageFormat.allCases.map(\.utType)
        panel.nameFieldStringValue = doc.fileURL.deletingPathExtension().lastPathComponent + " (edited).png"
        panel.directoryURL = doc.fileURL.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                try await doc.save(to: url)
                flash("Saved \(url.lastPathComponent)")
            } catch {
                flash("Save failed: \(error.localizedDescription)")
            }
        }
    }

    private func flash(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            if toast == message { toast = nil }
        }
    }
}

// MARK: - Toolbar

private struct ToolPicker: View {
    let doc: EditorDocument

    var body: some View {
        HStack(spacing: 2) {
            ForEach(EditorTool.allCases) { tool in
                Button {
                    doc.tool = tool
                } label: {
                    Image(systemName: tool.symbol)
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 30, height: 26)
                        .foregroundStyle(doc.tool == tool ? Color.white : Color.primary)
                        .background {
                            if doc.tool == tool {
                                RoundedRectangle(cornerRadius: 7).fill(Color.accentColor)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("\(tool.title) (\(String(tool.key).uppercased()))")
            }
        }
        .padding(.horizontal, 4)
    }
}

private struct StyleBar: View {
    let doc: EditorDocument

    private let palette: [NSColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue,
                                      .systemPurple, .systemPink, .black, .white]

    var body: some View {
        HStack(spacing: 14) {
            Label(doc.tool.title, systemImage: doc.tool.symbol)
                .font(.callout.weight(.semibold))
                .frame(minWidth: 120, alignment: .leading)

            if doc.tool.usesColor || doc.selectedAnnotation != nil {
                HStack(spacing: 6) {
                    ForEach(palette, id: \.self) { color in
                        let isSelected = doc.color.isApproximately(color)
                        Circle()
                            .fill(Color(nsColor: color))
                            .frame(width: 18, height: 18)
                            .overlay(Circle().strokeBorder(.primary.opacity(0.2), lineWidth: 1))
                            .padding(2)
                            .overlay(Circle().strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2))
                            .onTapGesture { doc.setColor(color) }
                    }
                    ColorPicker("Custom color", selection: Binding(
                        get: { Color(nsColor: doc.color) },
                        set: { doc.setColor(NSColor($0)) }
                    ), supportsOpacity: false)
                    .labelsHidden()
                }
            }

            if doc.tool.usesStroke {
                Divider().frame(height: 20)
                Picker("Stroke", selection: Binding(get: { doc.strokeSize }, set: { doc.setStrokeSize($0) })) {
                    ForEach(StrokeSize.allCases) { size in
                        Image(systemName: "line.diagonal")
                            .fontWeight(size == .thin ? .light : size == .medium ? .semibold : .black)
                            .help(size.title)
                            .tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 120)
            }

            if doc.tool.usesTextSize {
                Divider().frame(height: 20)
                Picker("Size", selection: Binding(get: { doc.textSize }, set: { doc.setTextSize($0) })) {
                    ForEach(TextSize.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 100)
            }

            if doc.tool.usesFill {
                Divider().frame(height: 20)
                Toggle(doc.tool == .text ? "Background" : "Fill", isOn: Binding(get: { doc.filled }, set: { doc.setFilled($0) }))
                    .toggleStyle(.checkbox)
            }

            if doc.tool == .crop {
                Divider().frame(height: 20)
                if doc.cropRect != nil {
                    Button("Apply Crop", systemImage: "checkmark") { doc.applyCrop() }
                        .buttonStyle(.borderedProminent)
                    Button("Cancel") { doc.cropRect = nil }
                } else {
                    Text("Drag over the image to choose the crop area.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if doc.tool == .select, doc.selectedAnnotation != nil {
                Divider().frame(height: 20)
                Button("Delete", systemImage: "trash", role: .destructive) { doc.deleteSelection() }
            }

            Spacer(minLength: 0)

            Text("\(Int(doc.imageSize.width)) × \(Int(doc.imageSize.height))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

// MARK: - Canvas

private struct EditorCanvas: View {
    let doc: EditorDocument
    var canvasFocused: FocusState<Bool>.Binding

    var body: some View {
        GeometryReader { geo in
            let layout = doc.layout
            let inset: CGFloat = 36
            let fit = min((geo.size.width - inset * 2) / layout.canvasSize.width,
                          (geo.size.height - inset * 2) / layout.canvasSize.height)
            let scale = max(0.01, min(fit, 1))
            let canvasSize = CGSize(width: layout.canvasSize.width * scale, height: layout.canvasSize.height * scale)
            let imageRect = CGRect(x: layout.imageRect.minX * scale, y: layout.imageRect.minY * scale,
                                   width: layout.imageRect.width * scale, height: layout.imageRect.height * scale)
            let radius = layout.cornerRadius * scale
            let beautify = doc.beautify

            ZStack(alignment: .topLeading) {
                if beautify.enabled {
                    LinearGradient(colors: beautify.preset.colors.map { Color(nsColor: $0) },
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                Image(decorative: doc.image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: imageRect.width, height: imageRect.height)
                    .clipShape(.rect(cornerRadius: radius))
                    .shadow(color: .black.opacity(layout.shadowRadius > 0 ? 0.4 : 0),
                            radius: layout.shadowRadius * scale / 2, y: layout.shadowRadius * scale * 0.4)
                    .position(x: imageRect.midX, y: imageRect.midY)

                AnnotationLayer(doc: doc, scale: scale, canvasFocused: canvasFocused)
                    .frame(width: imageRect.width, height: imageRect.height)
                    .clipShape(.rect(cornerRadius: radius))
                    .position(x: imageRect.midX, y: imageRect.midY)
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
            .clipped()
            .shadow(color: .black.opacity(beautify.enabled ? 0.15 : 0.25), radius: 12, y: 4)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .focusable()
        .focusEffectDisabled()
        .focused(canvasFocused)
        .onKeyPress(phases: .down) { press in handleKey(press) }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard doc.textEditing == nil else { return .ignored }
        switch press.key {
        case .delete, .deleteForward:
            doc.deleteSelection()
            return .handled
        case .escape:
            doc.escape()
            return .handled
        case .return:
            guard doc.cropRect != nil else { return .ignored }
            doc.applyCrop()
            return .handled
        case .leftArrow, .rightArrow, .upArrow, .downArrow:
            guard doc.selectedID != nil else { return .ignored }
            let step: CGFloat = press.modifiers.contains(.shift) ? 10 : 1
            let dx: CGFloat = press.key == .leftArrow ? -step : press.key == .rightArrow ? step : 0
            let dy: CGFloat = press.key == .upArrow ? -step : press.key == .downArrow ? step : 0
            doc.nudgeSelection(dx: dx, dy: dy)
            return .handled
        default:
            guard press.modifiers.subtracting(.shift).isEmpty, let char = press.characters.lowercased().first,
                  let tool = EditorTool.allCases.first(where: { $0.key == char }) else { return .ignored }
            doc.tool = tool
            return .handled
        }
    }
}

private struct AnnotationLayer: View {
    @Bindable var doc: EditorDocument
    let scale: CGFloat
    var canvasFocused: FocusState<Bool>.Binding

    @State private var isDragging = false
    @FocusState private var textFocused: Bool

    var body: some View {
        // Read observable state here so SwiftUI tracks it; the Canvas closure runs outside body.
        let annotations = doc.visibleAnnotations
        let pixelated = doc.pixelated
        let imageSize = doc.imageSize
        let selectionBounds = doc.tool == .select ? doc.selectedAnnotation?.bounds : nil
        let scale = scale

        Canvas { context, _ in
            context.scaleBy(x: scale, y: scale)
            context.withCGContext { cg in
                EditorRenderer.draw(annotations, pixelated: pixelated, imageSize: imageSize, in: cg)
            }
            if let selectionBounds {
                let rect = selectionBounds.insetBy(dx: -6 / scale, dy: -6 / scale)
                context.stroke(Path(roundedRect: rect, cornerRadius: 4 / scale), with: .color(.accentColor),
                               style: StrokeStyle(lineWidth: 1.5 / scale, dash: [5 / scale, 3 / scale]))
            }
        }
        .contentShape(.rect)
        .gesture(dragGesture)
        .onContinuousHover { phase in
            switch phase {
            case .active: cursor.set()
            case .ended: NSCursor.arrow.set()
            }
        }
        .overlay(alignment: .topLeading) { cropOverlay }
        .overlay(alignment: .topLeading) { textEditor }
    }

    private var cursor: NSCursor {
        switch doc.tool {
        case .select: .arrow
        case .text: .iBeam
        default: .crosshair
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let constrained = NSEvent.modifierFlags.contains(.shift)
                if !isDragging {
                    isDragging = true
                    doc.begin(at: imagePoint(value.startLocation))
                }
                doc.update(to: imagePoint(value.location), constrained: constrained)
            }
            .onEnded { value in
                isDragging = false
                doc.end(at: imagePoint(value.location))
                if doc.textEditing == nil { canvasFocused.wrappedValue = true }
            }
    }

    private func imagePoint(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x / scale, y: p.y / scale)
    }

    @ViewBuilder
    private var cropOverlay: some View {
        if doc.tool == .crop, let crop = doc.cropRect {
            let rect = CGRect(x: crop.minX * scale, y: crop.minY * scale, width: crop.width * scale, height: crop.height * scale)
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: CGSize(width: doc.imageSize.width * scale,
                                                                   height: doc.imageSize.height * scale)))
                    path.addRect(rect)
                }
                .fill(.black.opacity(0.5), style: FillStyle(eoFill: true))

                Rectangle()
                    .strokeBorder(.white, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)

                Text("\(Int(crop.width)) × \(Int(crop.height))")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.7), in: .capsule)
                    .offset(x: rect.minX + 6, y: rect.minY + 6)
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var textEditor: some View {
        if let editing = doc.textEditing {
            let fontSize = editing.fontSize * scale
            let pad = EditorRenderer.textPadding(fontSize: fontSize)
            TextField("Type text", text: Binding(
                get: { doc.textEditing?.text ?? "" },
                set: { doc.textEditing?.text = $0 }
            ), axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: fontSize, weight: .bold))
            .foregroundStyle(editing.filled ? .white : Color(nsColor: editing.color))
            .fixedSize()
            .frame(minWidth: max(80, fontSize * 4), alignment: .leading)
            .padding(.horizontal, pad.width)
            .padding(.vertical, pad.height)
            .background {
                RoundedRectangle(cornerRadius: fontSize * 0.3)
                    .fill(editing.filled ? Color(nsColor: editing.color) : Color.white.opacity(0.85))
            }
            .overlay {
                RoundedRectangle(cornerRadius: fontSize * 0.3)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
            .offset(x: editing.origin.x * scale, y: editing.origin.y * scale)
            .focused($textFocused)
            .onSubmit { finishText() }
            .onExitCommand { doc.escape(); canvasFocused.wrappedValue = true }
            .onAppear { textFocused = true }
            .onChange(of: textFocused) { _, focused in
                if !focused { finishText() }
            }
        }
    }

    private func finishText() {
        doc.commitTextEditing()
        canvasFocused.wrappedValue = true
    }
}

// MARK: - Inspector

private struct BeautifyPanel: View {
    @Bindable var doc: EditorDocument
    let copy: () -> Void
    let save: () -> Void
    let saveAs: () -> Void
    let showInFinder: () -> Void

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $doc.beautify.enabled) {
                    Label("Beautify", systemImage: "sparkles")
                }
                .toggleStyle(.switch)
            } footer: {
                Text("Place the screenshot on a background with padding, rounded corners and a shadow.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Background") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(GradientPreset.all) { preset in
                        let isSelected = doc.beautify.presetID == preset.id
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient(colors: preset.colors.map { Color(nsColor: $0) },
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(height: 40)
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(isSelected ? Color.accentColor : .primary.opacity(0.1), lineWidth: isSelected ? 2.5 : 1))
                            .help(preset.name)
                            .onTapGesture {
                                doc.beautify.presetID = preset.id
                                doc.beautify.enabled = true
                            }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Layout") {
                LabeledContent("Padding") {
                    Slider(value: $doc.beautify.padding, in: 0.02...0.25)
                }
                LabeledContent("Corners") {
                    Slider(value: $doc.beautify.cornerRadius, in: 0...0.05)
                }
                Toggle("Shadow", isOn: $doc.beautify.shadow)
                Picker("Aspect", selection: $doc.beautify.aspect) {
                    ForEach(AspectPreset.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            .disabled(!doc.beautify.enabled)

            Section("Export") {
                Button("Copy to Clipboard", systemImage: "doc.on.doc", action: copy)
                Button("Save", systemImage: "square.and.arrow.down", action: save)
                Button("Save As…", systemImage: "square.and.arrow.down.on.square", action: saveAs)
                Button("Show in Finder", systemImage: "folder", action: showInFinder)
            }
            .buttonStyle(.borderless)
        }
        .formStyle(.grouped)
    }
}

private extension NSColor {
    func isApproximately(_ other: NSColor) -> Bool {
        guard let a = usingColorSpace(.sRGB), let b = other.usingColorSpace(.sRGB) else { return false }
        return abs(a.redComponent - b.redComponent) < 0.01 && abs(a.greenComponent - b.greenComponent) < 0.01
            && abs(a.blueComponent - b.blueComponent) < 0.01
    }
}
