import CoreGraphics
import Vision

/// On-device text recognition (OCR) with the Vision framework.
enum TextRecognizer {
    /// Recognized lines in reading order, joined by newlines. Empty when the image has no text.
    static func recognize(_ image: CGImage) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        let observations = try await request.perform(on: image)
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One recognized line and where it sits in the image (pixels, top-left origin).
    struct Line: Sendable {
        let text: String
        let rect: CGRect
    }

    /// Every recognized line with its position, for "double-click text to copy it".
    static func lines(in image: CGImage) async throws -> [Line] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        let size = CGSize(width: image.width, height: image.height)
        return try await request.perform(on: image).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string
                .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return Line(text: text, rect: observation.boundingBox.toImageCoordinates(size, origin: .upperLeft))
        }
    }

    /// The line under `point`, or the closest one within `tolerance` pixels.
    static func line(at point: CGPoint, in lines: [Line], tolerance: CGFloat) -> Line? {
        lines
            .map { line -> (Line, CGFloat) in
                let r = line.rect
                let dx = max(r.minX - point.x, 0, point.x - r.maxX)
                let dy = max(r.minY - point.y, 0, point.y - r.maxY)
                return (line, hypot(dx, dy))
            }
            .filter { $0.1 <= tolerance }
            .min { $0.1 < $1.1 }?.0
    }
}
