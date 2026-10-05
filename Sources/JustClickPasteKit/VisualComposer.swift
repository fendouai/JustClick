import Foundation
import CoreGraphics

public struct VisualComposer: Sendable {
    public let input: CGRect
    public let click: CGPoint
    public let window: CGRect
    public let icons: ComposerIcons
    public static func locate(image: CGImage, lines: [OCRLine], window: CGRect, report: IconReport? = nil) -> VisualComposer? {
        guard case .found(let pair) = (report ?? IconLocator.analyze(image)).lookup else { return nil }
        let unit = max(pair.plus.width,pair.microphone.width)
        let placeholders = lines.filter { line in
            let normalized = line.text.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
            guard line.confidence >= 0.85, ["do anything", "ask anything", "ask codex", "message codex", "输入消息", "询问 codex"].contains(normalized) else { return false }
            let x = line.bounds.minX * Double(image.width)
            let y = (1-line.bounds.midY) * Double(image.height)
            return x >= pair.plus.minX-unit && x < pair.microphone.minX-unit
                && y < pair.plus.minY-unit*0.4 && y > pair.plus.minY-unit*7
        }
        let placeholder = placeholders.count == 1 ? placeholders.first : nil
        let sx = window.width / Double(image.width), sy = window.height / Double(image.height)
        let textTop = placeholder.map { (1-$0.bounds.maxY)*Double(image.height) } ?? (pair.plus.minY-unit*1.4)
        let pixelRect = CGRect(x:max(0,pair.plus.minX-unit*0.5),y:max(0,textTop-unit*0.35),width:pair.microphone.maxX-pair.plus.minX+unit*0.5,height:pair.plus.minY-unit*0.25-max(0,textTop-unit*0.35))
        guard pixelRect.height > unit*0.8 else { return nil }
        let input = CGRect(x:window.minX+pixelRect.minX*sx,y:window.minY+pixelRect.minY*sy,width:pixelRect.width*sx,height:pixelRect.height*sy)
        let click = placeholder.map { CGPoint(x:window.minX+($0.bounds.midX*Double(image.width))*sx,y:window.minY+(1-$0.bounds.midY)*Double(image.height)*sy) }
            ?? CGPoint(x:input.minX+min(input.width*0.25,unit*3*sx),y:window.minY+(pair.plus.minY-unit*0.75)*sy)
        return VisualComposer(input:input,click:click,window:window,icons:pair)
    }
    /// Empty OCR output is allowed; recognized draft text is preserved.
    public static func permitsEmptyInput(_ lines: [OCRLine]) -> Bool {
        let text = lines.map(\.text).joined().lowercased().components(separatedBy:.whitespacesAndNewlines).joined()
        return ["", "doanything", "askanything", "askcodex", "messagecodex", "输入消息", "询问codex"].contains(text)
    }
    public static func hasVisibleDraftEvidence(_ lines: [OCRLine], expected: String) -> Bool {
        func normalized(_ text: String) -> String { text.components(separatedBy:.whitespacesAndNewlines).joined() }
        let needle = normalized(expected)
        guard !needle.isEmpty else { return false }
        let visible = normalized(lines.map(\.text).joined())
        return visible.contains(String(needle.prefix(min(8,needle.count))))
    }
    /// Keep OCR's full-image context: tight crops can misread the caret as part of D.
    public func inputLines(_ lines: [OCRLine]) -> [OCRLine] {
        lines.filter { line in
            let point = CGPoint(x:window.minX+line.bounds.midX*window.width,y:window.minY+(1-line.bounds.midY)*window.height)
            return input.contains(point)
        }
    }
    /// Count visible copies outside the composer, never mistake the draft for a receipt.
    public func messageOccurrences(_ lines: [OCRLine], expected: String) -> Int {
        func normalized(_ value: String) -> String { value.precomposedStringWithCanonicalMapping.components(separatedBy:.whitespacesAndNewlines).joined() }
        let needle = normalized(expected)
        guard needle.count >= 4 else { return 0 }
        let outside = lines.filter { line in
            let point = CGPoint(x:window.minX+line.bounds.midX*window.width,y:window.minY+(1-line.bounds.midY)*window.height)
            return !input.contains(point) && line.confidence >= 0.8
        }.sorted { a,b in
            if abs(a.bounds.midY-b.bounds.midY) > min(a.bounds.height,b.bounds.height)*0.5 { return a.bounds.midY > b.bounds.midY }
            return a.bounds.minX < b.bounds.minX
        }
        return normalized(outside.map(\.text).joined()).components(separatedBy:needle).count-1
    }
    /// Compare visible text allowing OCR line wrapping, not content substitutions.
    public static func agrees(_ lines: [OCRLine], with expected: String) -> Bool {
        func normalized(_ text: String) -> String { text.precomposedStringWithCanonicalMapping.components(separatedBy:.whitespacesAndNewlines).joined() }
        let sorted = lines.sorted { a,b in
            if abs(a.bounds.midY-b.bounds.midY) > min(a.bounds.height,b.bounds.height)*0.5 { return a.bounds.midY > b.bounds.midY }
            return a.bounds.minX < b.bounds.minX
        }
        return !lines.isEmpty && lines.allSatisfy { $0.confidence >= 0.8 } && normalized(sorted.map(\.text).joined()) == normalized(expected)
    }
}
