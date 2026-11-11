// Focus.swift — watches which text box has the keyboard, in any app.
//
// Polls the focused element four times a second off the main thread (Accessibility notifications
// would need an observer per app and still miss web views). Only real, editable, visible text
// boxes count: no passwords, search or address bars, toolbars, or apps on the excluded list.

import AppKit
import ApplicationServices

/// A text box Penlight can write into.
struct Target {
    let element: AXUIElement
    let pid: pid_t
    let app: String
    let bundleId: String
    let window: AXUIElement?
    let windowTitle: String
    /// Screen frame, top-left origin.
    let frame: CGRect

    func same(_ o: Target?) -> Bool { o.map { CFEqual(element, $0.element) } ?? false }
}

final class Focus {
    static let shared = Focus()
    /// Called on the main thread when the box changes, moves, or goes away (nil).
    var onChange: ((Target?) -> Void)?
    private(set) var current: Target?

    private let queue = DispatchQueue(label: "penlight.focus", qos: .userInitiated)
    private var timer: Timer?
    private var busy = false

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    private func tick() {
        guard !busy, AX.trusted else { return }
        guard let front = NSWorkspace.shared.frontmostApplication else { publish(nil); return }
        // While Penlight's own panel has the keyboard, the last box stays the target.
        if front.processIdentifier == App.pid { return }
        let excluded = Prefs.excluded.contains(front.bundleIdentifier ?? "")
        busy = true
        queue.async { [weak self] in
            let t = excluded ? nil : Focus.find(in: front)
            DispatchQueue.main.async {
                self?.busy = false
                self?.publish(t)
            }
        }
    }

    private func publish(_ t: Target?) {
        let moved = t?.frame != current?.frame
        guard !(t?.same(current) ?? (current == nil)) || moved else { return }
        current = t
        onChange?(t)
    }

    /// The focused element of the frontmost app, if it's a text box worth offering help in.
    static func find(in app: NSRunningApplication) -> Target? {
        AX.wake(app)
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appEl, 0.25)
        guard var el = AX.element(AX.system, kAXFocusedUIElementAttribute) ?? AX.element(appEl, kAXFocusedUIElementAttribute)
        else { return nil }
        let pid = AX.pid(el)
        guard pid != App.pid, pid == app.processIdentifier else { return nil }

        guard editable(el) else { return nil }
        // In web pages the focused node can be a paragraph inside the editor; the box is the editable root.
        if let root = AX.element(el, "AXHighestEditableAncestor") { el = root }
        guard let frame = AX.frame(el), frame.width >= 80, frame.height >= 14 else { return nil }
        // Off-screen or scrolled-away boxes keep focus in some apps; ignore those.
        guard NSScreen.screens.contains(where: { $0.frame.intersects(AX.cocoa(frame)) }) else { return nil }
        if inToolbar(el) { return nil }

        let win = AX.element(el, kAXWindowAttribute)
        return Target(element: el, pid: pid, app: app.localizedName ?? "this app", bundleId: app.bundleIdentifier ?? "",
                      window: win, windowTitle: win.flatMap { AX.string($0, kAXTitleAttribute) } ?? "", frame: frame)
    }

    static func editable(_ el: AXUIElement) -> Bool {
        let role = AX.role(el), sub = AX.subrole(el)
        if sub == "AXSecureTextField" || sub == "AXSearchField" || role == "AXSearchField" { return false }
        if AX.bool(el, kAXEnabledAttribute) == false { return false }
        if AX.element(el, "AXEditableAncestor") != nil { return true }
        guard ["AXTextField", "AXTextArea", "AXComboBox"].contains(role) else { return false }
        // Read-only text areas (logs, message history) are AXTextArea too: only settable ones count.
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(el, kAXValueAttribute as CFString, &settable)
        return settable.boolValue
    }

    /// Address bars, find bars and toolbar search boxes live in a toolbar.
    private static func inToolbar(_ el: AXUIElement) -> Bool {
        var e: AXUIElement? = AX.element(el, kAXParentAttribute)
        for _ in 0..<14 {
            guard let cur = e else { return false }
            let r = AX.role(cur)
            if r == "AXToolbar" { return true }
            if r == "AXWindow" || r == "AXWebArea" { return false }
            e = AX.element(cur, kAXParentAttribute)
        }
        return false
    }

    /// Re-reads the box's frame (text areas grow as you type).
    static func refresh(_ t: Target) -> Target {
        guard let f = AX.frame(t.element) else { return t }
        return Target(element: t.element, pid: t.pid, app: t.app, bundleId: t.bundleId, window: t.window,
                      windowTitle: t.windowTitle, frame: f)
    }
}
