import AppKit
import ImageIO
import ScreenCaptureKit

enum ScreenshotService {
    static func capture(target: CaptureTarget, showsCursor: Bool) async throws -> CGImage {
        let config = SCStreamConfiguration()
        config.width = Int(target.nativePixelSize.width.rounded())
        config.height = Int(target.nativePixelSize.height.rounded())
        config.showsCursor = showsCursor
        config.captureResolution = .best
        config.scalesToFit = true
        config.preservesAspectRatio = true
        config.colorSpaceName = CGColorSpace.sRGB
        if let rect = target.sourceRect { config.sourceRect = rect }
        return try await SCScreenshotManager.captureImage(contentFilter: target.filter, configuration: config)
    }

    /// Encodes and writes the image. Call off the main thread.
    nonisolated static func write(_ image: CGImage, to url: URL, format: ImageFormat) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, format.utType.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var properties: [CFString: Any] = [:]
        if format != .png {
            properties[kCGImageDestinationLossyCompressionQuality] = 0.9
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    @MainActor
    static func copyToPasteboard(_ image: CGImage) {
        let nsImage = NSImage(cgImage: image, size: .zero)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([nsImage])
    }
}
