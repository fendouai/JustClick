import Foundation
import CoreGraphics
import ImageIO
import JustClickPasteKit
let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL,nil)!
let original = CGImageSourceCreateImageAtIndex(source,0,nil)!
func check(_ image: CGImage, scale: Double, name: String) {
 let start = Date()
 switch IconLocator.locate(image) {
 case .found(let icons):
  print("\(name): plus=\(icons.plus) microphone=\(icons.microphone) score=\(icons.score) seconds=\(Date().timeIntervalSince(start))")
  precondition(abs(icons.plus.midX-55*scale)<7*scale && abs(icons.plus.midY-284*scale)<7*scale)
  precondition(abs(icons.microphone.midX-1316*scale)<7*scale && abs(icons.microphone.midY-284*scale)<7*scale)
 case .absent: fatalError("\(name): no pair")
 case .ambiguous: fatalError("\(name): ambiguous")
 }
}
check(original,scale:1,name:"User screenshot")
for scale in [0.75,1.5,2.0] {
 let ctx = CGContext(data:nil,width:Int(Double(original.width)*scale),height:Int(Double(original.height)*scale),bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
 ctx.interpolationQuality = .high
 ctx.draw(original,in:CGRect(x:0,y:0,width:ctx.width,height:ctx.height))
 check(ctx.makeImage()!,scale:scale,name:"Scaled \(scale)")
}
print("PASS screenshot icon matching and scale variants; no live application controlled")
let gray = CGContext(data:nil,width:original.width,height:original.height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
gray.draw(original,in:CGRect(x:0,y:0,width:gray.width,height:gray.height))
gray.setBlendMode(.difference); gray.setFillColor(CGColor(gray:1,alpha:1)); gray.fill(CGRect(x:0,y:0,width:gray.width,height:gray.height))
check(gray.makeImage()!,scale:1,name:"Inverted contrast")
let blank = CGContext(data:nil,width:original.width,height:original.height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
blank.setFillColor(CGColor(gray:1,alpha:1)); blank.fill(CGRect(x:0,y:0,width:blank.width,height:blank.height))
if case .absent = IconLocator.locate(blank.makeImage()!) {} else { fatalError("Blank image matched") }
let lines = try LocalOCR.recognize(original)
guard let composer = VisualComposer.locate(image:original,lines:lines,window:CGRect(x:100,y:200,width:733,height:182)) else { fatalError("Icons plus actual OCR placeholder failed") }
precondition(composer.input.contains(composer.click))
precondition(composer.click.y < 200+268/2)
precondition(VisualComposer.locate(image:original,lines:[],window:composer.window) != nil)
precondition(VisualComposer.permitsEmptyInput([]))
precondition(!VisualComposer.permitsEmptyInput([OCRLine(text:"existing draft",confidence:1,bounds:.zero)]))
precondition(!VisualComposer.agrees([OCRLine(text:"wrong text",confidence:1,bounds:.zero)],with:"expected text"))
print("PASS inverted/blank images, actual OCR cross-check, screen-coordinate mapping and draft-readback rejection")
let noMic = CGContext(data:nil,width:original.width,height:original.height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
noMic.draw(original,in:CGRect(x:0,y:0,width:noMic.width,height:noMic.height))
// Quartz drawing origin is bottom-left, erase the microphone only.
noMic.setFillColor(CGColor(gray:1,alpha:1)); noMic.fill(CGRect(x:1295,y:Double(original.height)-305,width:44,height:44))
if case .absent = IconLocator.locate(noMic.makeImage()!) {} else { fatalError("Missing microphone must not match") }
print("PASS plus alone and blue voice button do not identify a composer")
for width in [2400,3600,4800] {
 let height = 1800
 let canvas = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
 canvas.setFillColor(CGColor(gray:0.96,alpha:1)); canvas.fill(CGRect(x:0,y:0,width:width,height:height))
 canvas.draw(original,in:CGRect(x:100,y:40,width:original.width,height:original.height))
 let image = canvas.makeImage()!
 guard case .found(let icons) = IconLocator.locate(image) else { fatalError("Full window width \(width): pair lost") }
 precondition(abs(icons.plus.midX-155)<9 && abs(icons.microphone.midX-1416)<9)
 guard VisualComposer.locate(image:image,lines:try LocalOCR.recognize(image),window:CGRect(x:0,y:0,width:width,height:height)) != nil else { fatalError("Full window width \(width): placeholder lost") }
 print("PASS original screenshot embedded in full-window canvas \(width)x\(height)")
}
let report = IconLocator.analyze(original)
precondition(report.plus.count == 1 && report.microphones.count == 1 && report.pairs.count == 1)
let absentReport = IconLocator.analyze(blank.makeImage()!)
precondition(absentReport.plus.isEmpty && absentReport.microphones.isEmpty && absentReport.pairs.isEmpty)
let partialReport = IconLocator.analyze(noMic.makeImage()!)
precondition(partialReport.plus.count == 1 && partialReport.microphones.isEmpty && partialReport.pairs.isEmpty)
print(report.summary)
print("PASS diagnostic counts: complete pair 1/1/1, blank 0/0/0, plus-only 1/0/0")
if CommandLine.arguments.count > 2 {
 let out = CGContext(data:nil,width:original.width,height:original.height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
 out.draw(original,in:CGRect(x:0,y:0,width:out.width,height:out.height))
 func mark(_ rect: CGRect, color: CGColor) {
  out.setStrokeColor(color); out.setLineWidth(3)
  out.stroke(CGRect(x:rect.minX,y:Double(out.height)-rect.maxY,width:rect.width,height:rect.height).insetBy(dx:-3,dy:-3))
 }
 for rect in report.plus { mark(rect,color:CGColor(red:0,green:0.7,blue:0.3,alpha:1)) }
 for rect in report.microphones { mark(rect,color:CGColor(red:1,green:0.45,blue:0,alpha:1)) }
 if let region = VisualComposer.locate(image:original,lines:[],window:CGRect(x:0,y:0,width:out.width,height:out.height),report:report) {
  mark(region.input,color:CGColor(red:0.1,green:0.4,blue:1,alpha:1))
  out.setFillColor(CGColor(red:1,green:0.1,blue:0.2,alpha:1))
  out.fillEllipse(in:CGRect(x:region.click.x-5,y:Double(out.height)-region.click.y-5,width:10,height:10))
 }
 let url = URL(fileURLWithPath:CommandLine.arguments[2])
 let dest = CGImageDestinationCreateWithURL(url as CFURL,"public.png" as CFString,1,nil)!
 CGImageDestinationAddImage(dest,out.makeImage()!,nil)
 precondition(CGImageDestinationFinalize(dest))
 print("Annotated result: \(url.path)")
}
let draftCenter = composer.input.centerForChecks
let draftLine = OCRLine(text:"test prompt",confidence:1,bounds:CGRect(x:(draftCenter.x-composer.window.minX)/composer.window.width,y:1-(draftCenter.y-composer.window.minY)/composer.window.height,width:0.1,height:0.02))
let chatLine = OCRLine(text:"test prompt",confidence:1,bounds:CGRect(x:0.2,y:0.9,width:0.2,height:0.04))
precondition(composer.messageOccurrences([draftLine],expected:"test prompt") == 0)
precondition(composer.messageOccurrences([draftLine,chatLine],expected:"test prompt") == 1)
precondition(composer.messageOccurrences([draftLine,chatLine,chatLine],expected:"test prompt") == 2)
print("PASS receipt counts exclude composer draft and count only outside copies")
extension CGRect { var centerForChecks: CGPoint { CGPoint(x:midX,y:midY) } }
if let full = VisualComposer.locate(image:original,lines:try LocalOCR.recognize(original),window:CGRect(x:0,y:0,width:original.width,height:original.height)), let cropped = original.cropping(to:full.input.integral) {
 let recognized = try LocalOCR.recognize(cropped)
 print("User screenshot empty-area OCR:",recognized.map(\.text)); fflush(stdout)
 let contextual = full.inputLines(try LocalOCR.recognize(original))
 print("Full-context input-area OCR:",contextual.map(\.text))
 precondition(VisualComposer.permitsEmptyInput(contextual),"Full-context empty input rejected")
 precondition(!VisualComposer.permitsEmptyInput([OCRLine(text:"po anything",confidence:1,bounds:.zero)]),"Do not hide the crop error with a permissive typo allowlist")
 print("PASS empty-field OCR preserves full-image context")
}
if let compact = VisualComposer.locate(image:original,lines:[],window:CGRect(x:0,y:0,width:original.width,height:original.height)) {
 let unit = max(compact.icons.plus.width,compact.icons.microphone.width)
 let compactTextBand = CGRect(x:compact.icons.plus.minX,y:compact.icons.plus.minY-unit*1.5,width:compact.icons.microphone.minX-compact.icons.plus.minX,height:unit*1.3)
 precondition(compactTextBand.contains(compact.click),"Fallback click must stay inside a compact composer band")
 precondition(!VisualComposer.hasVisibleDraftEvidence([],expected:"example prompt"))
 precondition(!VisualComposer.hasVisibleDraftEvidence([OCRLine(text:"unrelated message",confidence:1,bounds:.zero)],expected:"example prompt"))
 print("PASS compact-composer fallback stays near icon row; unrelated/absent text cannot authorize copy verification")
}
if let candidate = VisualComposer.locate(image:original,lines:try LocalOCR.recognize(original),window:CGRect(x:0,y:0,width:original.width,height:original.height)) {
 let now = Date(timeIntervalSince1970:1000)
 let cache = VisualPositionCache(composer:candidate,image:original,now:now)!
 let start = Date()
 precondition(cache.matches(original,window:candidate.window,now:now.addingTimeInterval(1)))
 print("Cache validation milliseconds:",Date().timeIntervalSince(start)*1000)
 precondition(!cache.matches(original,window:candidate.window.offsetBy(dx:10,dy:0),now:now))
 precondition(!cache.matches(original,window:candidate.window,now:now.addingTimeInterval(121)))
 precondition(!cache.matches(noMic.makeImage()!,window:candidate.window,now:now))
 precondition(!cache.matches(gray.makeImage()!,window:candidate.window,now:now))
 print("PASS position cache hit; movement, expiry, missing icon and theme change invalidate")
}
