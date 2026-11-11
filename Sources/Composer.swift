// Composer.swift — the small writing box: say what you want (or just press ↩), watch it write, and it
// goes into the text box.

import AppKit
import SwiftUI

/// A panel that takes the keyboard without bringing Penlight to the front, so the app you're in stays active.
final class KeyPanel: NSPanel {
    /// Grow down from this top edge, or up from this bottom edge, as the content changes height.
    var pinnedTop: CGFloat?
    var pinnedBottom: CGFloat?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Composer.width, height: 120),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        animationBehavior = .utilityWindow
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func setFrame(_ r: NSRect, display: Bool) {
        var f = r
        if let top = pinnedTop { f.origin.y = top - f.height } else if let bottom = pinnedBottom { f.origin.y = bottom }
        super.setFrame(f, display: display)
    }
}

final class ComposerModel: ObservableObject {
    enum Phase: Equatable { case asking, writing, review, failed(String) }

    @Published var phase: Phase = .asking
    @Published var ask = ""
    @Published var output = ""
    @Published var field = FieldText()
    @Published var screen: Screen?
    @Published var reading = false
    @Published var useScreen = true
    @Published var peek = false
    @Published var providerId = AI.current.id
    @Published var note: String?
    var target: Target?
    /// The version being refined (review mode: a new instruction changes this text).
    var previous: String?
    var lastAsk = ""

    var appName: String { target?.app ?? "" }
    var canInsert: Bool { target != nil }
    var provider: Provider { AI.all.first { $0.id == providerId } ?? AI.current }
}

enum Composer {
    static let width: CGFloat = 480
    static let model = ComposerModel()
    private static var run: AIRun?
    private static var mouseMonitor: Any?
    private static var appMonitor: NSObjectProtocol?
    private static var waitingForScreen = false

    private static let panel: KeyPanel = {
        let p = KeyPanel()
        let host = NSHostingController(rootView: ComposerView(model: model))
        host.sizingOptions = [.preferredContentSize]
        p.contentViewController = host
        return p
    }()

    static var isOpen: Bool { panel.isVisible }

    /// Opens for a text box, or (no box) as a free writing pad that copies its result.
    static func open(for t: Target?) {
        run?.cancel()
        let m = model
        m.target = t
        m.phase = .asking
        m.ask = ""; m.output = ""; m.note = nil; m.previous = nil; m.peek = false; m.useScreen = true
        m.providerId = AI.current.id
        m.field = t.map(Inserter.field) ?? FieldText()
        m.screen = nil
        m.reading = t != nil && Prefs.readScreen
        if let t {
            Context.read(t) { s in
                guard m.target?.same(t) == true else { return }
                m.screen = s
                m.reading = false
                if waitingForScreen { waitingForScreen = false; write() }
            }
        }
        position(near: t)
        panel.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: focusNow, object: nil)
        watch()
    }

    static let focusNow = Notification.Name("PenlightComposerFocus")

    static func close() {
        run?.cancel(); run = nil
        waitingForScreen = false
        Pill.shared.busy(false)
        panel.orderOut(nil)
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
        if let a = appMonitor { NSWorkspace.shared.notificationCenter.removeObserver(a); appMonitor = nil }
    }

    /// Below the box (or above it when there's no room); centred near the mouse with no box.
    private static func position(near t: Target?) {
        panel.pinnedTop = nil; panel.pinnedBottom = nil
        let h: CGFloat = 150
        guard let t else {
            let mouse = NSEvent.mouseLocation
            let vis = NSScreen.screens.first { $0.frame.contains(mouse) }?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            let top = min(vis.maxY - 40, mouse.y + 120)
            panel.setFrameOrigin(NSPoint(x: max(vis.minX + 8, min(mouse.x - width / 2, vis.maxX - width - 8)), y: top - h))
            panel.pinnedTop = top
            return
        }
        let f = AX.cocoa(t.frame)
        let vis = AX.screen(for: f)?.visibleFrame ?? f
        let x = max(vis.minX + 8, min(f.minX, vis.maxX - width - 8))
        // Tall boxes (a whole email body): sit over its bottom edge rather than far below it.
        let edge = f.height > 220 ? f.minY + 120 : f.minY
        if edge - 8 - 320 >= vis.minY {
            panel.pinnedTop = edge - 8
        } else if f.maxY + 8 + 320 <= vis.maxY {
            panel.pinnedBottom = f.maxY + 8
        } else {
            panel.pinnedTop = min(vis.maxY - 8, edge + 260)
        }
        panel.setFrame(NSRect(x: x, y: 0, width: width, height: panel.frame.height), display: false)
    }

    /// Closes on a click elsewhere or when you switch apps.
    private static func watch() {
        if mouseMonitor == nil {
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
                if model.phase != .writing { close() }
            }
        }
        if appMonitor == nil {
            appMonitor = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { n in
                let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                if app?.processIdentifier != App.pid && app?.processIdentifier != model.target?.pid { close() }
            }
        }
    }

    // MARK: Writing

    static func submit() {
        let m = model
        switch m.phase {
        case .writing: return
        case .review:
            if m.ask.trimmingCharacters(in: .whitespaces).isEmpty { insert(); return }
            m.previous = m.output
        case .asking, .failed:
            m.previous = nil
        }
        write()
    }

    static func chip(_ label: String) {
        model.ask = label
        submit()
    }

    static func retry() {
        let m = model
        guard m.phase != .writing else { return }
        m.ask = m.lastAsk
        m.previous = nil
        write()
    }

    private static func write() {
        let m = model
        if m.reading { waitingForScreen = true; m.phase = .writing; m.output = ""; return }
        AI.setProvider(m.providerId)
        let p = m.provider
        let ask = m.ask
        m.lastAsk = ask
        let screen = m.useScreen ? m.screen?.text : nil
        let prompt = Writer.prompt(ask: ask, field: m.field, screen: screen, app: m.appName,
                                   window: m.target?.windowTitle ?? "", previous: m.previous,
                                   terminal: m.target?.terminal == true)
        m.phase = .writing
        m.output = ""
        m.note = nil
        m.ask = ""
        Pill.shared.busy(true)
        log.info("writing with \(p.id, privacy: .public)")
        run = AI.write(system: Writer.system(about: Prefs.about), prompt: prompt, provider: p, delta: { piece in
            m.output += piece
        }, done: { r in
            Pill.shared.busy(false)
            switch r {
            case .failure(let e):
                m.phase = .failed(e.localizedDescription)
            case .success(let full):
                let raw = full.isEmpty ? m.output : full
                m.output = m.target?.terminal == true ? Writer.command(raw) : Writer.clean(raw)
                if m.output.isEmpty { m.phase = .failed("The AI sent back nothing. Try again, or say a little more."); return }
                if Prefs.preview || m.previous != nil || !m.canInsert { m.phase = .review } else { insert() }
            }
        })
    }

    static func stop() {
        run?.cancel(); run = nil
        waitingForScreen = false
        Pill.shared.busy(false)
        model.phase = model.output.isEmpty ? .asking : .review
    }

    static func insert() {
        let m = model
        let text = m.output
        guard !text.isEmpty else { return }
        guard let t = m.target else { copy(); return }
        let mode: FieldText.Mode = m.field.mode == .whole ? .whole : (m.field.mode == .selection ? .selection : .insert)
        close()
        Inserter.insert(text, into: t, mode: mode) { ok in
            if ok { Pill.shared.flashDone(); return }
            // The box didn't change (some apps refuse pasted text): leave it on the clipboard and say so.
            Inserter.copy(text)
            open(for: nil)
            m.output = text
            m.phase = .review
            m.note = "\(t.app) didn't take the text. It's on your clipboard: click the box and press ⌘V."
        }
    }

    static func copy() {
        Inserter.copy(model.output)
        model.note = "Copied."
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { if model.target == nil { close() } }
    }
}

// MARK: - The view

struct ComposerView: View {
    @ObservedObject var model: ComposerModel
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            askRow
            if model.phase == .asking || model.phase == .review { contextRow }
            if model.peek, let s = model.screen, !s.empty { peekBox(s) }
            if model.phase == .asking { chips }
            if model.phase != .asking { resultBox }
            if let note = model.note { Text(note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            if case .review = model.phase { actions }
            if case .failed = model.phase { failedActions }
        }
        .padding(14)
        .frame(width: Composer.width, alignment: .leading)
        .modifier(GlassCard())
        .tint(Brand.violet)
        .onExitCommand { Composer.close() }
        .onReceive(NotificationCenter.default.publisher(for: Composer.focusNow)) { _ in
            DispatchQueue.main.async { focused = true }
        }
        .onAppear { focused = true }
    }

    private var placeholder: String {
        switch model.phase {
        case .review: return "Change it… (↩ inserts as is)"
        case .writing: return "Writing…"
        default:
            if model.target?.terminal == true { return "What should the command do? ↩ suggests the next one" }
            if model.field.mode == .whole || model.field.mode == .selection { return "What should I do with it? ↩ polishes" }
            return model.canInsert ? "What should I write? ↩ replies for you" : "What should I write?"
        }
    }

    private var askRow: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(Brand.gradient)
                Nib().fill(.white, style: FillStyle(eoFill: true)).frame(width: 7, height: 11).rotationEffect(.degrees(35))
            }
            .frame(width: 22, height: 22)
            .padding(.top, 1)
            TextField(placeholder, text: $model.ask, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .lineLimit(1...4)
                .focused($focused)
                .disabled(model.phase == .writing)
                .onSubmit { Composer.submit() }
                .padding(.top, 2)
            providerMenu
        }
    }

    private var providerMenu: some View {
        Menu {
            ForEach(AI.all, id: \.id) { p in
                let problem = AI.problem(p)
                Button {
                    model.providerId = p.id
                    AI.setProvider(p.id)
                } label: {
                    Text(p.name + (p.id == model.providerId ? "  ✓" : "") + (problem == nil ? "" : "  · set up"))
                }
                .disabled(problem != nil && p.id != model.providerId)
            }
            Divider()
            Button("AI settings…") { Composer.close(); SettingsWindow.show(tab: .ai) }
        } label: {
            Text("\(model.provider.short) · \(AI.modelLabel(model.provider))")
                .font(.system(size: 11, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(.primary.opacity(0.06)))
        .help("Which AI writes")
    }

    private var contextRow: some View {
        HStack(spacing: 8) {
            if model.canInsert {
                Button { model.peek.toggle() } label: {
                    HStack(spacing: 5) {
                        if model.reading {
                            ProgressView().controlSize(.mini)
                            Text("Reading \(model.appName)…")
                        } else if let s = model.screen, !s.empty, model.useScreen {
                            Image(systemName: s.source == "pixels" ? "text.viewfinder" : "eye")
                            Text("Reading \(model.appName) · \(s.text.count.formatted()) chars")
                        } else if !model.useScreen {
                            Image(systemName: "eye.slash")
                            Text("Not reading the screen")
                        } else {
                            Image(systemName: "eye.slash")
                            Text(Prefs.readScreen ? "Nothing readable on screen" : "Screen reading off")
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("See what's sent to the AI")
                if model.screen.map({ !$0.empty }) == true {
                    Button { model.useScreen.toggle() } label: {
                        Text(model.useScreen ? "Don't use" : "Use it").font(.system(size: 11))
                    }
                    .buttonStyle(.plain).foregroundStyle(Brand.ink)
                }
            } else {
                Label("No text box — I'll copy the result", systemImage: "doc.on.clipboard")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if model.field.mode == .whole || model.field.mode == .selection {
                Label(model.field.mode == .selection ? "Using your selection" : "Using what you typed", systemImage: "text.cursor")
                    .font(.system(size: 11)).foregroundStyle(Brand.ink)
            } else if model.field.mode == .insert {
                Label("Adding at the cursor", systemImage: "text.insert")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
    }

    private func peekBox(_ s: Screen) -> some View {
        ScrollView {
            Text(s.text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(8)
        }
        .frame(maxHeight: 130)
        .background(RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(0.04)))
    }

    private var chips: some View {
        HStack(spacing: 6) {
            ForEach(Writer.chips(hasDraft: model.field.mode == .whole || model.field.mode == .selection, terminal: model.target?.terminal == true), id: \.self) { c in
                Button(c) { Composer.chip(c) }
                    .buttonStyle(ChipStyle())
            }
        }
    }

    private var resultBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            if case .failed(let why) = model.phase {
                Label(why, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        Group {
                            if model.output.isEmpty {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text(model.reading ? "Reading \(model.appName)…" : "Writing with \(model.provider.short)…")
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text(model.output)
                                    .textSelection(.enabled)
                            }
                        }
                        .font(.system(size: 13.5))
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .id("end")
                    }
                    .frame(maxHeight: 220)
                    .fixedSize(horizontal: false, vertical: true)
                    .onChange(of: model.output) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
                }
                .background(RoundedRectangle(cornerRadius: 10).fill(.primary.opacity(scheme == .dark ? 0.07 : 0.035)))
                if model.phase == .writing {
                    HStack {
                        Spacer()
                        Button("Stop") { Composer.stop() }.buttonStyle(.plain).foregroundStyle(Brand.ink).font(.system(size: 11))
                    }
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if model.canInsert {
                Button { Composer.insert() } label: { Text("Insert  ↩") }
                    .buttonStyle(PrimaryStyle())
                    .keyboardShortcut(.return, modifiers: .command)
            } else {
                Button { Composer.copy() } label: { Text("Copy") }
                    .buttonStyle(PrimaryStyle())
                    .keyboardShortcut(.return, modifiers: .command)
            }
            Button("Retry") { Composer.retry() }
                .buttonStyle(QuietStyle())
                .keyboardShortcut("r", modifiers: .command)
            if model.canInsert {
                Button("Copy") { Composer.copy() }.buttonStyle(QuietStyle())
            }
            Spacer()
            Text("esc").font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
        }
    }

    private var failedActions: some View {
        HStack(spacing: 8) {
            Button("Try again") { Composer.retry() }.buttonStyle(PrimaryStyle()).keyboardShortcut("r", modifiers: .command)
            Button("AI settings…") { Composer.close(); SettingsWindow.show(tab: .ai) }.buttonStyle(QuietStyle())
            Spacer()
        }
    }
}

/// Liquid Glass on macOS 26, a soft material before it.
struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: 18))
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.primary.opacity(0.08)))
        }
    }
}

struct ChipStyle: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        c.label
            .font(.system(size: 11.5, weight: .medium))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(Brand.violet.opacity(c.isPressed ? 0.22 : 0.10)))
            .foregroundStyle(Brand.ink)
            .contentShape(Capsule())
    }
}

struct PrimaryStyle: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        c.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(Capsule().fill(Brand.gradient).opacity(c.isPressed ? 0.8 : 1))
            .contentShape(Capsule())
    }
}

struct QuietStyle: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        c.label
            .font(.system(size: 12.5, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(.primary.opacity(c.isPressed ? 0.12 : 0.06)))
            .contentShape(Capsule())
    }
}
