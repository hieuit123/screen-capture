import AppKit
import Observation

enum EditorTool: String, CaseIterable, Identifiable {
    case select, crop, rectangle, ellipse, line, arrow, pencil, highlighter, text, pixelate, counter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: "Select & Move"
        case .crop: "Crop"
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .line: "Line"
        case .arrow: "Arrow"
        case .pencil: "Pencil"
        case .highlighter: "Highlighter"
        case .text: "Text"
        case .pixelate: "Pixelate"
        case .counter: "Step Number"
        }
    }

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .crop: "crop"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .line: "line.diagonal"
        case .arrow: "arrow.up.right"
        case .pencil: "pencil.tip"
        case .highlighter: "highlighter"
        case .text: "textformat"
        case .pixelate: "checkerboard.rectangle"
        case .counter: "1.circle"
        }
    }

    /// Single-key shortcut while the canvas is focused.
    var key: Character {
        switch self {
        case .select: "v"
        case .crop: "c"
        case .rectangle: "r"
        case .ellipse: "o"
        case .line: "l"
        case .arrow: "a"
        case .pencil: "p"
        case .highlighter: "h"
        case .text: "t"
        case .pixelate: "b"
        case .counter: "n"
        }
    }

    var usesColor: Bool { ![.select, .crop, .pixelate].contains(self) }
    var usesStroke: Bool { [.rectangle, .ellipse, .line, .arrow, .pencil, .highlighter].contains(self) }
    var usesFill: Bool { [.rectangle, .ellipse, .text].contains(self) }
    var usesTextSize: Bool { [.text, .counter].contains(self) }
}

enum StrokeSize: CGFloat, CaseIterable, Identifiable {
    case thin = 2, medium = 4, thick = 8
    var id: CGFloat { rawValue }
    var title: String {
        switch self {
        case .thin: "Thin"
        case .medium: "Medium"
        case .thick: "Thick"
        }
    }
}

enum TextSize: CGFloat, CaseIterable, Identifiable {
    case small = 16, medium = 24, large = 36
    var id: CGFloat { rawValue }
    var title: String {
        switch self {
        case .small: "S"
        case .medium: "M"
        case .large: "L"
        }
    }
}

enum AnnotationShape {
    case rectangle(CGRect)
    case ellipse(CGRect)
    case line(CGPoint, CGPoint)
    case arrow(CGPoint, CGPoint)
    case pencil([CGPoint])
    case highlighter([CGPoint])
    /// Top-left origin of the text box.
    case text(CGPoint, String)
    case pixelate(CGRect)
    case counter(CGPoint, Int)
}

/// A drawable mark on the screenshot. All geometry is in image pixels, top-left origin.
struct Annotation: Identifiable {
    let id: UUID
    var shape: AnnotationShape
    var color: NSColor
    var lineWidth: CGFloat
    var filled: Bool
    var fontSize: CGFloat

    init(id: UUID = UUID(), shape: AnnotationShape, color: NSColor, lineWidth: CGFloat, filled: Bool, fontSize: CGFloat) {
        self.id = id
        self.shape = shape
        self.color = color
        self.lineWidth = lineWidth
        self.filled = filled
        self.fontSize = fontSize
    }

    func offsetBy(dx: CGFloat, dy: CGFloat) -> Annotation {
        func move(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + dx, y: p.y + dy) }
        var copy = self
        switch shape {
        case .rectangle(let r): copy.shape = .rectangle(r.offsetBy(dx: dx, dy: dy))
        case .ellipse(let r): copy.shape = .ellipse(r.offsetBy(dx: dx, dy: dy))
        case .line(let a, let b): copy.shape = .line(move(a), move(b))
        case .arrow(let a, let b): copy.shape = .arrow(move(a), move(b))
        case .pencil(let pts): copy.shape = .pencil(pts.map(move))
        case .highlighter(let pts): copy.shape = .highlighter(pts.map(move))
        case .text(let p, let s): copy.shape = .text(move(p), s)
        case .pixelate(let r): copy.shape = .pixelate(r.offsetBy(dx: dx, dy: dy))
        case .counter(let p, let n): copy.shape = .counter(move(p), n)
        }
        return copy
    }

    var bounds: CGRect {
        switch shape {
        case .rectangle(let r), .ellipse(let r), .pixelate(let r):
            return r.insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2)
        case .line(let a, let b), .arrow(let a, let b):
            return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
                .insetBy(dx: -lineWidth * 2, dy: -lineWidth * 2)
        case .pencil(let pts), .highlighter(let pts):
            guard let first = pts.first else { return .null }
            var rect = CGRect(origin: first, size: .zero)
            for p in pts { rect = rect.union(CGRect(origin: p, size: .zero)) }
            return rect.insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2)
        case .text(let p, let s):
            return CGRect(origin: p, size: EditorRenderer.textBoxSize(s, fontSize: fontSize, filled: filled))
        case .counter(let p, _):
            let r = EditorRenderer.counterRadius(fontSize: fontSize)
            return CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
        }
    }

    func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        switch shape {
        case .line(let a, let b), .arrow(let a, let b):
            return Self.distance(point, toSegment: a, b) <= tolerance + lineWidth
        case .pencil(let pts), .highlighter(let pts):
            guard pts.count > 1 else {
                return pts.first.map { hypot($0.x - point.x, $0.y - point.y) <= tolerance + lineWidth } ?? false
            }
            return zip(pts, pts.dropFirst()).contains { Self.distance(point, toSegment: $0, $1) <= tolerance + lineWidth / 2 }
        default:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        }
    }

    private static func distance(_ p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}

// MARK: - Beautify

struct GradientPreset: Identifiable {
    let id: Int
    let name: String
    let colors: [NSColor]

    static let all: [GradientPreset] = [
        .init(id: 0, name: "Grape", colors: [.hex(0x8E2DE2), .hex(0x4A00E0)]),
        .init(id: 1, name: "Sunset", colors: [.hex(0xFF5F6D), .hex(0xFFC371)]),
        .init(id: 2, name: "Ocean", colors: [.hex(0x2193B0), .hex(0x6DD5ED)]),
        .init(id: 3, name: "Mint", colors: [.hex(0x11998E), .hex(0x38EF7D)]),
        .init(id: 4, name: "Candy", colors: [.hex(0xF857A6), .hex(0xFF5858)]),
        .init(id: 5, name: "Sky", colors: [.hex(0xA1C4FD), .hex(0xC2E9FB)]),
        .init(id: 6, name: "Peach", colors: [.hex(0xED4264), .hex(0xFFEDBC)]),
        .init(id: 7, name: "Midnight", colors: [.hex(0x232526), .hex(0x414345)]),
        .init(id: 8, name: "Snow", colors: [.hex(0xE6E9F0), .hex(0xEEF1F5)]),
    ]
}

enum AspectPreset: String, CaseIterable, Identifiable {
    case auto, wide, standard, square

    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: "Auto"
        case .wide: "16:9"
        case .standard: "4:3"
        case .square: "1:1"
        }
    }
    var ratio: CGFloat? {
        switch self {
        case .auto: nil
        case .wide: 16.0 / 9.0
        case .standard: 4.0 / 3.0
        case .square: 1
        }
    }
}

struct BeautifySettings: Equatable {
    var enabled = false
    var presetID = 0
    /// Fractions of the image's longer side.
    var padding: CGFloat = 0.08
    var cornerRadius: CGFloat = 0.012
    var shadow = true
    var aspect: AspectPreset = .auto

    var preset: GradientPreset { GradientPreset.all.first { $0.id == presetID } ?? GradientPreset.all[0] }
}

/// Where the screenshot sits inside the exported canvas.
struct CanvasLayout {
    let canvasSize: CGSize
    let imageRect: CGRect
    let cornerRadius: CGFloat
    let shadowRadius: CGFloat

    init(imageSize: CGSize, beautify: BeautifySettings) {
        guard beautify.enabled else {
            canvasSize = imageSize
            imageRect = CGRect(origin: .zero, size: imageSize)
            cornerRadius = 0
            shadowRadius = 0
            return
        }
        let longSide = max(imageSize.width, imageSize.height)
        let pad = (longSide * beautify.padding).rounded()
        var width = imageSize.width + pad * 2
        var height = imageSize.height + pad * 2
        if let ratio = beautify.aspect.ratio {
            if width / height < ratio { width = (height * ratio).rounded() } else { height = (width / ratio).rounded() }
        }
        canvasSize = CGSize(width: width, height: height)
        imageRect = CGRect(x: ((width - imageSize.width) / 2).rounded(), y: ((height - imageSize.height) / 2).rounded(),
                           width: imageSize.width, height: imageSize.height)
        cornerRadius = longSide * beautify.cornerRadius
        shadowRadius = beautify.shadow ? max(pad * 0.35, longSide * 0.01) : 0
    }
}

// MARK: - Document

@MainActor
@Observable
final class EditorDocument {
    struct TextEditing {
        var id: UUID?
        var origin: CGPoint
        var text: String
        var color: NSColor
        var fontSize: CGFloat
        var filled: Bool
    }

    private struct Snapshot {
        let image: CGImage
        let pixelated: CGImage?
        let annotations: [Annotation]
    }

    let fileURL: URL
    private(set) var image: CGImage
    private(set) var pixelated: CGImage?
    private(set) var annotations: [Annotation] = []
    var beautify = BeautifySettings() {
        didSet { if beautify != oldValue { isDirty = true } }
    }

    var tool: EditorTool = .arrow {
        didSet {
            guard tool != oldValue else { return }
            commitTextEditing()
            if tool != .select { selectedID = nil }
            if tool != .crop { cropRect = nil }
        }
    }
    private(set) var color: NSColor = .systemRed
    private(set) var strokeSize: StrokeSize = .medium
    private(set) var textSize: TextSize = .medium
    private(set) var filled = false

    var selectedID: UUID?
    private(set) var draft: Annotation?
    var cropRect: CGRect?
    var textEditing: TextEditing?
    private(set) var isDirty = false
    @ObservationIgnored var onSaved: ((URL) -> Void)?

    @ObservationIgnored private var undoStack: [Snapshot] = []
    @ObservationIgnored private var redoStack: [Snapshot] = []
    private(set) var canUndo = false
    private(set) var canRedo = false
    @ObservationIgnored private var dragStart: CGPoint?
    @ObservationIgnored private var lastPoint: CGPoint?
    @ObservationIgnored private var moveRecorded = false

    var imageSize: CGSize { CGSize(width: image.width, height: image.height) }
    var layout: CanvasLayout { CanvasLayout(imageSize: imageSize, beautify: beautify) }
    /// Scale factor so stroke/text sizes look the same on small and large screenshots.
    var unit: CGFloat { max(1, max(imageSize.width, imageSize.height) / 1600) }
    var selectedAnnotation: Annotation? { annotations.first { $0.id == selectedID } }
    var visibleAnnotations: [Annotation] {
        annotations.filter { $0.id != textEditing?.id } + (draft.map { [$0] } ?? [])
    }

    init(image: CGImage, fileURL: URL) {
        self.image = image
        self.fileURL = fileURL
        pixelated = Self.makePixelated(image)
    }

    convenience init?(url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return nil }
        self.init(image: image, fileURL: url)
    }

    // MARK: Style

    func setColor(_ newColor: NSColor) {
        color = newColor
        updateSelection { $0.color = newColor }
    }

    func setStrokeSize(_ size: StrokeSize) {
        strokeSize = size
        let unit = unit
        updateSelection { annotation in
            switch annotation.shape {
            case .highlighter: annotation.lineWidth = size.rawValue * unit * 5
            case .text, .counter, .pixelate: break
            default: annotation.lineWidth = size.rawValue * unit
            }
        }
    }

    func setFilled(_ value: Bool) {
        filled = value
        updateSelection { annotation in
            switch annotation.shape {
            case .rectangle, .ellipse, .text: annotation.filled = value
            default: break
            }
        }
    }

    func setTextSize(_ size: TextSize) {
        textSize = size
        let unit = unit
        updateSelection { annotation in
            switch annotation.shape {
            case .text, .counter: annotation.fontSize = size.rawValue * unit
            default: break
            }
        }
    }

    private func updateSelection(_ change: (inout Annotation) -> Void) {
        guard let index = annotations.firstIndex(where: { $0.id == selectedID }) else { return }
        pushUndo()
        change(&annotations[index])
    }

    // MARK: Undo

    private func pushUndo() {
        undoStack.append(Snapshot(image: image, pixelated: pixelated, annotations: annotations))
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
        isDirty = true
        syncUndoState()
    }

    func undo() {
        commitTextEditing()
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(Snapshot(image: image, pixelated: pixelated, annotations: annotations))
        restore(snapshot)
    }

    func redo() {
        commitTextEditing()
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(Snapshot(image: image, pixelated: pixelated, annotations: annotations))
        restore(snapshot)
    }

    private func restore(_ snapshot: Snapshot) {
        image = snapshot.image
        pixelated = snapshot.pixelated
        annotations = snapshot.annotations
        if !annotations.contains(where: { $0.id == selectedID }) { selectedID = nil }
        cropRect = nil
        isDirty = true
        syncUndoState()
    }

    private func syncUndoState() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    // MARK: Pointer interaction (image coordinates)

    func begin(at point: CGPoint) {
        commitTextEditing()
        dragStart = point
        lastPoint = point
        moveRecorded = false

        switch tool {
        case .select:
            selectedID = hitTest(point)?.id
        case .crop:
            cropRect = nil
        case .pencil:
            draft = newAnnotation(.pencil([point]))
        case .highlighter:
            draft = newAnnotation(.highlighter([point]))
        default:
            draft = nil
        }
    }

    func update(to point: CGPoint, constrained: Bool) {
        guard let start = dragStart else { return }
        defer { lastPoint = point }

        switch tool {
        case .select:
            guard let id = selectedID, let last = lastPoint,
                  let index = annotations.firstIndex(where: { $0.id == id }) else { return }
            if !moveRecorded {
                pushUndo()
                moveRecorded = true
            }
            annotations[index] = annotations[index].offsetBy(dx: point.x - last.x, dy: point.y - last.y)
        case .crop:
            cropRect = Self.rect(from: start, to: point, square: constrained)
                .intersection(CGRect(origin: .zero, size: imageSize))
        case .rectangle:
            draft = newAnnotation(.rectangle(Self.rect(from: start, to: point, square: constrained)))
        case .ellipse:
            draft = newAnnotation(.ellipse(Self.rect(from: start, to: point, square: constrained)))
        case .pixelate:
            draft = newAnnotation(.pixelate(Self.rect(from: start, to: point, square: constrained)))
        case .line:
            draft = newAnnotation(.line(start, constrained ? Self.snap(start, point) : point))
        case .arrow:
            draft = newAnnotation(.arrow(start, constrained ? Self.snap(start, point) : point))
        case .pencil, .highlighter:
            guard var current = draft else { return }
            switch current.shape {
            case .pencil(var pts):
                if let last = pts.last, hypot(last.x - point.x, last.y - point.y) < unit { return }
                pts.append(point)
                current.shape = .pencil(pts)
            case .highlighter(var pts):
                if let last = pts.last, hypot(last.x - point.x, last.y - point.y) < unit { return }
                pts.append(point)
                current.shape = .highlighter(pts)
            default:
                break
            }
            draft = current
        case .text, .counter:
            break
        }
    }

    func end(at point: CGPoint) {
        let moved = dragStart.map { hypot($0.x - point.x, $0.y - point.y) > 3 * unit } ?? false
        dragStart = nil
        lastPoint = nil

        switch tool {
        case .select:
            break
        case .crop:
            if let rect = cropRect, rect.width < 8 || rect.height < 8 { cropRect = nil }
        case .text:
            if let existing = hitTest(point), case .text(let origin, let string) = existing.shape {
                selectedID = existing.id
                textEditing = TextEditing(id: existing.id, origin: origin, text: string, color: existing.color,
                                          fontSize: existing.fontSize, filled: existing.filled)
            } else {
                let fontSize = textSize.rawValue * unit
                textEditing = TextEditing(id: nil, origin: CGPoint(x: point.x, y: point.y - fontSize * 0.7), text: "",
                                          color: color, fontSize: fontSize, filled: filled)
            }
        case .counter:
            let next = (annotations.compactMap { annotation -> Int? in
                if case .counter(_, let n) = annotation.shape { return n }
                return nil
            }.max() ?? 0) + 1
            pushUndo()
            annotations.append(newAnnotation(.counter(point, next)))
        case .pencil, .highlighter:
            if let draft {
                pushUndo()
                annotations.append(draft)
            }
            draft = nil
        default:
            if let draft, moved {
                pushUndo()
                annotations.append(draft)
            }
            draft = nil
        }
    }

    private func newAnnotation(_ shape: AnnotationShape) -> Annotation {
        var isHighlighter = false
        if case .highlighter = shape { isHighlighter = true }
        return Annotation(shape: shape, color: color,
                          lineWidth: strokeSize.rawValue * unit * (isHighlighter ? 5 : 1),
                          filled: filled, fontSize: textSize.rawValue * unit)
    }

    func hitTest(_ point: CGPoint) -> Annotation? {
        annotations.reversed().first { $0.hitTest(point, tolerance: 6 * unit) }
    }

    // MARK: Text

    func commitTextEditing() {
        guard let editing = textEditing else { return }
        textEditing = nil
        let trimmed = editing.text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let id = editing.id, let index = annotations.firstIndex(where: { $0.id == id }) {
            guard case .text(_, let old) = annotations[index].shape, old != editing.text || trimmed.isEmpty else { return }
            pushUndo()
            if trimmed.isEmpty {
                annotations.remove(at: index)
                selectedID = nil
            } else {
                annotations[index].shape = .text(editing.origin, editing.text)
            }
        } else if !trimmed.isEmpty {
            pushUndo()
            annotations.append(Annotation(shape: .text(editing.origin, editing.text), color: editing.color,
                                          lineWidth: 0, filled: editing.filled, fontSize: editing.fontSize))
        }
    }

    // MARK: Commands

    func deleteSelection() {
        guard let index = annotations.firstIndex(where: { $0.id == selectedID }) else { return }
        pushUndo()
        annotations.remove(at: index)
        selectedID = nil
    }

    func nudgeSelection(dx: CGFloat, dy: CGFloat) {
        guard let index = annotations.firstIndex(where: { $0.id == selectedID }) else { return }
        pushUndo()
        annotations[index] = annotations[index].offsetBy(dx: dx * unit, dy: dy * unit)
    }

    func escape() {
        if textEditing != nil { textEditing = nil; return }
        if cropRect != nil { cropRect = nil; return }
        selectedID = nil
    }

    func applyCrop() {
        guard let rect = cropRect?.integral.intersection(CGRect(origin: .zero, size: imageSize)),
              rect.width >= 8, rect.height >= 8, let cropped = image.cropping(to: rect) else { return }
        pushUndo()
        image = cropped
        pixelated = Self.makePixelated(cropped)
        annotations = annotations.map { $0.offsetBy(dx: -rect.minX, dy: -rect.minY) }
        cropRect = nil
        selectedID = nil
    }

    // MARK: Output

    func renderOutput() -> CGImage? {
        commitTextEditing()
        return EditorRenderer.render(image: image, pixelated: pixelated, annotations: annotations, beautify: beautify)
    }

    func save(to url: URL? = nil) async throws {
        guard let output = renderOutput() else { throw CocoaError(.fileWriteUnknown) }
        let target = url ?? fileURL
        let format = ImageFormat.from(extension: target.pathExtension)
        try await Task.detached(priority: .userInitiated) {
            try ScreenshotService.write(output, to: target, format: format)
        }.value
        if target == fileURL { isDirty = false }
        onSaved?(target)
    }

    func copyToPasteboard() {
        guard let output = renderOutput() else { return }
        ScreenshotService.copyToPasteboard(output)
    }

    // MARK: Helpers

    private static func rect(from a: CGPoint, to b: CGPoint, square: Bool) -> CGRect {
        var dx = b.x - a.x, dy = b.y - a.y
        if square {
            let side = max(abs(dx), abs(dy))
            dx = dx < 0 ? -side : side
            dy = dy < 0 ? -side : side
        }
        return CGRect(x: min(a.x, a.x + dx), y: min(a.y, a.y + dy), width: abs(dx), height: abs(dy))
    }

    /// Snaps a line to the nearest 45° angle.
    private static func snap(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = hypot(dx, dy)
        let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
        return CGPoint(x: a.x + cos(angle) * length, y: a.y + sin(angle) * length)
    }

    /// Low-resolution copy of the image; drawing it scaled up without interpolation gives a mosaic.
    private static func makePixelated(_ image: CGImage) -> CGImage? {
        let block = max(8, CGFloat(max(image.width, image.height)) / 120)
        let width = max(1, Int(CGFloat(image.width) / block))
        let height = max(1, Int(CGFloat(image.height) / block))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

extension ImageFormat {
    static func from(extension ext: String) -> ImageFormat {
        switch ext.lowercased() {
        case "jpg", "jpeg": .jpeg
        case "heic": .heic
        default: .png
        }
    }
}

extension NSColor {
    static func hex(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}
