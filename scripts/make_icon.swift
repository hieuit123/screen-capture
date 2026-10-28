// Renders the app icon PNGs into an .iconset folder. Usage: swift make_icon.swift <out.iconset>
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func render(_ pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let inset = size * 0.1
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let shape = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(colors: [NSColor(red: 0.16, green: 0.17, blue: 0.24, alpha: 1),
                        NSColor(red: 0.05, green: 0.05, blue: 0.09, alpha: 1)])!
        .draw(in: shape, angle: -90)

    let ring = rect.insetBy(dx: rect.width * 0.2, dy: rect.width * 0.2)
    let ringPath = NSBezierPath(ovalIn: ring)
    ringPath.lineWidth = rect.width * 0.06
    NSColor.white.withAlphaComponent(0.92).setStroke()
    ringPath.stroke()

    let dot = ring.insetBy(dx: ring.width * 0.22, dy: ring.width * 0.22)
    NSGradient(colors: [NSColor(red: 1, green: 0.36, blue: 0.33, alpha: 1),
                        NSColor(red: 0.86, green: 0.1, blue: 0.16, alpha: 1)])!
        .draw(in: NSBezierPath(ovalIn: dot), angle: -90)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: outDir.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: outDir.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
