// Brand.swift — Penlight's colours and its pen-nib mark, drawn in code (button, menu bar, app icon).

import AppKit
import SwiftUI

enum Brand {
    static let violet = Color(red: 0.545, green: 0.361, blue: 0.965)    // #8B5CF6
    static let pink = Color(red: 0.925, green: 0.282, blue: 0.600)      // #EC4899
    static let gradient = LinearGradient(colors: [violet, pink], startPoint: .topLeading, endPoint: .bottomTrailing)
    /// Violet for text and links: deeper on light, lighter on dark, so it reads on glass either way.
    static let ink = Color(nsColor: NSColor(name: nil) { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.769, green: 0.710, blue: 0.992, alpha: 1)    // #C4B5FD
            : NSColor(red: 0.427, green: 0.157, blue: 0.851, alpha: 1)    // #6D28D9
    })

    /// The pen nib in a unit square, y pointing down, tip at the bottom. Even-odd: the slit and breather hole are cut out.
    static func nib(in r: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        var path = Path()
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

    /// A four-point sparkle centred in `r`.
    static func sparkle(in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.midY), w = r.width / 2, h = r.height / 2, k: CGFloat = 0.18
        var path = Path()
        path.move(to: CGPoint(x: c.x, y: c.y - h))
        path.addQuadCurve(to: CGPoint(x: c.x + w, y: c.y), control: CGPoint(x: c.x + w * k, y: c.y - h * k))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + h), control: CGPoint(x: c.x + w * k, y: c.y + h * k))
        path.addQuadCurve(to: CGPoint(x: c.x - w, y: c.y), control: CGPoint(x: c.x - w * k, y: c.y + h * k))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - h), control: CGPoint(x: c.x - w * k, y: c.y - h * k))
        path.closeSubpath()
        return path
    }

    /// The menu-bar icon: a nib leaning right with a small sparkle. A template image, so macOS tints it.
    static let menuIcon: NSImage = {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            cg.saveGState()
            cg.translateBy(x: 8, y: 10)
            cg.rotate(by: .pi / 5)
            cg.addPath(nib(in: CGRect(x: -5, y: -7.5, width: 10, height: 15)).cgPath)
            cg.setFillColor(NSColor.black.cgColor)
            cg.fillPath(using: .evenOdd)
            cg.restoreGState()
            cg.addPath(sparkle(in: CGRect(x: 11.5, y: 0.5, width: 6, height: 6)).cgPath)
            cg.fillPath()
            _ = rect
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = App.name
        return img
    }()
}

/// The nib as a SwiftUI shape.
struct Nib: Shape {
    func path(in rect: CGRect) -> Path { Brand.nib(in: rect) }
}
