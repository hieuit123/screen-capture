import SwiftUI

enum EditorFinishAction {
    case copied, saved
}

struct EditorView: View {
    @Bindable var doc: EditorDocument
    @Bindable var settings: SettingsStore
    let showInFinder: () -> Void
    /// Called when ⌘C / ⌘S should close the editor (see Settings › Close the editor after copying or saving).
    let onFinish: (EditorFinishAction, CGImage) -> Void
    /// Floats the edited image on screen.
    let onPin: (CGImage) -> Void

    @State private var showInspector = true
    @State private var toast: String?
    /// nil means "zoom to fit".
    @State private var zoom: CGFloat?
    @State private var fitScale: CGFloat = 1
    @FocusState private var canvasFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            StyleBar(doc: doc)
            Divider()
            EditorCanvas(doc: doc, canvasFocused: $canvasFocused, zoom: $zoom, fitScale: $fitScale)
            Divider()
            ZoomBar(zoom: $zoom, fitScale: fitScale, maxZoom: EditorZoom.maxZoom(for: doc.layout.canvasSize))
        }
        .frame(minWidth: 760, minHeight: 480)
        .toolbar { toolbarContent }
        .inspector(isPresented: $showInspector) {
            BeautifyPanel(doc: doc, settings: settings, copy: copy, save: save, saveAs: saveAs, copyText: copyText,
                          pin: pin, showInFinder: showInFinder)
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
            DispatchQueue.main.async {
                // Write the image ourselves too, so the clipboard is filled before the window can close.
                ScreenshotService.copyToPasteboard(image)
                finishOrFlash(.copied, image)
            }
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
                .help(settings.closeEditorAfterCopyOrSave ? "Copy image and close (⌘C)" : "Copy image (⌘C)")
            Button("Save", systemImage: "square.and.arrow.down") { save() }
                .keyboardShortcut("s", modifiers: .command)
                .help(settings.closeEditorAfterCopyOrSave ? "Save and close (⌘S)" : "Save (⌘S)")
            Button("Inspector", systemImage: "sidebar.trailing") { showInspector.toggle() }
                .help("Show or hide the Beautify panel")
        }
    }

    private func copy() {
        guard let image = doc.renderOutput() else { return }
        ScreenshotService.copyToPasteboard(image)
        finishOrFlash(.copied, image)
    }

    private func save() {
        guard let image = doc.renderOutput() else { return }
        Task {
            do {
                try await doc.save(rendered: image)
                finishOrFlash(.saved, image)
            } catch {
                flash("Save failed: \(error.localizedDescription)")
            }
        }
    }

    /// Closes the editor after copy/save when enabled in Settings, otherwise shows an inline confirmation.
    private func finishOrFlash(_ action: EditorFinishAction, _ image: CGImage) {
        guard settings.closeEditorAfterCopyOrSave else {
            flash(action == .copied ? "Copied to clipboard" : "Saved")
            return
        }
        Task {
            // Keep the file in History identical to what was copied.
            if action == .copied, doc.isDirty { try? await doc.save(rendered: image) }
            onFinish(action, image)
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

    private func pin() {
        guard let image = doc.renderOutput() else { return }
        onPin(image)
    }

    /// OCRs the screenshot (without annotations) and copies the text.
    private func copyText() {
        let image = doc.image
        Task {
            do {
                let text = try await TextRecognizer.recognize(image)
                guard !text.isEmpty else {
                    flash("No text found")
                    return
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                flash("Text copied")
            } catch {
                flash("Couldn't recognize text")
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
                        .overlay(alignment: .bottomTrailing) {
                            if let number = tool.numberKey {
                                Text(String(number))
                                    .font(.system(size: 8, weight: .bold).monospacedDigit())
                                    .opacity(0.75)
                                    .padding(.trailing, 2)
                                    .padding(.bottom, 1)
                            }
                        }
                        .foregroundStyle(doc.tool == tool ? Color.white : Color.primary)
                        .background {
                            if doc.tool == tool {
                                RoundedRectangle(cornerRadius: 7).fill(Color.accentColor)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("\(tool.title) (\(tool.numberKey.map { "\($0) or " } ?? "")\(String(tool.key).uppercased()))")
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
        // In Select mode, show the options of the selected mark.
        let styleTool = doc.tool == .select ? doc.selectedAnnotation?.tool ?? .select : doc.tool

        HStack(spacing: 14) {
            Label(doc.tool.title, systemImage: doc.tool.symbol)
                .font(.callout.weight(.semibold))
                .frame(minWidth: 120, alignment: .leading)
                .fixedSize()

            if EditorTool.shapes.contains(doc.tool) {
                Picker("Shape", selection: Binding(get: { doc.tool }, set: { doc.tool = $0 })) {
                    ForEach(EditorTool.shapes) { shape in
                        Image(systemName: shape.symbol).help(shape.title).tag(shape)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 110)
                .help("Press 4 to switch shapes")
                Divider().frame(height: 20)
            }

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

            if styleTool.usesStroke {
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

            if styleTool.usesBorder {
                Picker("Border", selection: Binding(get: { doc.borderStyle }, set: { doc.setBorderStyle($0) })) {
                    ForEach(BorderStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .help("Outline around the shape")
            }

            if styleTool.usesTextSize {
                Divider().frame(height: 20)
                Picker("Size", selection: Binding(get: { doc.textSize }, set: { doc.setTextSize($0) })) {
                    ForEach(TextSize.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 100)
            }

            if styleTool.usesFill {
                Divider().frame(height: 20)
                Toggle(styleTool == .text ? "Background" : "Fill", isOn: Binding(get: { doc.filled }, set: { doc.setFilled($0) }))
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

            if doc.selectedAnnotation != nil, doc.tool != .crop {
                Divider().frame(height: 20)
                Button("Delete", systemImage: "trash", role: .destructive) { doc.deleteSelection() }
            } else if doc.tool == .text {
                Divider().frame(height: 20)
                Text("Click to add text · double-click text to edit it")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Text("\(Int(doc.imageSize.width)) × \(Int(doc.imageSize.height))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .controlSize(.small)
        .lineLimit(1)
        // Fixed height so the bar (and the canvas below it) doesn't jump when the controls change with the selection.
        .frame(height: 28)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

// MARK: - Canvas

private struct EditorCanvas: View {
    let doc: EditorDocument
    var canvasFocused: FocusState<Bool>.Binding
    @Binding var zoom: CGFloat?
    @Binding var fitScale: CGFloat

    @State private var pinchStart: CGFloat?

    var body: some View {
        GeometryReader { geo in
            let layout = doc.layout
            let inset: CGFloat = 36
            let fit = max(0.01, min((geo.size.width - inset * 2) / layout.canvasSize.width,
                                    (geo.size.height - inset * 2) / layout.canvasSize.height, 1))
            let scale = zoom ?? fit
            let canvasSize = CGSize(width: layout.canvasSize.width * scale, height: layout.canvasSize.height * scale)
            let imageRect = CGRect(x: layout.imageRect.minX * scale, y: layout.imageRect.minY * scale,
                                   width: layout.imageRect.width * scale, height: layout.imageRect.height * scale)
            let radius = layout.cornerRadius * scale
            let beautify = doc.beautify

            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    if beautify.enabled {
                        BeautifyBackgroundView(style: beautify)
                    } else if doc.extraSpace != .none {
                        Color.white
                    }
                    Image(decorative: doc.image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: imageRect.width, height: imageRect.height)
                        .clipShape(.rect(cornerRadius: radius))
                        .shadow(color: .black.opacity(layout.shadowRadius > 0 ? 0.4 : 0),
                                radius: layout.shadowRadius * scale / 2, y: layout.shadowRadius * scale * 0.4)
                        .position(x: imageRect.midX, y: imageRect.midY)

                    // Spans the whole canvas so marks can be drawn outside the screenshot.
                    AnnotationLayer(doc: doc, scale: scale, origin: imageRect.origin, canvasFocused: canvasFocused)
                        .frame(width: canvasSize.width, height: canvasSize.height)
                }
                .frame(width: canvasSize.width, height: canvasSize.height)
                .clipped()
                .shadow(color: .black.opacity(beautify.enabled ? 0.15 : 0.25), radius: 12, y: 4)
                .padding(inset)
                .frame(minWidth: geo.size.width, minHeight: geo.size.height)
            }
            .defaultScrollAnchor(.center, for: .sizeChanges)
            .defaultScrollAnchor(.center, for: .initialOffset)
            .scrollDisabled(zoom == nil)
            .scrollIndicators(zoom == nil ? .hidden : .automatic)
            .onChange(of: fit, initial: true) { fitScale = fit }
            // Trackpad pinch.
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        let start = pinchStart ?? scale
                        if pinchStart == nil { pinchStart = scale }
                        zoom = EditorZoom.clamp(start * value.magnification, max: EditorZoom.maxZoom(for: layout.canvasSize))
                    }
                    .onEnded { _ in
                        pinchStart = nil
                        if let zoom, abs(zoom - fit) < 0.02 { self.zoom = nil }
                    }
            )
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
            guard press.modifiers.subtracting(.shift).isEmpty, let char = press.characters.lowercased().first else {
                return .ignored
            }
            if char == "4" {
                doc.selectShapeTool()
                return .handled
            }
            guard let tool = EditorTool.allCases.first(where: { $0.numberKey == char })
                    ?? EditorTool.allCases.first(where: { $0.key == char }) else { return .ignored }
            doc.tool = tool
            return .handled
        }
    }
}

private struct AnnotationLayer: View {
    @Bindable var doc: EditorDocument
    let scale: CGFloat
    /// Where the screenshot's top-left corner sits in this layer, in points.
    let origin: CGPoint
    var canvasFocused: FocusState<Bool>.Binding

    @State private var isDragging = false
    @GestureState private var gestureDown = false
    @State private var pointer: PointerStyle = .default
    @FocusState private var textFocused: Bool

    var body: some View {
        // Read observable state here so SwiftUI tracks it; the Canvas closure runs outside body.
        let annotations = doc.visibleAnnotations
        let pixelated = doc.pixelated
        let imageSize = doc.imageSize
        let selected = doc.textEditing == nil && doc.tool != .crop ? doc.selectedAnnotation : nil
        let scale = scale
        let origin = origin

        Canvas { context, _ in
            context.translateBy(x: origin.x, y: origin.y)
            context.scaleBy(x: scale, y: scale)
            context.withCGContext { cg in
                EditorRenderer.draw(annotations, pixelated: pixelated, imageSize: imageSize, in: cg)
            }
            if let selected {
                let handles = selected.handles
                if !handles.contains(.start) {
                    let rect = selected.frame.insetBy(dx: -1 / scale, dy: -1 / scale)
                    context.stroke(Path(rect), with: .color(.accentColor),
                                   style: StrokeStyle(lineWidth: 1.5 / scale, dash: [5 / scale, 3 / scale]))
                }
                let r = 4.5 / scale
                for handle in handles {
                    let p = selected.point(of: handle)
                    let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                    context.fill(dot, with: .color(.white))
                    context.stroke(dot, with: .color(.accentColor), lineWidth: 1.5 / scale)
                }
            }
        }
        .contentShape(.rect)
        .gesture(dragGesture)
        // A cancelled gesture never calls onEnded; without this a stale isDragging would swallow the next click.
        .onChange(of: gestureDown) { _, down in
            if !down, isDragging { isDragging = false; doc.end(at: doc.lastPointForCancel) }
        }
        // NSCursor.set() gets reset by AppKit cursor rects on every mouse move, so let SwiftUI own the cursor.
        .pointerStyle(pointer)
        .onContinuousHover { phase in
            guard !isDragging, case .active(let location) = phase else { return }
            pointer = pointerStyle(at: imagePoint(location))
        }
        .onChange(of: scale, initial: true) { doc.viewScale = scale }
        .overlay(alignment: .topLeading) { cropOverlay }
        .overlay(alignment: .topLeading) { textEditor }
    }

    private func pointerStyle(at point: CGPoint) -> PointerStyle {
        if doc.tool != .crop {
            switch doc.handle(at: point) {
            case .topLeft: return .frameResize(position: .topLeading)
            case .top: return .frameResize(position: .top)
            case .topRight: return .frameResize(position: .topTrailing)
            case .right: return .frameResize(position: .trailing)
            case .bottomRight: return .frameResize(position: .bottomTrailing)
            case .bottom: return .frameResize(position: .bottom)
            case .bottomLeft: return .frameResize(position: .bottomLeading)
            case .left: return .frameResize(position: .leading)
            case .start, .end: return .rectSelection
            case nil: break
            }
            if doc.annotation(at: point) != nil { return .grabIdle }
        }
        switch doc.tool {
        case .select: return .default
        case .text: return .horizontalText
        default: return .rectSelection
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($gestureDown) { _, state, _ in state = true }
            .onChanged { value in
                let constrained = NSEvent.modifierFlags.contains(.shift)
                if !isDragging {
                    isDragging = true
                    doc.begin(at: imagePoint(value.startLocation))
                    if doc.isMovingSelection { pointer = .grabActive }
                }
                doc.update(to: imagePoint(value.location), constrained: constrained)
            }
            .onEnded { value in
                isDragging = false
                doc.end(at: imagePoint(value.location))
                pointer = pointerStyle(at: imagePoint(value.location))
                if doc.textEditing == nil { canvasFocused.wrappedValue = true }
            }
    }

    private func imagePoint(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - origin.x) / scale, y: (p.y - origin.y) / scale)
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
            .offset(x: origin.x, y: origin.y)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var textEditor: some View {
        if let editing = doc.textEditing {
            let fontSize = editing.fontSize * scale
            let pad = EditorRenderer.textPadding(fontSize: fontSize)
            // Grow with the text so it never wraps or clips; matches the width of the finished mark.
            let size = EditorRenderer.textBoxSize(editing.text, fontSize: editing.fontSize, filled: editing.filled)
            let lineHeight = EditorRenderer.textBoxSize("Ag", fontSize: editing.fontSize, filled: editing.filled).height * scale
            let textWidth = size.width * scale - pad.width * 2
            let textHeight = size.height * scale - pad.height * 2
            let lightText = editing.filled ? false : EditorRenderer.isLight(editing.color)
            // TextEditor keeps a 5pt line-fragment inset on each side; compensate so text lines up with the final mark.
            let inset: CGFloat = 5
            TextEditor(text: Binding(
                get: { doc.textEditing?.text ?? "" },
                set: { doc.textEditing?.text = $0 }
            ))
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .font(.system(size: fontSize, weight: .bold))
            .foregroundStyle(editing.filled ? .white : Color(nsColor: editing.color))
            .frame(width: max(fontSize * 12, textWidth + fontSize * 1.5) + inset * 2,
                   height: max(lineHeight * 3, textHeight + lineHeight * 0.5))
            .padding(.horizontal, max(pad.width * 2 - inset, 0))
            .padding(.vertical, pad.height * 2)
            .onKeyPress(.return, phases: .down) { press in
                // Shift+Return inserts a newline; plain Return commits.
                if press.modifiers.contains(.shift) { return .ignored }
                finishText()
                return .handled
            }
            .onKeyPress(.escape) { doc.escape(); canvasFocused.wrappedValue = true; return .handled }
            .background {
                // Backing is chosen for contrast with the text colour so the text stays readable on any screenshot.
                RoundedRectangle(cornerRadius: fontSize * 0.3)
                    .fill(editing.filled ? Color(nsColor: editing.color)
                          : lightText ? Color.black.opacity(0.65) : Color.white.opacity(0.9))
            }
            .overlay {
                RoundedRectangle(cornerRadius: fontSize * 0.3)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            .offset(x: origin.x + editing.origin.x * scale, y: origin.y + editing.origin.y * scale)
            .focused($textFocused)
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

// MARK: - Zoom

enum EditorZoom {
    static let steps: [CGFloat] = [0.1, 0.25, 0.33, 0.5, 0.67, 0.75, 1, 1.25, 1.5, 2, 3, 4]
    static let minZoom: CGFloat = 0.05

    /// Keeps the rendered canvas within GPU texture limits on very large images (e.g. full-page captures).
    static func maxZoom(for canvasSize: CGSize) -> CGFloat {
        max(minZoom, min(4, 12_000 / max(canvasSize.width, canvasSize.height, 1)))
    }

    static func clamp(_ value: CGFloat, max upper: CGFloat) -> CGFloat {
        min(max(value, minZoom), upper)
    }
}

private struct ZoomBar: View {
    @Binding var zoom: CGFloat?
    let fitScale: CGFloat
    let maxZoom: CGFloat

    var body: some View {
        let current = zoom ?? fitScale
        HStack(spacing: 6) {
            Text("Pinch to zoom · scroll to pan")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Zoom Out", systemImage: "minus.magnifyingglass") {
                zoom = EditorZoom.steps.last { $0 < current - 0.001 } ?? EditorZoom.minZoom
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(current <= EditorZoom.minZoom + 0.001)
            .help("Zoom Out (⌘−)")

            Menu("\(Int((current * 100).rounded()))%") {
                Button("Zoom to Fit") { zoom = nil }
                Divider()
                ForEach(EditorZoom.steps.filter { $0 <= maxZoom }, id: \.self) { step in
                    Button("\(Int((step * 100).rounded()))%") { zoom = step }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button("Zoom In", systemImage: "plus.magnifyingglass") {
                zoom = min(EditorZoom.steps.first { $0 > current + 0.001 } ?? maxZoom, maxZoom)
            }
            .keyboardShortcut("=", modifiers: .command)
            .disabled(current >= maxZoom - 0.001)
            .help("Zoom In (⌘+)")

            Button("Zoom to Fit", systemImage: "arrow.down.right.and.arrow.up.left") { zoom = nil }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(zoom == nil)
                .help("Zoom to Fit (⌘0)")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(.bar)
    }
}

// MARK: - Inspector

private struct BeautifyPanel: View {
    @Bindable var doc: EditorDocument
    @Bindable var settings: SettingsStore
    let copy: () -> Void
    let save: () -> Void
    let saveAs: () -> Void
    let copyText: () -> Void
    let pin: () -> Void
    let showInFinder: () -> Void

    var body: some View {
        Form {
            Section {
                Picker("Extra space", selection: $doc.extraSpace) {
                    ForEach(ExtraSpace.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Canvas")
            } footer: {
                Text("Adds blank room around the screenshot. You can draw marks and text anywhere on it, including outside the screenshot.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: $doc.beautify.enabled) {
                    Label("Beautify", systemImage: "sparkles")
                }
                .toggleStyle(.switch)
                Toggle("Auto-apply to new screenshots", isOn: $settings.autoApplyBeautify)
                    .font(.callout)
            } footer: {
                Text("Place the screenshot on a background with padding, rounded corners and a shadow. Your last style is remembered.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            BeautifyStyleControls(style: $doc.beautify, isEnabled: doc.beautify.enabled) {
                doc.beautify.enabled = true
            }

            Section("Export") {
                Button(settings.closeEditorAfterCopyOrSave ? "Copy & Close" : "Copy to Clipboard",
                       systemImage: "doc.on.doc", action: copy)
                Button(settings.closeEditorAfterCopyOrSave ? "Save & Close" : "Save",
                       systemImage: "square.and.arrow.down", action: save)
                Button("Save As…", systemImage: "square.and.arrow.down.on.square", action: saveAs)
                Button("Copy Text (OCR)", systemImage: "text.viewfinder", action: copyText)
                Button("Pin to Screen", systemImage: "pin", action: pin)
                Button("Show in Finder", systemImage: "folder", action: showInFinder)
            }
            .buttonStyle(.borderless)
        }
        .formStyle(.grouped)
    }
}

/// Background, padding, corners, shadow and aspect controls. Shared by the editor and Settings.
struct BeautifyStyleControls: View {
    @Binding var style: BeautifySettings
    var isEnabled = true
    var onPickPreset: (() -> Void)?

    @State private var importFailed = false
    private let library = BackgroundLibrary.shared
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        Section("Background") {
            Picker("Background", selection: binding(\.background)) {
                ForEach(BackgroundKind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch style.background {
            case .preset: presetGrid
            case .solid: ColorPicker("Colour", selection: colorBinding(\.solidColor), supportsOpacity: false)
            case .gradient: gradientControls
            case .image: imageControls
            }
        }

        Section("Layout") {
            LabeledContent("Padding") {
                Slider(value: $style.padding, in: 0.02...0.25)
            }
            LabeledContent("Corners") {
                Slider(value: $style.cornerRadius, in: 0...0.05)
            }
            Toggle("Shadow", isOn: $style.shadow)
            Picker("Aspect", selection: $style.aspect) {
                ForEach(AspectPreset.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .disabled(!isEnabled)
    }

    private var presetGrid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(GradientPreset.all) { preset in
                tile(selected: style.presetID == preset.id) {
                    LinearGradient(colors: preset.colors.map { Color(nsColor: $0) },
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                .help(preset.name)
                .onTapGesture { update { $0.presetID = preset.id } }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var gradientControls: some View {
        ColorPicker("From", selection: colorBinding(\.gradient.from), supportsOpacity: false)
        ColorPicker("To", selection: colorBinding(\.gradient.to), supportsOpacity: false)
        Picker("Direction", selection: binding(\.gradient.direction)) {
            ForEach(GradientDirection.allCases) { direction in
                Image(systemName: direction.symbol).help(direction.title).tag(direction)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var imageControls: some View {
        if !library.names.isEmpty {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(library.names, id: \.self) { name in
                    tile(selected: style.imageName == name) {
                        if let image = library.image(named: name) {
                            Image(decorative: image, scale: 1).resizable().scaledToFill()
                        } else {
                            Color.secondary.opacity(0.2)
                        }
                    }
                    .onTapGesture { update { $0.imageName = name } }
                    .contextMenu {
                        Button("Remove", role: .destructive) { library.remove(name) }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        Button("Choose Image…", systemImage: "photo", action: chooseImage)
        if importFailed {
            Text("Couldn't use that image.")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func tile(selected: Bool, @ViewBuilder content: () -> some View) -> some View {
        content()
            .frame(height: 36)
            .frame(maxWidth: .infinity)
            .clipShape(.rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(selected ? Color.accentColor : .primary.opacity(0.1), lineWidth: selected ? 2.5 : 1))
            .contentShape(.rect)
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let name = try library.importImage(from: url)
            importFailed = false
            update { $0.imageName = name }
        } catch {
            importFailed = true
        }
    }

    /// Applies a background change and turns Beautify on in the editor.
    private func update(_ change: (inout BeautifySettings) -> Void) {
        change(&style)
        onPickPreset?()
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<BeautifySettings, Value>) -> Binding<Value> {
        Binding(get: { style[keyPath: keyPath] }, set: { value in update { $0[keyPath: keyPath] = value } })
    }

    private func colorBinding(_ keyPath: WritableKeyPath<BeautifySettings, RGBColor>) -> Binding<Color> {
        Binding(get: { Color(nsColor: style[keyPath: keyPath].nsColor) },
                set: { color in update { $0[keyPath: keyPath] = RGBColor(NSColor(color)) } })
    }
}

/// SwiftUI twin of `EditorRenderer.drawBackground`, so previews match exported images.
struct BeautifyBackgroundView: View {
    let style: BeautifySettings

    var body: some View {
        switch style.resolvedBackground {
        case .gradient(let colors, let direction):
            let (start, end) = direction.points
            LinearGradient(colors: colors.map { Color(nsColor: $0) },
                           startPoint: UnitPoint(x: start.x, y: start.y), endPoint: UnitPoint(x: end.x, y: end.y))
        case .solid(let color):
            Color(nsColor: color)
        case .image(let image):
            GeometryReader { geo in
                let rect = EditorRenderer.aspectFillRect(for: CGSize(width: image.width, height: image.height),
                                                         in: CGRect(origin: .zero, size: geo.size))
                Image(decorative: image, scale: 1)
                    .resizable()
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
            .clipped()
        }
    }
}

private extension NSColor {
    func isApproximately(_ other: NSColor) -> Bool {
        guard let a = usingColorSpace(.sRGB), let b = other.usingColorSpace(.sRGB) else { return false }
        return abs(a.redComponent - b.redComponent) < 0.01 && abs(a.greenComponent - b.greenComponent) < 0.01
            && abs(a.blueComponent - b.blueComponent) < 0.01
    }
}
