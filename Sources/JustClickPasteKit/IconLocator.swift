import CoreGraphics
import Foundation

public struct ComposerIcons: Sendable {
    /// Screenshot pixel coordinates, origin at top left.
    public let plus: CGRect
    public let microphone: CGRect
    public let score: Double
}
public enum IconLookup { case found(ComposerIcons), absent, ambiguous }
public struct IconReport {
    public let plus: [CGRect]
    public let microphones: [CGRect]
    public let pairs: [ComposerIcons]
    public var lookup: IconLookup { pairs.count > 1 ? .ambiguous : pairs.first.map(IconLookup.found) ?? .absent }
    public var summary: String { "图标识别：＋\(plus.count) 个，麦克风 \(microphones.count) 个，有效配对 \(pairs.count) 组" }
}

/// Local normalized template correlation. Both contrast polarities are supported.
/// Only the stable plus/microphone pair participates; no send/voice-mode templates.
public enum IconLocator {
    private struct Hit { let rect: CGRect; let score: Double }
    public static func locate(_ image: CGImage) -> IconLookup { analyze(image).lookup }
    public static func analyze(_ image: CGImage) -> IconReport {
        // Keep native pixel resolution: resizing a whole window erased small icons.
        let ratio = 1.0
        let w = Int(Double(image.width) * ratio), h = Int(Double(image.height) * ratio)
        guard w > 80, h > 50 else { return IconReport(plus:[],microphones:[],pairs:[]) }
        var pixels = [UInt8](repeating: 0, count: w*h)
        let rendered = pixels.withUnsafeMutableBytes { data -> Bool in
            guard let ctx = CGContext(data: data.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h)); return true
        }
        guard rendered else { return IconReport(plus:[],microphones:[],pairs:[]) }
        func hits(_ template: [UInt8], aspect: Double) -> [Hit] {
            let mean = template.map(Double.init).reduce(0,+) / 256
            let centered = template.map { Double($0) - mean }
            let norm = centered.reduce(0) { $0 + $1*$1 }
            var output: [Hit] = []
            // Original screenshot icons occupy ~32 pixels; support display scaling.
            for side in [16,20,24,28,32,36,40,48,56,64] {
                let height = Int(Double(side)*aspect)
                guard w > side, h > height else { continue }
                let offsets = (0..<256).map { i in min(height-1, (i/16*2+1)*height/32)*w + min(side-1,(i%16*2+1)*side/32) }
                for y in stride(from: Int(Double(h)*0.5), through: h-height, by: 2) {
                    for x in stride(from: 0, through: w-side, by: 2) {
                        let start = y*w+x
                        // Fast contrast rejection using a sparse subset before correlation.
                        var low = 255, high = 0
                        for i in stride(from: 0, to: 256, by: 17) { let p = Int(pixels[start+offsets[i]]); low = min(low,p); high = max(high,p) }
                        if high-low < 45 { continue }
                        var sum = 0.0, squares = 0.0, product = 0.0
                        for i in 0..<256 { let p = Double(pixels[start+offsets[i]]); sum += p; squares += p*p; product += p*centered[i] }
                        let variance = squares-sum*sum/256
                        guard variance > 4000 else { continue }
                        let score = abs(product) / sqrt(norm*variance)
                        if score >= 0.76 { output.append(Hit(rect: CGRect(x:x,y:y,width:side,height:height),score:score)) }
                    }
                }
            }
            // Suppress duplicate scales/nearby peaks of the same icon.
            var kept: [Hit] = []
            for hit in output.sorted(by: { $0.score > $1.score }) {
                if !kept.contains(where: { abs($0.rect.midX-hit.rect.midX) < max($0.rect.width,hit.rect.width)*0.55 && abs($0.rect.midY-hit.rect.midY) < max($0.rect.height,hit.rect.height)*0.55 }) { kept.append(hit) }
                if kept.count >= 24 { break }
            }
            return kept
        }
        let plus = hits(IconSamples.plus, aspect: 1)
        let microphones = hits(IconSamples.microphone, aspect: 34.0/32.0)
        var pairs: [ComposerIcons] = []
        for left in plus { for right in microphones {
            let unit = max(left.rect.width,right.rect.width)
            guard right.rect.midX-left.rect.midX > max(150,unit*5),
                  abs(left.rect.midY-right.rect.midY) < unit*0.4,
                  right.rect.width/left.rect.width > 0.7, right.rect.width/left.rect.width < 1.4 else { continue }
            let scale = CGAffineTransform(scaleX: 1/ratio, y: 1/ratio)
            pairs.append(ComposerIcons(plus:left.rect.applying(scale),microphone:right.rect.applying(scale),score:min(left.score,right.score)))
        } }
        return IconReport(plus:plus.map(\.rect),microphones:microphones.map(\.rect),pairs:pairs)
    }
}
