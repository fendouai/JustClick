import CoreGraphics
import Foundation
import Vision

public struct OCRLine: Sendable {
    public let text: String
    public let confidence: Float
    /// Vision's normalized, bottom-left origin coordinates.
    public let bounds: CGRect
    public init(text: String, confidence: Float, bounds: CGRect) {
        self.text = text; self.confidence = confidence; self.bounds = bounds
    }
}
public enum OCRSelection { case target(CGRect), absent, ambiguous }
public enum LocalOCR {
    public static func recognize(_ image: CGImage) throws -> [OCRLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US", "zh-Hans"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first.map { OCRLine(text: $0.string, confidence: $0.confidence, bounds: observation.boundingBox) }
        }
    }
    /// A placeholder is only a click hint. The backend must confirm the real input and read-back.
    public static func select(_ lines: [OCRLine], axWindow: CGRect) -> OCRSelection {
        let candidates = lines.filter { line in
            let text = line.text.lowercased()
            guard line.confidence >= 0.85, line.bounds.midY < 0.35,
                  line.bounds.width > 0, line.bounds.height > 0,
                  CGRect(x: 0, y: 0, width: 1, height: 1).contains(line.bounds),
                  !["search", "搜索", "terminal", "终端", "password", "密码"].contains(where: text.contains) else { return false }
            return ["message test chat", "message codex", "ask codex", "ask anything", "do anything", "输入消息", "询问 codex"].contains(where: text.contains)
        }
        guard candidates.count <= 1 else { return .ambiguous }
        guard let line = candidates.first else { return .absent }
        let bounds = line.bounds
        return .target(CGRect(x: axWindow.minX + bounds.minX * axWindow.width,
                              y: axWindow.minY + (1 - bounds.maxY) * axWindow.height,
                              width: bounds.width * axWindow.width, height: bounds.height * axWindow.height))
    }
}
