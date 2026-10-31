import AppKit
import ImageIO
import Observation

/// Images imported as Beautify backgrounds, copied into Application Support so they outlive the originals.
@MainActor
@Observable
final class BackgroundLibrary {
    static let shared = BackgroundLibrary()

    /// Imported file names, newest first.
    private(set) var names: [String] = []

    @ObservationIgnored private let cache = NSCache<NSString, CGImage>()

    static var folderURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "ScreenCapture", directoryHint: .isDirectory)
            .appending(path: "Backgrounds", directoryHint: .isDirectory)
    }

    init() {
        cache.countLimit = 12
        reload()
    }

    /// Copies the image into the library and returns its file name.
    func importImage(from url: URL) throws -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
        else { throw CocoaError(.fileReadCorruptFile) }
        try FileManager.default.createDirectory(at: Self.folderURL, withIntermediateDirectories: true)
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension.lowercased()
        let name = "\(UUID().uuidString).\(ext)"
        try FileManager.default.copyItem(at: url, to: Self.folderURL.appending(path: name))
        reload()
        return name
    }

    func remove(_ name: String) {
        try? FileManager.default.removeItem(at: Self.folderURL.appending(path: name))
        cache.removeObject(forKey: name as NSString)
        reload()
    }

    func image(named name: String) -> CGImage? {
        if let cached = cache.object(forKey: name as NSString) { return cached }
        let url = Self.folderURL.appending(path: name)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return image
    }

    private func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: Self.folderURL, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])) ?? []
        func created(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
        }
        names = urls.sorted { created($0) > created($1) }.map(\.lastPathComponent)
    }
}
