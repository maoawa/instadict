import AppKit

// Original vector artwork, rasterized to the App Store's required icon size.
let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                             bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
                             isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let mint = NSColor(srgbRed: 0.690, green: 0.886, blue: 0.702, alpha: 1)
let ink = NSColor(srgbRed: 0.055, green: 0.12, blue: 0.08, alpha: 1)
mint.setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()

let cover = NSBezierPath(roundedRect: NSRect(x: 245, y: 208, width: 534, height: 610), xRadius: 60, yRadius: 60)
ink.setFill()
cover.fill()
mint.setFill()
NSBezierPath(roundedRect: NSRect(x: 276, y: 313, width: 472, height: 474), xRadius: 32, yRadius: 32).fill()
NSBezierPath(roundedRect: NSRect(x: 276, y: 239, width: 472, height: 48), xRadius: 24, yRadius: 24).fill()

ink.setStroke()
let spine = NSBezierPath()
spine.move(to: NSPoint(x: 335, y: 330))
spine.line(to: NSPoint(x: 335, y: 768))
spine.lineWidth = 16
spine.lineCapStyle = .round
spine.stroke()

let letter: NSString = "a"
let font = NSFont(name: "Georgia-Bold", size: 365) ?? NSFont.boldSystemFont(ofSize: 365)
letter.draw(at: NSPoint(x: 405, y: 334), withAttributes: [.font: font, .foregroundColor: ink])
NSGraphicsContext.restoreGraphicsState()

let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "InstaDict Watch App/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
try bitmap.representation(using: .png, properties: [:])!.write(to: output)
print(output.path)
