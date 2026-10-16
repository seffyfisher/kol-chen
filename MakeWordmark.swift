import AppKit
import CoreText

// Usage: swift MakeWordmark.swift /path/to/font.otf /path/to/output-directory
// Render the supplied face exactly; do not synthesize a heavier weight.
let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fatalError("Supply a font file and output directory")
}
let fontURL = URL(fileURLWithPath: arguments[1])
let destination = URL(fileURLWithPath: arguments[2], isDirectory: true)
let descriptors = CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as? [CTFontDescriptor]
guard let descriptor = descriptors?.first else { fatalError("Cannot read font") }
let font = CTFontCreateWithFontDescriptor(descriptor, 100, nil)
let paragraph = NSMutableParagraphStyle()
paragraph.baseWritingDirection = .rightToLeft
let text = NSAttributedString(string: "קול-חן", attributes: [.font: font, .paragraphStyle: paragraph])
let line = CTLineCreateWithAttributedString(text)
let outline = CGMutablePath()
for run in CTLineGetGlyphRuns(line) as! [CTRun] {
    let count = CTRunGetGlyphCount(run)
    var glyphs = [CGGlyph](repeating: 0, count: count)
    var positions = [CGPoint](repeating: .zero, count: count)
    CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
    CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
    let attributes = CTRunGetAttributes(run) as NSDictionary
    let runFont = attributes[kCTFontAttributeName] as! CTFont
    guard CTFontCopyPostScriptName(runFont) == CTFontCopyPostScriptName(font) else {
        fatalError("Wordmark contains a fallback font")
    }
    for index in 0..<count {
        guard glyphs[index] != 0,
              let glyph = CTFontCreatePathForGlyph(runFont, glyphs[index], nil) else {
            fatalError("Font lacks a wordmark glyph")
        }
        outline.addPath(glyph, transform: CGAffineTransform(translationX: positions[index].x, y: positions[index].y))
    }
}
let bounds = outline.boundingBoxOfPath
let padding: CGFloat = 2
let canvas = CGRect(x: 0, y: 0, width: bounds.width + padding * 2, height: bounds.height + padding * 2)
let ink = CGColor(gray: 0.93, alpha: 1)
func draw(in context: CGContext) {
    context.translateBy(x: padding - bounds.minX, y: padding - bounds.minY)
    context.setFillColor(ink)
    context.addPath(outline)
    context.fillPath()
}
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let pdfURL = destination.appendingPathComponent("kol-chen-logo.pdf")
var mediaBox = canvas
guard let consumer = CGDataConsumer(url: pdfURL as CFURL),
      let pdf = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { fatalError("Cannot create PDF") }
pdf.beginPDFPage(nil)
draw(in: pdf)
pdf.endPDFPage()
pdf.closePDF()
let scale: CGFloat = 6
let width = Int(ceil(canvas.width * scale))
let height = Int(ceil(canvas.height * scale))
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                             isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
context.scaleBy(x: scale, y: scale)
draw(in: context)
try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent("kol-chen-logo.png"))
print("Rendered \(CTFontCopyPostScriptName(font)) as vector outlines: \(pdfURL.path)")
