import Foundation
import CoreGraphics

/// Stores only geometry and tiny layout fingerprints, not a full window screenshot.
public struct VisualPositionCache {
    public let composer: VisualComposer
    private let created: Date
    private let imageWidth: Int
    private let imageHeight: Int
    private let regions: [CGRect]
    private let fingerprints: [[UInt8]]
    public init?(composer: VisualComposer, image: CGImage, now: Date = Date()) {
        self.composer = composer; created = now; imageWidth = image.width; imageHeight = image.height
        let sx = Double(image.width)/composer.window.width, sy = Double(image.height)/composer.window.height
        let input = CGRect(x:(composer.input.minX-composer.window.minX)*sx,y:(composer.input.minY-composer.window.minY)*sy,width:composer.input.width*sx,height:composer.input.height*sy)
        regions = [composer.icons.plus, composer.icons.microphone,
                   CGRect(x:input.minX,y:input.minY,width:input.width,height:4),
                   CGRect(x:input.minX,y:input.maxY-4,width:input.width,height:4)]
        let values = regions.compactMap { Self.sample(image,region:$0) }
        guard values.count == regions.count else { return nil }
        fingerprints = values
    }
    public func matches(_ image: CGImage, window: CGRect, now: Date = Date()) -> Bool {
        guard window == composer.window, image.width == imageWidth, image.height == imageHeight,
              now.timeIntervalSince(created) >= 0, now.timeIntervalSince(created) < 120 else { return false }
        for (region, baseline) in zip(regions,fingerprints) {
            guard let current = Self.sample(image,region:region),
                  zip(current,baseline).allSatisfy({ abs(Int($0.0)-Int($0.1)) <= 3 }) else { return false }
        }
        return true
    }
    private static func sample(_ image: CGImage, region: CGRect) -> [UInt8]? {
        guard CGRect(x:0,y:0,width:image.width,height:image.height).contains(region.integral),
              let crop = image.cropping(to:region.integral) else { return nil }
        var bytes = [UInt8](repeating:0,count:256)
        let success = bytes.withUnsafeMutableBytes { data -> Bool in
            guard let context = CGContext(data:data.baseAddress,width:16,height:16,bitsPerComponent:8,bytesPerRow:16,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .high; context.draw(crop,in:CGRect(x:0,y:0,width:16,height:16)); return true
        }
        return success ? bytes : nil
    }
}
