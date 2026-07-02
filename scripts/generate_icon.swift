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

// Same geometry as makeStatusLogoImage in BellApp.swift (18pt design space):
// square body + equilateral roof, single stroke weight, open bottom.
// Rendered into the central ~72% of the icon canvas so the app icon keeps
// conventional margins.
func drawLogo(scale: CGFloat) {
    let inset: CGFloat = 0.72
    let u = scale * 256 * inset / 18
    let off = scale * 256 * (1 - inset) / 2
    func p(_ px: CGFloat, _ py: CGFloat) -> NSPoint { NSPoint(x: off + px * u, y: off + py * u) }

    black.setFill()
    black.setStroke()

    let strokeW: CGFloat = 1.45
    let cx: CGFloat = 9
    let half: CGFloat = 4.05
    let left = cx - half
    let right = cx + half
    let bottom: CGFloat = 1.3
    let eaves = bottom + 2 * half
    let apex = eaves + half * 1.732

    let tower = NSBezierPath()
    tower.move(to: p(left, bottom))
    tower.line(to: p(left, eaves))
    tower.line(to: p(cx, apex))
    tower.line(to: p(right, eaves))
    tower.line(to: p(right, bottom))
    tower.lineWidth = strokeW * u
    tower.lineCapStyle = .butt
    tower.lineJoinStyle = .miter
    tower.stroke()

    let beam = NSBezierPath()
    beam.move(to: p(left, eaves))
    beam.line(to: p(right, eaves))
    beam.lineWidth = strokeW * u
    beam.lineCapStyle = .butt
    beam.stroke()

    let cy = (bottom + eaves) / 2
    let d: CGFloat = 4.7
    let clock = NSBezierPath(ovalIn: NSRect(x: off + (cx - d / 2) * u, y: off + (cy - d / 2) * u, width: d * u, height: d * u))
    clock.lineWidth = 0.85 * u
    clock.stroke()

    let hands = NSBezierPath()
    hands.move(to: p(cx, cy + 1.3))
    hands.line(to: p(cx, cy))
    hands.line(to: p(cx + 1.2, cy))
    hands.lineWidth = 0.65 * u
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
