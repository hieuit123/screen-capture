import AVFoundation
import UniformTypeIdentifiers

enum CaptureKind: String, CaseIterable, Identifiable, Sendable {
    case recording, screenshot

    var id: String { rawValue }
    var title: String { self == .recording ? "Record" : "Screenshot" }
    var historyTitle: String { self == .recording ? "Recordings" : "Screenshots" }
    var symbol: String { self == .recording ? "record.circle" : "camera.viewfinder" }
}

enum CaptureSource: String, CaseIterable, Identifiable, Sendable {
    case display, window, application, area

    var id: String { rawValue }
    var title: String {
        switch self {
        case .display: "Screen"
        case .window: "Window"
        case .application: "App"
        case .area: "Area"
        }
    }
    var symbol: String {
        switch self {
        case .display: "display"
        case .window: "macwindow"
        case .application: "app.badge"
        case .area: "rectangle.dashed"
        }
    }
}

enum FrameRate: Int, CaseIterable, Identifiable, Sendable {
    case fps15 = 15, fps24 = 24, fps30 = 30, fps60 = 60, fps120 = 120

    var id: Int { rawValue }
    var title: String { "\(rawValue)" }
}

enum VideoQuality: String, CaseIterable, Identifiable, Sendable {
    case low, medium, high, best

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// Output resolution relative to the native pixel resolution of the source.
    var resolutionScale: Double {
        switch self {
        case .low: 0.5
        case .medium: 0.75
        case .high, .best: 1.0
        }
    }

    /// Bits per pixel per frame used to derive the H.264 bitrate (HEVC uses less).
    var bitsPerPixel: Double {
        switch self {
        case .low: 0.05
        case .medium: 0.08
        case .high: 0.12
        case .best: 0.25
        }
    }

    var detail: String {
        switch self {
        case .low: "50% resolution · smallest files"
        case .medium: "75% resolution · balanced"
        case .high: "Native resolution · sharp"
        case .best: "Native resolution · maximum bitrate"
        }
    }
}

enum VideoCodec: String, CaseIterable, Identifiable, Sendable {
    case hevc, h264

    var id: String { rawValue }
    var title: String { self == .hevc ? "HEVC (H.265)" : "H.264" }
    var avCodec: AVVideoCodecType { self == .hevc ? .hevc : .h264 }
    var bitrateFactor: Double { self == .hevc ? 0.6 : 1.0 }
}

enum VideoContainer: String, CaseIterable, Identifiable, Sendable {
    case mp4, mov

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
    var fileType: AVFileType { self == .mp4 ? .mp4 : .mov }
}

enum ImageFormat: String, CaseIterable, Identifiable, Sendable {
    case png, jpeg, heic

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
    var fileExtension: String { self == .jpeg ? "jpg" : rawValue }
    var utType: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .heic: .heic
        }
    }
}

struct CaptureItem: Identifiable, Hashable, Sendable {
    let url: URL
    let kind: CaptureKind
    let date: Date
    var modified: Date
    let size: Int64

    init(url: URL, kind: CaptureKind, date: Date, modified: Date? = nil, size: Int64) {
        self.url = url
        self.kind = kind
        self.date = date
        self.modified = modified ?? date
        self.size = size
    }

    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }
    var formattedSize: String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
}

/// A rectangle chosen by the user, in points, relative to the top-left of a display.
struct AreaSelection: Sendable {
    let displayID: CGDirectDisplayID
    let rect: CGRect
}
