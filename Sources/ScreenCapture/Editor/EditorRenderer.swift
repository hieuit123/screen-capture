import AppKit

/// Draws annotations with CoreGraphics. Used both for the live canvas and the exported image,
/// so the saved file matches the preview exactly. All contexts are expected to be y-down.
@MainActor
enum EditorRenderer {
    // MARK: Export

    static func render(image: CGImage, pixelated: CGImage?, annotations: [Annotation], beautify: BeautifySettings,
                       extraSpace: ExtraSpace = .none) -> CGImage? {
        let imageSize = CGSize(width: image.width, height: image.height)
        let layout = CanvasLayout(imageSize: imageSize, beautify: beautify, extraSpace: extraSpace)
        let width = Int(layout.canvasSize.width), height = Int(layout.canvasSize.height)
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }

        // Flip to a top-left origin to match the editor's coordinate space.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high

        let imagePath = CGPath(roundedRect: layout.imageRect, cornerWidth: layout.cornerRadius,
                               cornerHeight: layout.cornerRadius, transform: nil)
        if !beautify.enabled && extraSpace != .none {
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(origin: .zero, size: layout.canvasSize))
        }
        if beautify.enabled {
            drawBackground(beautify.resolvedBackground, in: CGRect(origin: .zero, size: layout.canvasSize), context: ctx)
            if layout.shadowRadius > 0 {
                ctx.saveGState()
                // Shadow offsets are in device space (y-up), so a negative height points down.
                ctx.setShadow(offset: CGSize(width: 0, height: -layout.shadowRadius * 0.4), blur: layout.shadowRadius,
                              color: NSColor.black.withAlphaComponent(0.4).cgColor)
                ctx.addPath(imagePath)
                ctx.setFillColor(NSColor.black.cgColor)
                ctx.fillPath()
                ctx.restoreGState()
            }
        }

        ctx.saveGState()
        ctx.addPath(imagePath)
        ctx.clip()
        drawImage(image, in: layout.imageRect, context: ctx)
        ctx.restoreGState()

        // Marks are not clipped to the screenshot, so they can extend over the background or extra space.
        ctx.saveGState()
        ctx.clip(to: CGRect(origin: .zero, size: layout.canvasSize))
        ctx.translateBy(x: layout.imageRect.minX, y: layout.imageRect.minY)
        draw(annotations, pixelated: pixelated, imageSize: imageSize, in: ctx)
        ctx.restoreGState()

        return ctx.makeImage()
    }

    // MARK: Primitives

    static func drawImage(_ image: CGImage, in rect: CGRect, context ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }

    static func drawBackground(_ background: ResolvedBackground, in rect: CGRect, context ctx: CGContext) {
        switch background {
        case .gradient(let colors, let direction):
            drawGradient(colors, direction: direction, in: rect, context: ctx)
        case .solid(let color):
            ctx.saveGState()
            ctx.setFillColor(color.cgColor)
            ctx.fill(rect)
            ctx.restoreGState()
        case .image(let image):
            ctx.saveGState()
            ctx.clip(to: rect)
            drawImage(image, in: aspectFillRect(for: CGSize(width: image.width, height: image.height), in: rect), context: ctx)
            ctx.restoreGState()
        }
    }

    /// Scales `size` to cover `rect`, centred. Shared with the SwiftUI preview.
    nonisolated static func aspectFillRect(for size: CGSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = max(rect.width / size.width, rect.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }

    static func drawGradient(_ colors: [NSColor], direction: GradientDirection = .diagonalDown, in rect: CGRect,
                             context ctx: CGContext) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                        colors: colors.map(\.cgColor) as CFArray, locations: nil) else { return }
        let (start, end) = direction.points
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: rect.minX + start.x * rect.width, y: rect.minY + start.y * rect.height),
                               end: CGPoint(x: rect.minX + end.x * rect.width, y: rect.minY + end.y * rect.height),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }

    static func draw(_ annotations: [Annotation], pixelated: CGImage?, imageSize: CGSize, in ctx: CGContext) {
        for annotation in annotations {
            ctx.saveGState()
            draw(annotation, pixelated: pixelated, imageSize: imageSize, in: ctx)
            ctx.restoreGState()
        }
    }

    private static func draw(_ a: Annotation, pixelated: CGImage?, imageSize: CGSize, in ctx: CGContext) {
        let color = a.color.cgColor
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(a.lineWidth)
        ctx.setStrokeColor(color)
        ctx.setFillColor(color)

        switch a.shape {
        case .rectangle(let r):
            let radius = min(a.lineWidth * 1.5, min(r.width, r.height) / 2)
            let path = CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
            if a.filled { fill(path, a, in: ctx) }
            stroke(path, a, in: ctx)

        case .ellipse(let r):
            let path = CGPath(ellipseIn: r, transform: nil)
            if a.filled { fill(path, a, in: ctx) }
            stroke(path, a, in: ctx)

        case .line(let p1, let p2):
            let path = CGMutablePath()
            path.move(to: p1)
            path.addLine(to: p2)
            stroke(path, a, in: ctx)

        case .arrow(let p1, let p2):
            drawArrow(from: p1, to: p2, width: a.lineWidth, color: color, border: a.borderColor?.cgColor,
                      borderWidth: a.borderWidth, in: ctx)

        case .pencil(let points):
            stroke(smoothPath(points), a, in: ctx)

        case .highlighter(let points):
            ctx.setStrokeColor(a.color.withAlphaComponent(0.4).cgColor)
            ctx.setLineCap(.square)
            ctx.addPath(smoothPath(points))
            ctx.strokePath()

        case .text(let origin, let string):
            drawText(string, at: origin, color: a.color, fontSize: a.fontSize, filled: a.filled, in: ctx)

        case .pixelate(let r):
            ctx.clip(to: r.intersection(CGRect(origin: .zero, size: imageSize)))
            if let pixelated {
                ctx.interpolationQuality = .none
                drawImage(pixelated, in: CGRect(origin: .zero, size: imageSize), context: ctx)
            } else {
                ctx.setFillColor(NSColor.gray.cgColor)
                ctx.fill(r)
            }

        case .blackout(let r):
            ctx.fill(r)

        case .counter(let center, let number):
            let radius = counterRadius(fontSize: a.fontSize)
            let circle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -radius * 0.1), blur: radius * 0.3,
                          color: NSColor.black.withAlphaComponent(0.3).cgColor)
            ctx.fillEllipse(in: circle)
            ctx.restoreGState()
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(max(1.5, radius * 0.12))
            ctx.strokeEllipse(in: circle.insetBy(dx: radius * 0.06, dy: radius * 0.06))
            let label = NSAttributedString(string: "\(number)", attributes: [
                .font: NSFont.systemFont(ofSize: a.fontSize * 0.95, weight: .bold),
                .foregroundColor: contrastingTextColor(for: a.color),
            ])
            let size = label.size()
            withAppKit(ctx) { label.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)) }
        }
    }

    // MARK: Text

    nonisolated static func textAttributes(fontSize: CGFloat, color: NSColor) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: fontSize, weight: .bold), .foregroundColor: color]
    }

    nonisolated static func textPadding(fontSize: CGFloat) -> CGSize {
        CGSize(width: fontSize * 0.4, height: fontSize * 0.2)
    }

    nonisolated static func textBoxSize(_ string: String, fontSize: CGFloat, filled: Bool) -> CGSize {
        let measured = NSAttributedString(string: string.isEmpty || string.hasSuffix("\n") ? string + " " : string,
                                          attributes: textAttributes(fontSize: fontSize, color: .black))
            .boundingRect(with: CGSize(width: 100_000, height: 100_000), options: [.usesLineFragmentOrigin]).size
        let pad = textPadding(fontSize: fontSize)
        return CGSize(width: ceil(measured.width) + pad.width * 2, height: ceil(measured.height) + pad.height * 2)
    }

    private static func drawText(_ string: String, at origin: CGPoint, color: NSColor, fontSize: CGFloat, filled: Bool,
                                 in ctx: CGContext) {
        let size = textBoxSize(string, fontSize: fontSize, filled: filled)
        let box = CGRect(origin: origin, size: size)
        let pad = textPadding(fontSize: fontSize)
        let textColor = filled ? contrastingTextColor(for: color) : color

        if filled {
            ctx.addPath(CGPath(roundedRect: box, cornerWidth: fontSize * 0.3, cornerHeight: fontSize * 0.3, transform: nil))
            ctx.setFillColor(color.cgColor)
            ctx.fillPath()
        }
        let rect = CGRect(x: box.minX + pad.width, y: box.minY + pad.height,
                          width: box.width - pad.width * 2 + 1, height: box.height - pad.height * 2 + 1)
        withAppKit(ctx) {
            if !filled {
                // Outline drawn first and the fill on top, so only the outer half of the stroke shows. This keeps text
                // readable on busy backgrounds without blurring or thinning the letters.
                var outline = textAttributes(fontSize: fontSize, color: textColor)
                outline[.strokeColor] = contrastingTextColor(for: color)
                outline[.strokeWidth] = 6
                NSAttributedString(string: string, attributes: outline).draw(with: rect, options: [.usesLineFragmentOrigin])
            }
            NSAttributedString(string: string, attributes: textAttributes(fontSize: fontSize, color: textColor))
                .draw(with: rect, options: [.usesLineFragmentOrigin])
        }
    }

    nonisolated static func isLight(_ color: NSColor) -> Bool {
        guard let rgb = color.usingColorSpace(.sRGB) else { return false }
        return 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent > 0.65
    }

    nonisolated static func counterRadius(fontSize: CGFloat) -> CGFloat { fontSize * 0.85 }

    private static func contrastingTextColor(for color: NSColor) -> NSColor {
        guard let rgb = color.usingColorSpace(.sRGB) else { return .white }
        let luminance = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return luminance > 0.65 ? .black : .white
    }

    private static func withAppKit(_ ctx: CGContext, _ body: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        body()
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: Paths

    private static func fill(_ path: CGPath, _ a: Annotation, in ctx: CGContext) {
        ctx.setFillColor(a.color.withAlphaComponent(0.35).cgColor)
        ctx.addPath(path)
        ctx.fillPath()
    }

    /// Strokes the path in the annotation colour, on top of a wider border stroke when it has one.
    private static func stroke(_ path: CGPath, _ a: Annotation, in ctx: CGContext) {
        if let border = a.borderColor {
            ctx.setStrokeColor(border.cgColor)
            ctx.setLineWidth(a.lineWidth + a.borderWidth * 2)
            ctx.addPath(path)
            ctx.strokePath()
        }
        ctx.setStrokeColor(a.color.cgColor)
        ctx.setLineWidth(a.lineWidth)
        ctx.addPath(path)
        ctx.strokePath()
    }

    private static func drawArrow(from start: CGPoint, to end: CGPoint, width: CGFloat, color: CGColor,
                                  border: CGColor?, borderWidth: CGFloat, in ctx: CGContext) {
        let dx = end.x - start.x, dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0.5 else { return }
        let angle = atan2(dy, dx)
        let headLength = min(max(width * 4.5, 12), length * 0.6)
        let headAngle = CGFloat.pi / 7

        let shaftEnd = CGPoint(x: end.x - cos(angle) * headLength * 0.7, y: end.y - sin(angle) * headLength * 0.7)
        let shaft = CGMutablePath()
        shaft.move(to: start)
        shaft.addLine(to: shaftEnd)

        let head = CGMutablePath()
        head.move(to: end)
        head.addLine(to: CGPoint(x: end.x - cos(angle - headAngle) * headLength, y: end.y - sin(angle - headAngle) * headLength))
        head.addLine(to: CGPoint(x: end.x - cos(angle + headAngle) * headLength, y: end.y - sin(angle + headAngle) * headLength))
        head.closeSubpath()

        func pass(_ color: CGColor, extra: CGFloat) {
            ctx.setStrokeColor(color)
            ctx.setFillColor(color)
            ctx.setLineWidth(width + extra)
            ctx.addPath(shaft)
            ctx.strokePath()
            ctx.setLineWidth(width * 0.5 + extra)
            ctx.addPath(head)
            ctx.drawPath(using: .fillStroke)
        }
        if let border { pass(border, extra: borderWidth * 2) }
        pass(color, extra: 0)
    }

    private static func smoothPath(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            path.addLine(to: points.last!)
            return path
        }
        for i in 1..<points.count - 1 {
            let mid = CGPoint(x: (points[i].x + points[i + 1].x) / 2, y: (points[i].y + points[i + 1].y) / 2)
            path.addQuadCurve(to: mid, control: points[i])
        }
        path.addLine(to: points.last!)
        return path
    }
}
