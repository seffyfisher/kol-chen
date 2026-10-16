import AppKit
import Foundation

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Resources", isDirectory: true)
let logo = NSImage(contentsOf: resources.appendingPathComponent("kol-chen-logo.pdf"))
guard let reel = NSImage(contentsOf: resources.appendingPathComponent("CassetteReel.png")) else {
    fatalError("Missing kol-chen icon artwork")
}

func drawFit(_ image: NSImage, in rect: NSRect) {
    let scale = min(rect.width / image.size.width, rect.height / image.size.height)
    let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
    image.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
}

try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for (name, pixels) in [("icon_16x16",16), ("icon_16x16@2x",32), ("icon_32x32",32),
                       ("icon_32x32@2x",64), ("icon_128x128",128), ("icon_128x128@2x",256),
                       ("icon_256x256",256), ("icon_256x256@2x",512),
                       ("icon_512x512",512), ("icon_512x512@2x",1024)] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    let background = NSBezierPath(roundedRect: NSRect(x: 30, y: 30, width: 964, height: 964), xRadius: 214, yRadius: 214)
    NSGradient(starting: NSColor(white: 0.24, alpha: 1), ending: NSColor(white: 0.11, alpha: 1))!
        .draw(in: background, angle: -90)
    NSColor.white.withAlphaComponent(0.14).setStroke()
    background.lineWidth = 2
    background.stroke()

    let cassette = NSBezierPath(roundedRect: NSRect(x: 88, y: 208, width: 848, height: 680), xRadius: 64, yRadius: 64)
    NSGradient(starting: NSColor(white: 0.13, alpha: 1), ending: NSColor(white: 0.045, alpha: 1))!
        .draw(in: cassette, angle: -90)
    NSColor(white: 0.33, alpha: 1).setStroke()
    cassette.lineWidth = 5
    cassette.stroke()
    let label = NSBezierPath(roundedRect: NSRect(x: 122, y: 704, width: 780, height: 146), xRadius: 22, yRadius: 22)
    NSColor(white: 0.065, alpha: 1).setFill()
    label.fill()
    NSColor.white.withAlphaComponent(0.23).setStroke()
    label.lineWidth = 2
    label.stroke()
    if let logo {
        drawFit(logo, in: NSRect(x: 270, y: 716, width: 484, height: 120))
    } else {
        let wordmark = NSAttributedString(string: "קול-חן", attributes: [
            .font: NSFont.boldSystemFont(ofSize: 110),
            .foregroundColor: NSColor(white: 0.93, alpha: 1)
        ])
        let size = wordmark.size()
        wordmark.draw(at: NSPoint(x: 512 - size.width / 2, y: 776 - size.height / 2))
    }

    let tape = NSBezierPath()
    tape.move(to: NSPoint(x: 234, y: 336))
    tape.line(to: NSPoint(x: 234, y: 264))
    tape.line(to: NSPoint(x: 790, y: 264))
    tape.line(to: NSPoint(x: 790, y: 336))
    NSColor(srgbRed: 0.20, green: 0.12, blue: 0.085, alpha: 1).setStroke()
    tape.lineWidth = 17
    tape.stroke()
    for (index, centerX) in [CGFloat(305), CGFloat(719)].enumerated() {
        let roll = NSBezierPath(ovalIn: NSRect(x: centerX - 193, y: 297, width: 386, height: 386))
        NSGradient(starting: NSColor(white: 0.055, alpha: 1), ending: NSColor(srgbRed: 0.12, green: 0.085, blue: 0.07, alpha: 1))!
            .draw(in: roll, angle: -90)
        NSColor.white.withAlphaComponent(0.07).setStroke()
        roll.lineWidth = 3
        roll.stroke()
        NSGraphicsContext.saveGraphicsState()
        context.cgContext.translateBy(x: centerX, y: 490)
        context.cgContext.rotate(by: index == 0 ? 0 : .pi * 32 / 180)
        reel.draw(in: NSRect(x: -174, y: -174, width: 348, height: 348))
        NSGraphicsContext.restoreGraphicsState()
    }
    let record = NSBezierPath(roundedRect: NSRect(x: 390, y: 86, width: 244, height: 85), xRadius: 22, yRadius: 22)
    NSColor(srgbRed: 0.79, green: 0.13, blue: 0.15, alpha: 1).setFill()
    record.fill()
    NSColor(srgbRed: 0.97, green: 0.94, blue: 0.88, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 496, y: 112, width: 32, height: 32)).fill()
    NSGraphicsContext.restoreGraphicsState()
    let png = bitmap.representation(using: .png, properties: [:])!
    try png.write(to: destination.appendingPathComponent(name + ".png"))
}
