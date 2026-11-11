// AppDelegate.swift — the menu-bar item, and wiring focus → button → writing box.

import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var item: NSStatusItem!

    func applicationDidFinishLaunching(_ n: Notification) {
        Prefs.register()
        Prefs.applyAppearance()

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Brand.menuIcon
        item.button?.toolTip = App.name
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        build(menu)

        Focus.shared.onChange = { [weak self] t in self?.focusChanged(t) }
        Pill.shared.onTap = { t in Composer.isOpen ? Composer.close() : Composer.open(for: Focus.refresh(t)) }
        Hotkey.shared.action = { Self.hotkey() }
        apply()
        NotificationCenter.default.addObserver(forName: Prefs.didChange, object: nil, queue: .main) { [weak self] _ in self?.apply() }

        NexusBeacon.start(name: App.name) {
            if !AX.trusted { return ("warn", "needs Accessibility") }
            if Prefs.paused { return ("ok", "paused") }
            if let p = AI.problem() { return ("warn", p) }
            return ("ok", "writing with \(AI.current.short)")
        }
        NexusBeacon.attach(item)

        if !UserDefaults.standard.bool(forKey: "loginSet") {
            UserDefaults.standard.set(true, forKey: "loginSet")
            try? SMAppService.mainApp.register()
        }
        if !AX.trusted {
            AX.askForTrust()
            SettingsWindow.show(tab: .permissions)
        }
        Focus.shared.start()
        log.info("started \(App.version, privacy: .public)")
    }

    private func apply() {
        Hotkey.shared.set(Prefs.hotkey)
        focusChanged(Focus.shared.current)
    }

    private func focusChanged(_ t: Target?) {
        guard Prefs.showButton, !Prefs.paused, let t else { Pill.shared.show(nil); return }
        Pill.shared.show(t)
    }

    /// ⌃⌥Space: the box you're in (even in an excluded app — you asked), else a free writing pad.
    private static func hotkey() {
        if Composer.isOpen { Composer.close(); return }
        guard AX.trusted else { SettingsWindow.show(tab: .permissions); return }
        if let t = Focus.shared.current { Composer.open(for: Focus.refresh(t)); return }
        guard let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != App.pid else { Composer.open(for: nil); return }
        DispatchQueue.global(qos: .userInitiated).async {
            let t = Focus.find(in: front)
            DispatchQueue.main.async { Composer.open(for: t) }
        }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) { build(menu) }

    private func build(_ menu: NSMenu) {
        menu.removeAllItems()
        let status: String
        if !AX.trusted { status = "⚠️ Needs Accessibility — open Permissions" }
        else if Prefs.paused { status = "Paused until \(Prefs.pausedUntil.formatted(date: .omitted, time: .shortened))" }
        else if let p = AI.problem() { status = "⚠️ " + p }
        else { status = "Writing with \(AI.current.name) · \(AI.modelLabel(AI.current))" }
        let s = NSMenuItem(title: status, action: AX.trusted ? nil : #selector(openPermissions), keyEquivalent: "")
        s.target = self
        menu.addItem(s)
        menu.addItem(.separator())

        add(menu, "Write here  \(Hotkey.label)", #selector(writeHere))
        let copy = add(menu, "Copy last result", #selector(copyLast))
        copy.isEnabled = !Inserter.last.isEmpty
        menu.addItem(.separator())

        add(menu, "Show button beside text boxes", #selector(toggleButton)).state = Prefs.showButton ? .on : .off
        if Prefs.paused { add(menu, "Resume", #selector(resume)) } else { add(menu, "Pause for 1 hour", #selector(pause)) }
        if let front = NSWorkspace.shared.frontmostApplication, let id = front.bundleIdentifier, front.processIdentifier != App.pid {
            let ex = Prefs.excluded.contains(id)
            let i = add(menu, ex ? "Show in \(front.localizedName ?? id) again" : "Don't show in \(front.localizedName ?? id)", #selector(toggleApp(_:)))
            i.representedObject = id
        }
        menu.addItem(.separator())

        let ai = NSMenuItem(title: "AI", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for p in AI.all {
            let i = NSMenuItem(title: p.name, action: #selector(pickAI(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = p.id
            i.state = AI.current.id == p.id ? .on : .off
            if let problem = AI.problem(p) { i.toolTip = problem; i.title += "  (set up)" }
            sub.addItem(i)
        }
        sub.addItem(.separator())
        let set = NSMenuItem(title: "AI settings…", action: #selector(openAI), keyEquivalent: "")
        set.target = self
        sub.addItem(set)
        ai.submenu = sub
        menu.addItem(ai)

        let look = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        let lsub = NSMenu()
        for (id, name) in [("system", "System"), ("light", "Light"), ("dark", "Dark")] {
            let i = NSMenuItem(title: name, action: #selector(pickLook(_:)), keyEquivalent: "")
            i.target = self; i.representedObject = id
            i.state = Prefs.appearance == id ? .on : .off
            lsub.addItem(i)
        }
        look.submenu = lsub
        menu.addItem(look)

        add(menu, "Settings…", #selector(openSettings), key: ",")
        add(menu, "About \(App.name)", #selector(about))
        menu.addItem(.separator())
        add(menu, "Quit \(App.name)", #selector(quit), key: "q")
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ sel: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = self
        menu.addItem(i)
        return i
    }

    @objc private func writeHere() { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { Self.hotkey() } }
    @objc private func copyLast() { Inserter.copy(Inserter.last) }
    @objc private func toggleButton() { Prefs.showButton.toggle() }
    @objc private func pause() { Prefs.pausedUntil = Date().addingTimeInterval(3600) }
    @objc private func resume() { Prefs.pausedUntil = .distantPast }
    @objc private func toggleApp(_ i: NSMenuItem) {
        guard let id = i.representedObject as? String else { return }
        var list = Prefs.excluded
        if list.contains(id) { list.removeAll { $0 == id } } else { list.append(id) }
        Prefs.excluded = list
    }
    @objc private func pickAI(_ i: NSMenuItem) {
        guard let id = i.representedObject as? String, let p = AI.all.first(where: { $0.id == id }) else { return }
        if AI.problem(p) != nil { AI.setProvider(id); SettingsWindow.show(tab: .ai) } else { AI.setProvider(id) }
    }
    @objc private func pickLook(_ i: NSMenuItem) { if let id = i.representedObject as? String { Prefs.appearance = id } }
    @objc private func openAI() { SettingsWindow.show(tab: .ai) }
    @objc private func openPermissions() { SettingsWindow.show(tab: .permissions) }
    @objc private func openSettings() { SettingsWindow.show() }
    @objc private func about() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "Writes the reply for the box you're typing in, from what's on screen.\n\(App.repo.absoluteString)",
                                         attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]),
        ])
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
