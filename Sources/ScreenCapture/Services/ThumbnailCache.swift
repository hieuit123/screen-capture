import AppKit
import AVFoundation
import QuickLookThumbnailing

/// Shared, memory-bounded cache for file thumbnails and video durations.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let images = NSCache<NSString, NSImage>()
    private var durations: [URL: Double] = [:]

    init() {
        images.countLimit = 400
    }

    func cachedThumbnail(for url: URL, version: Date, maxPixel: CGFloat) -> NSImage? {
        images.object(forKey: key(url, version, maxPixel))
    }

    func thumbnail(for url: URL, version: Date, maxPixel: CGFloat) async -> NSImage? {
        let key = key(url, version, maxPixel)
        if let cached = images.object(forKey: key) { return cached }

        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: maxPixel, height: maxPixel),
            scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        guard let cgImage = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).cgImage else {
            return nil
        }
        let image = NSImage(cgImage: cgImage, size: .zero)
        images.setObject(image, forKey: key)
        return image
    }

    func duration(for url: URL) async -> Double? {
        if let cached = durations[url] { return cached }
        guard let time = try? await AVURLAsset(url: url).load(.duration), time.isNumeric else { return nil }
        durations[url] = time.seconds
        return time.seconds
    }

    private func key(_ url: URL, _ version: Date, _ size: CGFloat) -> NSString {
        "\(url.path)#\(version.timeIntervalSince1970)#\(Int(size))" as NSString
    }
}

extension Double {
    var durationString: String {
        let total = Int(rounded())
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
