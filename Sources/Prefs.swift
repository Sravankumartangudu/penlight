// Prefs.swift — settings, kept in UserDefaults (keys in the Keychain, see AI.swift).

import AppKit

enum Prefs {
    private static let d = UserDefaults.standard

    /// Apps where the button never shows: terminals, code editors and password managers type for you
    /// or hold secrets, and launchers close before you could use it.
    static let defaultExcluded = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
        "com.apple.dt.Xcode", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92",
        "com.1password.1password", "com.agilebits.onepassword7", "com.apple.keychainaccess", "com.apple.Passwords",
        "com.apple.Spotlight", "com.raycast.macos", "com.runningwithcrayons.Alfred",
    ]

    static func register() {
        d.register(defaults: [
            "showButton": true, "hotkey": true, "preview": false, "readScreen": true, "ocr": true,
            "about": "", "appearance": "system", "excluded": defaultExcluded, "pausedUntil": 0.0,
        ])
    }

    static var showButton: Bool { get { d.bool(forKey: "showButton") } set { d.set(newValue, forKey: "showButton"); changed() } }
    static var hotkey: Bool { get { d.bool(forKey: "hotkey") } set { d.set(newValue, forKey: "hotkey"); changed() } }
    /// Show the result first and insert on ↩, instead of typing it straight in.
    static var preview: Bool { get { d.bool(forKey: "preview") } set { d.set(newValue, forKey: "preview") } }
    static var readScreen: Bool { get { d.bool(forKey: "readScreen") } set { d.set(newValue, forKey: "readScreen") } }
    /// Fall back to reading the window's pixels when an app doesn't expose its text.
    static var ocr: Bool { get { d.bool(forKey: "ocr") } set { d.set(newValue, forKey: "ocr") } }
    static var about: String { get { d.string(forKey: "about") ?? "" } set { d.set(newValue, forKey: "about") } }
    static var appearance: String { get { d.string(forKey: "appearance") ?? "system" } set { d.set(newValue, forKey: "appearance"); applyAppearance() } }
    static var excluded: [String] { get { d.stringArray(forKey: "excluded") ?? [] } set { d.set(newValue, forKey: "excluded"); changed() } }

    static var pausedUntil: Date {
        get { Date(timeIntervalSince1970: d.double(forKey: "pausedUntil")) }
        set { d.set(newValue.timeIntervalSince1970, forKey: "pausedUntil"); changed() }
    }
    static var paused: Bool { pausedUntil > Date() }

    static func applyAppearance() {
        switch appearance {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    static let didChange = Notification.Name("PenlightPrefsChanged")
    private static func changed() { NotificationCenter.default.post(name: didChange, object: nil) }
}
