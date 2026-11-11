// SettingsWindow.swift — General, AI, You, Apps and Permissions.

import AppKit
import SwiftUI
import ServiceManagement
import Combine

enum SettingsTab: String, CaseIterable { case general, ai, you, apps, permissions }

final class SettingsModel: ObservableObject {
    @Published var tab: SettingsTab = .general
    @Published var tick = 0
    func refresh() { tick += 1 }
}

enum SettingsWindow {
    static let model = SettingsModel()
    private static var window: NSWindow?

    static func show(tab: SettingsTab? = nil) {
        if let tab { model.tab = tab }
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
                             styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = "\(App.name) Settings"
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: SettingsView(model: model))
            w.center()
            window = w
        }
        model.refresh()
        AI.refreshOllama { model.refresh() }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        TabView(selection: $model.tab) {
            GeneralPane().tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsTab.general)
            AIPane(model: model).tabItem { Label("AI", systemImage: "sparkles") }.tag(SettingsTab.ai)
            YouPane().tabItem { Label("You", systemImage: "person.crop.circle") }.tag(SettingsTab.you)
            AppsPane().tabItem { Label("Apps", systemImage: "square.grid.2x2") }.tag(SettingsTab.apps)
            PermissionsPane().tabItem { Label("Permissions", systemImage: "lock.shield") }.tag(SettingsTab.permissions)
        }
        .frame(width: 620, height: 540)
        .tint(Brand.violet)
    }
}

// MARK: General

struct GeneralPane: View {
    @AppStorage("showButton") private var showButton = true
    @AppStorage("hotkey") private var hotkey = true
    @AppStorage("preview") private var preview = false
    @AppStorage("readScreen") private var readScreen = true
    @AppStorage("ocr") private var ocr = true
    @AppStorage("appearance") private var appearance = "system"
    @State private var atLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                Toggle("Show the \(App.name) button beside text boxes", isOn: $showButton)
                Toggle("Open with \(Hotkey.label) in any app", isOn: $hotkey)
                Toggle("Show the text before putting it in the box", isOn: $preview)
                    .help("Off: it goes straight into the box when it's written. You can always ⌘Z in the app.")
            } header: { Text("Writing") }
            Section {
                Toggle("Read what's on screen around the box", isOn: $readScreen)
                Toggle("When an app hides its text, read the window's pixels", isOn: $ocr)
                    .disabled(!readScreen)
                    .help("Text recognition runs on this Mac. Needs Screen Recording.")
                Text("Screen text goes to the AI you pick only when you press ↩. Click “Reading …” in the writing box to see exactly what's sent.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Context") }
            Section {
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                Toggle("Open at login", isOn: $atLogin)
                    .onChange(of: atLogin) { _, on in
                        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                        catch { atLogin = SMAppService.mainApp.status == .enabled }
                    }
            } header: { Text("App") }
            Section {
                HStack {
                    Text("\(App.name) \(App.version)")
                    Spacer()
                    Link("Website & help", destination: App.repo)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: showButton) { _, v in Prefs.showButton = v }
        .onChange(of: hotkey) { _, v in Prefs.hotkey = v }
        .onChange(of: appearance) { _, v in Prefs.appearance = v }
    }
}

// MARK: AI

struct AIPane: View {
    @ObservedObject var model: SettingsModel
    @State private var current = AI.current.id

    var body: some View {
        Form {
            Section {
                ForEach(AI.all, id: \.id) { p in
                    ProviderRow(p: p, chosen: current == p.id) {
                        current = p.id
                        AI.setProvider(p.id)
                    }
                }
            } header: { Text("Writes with") } footer: {
                Text("Keys are kept in your Mac's Keychain and sent only to that provider.").font(.caption).foregroundStyle(.secondary)
            }
            if !AI.desktopApps.isEmpty {
                Section {
                    ForEach(AI.desktopApps, id: \.name) { a in
                        HStack(alignment: .firstTextBaseline) {
                            Text(a.name).frame(width: 110, alignment: .leading)
                            Text(a.route).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            if current != a.providerId {
                                Button("Use") { current = a.providerId; AI.setProvider(a.providerId) }.controlSize(.small)
                            }
                        }
                    }
                } header: { Text("AI apps on this Mac") } footer: {
                    Text("Chat apps don't let other apps use them, so each one is matched with the way to the same AI that does.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .id(model.tick)
    }
}

struct ProviderRow: View {
    let p: Provider
    let chosen: Bool
    let choose: () -> Void
    @State private var open = false
    @State private var key = ""
    @State private var base = ""
    @State private var model = ""
    @State private var testing = false
    @State private var result: (Bool, String)?

    var body: some View {
        DisclosureGroup(isExpanded: $open) {
            VStack(alignment: .leading, spacing: 10) {
                Text(p.note).font(.callout).foregroundStyle(.secondary)
                if p.key != .none {
                    HStack {
                        SecureField(AI.hasKey(p) ? "Key saved · paste to replace" : (p.key == .optional ? "Key (if the server needs one)" : "API key"), text: $key)
                            .textFieldStyle(.roundedBorder)
                        Button("Save") { AI.setKey(key, for: p); key = ""; result = nil }.disabled(key.isEmpty)
                        if AI.hasKey(p) { Button("Remove") { AI.setKey(nil, for: p); result = nil } }
                        if !p.help.isEmpty, let u = URL(string: p.help) { Link("Get a key", destination: u).font(.callout) }
                    }
                }
                if !p.defaultBase.isEmpty && p.id != "openai" {
                    HStack {
                        Text("Address").frame(width: 60, alignment: .leading)
                        TextField(p.defaultBase, text: $base).textFieldStyle(.roundedBorder)
                            .onSubmit { AI.setBase(base, for: p) }
                    }
                }
                if p.id != "apple" {
                    HStack {
                        Text("Model").frame(width: 60, alignment: .leading)
                        let opts = AI.models(p)
                        if opts.isEmpty || p.id == "compatible" {
                            TextField("model name", text: $model).textFieldStyle(.roundedBorder)
                                .onSubmit { AI.setModel(model, for: p) }
                        } else {
                            Picker("", selection: $model) {
                                ForEach(opts, id: \.0) { Text($0.1).tag($0.0) }
                            }
                            .labelsHidden()
                            .onChange(of: model) { _, v in AI.setModel(v, for: p) }
                        }
                        if p.id == "ollama" { Button("↻") { AI.refreshOllama { model = AI.model(p) } }.help("Read the models Ollama has") }
                    }
                }
                HStack {
                    Button(testing ? "Testing…" : "Test") {
                        if !base.isEmpty { AI.setBase(base, for: p) }
                        if !model.isEmpty { AI.setModel(model, for: p) }
                        testing = true; result = nil
                        AI.test(p) { ok, msg in testing = false; result = (ok, msg) }
                    }
                    .disabled(testing)
                    if let r = result {
                        Label(r.1, systemImage: r.0 ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .font(.callout).foregroundStyle(r.0 ? .green : .red)
                            .lineLimit(3).textSelection(.enabled)
                    }
                }
            }
            .padding(.vertical, 6)
        } label: {
            HStack {
                Image(systemName: chosen ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(chosen ? Brand.violet : .secondary)
                    .onTapGesture(perform: choose)
                Text(p.name).fontWeight(chosen ? .semibold : .regular)
                Spacer()
                badge
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: choose)
        }
        .onAppear {
            base = (UserDefaults.standard.string(forKey: "base." + p.id) ?? "")
            model = AI.model(p)
            if chosen && AI.problem(p) != nil { open = true }
        }
    }

    private var badge: some View {
        let problem = AI.problem(p)
        return Text(problem == nil ? "Ready" : (p.id == "claude-code" || p.id == "apple" ? "Not available" : "Set up"))
            .font(.caption.weight(.medium))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill((problem == nil ? Color.green : Color.secondary).opacity(0.15)))
            .foregroundStyle(problem == nil ? .green : .secondary)
            .help(problem ?? "")
    }
}

// MARK: You

struct YouPane: View {
    @AppStorage("about") private var about = ""
    var body: some View {
        Form {
            Section {
                TextEditor(text: $about)
                    .font(.body)
                    .frame(minHeight: 160)
                    .scrollContentBackground(.hidden)
            } header: { Text("About you") } footer: {
                Text("Sent with every request so the writing sounds like you. For example: “I'm Sam, a product designer. I write short and friendly, no exclamation marks. I sign emails ‘— Sam’.”")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Apps

struct AppsPane: View {
    @State private var list = Prefs.excluded
    @State private var pick: String?

    var body: some View {
        Form {
            Section {
                ForEach(list, id: \.self) { id in
                    HStack {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 18, height: 18)
                            Text(FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
                        } else {
                            Image(systemName: "app.dashed").frame(width: 18, height: 18)
                            Text(id).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { list.removeAll { $0 == id }; Prefs.excluded = list } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
            } header: { Text("The button never shows in") } footer: {
                HStack {
                    Button("Add an app…") { add() }
                    Button("Reset to defaults") { list = Prefs.defaultExcluded; Prefs.excluded = list }
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
    }

    private func add() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !list.contains(id) { list.append(id) }
        }
        Prefs.excluded = list
    }
}

// MARK: Permissions

struct PermissionsPane: View {
    @State private var ax = AX.trusted
    @State private var screen = CGPreflightScreenCaptureAccess()
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                row(ok: ax, title: "Accessibility", detail: "Needed. Lets \(App.name) see which text box you're in, read the conversation around it, and paste the text in.",
                    action: "Allow…") {
                    AX.askForTrust()
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                row(ok: screen, title: "Screen Recording", detail: "Optional. Only for apps that hide their text from Accessibility: \(App.name) reads the window's pixels on this Mac instead.",
                    action: "Allow…") {
                    CGRequestScreenCaptureAccess()
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                }
            } footer: {
                Text("After an update you may need to switch \(App.name) off and on again in the Accessibility list.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onReceive(timer) { _ in ax = AX.trusted; screen = CGPreflightScreenCaptureAccess() }
    }

    private func row(ok: Bool, title: String, detail: String, action: String, _ go: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                .font(.title2).foregroundStyle(ok ? .green : .orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if ok { Text("Allowed").foregroundStyle(.secondary) } else { Button(action, action: go) }
        }
        .padding(.vertical, 4)
    }
}
