import AppKit
import Observation

enum EditorTool: String, CaseIterable, Identifiable {
    case select, text, arrow, blackout, rectangle, ellipse, line, pencil, highlighter, pixelate, counter, crop

    /// Tools that key 4 cycles through; the first one is the default.
    static let shapes: [EditorTool] = [.rectangle, .ellipse, .line]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: "Select & Move"
        case .crop: "Crop"
        case .blackout: "Black Box"
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
        case .blackout: "rectangle.fill"
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
        case .blackout: "k"
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

    /// Number-row shortcut: 1 text, 2 arrow, 3 black box, 4 shapes.
    var numberKey: Character? {
        switch self {
        case .text: "1"
        case .arrow: "2"
        case .blackout: "3"
        case .rectangle, .ellipse, .line: "4"
        default: nil
        }
    }

    var usesColor: Bool { ![.select, .crop, .pixelate, .blackout].contains(self) }
    var usesStroke: Bool { [.rectangle, .ellipse, .line, .arrow, .pencil, .highlighter].contains(self) }
    var usesBorder: Bool { [.rectangle, .ellipse, .line, .arrow, .pencil].contains(self) }
    var usesFill: Bool { [.rectangle, .ellipse, .text].contains(self) }
    var usesTextSize: Bool { [.text, .counter].contains(self) }
    /// One-shot tools: after a mark is finished the editor switches back to Select (V).
    var returnsToSelect: Bool { [.text, .arrow, .blackout, .rectangle, .ellipse, .line].contains(self) }
}

enum StrokeSize: CGFloat, CaseIterable, Identifiable {
    case thin = 3, medium = 6, thick = 10
    var id: CGFloat { rawValue }
    var title: String {
        switch self {
        case .thin: "Thin"
        case .medium: "Medium"
        case .thick: "Thick"
        }
    }

    /// Highlighter strokes are this many times wider than the selected size.
    static let highlighterFactor: CGFloat = 3.5
}

/// Outline drawn around shapes so they stand out on any background.
enum BorderStyle: String, CaseIterable, Identifiable {
    case none, white, black
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var color: NSColor? {
        switch self {
        case .none: nil
        case .white: .white
        case .black: .black
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
    case blackout(CGRect)
    case counter(CGPoint, Int)
}

/// A drag handle on the selected annotation.
enum EditHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left, start, end

    /// Position inside the frame as fractions of its size; nil for line endpoints.
    var unitPoint: CGPoint? {
        switch self {
        case .topLeft: CGPoint(x: 0, y: 0)
        case .top: CGPoint(x: 0.5, y: 0)
        case .topRight: CGPoint(x: 1, y: 0)
        case .right: CGPoint(x: 1, y: 0.5)
        case .bottomRight: CGPoint(x: 1, y: 1)
        case .bottom: CGPoint(x: 0.5, y: 1)
        case .bottomLeft: CGPoint(x: 0, y: 1)
        case .left: CGPoint(x: 0, y: 0.5)
        case .start, .end: nil
        }
    }

    var isCorner: Bool { [.topLeft, .topRight, .bottomRight, .bottomLeft].contains(self) }
}

/// A drawable mark on the screenshot. All geometry is in image pixels, top-left origin.
struct Annotation: Identifiable {
    let id: UUID
    var shape: AnnotationShape
    var color: NSColor
    var lineWidth: CGFloat
    var filled: Bool
    var fontSize: CGFloat
    var borderColor: NSColor?

    init(id: UUID = UUID(), shape: AnnotationShape, color: NSColor, lineWidth: CGFloat, filled: Bool, fontSize: CGFloat,
         borderColor: NSColor? = nil) {
        self.id = id
        self.shape = shape
        self.color = color
        self.lineWidth = lineWidth
        self.filled = filled
        self.fontSize = fontSize
        self.borderColor = Self.supportsBorder(shape) ? borderColor : nil
    }

    var supportsBorder: Bool { Self.supportsBorder(shape) }

    /// The tool that draws this kind of mark; drives the style bar while it's selected.
    var tool: EditorTool {
        switch shape {
        case .rectangle: .rectangle
        case .ellipse: .ellipse
        case .line: .line
        case .arrow: .arrow
        case .pencil: .pencil
        case .highlighter: .highlighter
        case .text: .text
        case .pixelate: .pixelate
        case .blackout: .blackout
        case .counter: .counter
        }
    }

    private static func supportsBorder(_ shape: AnnotationShape) -> Bool {
        switch shape {
        case .rectangle, .ellipse, .line, .arrow, .pencil: true
        default: false
        }
    }

    /// Width of the outline on each side of the stroke.
    var borderWidth: CGFloat { borderColor == nil ? 0 : max(1, lineWidth * 0.35) }

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
        case .blackout(let r): copy.shape = .blackout(r.offsetBy(dx: dx, dy: dy))
        case .counter(let p, let n): copy.shape = .counter(move(p), n)
        }
        return copy
    }

    var bounds: CGRect {
        switch shape {
        case .rectangle(let r), .ellipse(let r), .pixelate(let r), .blackout(let r):
            return r.insetBy(dx: -(lineWidth / 2 + borderWidth), dy: -(lineWidth / 2 + borderWidth))
        case .line(let a, let b), .arrow(let a, let b):
            return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
                .insetBy(dx: -lineWidth * 2, dy: -lineWidth * 2)
        case .pencil(let pts), .highlighter(let pts):
            guard let first = pts.first else { return .null }
            var rect = CGRect(origin: first, size: .zero)
            for p in pts { rect = rect.union(CGRect(origin: p, size: .zero)) }
            return rect.insetBy(dx: -(lineWidth / 2 + borderWidth), dy: -(lineWidth / 2 + borderWidth))
        case .text(let p, let s):
            return CGRect(origin: p, size: EditorRenderer.textBoxSize(s, fontSize: fontSize, filled: filled))
        case .counter(let p, _):
            let r = EditorRenderer.counterRadius(fontSize: fontSize)
            return CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
        }
    }

    /// The rectangle that resize handles act on.
    var frame: CGRect {
        switch shape {
        case .rectangle(let r), .ellipse(let r), .pixelate(let r), .blackout(let r): r
        case .pencil, .highlighter: bounds.insetBy(dx: lineWidth / 2 + borderWidth, dy: lineWidth / 2 + borderWidth)
        default: bounds
        }
    }

    var handles: [EditHandle] {
        switch shape {
        case .line, .arrow: [.start, .end]
        case .text, .counter: [.topLeft, .topRight, .bottomRight, .bottomLeft]
        default: [.topLeft, .top, .topRight, .right, .bottomRight, .bottom, .bottomLeft, .left]
        }
    }

    func point(of handle: EditHandle) -> CGPoint {
        switch (handle, shape) {
        case (.start, .line(let a, _)), (.start, .arrow(let a, _)): return a
        case (.end, .line(_, let b)), (.end, .arrow(_, let b)): return b
        default:
            let f = frame, u = handle.unitPoint ?? .zero
            return CGPoint(x: f.minX + f.width * u.x, y: f.minY + f.height * u.y)
        }
    }

    func handle(at p: CGPoint, tolerance: CGFloat) -> EditHandle? {
        let distances = handles.map { handle in
            let h = point(of: handle)
            return (handle, max(abs(h.x - p.x), abs(h.y - p.y)))
        }
        return distances.filter { $0.1 <= tolerance }.min { $0.1 < $1.1 }?.0
    }

    /// A copy with `handle` dragged to `target`. Text and step numbers always scale proportionally;
    /// `uniform` (Shift) does the same for corner handles of other shapes.
    func resized(_ handle: EditHandle, to target: CGPoint, uniform: Bool) -> Annotation {
        var copy = self
        switch (handle, shape) {
        case (.start, .line(_, let b)): copy.shape = .line(target, b)
        case (.start, .arrow(_, let b)): copy.shape = .arrow(target, b)
        case (.end, .line(let a, _)): copy.shape = .line(a, target)
        case (.end, .arrow(let a, _)): copy.shape = .arrow(a, target)
        default:
            guard let u = handle.unitPoint else { return self }
            let f = frame
            var isTextLike = false
            switch shape {
            case .text, .counter: isTextLike = true
            default: break
            }
            var scale: CGFloat = 1
            let rect: CGRect
            if (isTextLike || uniform), handle.isCorner, f.width > 0, f.height > 0 {
                let anchor = CGPoint(x: f.minX + f.width * (1 - u.x), y: f.minY + f.height * (1 - u.y))
                scale = max(0.2, max(abs(target.x - anchor.x) / f.width, abs(target.y - anchor.y) / f.height))
                let w = f.width * scale, h = f.height * scale
                rect = CGRect(x: u.x == 0 ? anchor.x - w : anchor.x, y: u.y == 0 ? anchor.y - h : anchor.y, width: w, height: h)
            } else {
                var minX = f.minX, maxX = f.maxX, minY = f.minY, maxY = f.maxY
                if u.x == 0 { minX = target.x } else if u.x == 1 { maxX = target.x }
                if u.y == 0 { minY = target.y } else if u.y == 1 { maxY = target.y }
                rect = CGRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))
            }
            func map(_ p: CGPoint) -> CGPoint {
                CGPoint(x: f.width > 0 ? rect.minX + (p.x - f.minX) * rect.width / f.width : p.x + rect.minX - f.minX,
                        y: f.height > 0 ? rect.minY + (p.y - f.minY) * rect.height / f.height : p.y + rect.minY - f.minY)
            }
            switch shape {
            case .rectangle: copy.shape = .rectangle(rect)
            case .ellipse: copy.shape = .ellipse(rect)
            case .pixelate: copy.shape = .pixelate(rect)
            case .blackout: copy.shape = .blackout(rect)
            case .pencil(let pts): copy.shape = .pencil(pts.map(map))
            case .highlighter(let pts): copy.shape = .highlighter(pts.map(map))
            case .text(_, let s):
                copy.shape = .text(rect.origin, s)
                copy.fontSize = fontSize * scale
            case .counter(_, let n):
                copy.shape = .counter(CGPoint(x: rect.midX, y: rect.midY), n)
                copy.fontSize = fontSize * scale
            case .line, .arrow:
                break
            }
        }
        return copy
    }

    /// `interior: false` makes outlined rectangles and ellipses hit only near their border,
    /// so drawing tools can still start new marks inside them.
    func hitTest(_ point: CGPoint, tolerance: CGFloat, interior: Bool = true) -> Bool {
        switch shape {
        case .rectangle(let r) where !filled && !interior:
            let band = tolerance + lineWidth / 2
            return r.insetBy(dx: -band, dy: -band).contains(point) && !r.insetBy(dx: band, dy: band).contains(point)
        case .ellipse(let r) where !filled && !interior && r.width > 0 && r.height > 0:
            let a = r.width / 2, b = r.height / 2
            let d = hypot((point.x - r.midX) / a, (point.y - r.midY) / b)
            return abs(d - 1) * min(a, b) <= tolerance + lineWidth / 2
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

enum AspectPreset: String, CaseIterable, Identifiable, Codable {
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

enum BackgroundKind: String, CaseIterable, Identifiable, Codable {
    case preset, solid, gradient, image

    var id: String { rawValue }
    var title: String {
        switch self {
        case .preset: "Presets"
        case .solid: "Solid"
        case .gradient: "Gradient"
        case .image: "Image"
        }
    }
}

/// An opaque sRGB colour that can be persisted.
struct RGBColor: Codable, Equatable {
    var hex: UInt32

    init(hex: UInt32) { self.hex = hex }

    init(_ color: NSColor) {
        let rgb = color.usingColorSpace(.sRGB) ?? .black
        func byte(_ v: CGFloat) -> UInt32 { UInt32((min(max(v, 0), 1) * 255).rounded()) }
        hex = byte(rgb.redComponent) << 16 | byte(rgb.greenComponent) << 8 | byte(rgb.blueComponent)
    }

    var nsColor: NSColor { .hex(hex) }
}

enum GradientDirection: String, CaseIterable, Identifiable, Codable {
    case diagonalDown, horizontal, vertical, diagonalUp

    var id: String { rawValue }
    var title: String {
        switch self {
        case .diagonalDown: "Diagonal down"
        case .horizontal: "Horizontal"
        case .vertical: "Vertical"
        case .diagonalUp: "Diagonal up"
        }
    }
    var symbol: String {
        switch self {
        case .diagonalDown: "arrow.down.right"
        case .horizontal: "arrow.right"
        case .vertical: "arrow.down"
        case .diagonalUp: "arrow.up.right"
        }
    }
    /// Start and end as unit points with a top-left origin.
    var points: (start: CGPoint, end: CGPoint) {
        switch self {
        case .diagonalDown: (CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1))
        case .horizontal: (CGPoint(x: 0, y: 0.5), CGPoint(x: 1, y: 0.5))
        case .vertical: (CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 1))
        case .diagonalUp: (CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 0))
        }
    }
}

struct CustomGradient: Codable, Equatable {
    var from = RGBColor(hex: 0x4A00E0)
    var to = RGBColor(hex: 0xFF5F6D)
    var direction: GradientDirection = .diagonalDown
}

/// What the background resolves to when drawn.
enum ResolvedBackground {
    case gradient([NSColor], GradientDirection)
    case solid(NSColor)
    case image(CGImage)
}

struct BeautifySettings: Equatable, Codable {
    var enabled = false
    var background: BackgroundKind = .preset
    var presetID = 0
    var solidColor = RGBColor(hex: 0x1E1E1E)
    var gradient = CustomGradient()
    /// File name inside `BackgroundLibrary`.
    var imageName: String?
    /// Fractions of the image's longer side.
    var padding: CGFloat = 0.08
    var cornerRadius: CGFloat = 0.012
    var shadow = true
    var aspect: AspectPreset = .auto

    init() {}

    // Styles saved before custom backgrounds existed lack the newer keys.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = BeautifySettings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        background = try c.decodeIfPresent(BackgroundKind.self, forKey: .background) ?? defaults.background
        presetID = try c.decodeIfPresent(Int.self, forKey: .presetID) ?? defaults.presetID
        solidColor = try c.decodeIfPresent(RGBColor.self, forKey: .solidColor) ?? defaults.solidColor
        gradient = try c.decodeIfPresent(CustomGradient.self, forKey: .gradient) ?? defaults.gradient
        imageName = try c.decodeIfPresent(String.self, forKey: .imageName)
        padding = try c.decodeIfPresent(CGFloat.self, forKey: .padding) ?? defaults.padding
        cornerRadius = try c.decodeIfPresent(CGFloat.self, forKey: .cornerRadius) ?? defaults.cornerRadius
        shadow = try c.decodeIfPresent(Bool.self, forKey: .shadow) ?? defaults.shadow
        aspect = try c.decodeIfPresent(AspectPreset.self, forKey: .aspect) ?? defaults.aspect
    }

    var preset: GradientPreset { GradientPreset.all.first { $0.id == presetID } ?? GradientPreset.all[0] }

    /// The background to draw. A missing image falls back to the first preset.
    @MainActor
    var resolvedBackground: ResolvedBackground {
        switch background {
        case .preset:
            return .gradient(preset.colors, .diagonalDown)
        case .solid:
            return .solid(solidColor.nsColor)
        case .gradient:
            return .gradient([gradient.from.nsColor, gradient.to.nsColor], gradient.direction)
        case .image:
            if let imageName, let image = BackgroundLibrary.shared.image(named: imageName) { return .image(image) }
            return .gradient(GradientPreset.all[0].colors, .diagonalDown)
        }
    }

    /// The same style with Beautify switched on.
    var applied: BeautifySettings {
        var copy = self
        copy.enabled = true
        return copy
    }
}

/// Where the screenshot sits inside the exported canvas.
/// Blank room added around the screenshot so marks can extend past its edges.
enum ExtraSpace: String, CaseIterable, Identifiable {
    case none, small, medium, large

    var id: Self { self }

    /// Fraction of the image's longer side added on every edge.
    var fraction: CGFloat {
        switch self {
        case .none: 0
        case .small: 0.1
        case .medium: 0.2
        case .large: 0.35
        }
    }

    var title: String {
        switch self {
        case .none: "None"
        case .small: "S"
        case .medium: "M"
        case .large: "L"
        }
    }
}

struct CanvasLayout {
    let canvasSize: CGSize
    let imageRect: CGRect
    let cornerRadius: CGFloat
    let shadowRadius: CGFloat

    init(imageSize: CGSize, beautify: BeautifySettings, extraSpace: ExtraSpace = .none) {
        let longSide = max(imageSize.width, imageSize.height)
        let extra = (longSide * extraSpace.fraction).rounded()
        guard beautify.enabled else {
            canvasSize = CGSize(width: imageSize.width + extra * 2, height: imageSize.height + extra * 2)
            imageRect = CGRect(x: extra, y: extra, width: imageSize.width, height: imageSize.height)
            cornerRadius = 0
            shadowRadius = 0
            return
        }
        let pad = (longSide * beautify.padding).rounded() + extra
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

    private enum DragMode {
        case none, draw, move
        case resize(EditHandle, Annotation)
    }

    let fileURL: URL
    private(set) var image: CGImage {
        didSet { ocrLines = nil; ocrTask?.cancel(); ocrTask = nil; ocrHighlight = nil }
    }
    private(set) var pixelated: CGImage?
    private(set) var annotations: [Annotation] = []
    var beautify = BeautifySettings() {
        didSet {
            guard beautify != oldValue else { return }
            isDirty = true
            onBeautifyChanged?(beautify)
        }
    }
    /// Session-only: extends the canvas past the screenshot so marks can go outside it.
    var extraSpace: ExtraSpace = .none {
        didSet { if extraSpace != oldValue { isDirty = true } }
    }
    /// Lets the app remember the last Beautify style as the default for new screenshots.
    @ObservationIgnored var onBeautifyChanged: ((BeautifySettings) -> Void)?

    /// Every screenshot starts with nothing drawn-with: Select, where double-clicking text copies it (OCR).
    var tool: EditorTool = .select {
        didSet {
            guard tool != oldValue else { return }
            commitTextEditing()
            if tool != .select { selectedID = nil }
            if tool != .crop { cropRect = nil }
            if EditorTool.shapes.contains(tool) { lastShape = tool }
        }
    }
    private(set) var lastShape: EditorTool = .rectangle
    private(set) var color: NSColor = .systemRed
    private(set) var strokeSize: StrokeSize = .medium
    private(set) var borderStyle: BorderStyle = .white
    private(set) var textSize: TextSize = .medium
    private(set) var filled = false

    var selectedID: UUID?
    private(set) var draft: Annotation?
    var cropRect: CGRect?
    var textEditing: TextEditing?
    /// The line just copied by a double-click (image space); shown briefly as feedback.
    private(set) var ocrHighlight: CGRect?
    /// Reports the outcome of a double-click OCR copy (for a toast).
    @ObservationIgnored var onTextCopied: ((String) -> Void)?
    @ObservationIgnored private var ocrLines: [TextRecognizer.Line]?
    @ObservationIgnored private var ocrTask: Task<Void, Never>?
    private(set) var isDirty = false
    @ObservationIgnored var onSaved: ((URL) -> Void)?

    @ObservationIgnored private var undoStack: [Snapshot] = []
    @ObservationIgnored private var redoStack: [Snapshot] = []
    private(set) var canUndo = false
    private(set) var canRedo = false
    @ObservationIgnored private var dragStart: CGPoint?
    @ObservationIgnored private var lastPoint: CGPoint?
    @ObservationIgnored private var moveRecorded = false
    @ObservationIgnored private var dragMode = DragMode.none
    var isMovingSelection: Bool { if case .move = dragMode { true } else { false } }
    @ObservationIgnored private var lastClick: (time: TimeInterval, point: CGPoint)?
    /// On-screen points per image pixel; keeps hit areas a constant size on screen.
    @ObservationIgnored var viewScale: CGFloat = 1

    var imageSize: CGSize { CGSize(width: image.width, height: image.height) }
    var layout: CanvasLayout { CanvasLayout(imageSize: imageSize, beautify: beautify, extraSpace: extraSpace) }
    /// Scale factor so stroke/text sizes look the same on small and large screenshots.
    var unit: CGFloat { max(1, max(imageSize.width, imageSize.height) / 1600) }
    var selectedAnnotation: Annotation? { annotations.first { $0.id == selectedID } }
    var visibleAnnotations: [Annotation] {
        annotations.filter { $0.id != textEditing?.id } + (draft.map { [$0] } ?? [])
    }

    /// `beautify` is the starting style; it does not count as an unsaved change.
    init(image: CGImage, fileURL: URL, beautify: BeautifySettings = BeautifySettings()) {
        self.image = image
        self.fileURL = fileURL
        self.beautify = beautify
        pixelated = Self.makePixelated(image)
        // @Observable routes init assignments through didSet; the starting style isn't an edit.
        isDirty = false
    }

    convenience init?(url: URL, beautify: BeautifySettings = BeautifySettings()) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return nil }
        self.init(image: image, fileURL: url, beautify: beautify)
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
            case .highlighter: annotation.lineWidth = size.rawValue * unit * StrokeSize.highlighterFactor
            case .text, .counter, .pixelate, .blackout: break
            default: annotation.lineWidth = size.rawValue * unit
            }
        }
    }

    func setBorderStyle(_ style: BorderStyle) {
        borderStyle = style
        updateSelection { annotation in
            if annotation.supportsBorder { annotation.borderColor = style.color }
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

    /// Click a mark to select it, drag it to move, drag a handle to resize, double-click text to edit it.
    /// Clicking empty space draws with the current tool.
    var lastPointForCancel: CGPoint { lastPoint ?? .zero }

    func begin(at point: CGPoint) {
        let now = ProcessInfo.processInfo.systemUptime
        let isDoubleClick = lastClick.map {
            now - $0.time <= NSEvent.doubleClickInterval && hypot($0.point.x - point.x, $0.point.y - point.y) <= 5 / viewScale
        } ?? false
        lastClick = isDoubleClick ? nil : (now, point)

        commitTextEditing()
        dragStart = point
        lastPoint = point
        moveRecorded = false
        draft = nil

        if tool != .crop {
            if let selected = selectedAnnotation, let handle = handle(at: point) {
                dragMode = .resize(handle, selected)
                return
            }
            if let hit = annotation(at: point) {
                selectedID = hit.id
                if isDoubleClick, case .text(let origin, let string) = hit.shape {
                    textEditing = TextEditing(id: hit.id, origin: origin, text: string, color: hit.color,
                                              fontSize: hit.fontSize, filled: hit.filled)
                    dragMode = .none
                } else {
                    dragMode = .move
                }
                return
            }
        }

        selectedID = nil
        dragMode = tool == .select ? .none : .draw
        if tool == .select {
            prepareOCR()
            if isDoubleClick { copyText(at: point) }
        }
        switch tool {
        case .crop:
            cropRect = nil
        case .pencil:
            draft = newAnnotation(.pencil([point]))
        case .highlighter:
            draft = newAnnotation(.highlighter([point]))
        default:
            break
        }
    }

    func update(to point: CGPoint, constrained: Bool) {
        guard let start = dragStart, let last = lastPoint else { return }
        defer { lastPoint = point }

        switch dragMode {
        case .none:
            return
        case .move:
            guard point != last, let index = annotations.firstIndex(where: { $0.id == selectedID }) else { return }
            recordMoveUndo()
            annotations[index] = annotations[index].offsetBy(dx: point.x - last.x, dy: point.y - last.y)
            return
        case .resize(let handle, let original):
            guard point != last, let index = annotations.firstIndex(where: { $0.id == original.id }) else { return }
            recordMoveUndo()
            let origin = original.point(of: handle)
            var target = CGPoint(x: origin.x + point.x - start.x, y: origin.y + point.y - start.y)
            if constrained, handle == .start || handle == .end {
                target = Self.snap(original.point(of: handle == .start ? .end : .start), target)
            }
            annotations[index] = original.resized(handle, to: target, uniform: constrained)
            return
        case .draw:
            break
        }

        switch tool {
        case .select:
            break
        case .crop:
            cropRect = Self.rect(from: start, to: point, square: constrained)
                .intersection(CGRect(origin: .zero, size: imageSize))
        case .rectangle:
            draft = newAnnotation(.rectangle(Self.rect(from: start, to: point, square: constrained)))
        case .ellipse:
            draft = newAnnotation(.ellipse(Self.rect(from: start, to: point, square: constrained)))
        case .pixelate:
            draft = newAnnotation(.pixelate(Self.rect(from: start, to: point, square: constrained)))
        case .blackout:
            draft = newAnnotation(.blackout(Self.rect(from: start, to: point, square: constrained)))
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
        let mode = dragMode
        dragMode = .none
        guard case .draw = mode else { return }

        switch tool {
        case .select:
            break
        case .crop:
            if let rect = cropRect, rect.width < 8 || rect.height < 8 { cropRect = nil }
        case .text:
            let fontSize = textSize.rawValue * unit
            textEditing = TextEditing(id: nil, origin: CGPoint(x: point.x, y: point.y - fontSize * 0.7), text: "",
                                      color: color, fontSize: fontSize, filled: filled)
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
                if tool.returnsToSelect { tool = .select }
                selectedID = draft.id
            }
            draft = nil
        }
    }

    // MARK: OCR (double-click empty space in Select)

    /// Starts recognizing the screenshot (once) so the double-click answer is instant.
    private func prepareOCR() {
        guard ocrLines == nil, ocrTask == nil else { return }
        let image = image
        ocrTask = Task { [weak self] in
            let lines = (try? await TextRecognizer.lines(in: image)) ?? []
            guard !Task.isCancelled, let self else { return }
            ocrLines = lines
            ocrTask = nil
        }
    }

    private func copyText(at point: CGPoint) {
        let image = image
        Task { [weak self] in
            guard let self else { return }
            if ocrLines == nil {
                prepareOCR()
                await ocrTask?.value
            }
            guard self.image === image, let lines = ocrLines else { return }
            guard let line = TextRecognizer.line(at: point, in: lines, tolerance: 6 * unit) else {
                onTextCopied?("No text here")
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(line.text, forType: .string)
            ocrHighlight = line.rect
            onTextCopied?("Text copied")
            try? await Task.sleep(for: .seconds(0.9))
            if ocrHighlight == line.rect { ocrHighlight = nil }
        }
    }

    private func recordMoveUndo() {
        guard !moveRecorded else { return }
        pushUndo()
        moveRecorded = true
    }

    private func newAnnotation(_ shape: AnnotationShape) -> Annotation {
        switch shape {
        case .highlighter:
            return Annotation(shape: shape, color: color, lineWidth: strokeSize.rawValue * unit * StrokeSize.highlighterFactor,
                              filled: filled, fontSize: textSize.rawValue * unit)
        case .blackout:
            return Annotation(shape: shape, color: .black, lineWidth: 0, filled: true, fontSize: textSize.rawValue * unit)
        default:
            return Annotation(shape: shape, color: color, lineWidth: strokeSize.rawValue * unit,
                              filled: filled, fontSize: textSize.rawValue * unit, borderColor: borderStyle.color)
        }
    }

    /// The topmost mark under the point. Outlined shapes only respond near their border while drawing,
    /// unless they're already selected.
    func annotation(at point: CGPoint) -> Annotation? {
        let tolerance = 6 / viewScale
        if let selected = selectedAnnotation, selected.hitTest(point, tolerance: tolerance) { return selected }
        return annotations.reversed().first { $0.hitTest(point, tolerance: tolerance, interior: tool == .select) }
    }

    /// The resize handle of the selected mark under the point.
    func handle(at point: CGPoint) -> EditHandle? {
        guard textEditing == nil else { return nil }
        return selectedAnnotation?.handle(at: point, tolerance: 8 / viewScale)
    }

    /// Key 4: picks the last used shape (rectangle by default), or the next shape if one is already active.
    func selectShapeTool() {
        if let index = EditorTool.shapes.firstIndex(of: tool) {
            tool = EditorTool.shapes[(index + 1) % EditorTool.shapes.count]
        } else {
            tool = lastShape
        }
    }

    // MARK: Text

    func commitTextEditing() {
        guard let editing = textEditing else { return }
        textEditing = nil
        // Clicking away from a text box goes to Select mode instead of starting another one.
        if tool == .text { tool = .select }
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
            let annotation = Annotation(shape: .text(editing.origin, editing.text), color: editing.color,
                                        lineWidth: 0, filled: editing.filled, fontSize: editing.fontSize)
            annotations.append(annotation)
            selectedID = annotation.id
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
        return EditorRenderer.render(image: image, pixelated: pixelated, annotations: annotations, beautify: beautify,
                                     extraSpace: extraSpace)
    }

    func save(to url: URL? = nil, rendered: CGImage? = nil) async throws {
        guard let output = rendered ?? renderOutput() else { throw CocoaError(.fileWriteUnknown) }
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
