// Context.swift — reads what's on screen around the text box: the chat, the email thread, the post.
//
// First the window's accessibility tree (fast, exact text). When an app exposes too little text that
// way (some Electron and canvas apps), and Screen Recording is allowed, it reads the window's pixels
// with on-device text recognition instead. Either way the text stays on this Mac until you press ↩.

import AppKit
import ApplicationServices
import ScreenCaptureKit
import Vision

struct Screen {
    var text = ""
    /// "screen" (accessibility) or "pixels" (text recognition).
    var source = "screen"
    var empty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

enum Context {
    /// Reads the target's window. Runs off the main thread; calls back on main.
    static func read(_ t: Target, done: @escaping (Screen) -> Void) {
        guard Prefs.readScreen else { done(Screen()); return }
        DispatchQueue.global(qos: .userInitiated).async {
            let items = t.window.map { tree($0, skip: t.element) } ?? []
            let text = Writer.pick(items, field: t.frame)
            if text.count >= 160 || !Prefs.ocr || !CGPreflightScreenCaptureAccess() {
                DispatchQueue.main.async { done(Screen(text: text, source: "screen")) }
                return
            }
            Task {
                let seen = await pixels(t)
                let use = seen.count > text.count ? Screen(text: seen, source: "pixels") : Screen(text: text, source: "screen")
                DispatchQueue.main.async { done(use) }
            }
        }
    }

    // MARK: Accessibility tree

    private static let skipRoles: Set<String> = [
        "AXMenuBar", "AXMenu", "AXMenuItem", "AXToolbar", "AXButton", "AXImage", "AXScrollBar", "AXSlider",
        "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXIncrementor", "AXDisclosureTriangle",
        "AXTabGroup", "AXProgressIndicator", "AXBusyIndicator", "AXValueIndicator", "AXSecureTextField",
    ]
    private static let textRoles: Set<String> = ["AXStaticText", "AXTextArea", "AXTextField", "AXHeading", "AXLink"]
    private static let attrs = [kAXRoleAttribute, kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute,
                                kAXPositionAttribute, kAXSizeAttribute, kAXChildrenAttribute] as CFArray

    /// (frame, text) for every readable text node, in the window's own order. Bounded in time and size.
    static func tree(_ window: AXUIElement, skip target: AXUIElement) -> [(CGRect, String)] {
        let deadline = Date().addingTimeInterval(0.8)
        var out: [(CGRect, String)] = [], visited = 0
        func walk(_ e: AXUIElement, depth: Int) {
            guard depth < 80, visited < 5000, Date() < deadline else { return }
            visited += 1
            if CFEqual(e, target) { return }
            var raw: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(e, attrs, [], &raw) == .success,
                  let v = raw as [AnyObject]?, v.count == 7 else { return }
            func str(_ i: Int) -> String? { v[i] as? String }
            let role = str(0) ?? ""
            if skipRoles.contains(role) { return }
            if textRoles.contains(role) {
                var s = str(1) ?? ""
                if s.isEmpty { s = str(2) ?? "" }
                if s.isEmpty, role == "AXHeading" || role == "AXLink" { s = str(3) ?? "" }
                if !s.isEmpty, let r = AX.rect(position: v[4], size: v[5]), r.width > 0, r.height > 0 {
                    out.append((r, s))
                }
                // A static text's children only repeat it; a text area's are its lines.
                if role == "AXStaticText" || role == "AXTextArea" || role == "AXTextField" { return }
            }
            for c in (v[6] as? [AXUIElement]) ?? [] { walk(c, depth: depth + 1) }
        }
        walk(window, depth: 0)
        return out
    }

    // MARK: Pixels (Screen Recording + Vision, all on this Mac)

    static func pixels(_ t: Target) async -> String {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            guard let win = window(content.windows, pid: t.pid, near: t.frame) else { return "" }
            let filter = SCContentFilter(desktopIndependentWindow: win)
            let cfg = SCStreamConfiguration()
            let scale = NSScreen.screens.first(where: { $0.frame.intersects(AX.cocoa(win.frame)) })?.backingScaleFactor ?? 2
            cfg.width = Int(win.frame.width * scale)
            cfg.height = Int(win.frame.height * scale)
            cfg.showsCursor = false
            let img = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
            let items = recognize(img, in: win.frame)
            return Writer.pick(items, field: t.frame)
        } catch {
            log.error("screen read failed: \(error.localizedDescription, privacy: .public)")
            return ""
        }
    }

    /// The app's on-screen window that holds the text box. SCWindow frames use the same top-left origin as AX.
    private static func window(_ all: [SCWindow], pid: pid_t, near f: CGRect) -> SCWindow? {
        let mine = all.filter { $0.owningApplication?.processID == pid && $0.windowLayer == 0 && $0.frame.width > 50 }
        return mine.first { $0.frame.contains(CGPoint(x: f.midX, y: f.midY)) }
            ?? mine.max { $0.frame.intersection(f).area < $1.frame.intersection(f).area }
    }

    /// Text lines and their frames in screen points (top-left origin).
    private static func recognize(_ img: CGImage, in frame: CGRect) -> [(CGRect, String)] {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        req.automaticallyDetectsLanguage = true
        try? VNImageRequestHandler(cgImage: img).perform([req])
        let obs = (req.results ?? []).compactMap { o -> (CGRect, String)? in
            guard let s = o.topCandidates(1).first?.string, !s.isEmpty else { return nil }
            // Vision boxes are normalised, bottom-left origin.
            let b = o.boundingBox
            let r = CGRect(x: frame.minX + b.minX * frame.width, y: frame.minY + (1 - b.maxY) * frame.height,
                           width: b.width * frame.width, height: b.height * frame.height)
            return (r, s)
        }
        // Reading order: top to bottom, then left to right on the same line.
        return obs.sorted { a, b in abs(a.0.minY - b.0.minY) < 6 ? a.0.minX < b.0.minX : a.0.minY < b.0.minY }
    }
}
