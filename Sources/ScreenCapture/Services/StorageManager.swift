import Foundation

/// Manages `~/Documents/ScreenCapture/{videos,images}`.
enum StorageManager {
    static var rootURL: URL {
        URL.documentsDirectory.appending(path: "ScreenCapture", directoryHint: .isDirectory)
    }
    static var videosURL: URL { rootURL.appending(path: "videos", directoryHint: .isDirectory) }
    static var imagesURL: URL { rootURL.appending(path: "images", directoryHint: .isDirectory) }

    static func folder(for kind: CaptureKind) -> URL {
        kind == .recording ? videosURL : imagesURL
    }

    /// Creates the folders if they are missing. Safe to call often.
    static func ensureFolders() throws {
        let fm = FileManager.default
        for url in [videosURL, imagesURL] where !fm.fileExists(atPath: url.path) {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    static func newFileURL(kind: CaptureKind, fileExtension: String) throws -> URL {
        try ensureFolders()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let prefix = kind == .recording ? "Recording" : "Screenshot"
        let base = "\(prefix) \(formatter.string(from: .now))"
        let folder = folder(for: kind)

        var url = folder.appending(path: "\(base).\(fileExtension)")
        var index = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appending(path: "\(base) (\(index)).\(fileExtension)")
            index += 1
        }
        return url
    }

    /// Hidden sibling used while a recording is still being written, so it never shows in history.
    static func temporaryURL(for finalURL: URL) -> URL {
        finalURL.deletingLastPathComponent().appending(path: ".\(UUID().uuidString).\(finalURL.pathExtension)")
    }
}
