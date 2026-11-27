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

    /// One recognized word and where it sits in the image (pixels, top-left origin).
    struct Word: Sendable {
        let text: String
        let rect: CGRect
        /// Words on the same recognized line share this, so a selection knows when to break the line.
        let line: Int
    }

    /// Every recognized word in reading order, for double-click / drag text selection.
    static func words(in image: CGImage) async throws -> [Word] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        let size = CGSize(width: image.width, height: image.height)
        var words: [Word] = []
        for (lineIndex, observation) in try await request.perform(on: image).enumerated() {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let string = candidate.string
            var index = string.startIndex
            while index < string.endIndex {
                if string[index].isWhitespace { index = string.index(after: index); continue }
                var end = index
                while end < string.endIndex, !string[end].isWhitespace { end = string.index(after: end) }
                if let box = candidate.boundingBox(for: index..<end)?.boundingBox {
                    words.append(Word(text: String(string[index..<end]),
                                      rect: box.toImageCoordinates(size, origin: .upperLeft), line: lineIndex))
                }
                index = end
            }
        }
        return words
    }

    /// The word under `point` (within `tolerance` pixels), or with no tolerance limit the closest one.
    static func nearestWord(to point: CGPoint, in words: [Word], tolerance: CGFloat = .infinity) -> Int? {
        let distances = words.enumerated().map { index, word -> (Int, CGFloat) in
            let r = word.rect
            return (index, hypot(max(r.minX - point.x, 0, point.x - r.maxX), max(r.minY - point.y, 0, point.y - r.maxY)))
        }
        return distances.filter { $0.1 <= tolerance }.min { $0.1 < $1.1 }?.0
    }

    /// Text of words `range`: spaces within a line, newlines between lines.
    static func text(of words: [Word], range: ClosedRange<Int>) -> String {
        var result = ""
        for index in range {
            if index > range.lowerBound { result += words[index].line == words[index - 1].line ? " " : "\n" }
            result += words[index].text
        }
        return result
    }
}
