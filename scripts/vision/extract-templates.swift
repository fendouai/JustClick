import AppKit
import ImageIO
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
print("// Icon samples extracted from the user-supplied screenshot; no conversation pixels retained.")
print("enum IconSamples {")
for (name, rect) in [("plus", CGRect(x: 39, y: 268, width: 32, height: 32)), ("microphone", CGRect(x: 1300, y: 267, width: 32, height: 34))] {
 let crop = image.cropping(to: rect)!
 var pixels = [UInt8](repeating: 0, count: 16*16)
 pixels.withUnsafeMutableBytes { buf in
  let context = CGContext(data: buf.baseAddress, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 16, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
  context.interpolationQuality = .high
  context.draw(crop, in: CGRect(x: 0, y: 0, width: 16, height: 16))
 }
 print(" static let \(name): [UInt8] = [\(pixels.map(String.init).joined(separator: ","))]")
}
print("}")
