import AppKit
import Foundation

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let black = NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
let iconEntries: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func drawLogo(scale: CGFloat) {
    func x(_ value: CGFloat) -> CGFloat { value * scale }
    func y(_ value: CGFloat) -> CGFloat { (256 - value) * scale }

    black.setFill()
    black.setStroke()

    let roof = NSBezierPath()
    roof.move(to: NSPoint(x: x(88), y: y(96)))
    roof.line(to: NSPoint(x: x(128), y: y(48)))
    roof.line(to: NSPoint(x: x(168), y: y(96)))
    roof.line(to: NSPoint(x: x(160), y: y(96)))
    roof.line(to: NSPoint(x: x(128), y: y(58)))
    roof.line(to: NSPoint(x: x(96), y: y(96)))
    roof.close()
    roof.fill()

    NSBezierPath(rect: NSRect(x: x(88), y: y(102), width: 80 * scale, height: 6 * scale)).fill()
    NSBezierPath(rect: NSRect(x: x(88), y: y(208), width: 6 * scale, height: 112 * scale)).fill()
    NSBezierPath(rect: NSRect(x: x(162), y: y(208), width: 6 * scale, height: 112 * scale)).fill()

    let clock = NSBezierPath(ovalIn: NSRect(x: x(110), y: y(151), width: 36 * scale, height: 36 * scale))
    clock.lineWidth = max(1, 4 * scale)
    clock.stroke()

    let hands = NSBezierPath()
    hands.move(to: NSPoint(x: x(128), y: y(121)))
    hands.line(to: NSPoint(x: x(128), y: y(133)))
    hands.line(to: NSPoint(x: x(140), y: y(133)))
    hands.lineWidth = max(1, 4 * scale)
    hands.lineCapStyle = .butt
    hands.lineJoinStyle = .miter
    hands.stroke()
}

for entry in iconEntries {
    let size = entry.pixels
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    NSGraphicsContext.current?.imageInterpolation = .high
    NSColor.clear.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
    drawLogo(scale: CGFloat(size) / 256)

    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        continue
    }

    let base = outputDirectory.appendingPathComponent(entry.name)
    try png.write(to: base)
}
