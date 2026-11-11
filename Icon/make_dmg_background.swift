// Renders the background for the Penlight.dmg installer window (640×400, plus @2x).
//   swift Icon/make_dmg_background.swift <out.tiff>
// build.sh --dist runs this; icons sit at (160, 190) and (480, 190) in Finder's top-left coordinates.
import AppKit

let w = 640.0, h = 400.0
func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
}
let ink = hex(0x2E1065), violet = hex(0x7C3AED), pink = hex(0xEC4899)

func render(scale: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w) * scale, pixelsHigh: Int(h) * scale,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: w, height: h)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let cg = NSGraphicsContext.current!.cgContext
    cg.scaleBy(x: CGFloat(scale), y: CGFloat(scale))

    // Pale lavender into blush.
    let bg = CGGradient(colorsSpace: nil, colors: [hex(0xF1ECFF).cgColor, hex(0xF6EEFB).cgColor, hex(0xFDEEF5).cgColor] as CFArray,
                        locations: [0, 0.55, 1])!
    cg.drawLinearGradient(bg, start: CGPoint(x: 0, y: h), end: CGPoint(x: w, y: 0), options: [])

    // Sparkles.
    func sparkle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ c: NSColor) {
        let k: CGFloat = 0.18, p = CGMutablePath()
        p.move(to: CGPoint(x: x, y: y + r))
        p.addQuadCurve(to: CGPoint(x: x + r, y: y), control: CGPoint(x: x + r * k, y: y + r * k))
        p.addQuadCurve(to: CGPoint(x: x, y: y - r), control: CGPoint(x: x + r * k, y: y - r * k))
        p.addQuadCurve(to: CGPoint(x: x - r, y: y), control: CGPoint(x: x - r * k, y: y - r * k))
        p.addQuadCurve(to: CGPoint(x: x, y: y + r), control: CGPoint(x: x - r * k, y: y + r * k))
        cg.addPath(p); cg.setFillColor(c.cgColor); cg.fillPath()
    }
    sparkle(70, h - 58, 14, violet.withAlphaComponent(0.35))
    sparkle(96, h - 34, 6, pink.withAlphaComponent(0.4))
    sparkle(574, h - 50, 11, pink.withAlphaComponent(0.35))
    sparkle(548, h - 76, 5, violet.withAlphaComponent(0.4))

    // Dotted violet → pink arc from the app to Applications, ending in an arrowhead.
    let y = h - 190
    let arc = CGMutablePath()
    arc.move(to: CGPoint(x: 245, y: y))
    arc.addQuadCurve(to: CGPoint(x: 370, y: y + 4), control: CGPoint(x: 310, y: y + 40))
    cg.saveGState()
    cg.addPath(arc.copy(dashingWithPhase: 0, lengths: [2, 12]).copy(strokingWithWidth: 5, lineCap: .round, lineJoin: .round, miterLimit: 10))
    cg.move(to: CGPoint(x: 398, y: y - 4))
    cg.addLine(to: CGPoint(x: 376, y: y + 12))
    cg.addLine(to: CGPoint(x: 380, y: y - 12))
    cg.closePath()
    cg.clip()
    let g = CGGradient(colorsSpace: nil, colors: [violet.cgColor, pink.cgColor] as CFArray, locations: [0, 1])!
    cg.drawLinearGradient(g, start: CGPoint(x: 240, y: y), end: CGPoint(x: 400, y: y), options: [])
    cg.restoreGState()

    // Finder draws icon labels in black (Light Mode) or white (Dark Mode); a mid-tone nameplate
    // under each label keeps both readable on the light background.
    for x in [160.0, 480.0] {
        let plate = CGPath(roundedRect: CGRect(x: x - 75, y: h - 283, width: 150, height: 28),
                           cornerWidth: 14, cornerHeight: 14, transform: nil)
        cg.addPath(plate)
        cg.setFillColor(ink.withAlphaComponent(0.35).cgColor)
        cg.fillPath()
    }

    func text(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor, y: CGFloat, kern: CGFloat = 0) {
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        var font = NSFont.systemFont(ofSize: size, weight: weight)
        if let d = font.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: size) { font = f }
        let str = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: para, .kern: kern])
        str.draw(in: CGRect(x: 0, y: y, width: w, height: size * 1.5))
    }
    text("✦ PENLIGHT", 14, .heavy, violet, y: h - 104, kern: 2)
    text("Drag Penlight into Applications to install", 17, .bold, ink, y: 84)
    text("First launch blocked? System Settings → Privacy & Security → Open Anyway", 11, .medium,
         ink.withAlphaComponent(0.75), y: 18)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "background.tiff"
// A multi-representation TIFF lets Finder pick the sharp 2x image on Retina screens.
let data = NSBitmapImageRep.tiffRepresentationOfImageReps(in: [render(scale: 1), render(scale: 2)], using: .lzw, factor: 0)!
try! data.write(to: URL(fileURLWithPath: out))
print("✓ wrote \(out)")
