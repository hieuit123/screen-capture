import AVFoundation

enum TrimError: LocalizedError {
    case unsupportedFile
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFile: "This recording can't be trimmed."
        case .exportFailed(let reason): "Trimming failed: \(reason)"
        }
    }
}

/// Cuts a recording to a time range without re-encoding and replaces the original (which goes to the Trash).
enum VideoTrimmer {
    static func trim(_ url: URL, to range: CMTimeRange) async throws {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration), duration.isNumeric else {
            throw TrimError.unsupportedFile
        }
        let full = CMTimeRange(start: .zero, duration: duration)
        let clamped = range.intersection(full)
        guard clamped.duration.seconds > 0 else { throw TrimError.exportFailed("The selection is empty.") }
        // Nothing to cut.
        if abs(clamped.start.seconds) < 0.01, abs(clamped.end.seconds - duration.seconds) < 0.01 { return }

        guard let container = VideoContainer(rawValue: url.pathExtension.lowercased()),
              let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough)
        else { throw TrimError.unsupportedFile }
        session.timeRange = clamped

        let fm = FileManager.default
        let tempURL = StorageManager.temporaryURL(for: url)
        var trashedURL: NSURL?
        do {
            try await session.export(to: tempURL, as: container.fileType)
            // Keep the recording's place in History, which is sorted by creation date.
            if let created = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate {
                try? fm.setAttributes([.creationDate: created], ofItemAtPath: tempURL.path)
            }
            try fm.trashItem(at: url, resultingItemURL: &trashedURL)
            try fm.moveItem(at: tempURL, to: url)
        } catch {
            try? fm.removeItem(at: tempURL)
            // Put the original back if it was already moved to the Trash.
            if let trashed = trashedURL as URL?, !fm.fileExists(atPath: url.path) {
                try? fm.moveItem(at: trashed, to: url)
            }
            throw TrimError.exportFailed(error.localizedDescription)
        }
    }
}
