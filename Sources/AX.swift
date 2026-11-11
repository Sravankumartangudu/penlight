// AX.swift — small wrappers over the Accessibility API.

import AppKit
import ApplicationServices

enum AX {
    static let system: AXUIElement = {
        let s = AXUIElementCreateSystemWide()
        // A hung app must never freeze Penlight: give up on any one call after a quarter second.
        AXUIElementSetMessagingTimeout(s, 0.25)
        return s
    }()

    static var trusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that adds Penlight to the Accessibility list.
    static func askForTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
    }
    static func string(_ e: AXUIElement, _ name: String) -> String? { attr(e, name) as? String }
    static func bool(_ e: AXUIElement, _ name: String) -> Bool? { (attr(e, name) as? NSNumber)?.boolValue }
    static func element(_ e: AXUIElement, _ name: String) -> AXUIElement? {
        guard let v = attr(e, name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }
    static func role(_ e: AXUIElement) -> String { string(e, kAXRoleAttribute) ?? "" }
    static func subrole(_ e: AXUIElement) -> String { string(e, kAXSubroleAttribute) ?? "" }
    static func pid(_ e: AXUIElement) -> pid_t { var p: pid_t = 0; AXUIElementGetPid(e, &p); return p }

    /// The element's frame in screen points, top-left origin (the Accessibility API's own coordinates).
    static func frame(_ e: AXUIElement) -> CGRect? {
        guard let p = attr(e, kAXPositionAttribute), let s = attr(e, kAXSizeAttribute) else { return nil }
        return rect(position: p, size: s)
    }
    static func rect(position p: AnyObject, size s: AnyObject) -> CGRect? {
        guard CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var pt = CGPoint.zero, sz = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &pt), AXValueGetValue(s as! AXValue, .cgSize, &sz) else { return nil }
        return CGRect(origin: pt, size: sz)
    }

    /// The selected range in UTF-16 units.
    static func selectedRange(_ e: AXUIElement) -> NSRange? {
        guard let v = attr(e, kAXSelectedTextRangeAttribute), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var r = CFRange()
        guard AXValueGetValue(v as! AXValue, .cfRange, &r) else { return nil }
        return NSRange(location: r.location, length: r.length)
    }

    static func set(_ e: AXUIElement, _ name: String, _ value: AnyObject) {
        AXUIElementSetAttributeValue(e, name as CFString, value)
    }

    /// Converts an Accessibility frame (top-left origin) to Cocoa's (bottom-left origin).
    static func cocoa(_ r: CGRect) -> CGRect {
        let h = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
    }
    /// The screen that holds most of a Cocoa rect.
    static func screen(for r: CGRect) -> NSScreen? {
        NSScreen.screens.max { a, b in a.frame.intersection(r).area < b.frame.intersection(r).area } ?? NSScreen.main
    }

    /// Chrome, Electron and friends only build their accessibility tree once someone asks for it.
    private static var woken = Set<pid_t>()
    static func wake(_ app: NSRunningApplication) {
        guard !woken.contains(app.processIdentifier), let url = app.bundleURL else { return }
        woken.insert(app.processIdentifier)
        let fm = FileManager.default
        let electron = fm.fileExists(atPath: url.appendingPathComponent("Contents/Frameworks/Electron Framework.framework").path)
        let chromium = ["com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser", "company.thebrowser.Browser",
                        "com.vivaldi.Vivaldi", "com.operasoftware.Opera"].contains(app.bundleIdentifier ?? "")
        guard electron || chromium else { return }
        let e = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(e, 0.25)
        set(e, "AXManualAccessibility", kCFBooleanTrue)
        // Browsers listen for this one instead (Electron apps don't need it, and it slows their window moves).
        if chromium { set(e, "AXEnhancedUserInterface", kCFBooleanTrue) }
        log.info("woke accessibility for \(app.bundleIdentifier ?? "?", privacy: .public)")
    }
}

extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
