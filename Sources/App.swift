// App.swift — names, folders and the log.

import AppKit
import os

enum App {
    static let name = "Penlight"
    static let bundleId = Bundle.main.bundleIdentifier ?? "com.stangudu.penlight"
    static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    static let repo = URL(string: "https://github.com/Sravankumartangudu/penlight")!
    static let pid = ProcessInfo.processInfo.processIdentifier

    /// ~/Library/Application Support/Penlight — Claude Code runs here, so no project settings ride along.
    static let support: URL = {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()
}

/// Logs what Penlight does, never what it reads or writes: screen text and drafts stay out of the log.
let log = Logger(subsystem: App.bundleId, category: "app")
