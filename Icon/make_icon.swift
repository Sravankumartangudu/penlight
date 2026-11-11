// Draws Penlight's app icon once at 1024 px and writes AppIcon.icns.
//   swift Icon/make_icon.swift     (run from the repo folder)

import AppKit

let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let cg = NSGraphicsContext.current!.cgContext

// The tile: Apple's grid (824 pt body, 100 pt margin), soft shadow, violet → pink.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let tile = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: NSColor.black.withAlphaComponent(0.28).cgColor)
cg.addPath(tile); cg.setFillColor(NSColor.white.cgColor); cg.fillPath()
cg.restoreGState()
cg.saveGState()
cg.addPath(tile); cg.clip()
let colors = [NSColor(red: 0.545, green: 0.361, blue: 0.965, alpha: 1).cgColor,
              NSColor(red: 0.925, green: 0.282, blue: 0.600, alpha: 1).cgColor] as CFArray
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
cg.drawLinearGradient(grad, start: CGPoint(x: 100, y: 924), end: CGPoint(x: 924, y: 100), options: [])
// A soft light from the top.
let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: [NSColor.white.withAlphaComponent(0.22).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
cg.drawRadialGradient(glow, startCenter: CGPoint(x: 380, y: 860), startRadius: 0, endCenter: CGPoint(x: 380, y: 860), endRadius: 620, options: [])

// Faint lines of writing, bottom left, as if the nib just wrote them.
cg.setFillColor(NSColor.white.withAlphaComponent(0.28).cgColor)
for (i, w) in [CGFloat(330), 250, 170].enumerated() {
    cg.addPath(CGPath(roundedRect: CGRect(x: 200, y: 330 - CGFloat(i) * 70, width: w, height: 30), cornerWidth: 15, cornerHeight: 15, transform: nil))
}
cg.fillPath()

// The nib, leaning right, tip down-left toward the lines. Unit shape with y down, as in Brand.nib.
func nibPath(_ r: CGRect) -> CGPath {
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
    let path = CGMutablePath()
    path.move(to: p(0.5, 0.97))
    path.addQuadCurve(to: p(0.17, 0.46), control: p(0.27, 0.78))
    path.addLine(to: p(0.31, 0.06))
    path.addQuadCurve(to: p(0.69, 0.06), control: p(0.5, 0.0))
    path.addLine(to: p(0.83, 0.46))
    path.addQuadCurve(to: p(0.5, 0.97), control: p(0.73, 0.78))
    path.closeSubpath()
    path.addEllipse(in: CGRect(x: r.minX + 0.43 * r.width, y: r.minY + 0.37 * r.height, width: 0.14 * r.width, height: 0.14 * r.height))
    path.addRect(CGRect(x: r.minX + 0.48 * r.width, y: r.minY + 0.53 * r.height, width: 0.04 * r.width, height: 0.40 * r.height))
    return path
}
cg.saveGState()
cg.translateBy(x: 580, y: 560)
cg.scaleBy(x: 1, y: -1)              // the shape is drawn y-down
cg.rotate(by: .pi / 5)
cg.setShadow(offset: CGSize(width: 0, height: 12), blur: 30, color: NSColor(red: 0.3, green: 0.1, blue: 0.5, alpha: 0.45).cgColor)
cg.addPath(nibPath(CGRect(x: -170, y: -250, width: 340, height: 500)))
cg.setFillColor(NSColor.white.cgColor)
cg.fillPath(using: .evenOdd)
cg.restoreGState()

// The sparkle: the "light" in Penlight.
func sparkle(_ c: CGPoint, _ r: CGFloat) -> CGPath {
    let k: CGFloat = 0.18, path = CGMutablePath()
    path.move(to: CGPoint(x: c.x, y: c.y + r))
    path.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + r * k, y: c.y + r * k))
    path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x + r * k, y: c.y - r * k))
    path.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - r * k, y: c.y - r * k))
    path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x - r * k, y: c.y + r * k))
    path.closeSubpath()
    return path
}
cg.setFillColor(NSColor.white.cgColor)
cg.addPath(sparkle(CGPoint(x: 790, y: 790), 78)); cg.fillPath()
cg.setFillColor(NSColor.white.withAlphaComponent(0.75).cgColor)
cg.addPath(sparkle(CGPoint(x: 700, y: 870), 30)); cg.fillPath()
cg.restoreGState()
NSGraphicsContext.restoreGraphicsState()

// Shrink to every size the .icns needs.
let set = URL(fileURLWithPath: "Icon/AppIcon.iconset")
try? FileManager.default.removeItem(at: set)
try! FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
let full = NSImage(size: NSSize(width: size, height: size)); full.addRepresentation(rep)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let r = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                                 hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: r)
        NSGraphicsContext.current?.imageInterpolation = .high
        full.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        try! r.representation(using: .png, properties: [:])!.write(to: set.appendingPathComponent(name))
    }
}
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "Icon/icon-1024.png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", "Icon/AppIcon.icns"]
try! p.run(); p.waitUntilExit()
try? FileManager.default.removeItem(at: set)
print("✓ Icon/AppIcon.icns")
