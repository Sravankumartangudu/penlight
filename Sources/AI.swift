// AI.swift — the AIs Penlight can write with, all streaming so words appear as they're written.
//
// Claude Code (your own Claude sign-in, no key), Apple Intelligence on this Mac (free, private), and the
// APIs: Anthropic, OpenAI, Google Gemini, OpenRouter, Ollama and any OpenAI-compatible server. Keys live
// in the macOS Keychain, never in a file.
//
// Desktop chat apps (ChatGPT, Claude, Gemini, Perplexity, Copilot) can't be driven by another app; Settings
// lists the ones installed with the matching route that does work.

import AppKit
import Security
#if canImport(FoundationModels)
import FoundationModels
#endif

struct Provider {
    enum Key { case none, required, optional }
    let id: String
    let name: String
    /// The chip in the writing box: "Claude", "GPT", "Gemini".
    let short: String
    let key: Key
    /// Default server address; "" = fixed endpoint, no address field.
    let defaultBase: String
    let help: String
    /// The first is the default.
    let models: [(String, String)]
    let note: String
}

/// A desktop AI app that's installed, and the route to its AI that works from Penlight.
struct DesktopApp {
    let name: String
    let route: String
    let providerId: String
}

enum AI {
    struct Failure: LocalizedError { let errorDescription: String? }

    static let all: [Provider] = [
        Provider(id: "claude-code", name: "Claude Code", short: "Claude", key: .none, defaultBase: "",
                 help: "https://claude.com/claude-code",
                 models: [("haiku", "Haiku · fastest"), ("sonnet", "Sonnet · best writing"), ("opus", "Opus · most careful")],
                 note: "Uses the Claude sign-in on this Mac. No key."),
        Provider(id: "apple", name: "Apple Intelligence", short: "Apple", key: .none, defaultBase: "", help: "",
                 models: [("default", "On-device model")],
                 note: "Runs on this Mac. Free, and nothing leaves it."),
        Provider(id: "anthropic", name: "Anthropic API", short: "Claude", key: .required, defaultBase: "",
                 help: "https://console.anthropic.com/settings/keys",
                 models: [("claude-haiku-4-5-20251001", "Claude Haiku 4.5"), ("claude-sonnet-5-5", "Claude Sonnet 5.5"),
                          ("claude-opus-5-5", "Claude Opus 5.5")],
                 note: "Your Anthropic key."),
        Provider(id: "openai", name: "OpenAI · ChatGPT models", short: "GPT", key: .required, defaultBase: "https://api.openai.com/v1",
                 help: "https://platform.openai.com/api-keys",
                 models: [("gpt-5-mini", "GPT-5 mini"), ("gpt-5", "GPT-5")],
                 note: "Your OpenAI API key (a ChatGPT subscription doesn't include API use)."),
        Provider(id: "gemini", name: "Google Gemini", short: "Gemini", key: .required, defaultBase: "",
                 help: "https://aistudio.google.com/apikey",
                 models: [("gemini-2.5-flash", "Gemini 2.5 Flash"), ("gemini-2.5-pro", "Gemini 2.5 Pro")],
                 note: "A free key from Google AI Studio works."),
        Provider(id: "openrouter", name: "OpenRouter · many models, one key", short: "AI", key: .required,
                 defaultBase: "https://openrouter.ai/api/v1", help: "https://openrouter.ai/keys",
                 models: [("openrouter/auto", "Auto · OpenRouter picks"), ("perplexity/sonar", "Perplexity Sonar"),
                          ("x-ai/grok-4-fast", "Grok 4 Fast"), ("mistralai/mistral-medium-3.1", "Mistral Medium")],
                 note: "One key for Perplexity, Grok, Mistral, Llama and more."),
        Provider(id: "ollama", name: "Ollama · on this Mac", short: "Ollama", key: .none, defaultBase: "http://localhost:11434",
                 help: "https://ollama.com/download", models: [], note: "Free local models. Start Ollama and pull one."),
        Provider(id: "compatible", name: "OpenAI-compatible server", short: "AI", key: .optional,
                 defaultBase: "http://localhost:1234/v1", help: "", models: [],
                 note: "LM Studio, Groq, Mistral, DeepSeek, Together, a company gateway…"),
    ]

    private static let d = UserDefaults.standard

    // MARK: Which provider and model

    static var current: Provider {
        if let id = d.string(forKey: "provider"), let p = all.first(where: { $0.id == id }) { return p }
        if claudeInstalled { return all[0] }
        if appleReady { return all[1] }
        return all.first { hasKey($0) } ?? all[0]
    }
    static func setProvider(_ id: String) { d.set(id, forKey: "provider"); NotificationCenter.default.post(name: Prefs.didChange, object: nil) }

    static func models(_ p: Provider) -> [(String, String)] {
        var list = p.id == "ollama" ? ollamaModels.map { ($0, $0) } : p.models
        if let cur = d.string(forKey: "model." + p.id), !cur.isEmpty, !list.contains(where: { $0.0 == cur }) { list.insert((cur, cur), at: 0) }
        return list
    }
    static func model(_ p: Provider) -> String {
        if let m = d.string(forKey: "model." + p.id), !m.isEmpty { return m }
        return models(p).first?.0 ?? ""
    }
    static func setModel(_ m: String, for p: Provider) { d.set(m.trimmingCharacters(in: .whitespaces), forKey: "model." + p.id) }
    static func modelLabel(_ p: Provider) -> String {
        let m = model(p)
        return models(p).first { $0.0 == m }?.1.components(separatedBy: " · ")[0] ?? m
    }

    static func base(_ p: Provider) -> String {
        let b = (d.string(forKey: "base." + p.id) ?? "").trimmingCharacters(in: .whitespaces)
        return (b.isEmpty ? p.defaultBase : b).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
    static func setBase(_ b: String, for p: Provider) { d.set(b.trimmingCharacters(in: .whitespaces), forKey: "base." + p.id) }

    // MARK: Keys (Keychain; a plain flag remembers which exist, so drawing the UI never opens the Keychain)

    private static let service = App.bundleId + ".ai"
    private static var keys: [String: String] = [:]

    static func hasKey(_ p: Provider) -> Bool { d.bool(forKey: "hasKey." + p.id) }
    static func key(_ p: Provider) -> String {
        if let k = keys[p.id] { return k }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: p.id, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        let k = SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? (out as? Data).flatMap { String(data: $0, encoding: .utf8) } ?? "" : ""
        keys[p.id] = k
        return k
    }
    static func setKey(_ key: String?, for p: Provider) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: p.id]
        SecItemDelete(q as CFDictionary)
        let k = (key ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        keys[p.id] = k
        d.set(!k.isEmpty, forKey: "hasKey." + p.id)
        guard !k.isEmpty else { return }
        var add = q
        add[kSecValueData as String] = Data(k.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    // MARK: Ready?

    static func installed(_ cmd: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", #"export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"; command -v "$1" >/dev/null"#, "penlight", cmd]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        // Not waitUntilExit(): it spins the main run loop, and a menu opening meanwhile would re-enter this check.
        let gone = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in gone.signal() }
        do { try p.run() } catch { return false }
        gone.wait()
        return p.terminationStatus == 0
    }
    static let claudeInstalled = installed("claude")

    /// nil when Apple Intelligence can write now, else why not.
    static var appleProblem: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return nil
            case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in System Settings."
            case .unavailable(.deviceNotEligible): return "This Mac can't run Apple Intelligence."
            case .unavailable(.modelNotReady): return "Apple's model is still downloading. Try again later."
            case .unavailable: return "Apple Intelligence isn't available right now."
            }
        }
        #endif
        return "Needs macOS 26 or later."
    }
    static var appleReady: Bool { appleProblem == nil }

    /// nil when the provider can run, else what's missing, in plain words.
    static func problem(_ p: Provider = current) -> String? {
        switch p.id {
        case "claude-code": return claudeInstalled ? nil : "Claude Code isn't installed. Install it, or pick another AI."
        case "apple": return appleProblem
        case "ollama": return model(p).isEmpty ? "No Ollama model yet. Start Ollama and run `ollama pull llama3.2`." : nil
        case "compatible": return base(p).isEmpty ? "Add the server address in Settings." : model(p).isEmpty ? "Type a model name in Settings." : nil
        default: return hasKey(p) ? nil : "Add your \(p.name.components(separatedBy: " · ")[0]) key in Settings › AI."
        }
    }

    /// Installed AI apps, each with the route that works from here.
    static let desktopApps: [DesktopApp] = {
        let ws = NSWorkspace.shared
        let known: [(String, [String], String, String)] = [
            ("ChatGPT", ["com.openai.chat"], "Use the OpenAI API (needs an API key; the app's subscription can't be used).", "openai"),
            ("Claude", ["com.anthropic.claudefordesktop"], claudeInstalled ? "Claude Code is installed: it uses the same Claude sign-in." : "Install Claude Code, or use an Anthropic key.", claudeInstalled ? "claude-code" : "anthropic"),
            ("Gemini", ["com.google.GeminiMacOS", "com.google.gemini"], "Use a free Google AI Studio key.", "gemini"),
            ("Perplexity", ["ai.perplexity.mac"], "Use OpenRouter's Perplexity Sonar model.", "openrouter"),
            ("GitHub Copilot", ["com.github.CopilotForXcode", "com.github.copilot"], "Copilot has no API for other apps; Claude Code or OpenAI work instead.", claudeInstalled ? "claude-code" : "openai"),
        ]
        var out: [DesktopApp] = []
        for (name, ids, route, pid) in known {
            let found = ids.contains { ws.urlForApplication(withBundleIdentifier: $0) != nil }
                || FileManager.default.fileExists(atPath: "/Applications/\(name).app")
            if found { out.append(DesktopApp(name: name, route: route, providerId: pid)) }
        }
        return out
    }()

    // MARK: Ollama's model list

    private(set) static var ollamaModels: [String] = UserDefaults.standard.stringArray(forKey: "ollamaModels") ?? []
    static func refreshOllama(done: @escaping () -> Void = {}) {
        guard let p = all.first(where: { $0.id == "ollama" }), let url = URL(string: base(p) + "/api/tags") else { return }
        URLSession.shared.dataTask(with: URLRequest(url: url, timeoutInterval: 3)) { data, _, _ in
            let j = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let names = ((j?["models"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }
            DispatchQueue.main.async {
                if j != nil { ollamaModels = names; UserDefaults.standard.set(names, forKey: "ollamaModels") }
                done()
            }
        }.resume()
    }

    // MARK: Writing

    /// Streams a reply. `delta` gets each new piece, `done` the whole text or an error; both on main.
    @discardableResult
    static func write(system: String, prompt: String, provider p: Provider = current,
                      delta: @escaping (String) -> Void, done: @escaping (Result<String, Error>) -> Void) -> AIRun {
        let run = AIRun(delta: delta, done: done)
        if let problem = problem(p) { run.finish(.failure(Failure(errorDescription: problem))); return run }
        switch p.id {
        case "claude-code": runClaude(run, system: system, prompt: prompt, model: model(p))
        case "apple": runApple(run, system: system, prompt: prompt)
        default: runHTTP(run, p, system: system, prompt: prompt)
        }
        return run
    }

    /// Checks a provider with a tiny request.
    static func test(_ p: Provider, done: @escaping (Bool, String) -> Void) {
        let t0 = Date()
        write(system: "Reply with exactly: OK", prompt: "Say OK.", provider: p, delta: { _ in }) { r in
            switch r {
            case .success(let s): done(true, "Working · answered “\(s.prefix(20))” in \(String(format: "%.1f", Date().timeIntervalSince(t0))) s")
            case .failure(let e): done(false, e.localizedDescription)
            }
        }
    }

    // MARK: Claude Code

    /// Copies only the sign-in keys from ~/.claude/settings.json: user settings are skipped
    /// (`--setting-sources project`) so no hook, plugin or allow-list rides along.
    static func authSettings() -> URL {
        let out = App.support.appendingPathComponent("auth-settings.json")
        let user = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
        var auth: [String: Any] = ["enabledPlugins": [String: Any]()]
        if let d = try? Data(contentsOf: user), let all = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            for k in ["apiKeyHelper", "env", "awsAuthRefresh", "awsCredentialExport", "forceLoginMethod"] { auth[k] = all[k] }
        }
        if let d = try? JSONSerialization.data(withJSONObject: auth) {
            try? d.write(to: out, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: out.path)
        }
        return out
    }

    private static func runClaude(_ run: AIRun, system: String, prompt: String, model: String) {
        let args = ["penlight", "-p", "--output-format", "stream-json", "--verbose", "--include-partial-messages",
                    "--no-session-persistence", "--disable-slash-commands", "--setting-sources", "project",
                    "--strict-mcp-config", "--tools", "", "--settings", authSettings().path,
                    "--model", model, "--system-prompt", system]
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", #"export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"; exec claude "$@""#] + args
        p.currentDirectoryURL = App.support
        var env = ProcessInfo.processInfo.environment.filter { !["CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SESSION_ID"].contains($0.key) }
        env["CLAUDE_CODE_DISABLE_AUTO_MEMORY"] = "1"
        env["MAX_THINKING_TOKENS"] = "0"
        p.environment = env
        let inp = Pipe(), out = Pipe(), err = Pipe()
        p.standardInput = inp; p.standardOutput = out; p.standardError = err
        run.onCancel = { if p.isRunning { p.terminate() } }

        var buffer = Data(), text = "", final: String?, failure: String?
        let lock = NSLock()
        func handle(_ line: Data) {
            guard let j = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
            switch j["type"] as? String {
            case "stream_event":
                if let e = j["event"] as? [String: Any], e["type"] as? String == "content_block_delta",
                   let dl = e["delta"] as? [String: Any], dl["type"] as? String == "text_delta", let s = dl["text"] as? String {
                    text += s
                    run.send(s)
                }
            case "result":
                if j["is_error"] as? Bool == true { failure = (j["result"] as? String) ?? "Claude couldn't answer." }
                else { final = j["result"] as? String }
            default: break
            }
        }
        out.fileHandleForReading.readabilityHandler = { h in
            let chunk = h.availableData
            lock.lock(); defer { lock.unlock() }
            if chunk.isEmpty { h.readabilityHandler = nil; return }
            buffer.append(chunk)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<nl]
                buffer = Data(buffer[buffer.index(after: nl)...])
                handle(Data(line))
            }
        }
        p.terminationHandler = { proc in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                lock.lock()
                out.fileHandleForReading.readabilityHandler = nil
                if !buffer.isEmpty { handle(buffer); buffer = Data() }
                let result = final ?? (text.isEmpty ? nil : text), failed = failure
                lock.unlock()
                let errText = String(decoding: err.fileHandleForReading.availableData, as: UTF8.self)
                if run.cancelled { return }
                if let result, failed == nil { run.finish(.success(result)); return }
                var msg = failed ?? errText.trimmingCharacters(in: .whitespacesAndNewlines)
                if proc.terminationReason == .uncaughtSignal { msg = "Claude took too long." }
                if msg.lowercased().contains("login") || msg.lowercased().contains("auth") { msg = "Claude Code isn't signed in. Run `claude` in Terminal once to sign in. (\(msg.prefix(120)))" }
                run.finish(.failure(Failure(errorDescription: msg.isEmpty ? "Claude returned nothing (exit \(proc.terminationStatus))." : String(msg.suffix(300)))))
            }
        }
        do { try p.run() } catch {
            run.finish(.failure(Failure(errorDescription: "Couldn't start Claude Code: \(error.localizedDescription)"))); return
        }
        DispatchQueue.global().async {
            inp.fileHandleForWriting.write(Data(prompt.utf8))
            try? inp.fileHandleForWriting.close()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 120) { if p.isRunning { p.terminate() } }
    }

    // MARK: Apple Intelligence

    private static func runApple(_ run: AIRun, system: String, prompt: String) {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            let task = Task {
                do {
                    let s = LanguageModelSession(instructions: system)
                    var sent = ""
                    for try await part in s.streamResponse(to: prompt) {
                        let all: String = part.content
                        if all.hasPrefix(sent) { run.send(String(all.dropFirst(sent.count))) }
                        sent = all
                    }
                    run.finish(.success(sent))
                } catch {
                    if !run.cancelled { run.finish(.failure(Failure(errorDescription: "Apple Intelligence: \(error.localizedDescription)"))) }
                }
            }
            run.onCancel = { task.cancel() }
            return
        }
        #endif
        run.finish(.failure(Failure(errorDescription: appleProblem)))
    }

    // MARK: HTTP APIs

    private static func runHTTP(_ run: AIRun, _ p: Provider, system: String, prompt: String) {
        let m = model(p), k = key(p)
        var req: URLRequest
        var body: [String: Any]
        switch p.id {
        case "anthropic":
            req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            req.setValue(k, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = ["model": m, "max_tokens": 2000, "system": system, "stream": true,
                    "messages": [["role": "user", "content": prompt]]]
        case "gemini":
            req = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(m):streamGenerateContent?alt=sse")!)
            req.setValue(k, forHTTPHeaderField: "x-goog-api-key")
            body = ["systemInstruction": ["parts": [["text": system]]],
                    "contents": [["role": "user", "parts": [["text": prompt]]]]]
        case "ollama":
            guard let u = URL(string: base(p) + "/api/chat") else { run.finish(.failure(Failure(errorDescription: "Check Ollama's address in Settings."))); return }
            req = URLRequest(url: u)
            body = ["model": m, "stream": true, "messages": [["role": "system", "content": system], ["role": "user", "content": prompt]]]
        default:
            guard let u = URL(string: base(p) + "/chat/completions") else { run.finish(.failure(Failure(errorDescription: "Check the server address in Settings."))); return }
            req = URLRequest(url: u)
            if !k.isEmpty { req.setValue("Bearer " + k, forHTTPHeaderField: "Authorization") }
            if p.id == "openrouter" {
                req.setValue(App.repo.absoluteString, forHTTPHeaderField: "HTTP-Referer")
                req.setValue(App.name, forHTTPHeaderField: "X-Title")
            }
            body = ["model": m, "stream": true, "messages": [["role": "system", "content": system], ["role": "user", "content": prompt]]]
        }
        req.httpMethod = "POST"
        req.timeoutInterval = 90
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let host = req.url?.host ?? "the server"

        let task = Task {
            do {
                let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if !(200..<300).contains(code) {
                    var raw = Data()
                    for try await b in bytes { raw.append(b); if raw.count > 20_000 { break } }
                    throw Failure(errorDescription: httpError(code, raw))
                }
                var text = ""
                for try await line in bytes.lines {
                    if Task.isCancelled { return }
                    var l = line
                    if p.id != "ollama" {
                        guard l.hasPrefix("data:") else { continue }
                        l = String(l.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        if l == "[DONE]" { break }
                    }
                    guard let j = try? JSONSerialization.jsonObject(with: Data(l.utf8)) as? [String: Any] else { continue }
                    if let e = j["error"] { throw Failure(errorDescription: ((e as? [String: Any])?["message"] as? String) ?? "\(e)") }
                    let piece = pieceOf(p.id, j)
                    if !piece.isEmpty { text += piece; run.send(piece) }
                }
                run.finish(.success(text))
            } catch let e as URLError {
                if run.cancelled { return }
                let msg: String
                switch e.code {
                case .notConnectedToInternet: msg = "You're offline."
                case .cannotConnectToHost, .cannotFindHost: msg = "Couldn't reach \(host). Is it running, and is the address right?"
                case .timedOut: msg = "\(host) took too long to answer."
                case .cancelled: return
                default: msg = e.localizedDescription
                }
                run.finish(.failure(Failure(errorDescription: msg)))
            } catch {
                if !run.cancelled { run.finish(.failure(error)) }
            }
        }
        run.onCancel = { task.cancel() }
    }

    private static func pieceOf(_ id: String, _ j: [String: Any]) -> String {
        switch id {
        case "anthropic":
            guard j["type"] as? String == "content_block_delta", let dl = j["delta"] as? [String: Any] else { return "" }
            return dl["text"] as? String ?? ""
        case "gemini":
            let parts = (((j["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
            return parts.compactMap { $0["thought"] as? Bool == true ? nil : $0["text"] as? String }.joined()
        case "ollama":
            return ((j["message"] as? [String: Any])?["content"] as? String) ?? ""
        default:
            return (((j["choices"] as? [[String: Any]])?.first?["delta"] as? [String: Any])?["content"] as? String) ?? ""
        }
    }

    private static func httpError(_ code: Int, _ raw: Data) -> String {
        let j = try? JSONSerialization.jsonObject(with: raw)
        let obj = (j as? [String: Any]) ?? ((j as? [[String: Any]])?.first)
        var msg = (obj?["error"] as? [String: Any])?["message"] as? String ?? obj?["error"] as? String ?? obj?["message"] as? String ?? ""
        if msg.isEmpty {
            switch code {
            case 401, 403: msg = "The key was refused. Check it in Settings › AI."
            case 404: msg = "Not found — the model or address may be wrong."
            case 429: msg = "Rate limit or quota reached. Wait a bit, or check your plan."
            default: msg = "The AI service answered \(code)."
            }
        } else if [401, 403].contains(code) { msg = "The key was refused: " + msg }
        return String(msg.prefix(300))
    }
}

/// One writing request: streams pieces, finishes once, can be stopped.
final class AIRun {
    private let delta: (String) -> Void
    private let done: (Result<String, Error>) -> Void
    private var finished = false
    private(set) var cancelled = false
    var onCancel: (() -> Void)?

    init(delta: @escaping (String) -> Void, done: @escaping (Result<String, Error>) -> Void) {
        self.delta = delta; self.done = done
    }
    func send(_ s: String) {
        guard !s.isEmpty else { return }
        DispatchQueue.main.async { if !self.cancelled && !self.finished { self.delta(s) } }
    }
    func finish(_ r: Result<String, Error>) {
        DispatchQueue.main.async {
            guard !self.finished, !self.cancelled else { return }
            self.finished = true
            self.done(r)
        }
    }
    func cancel() {
        DispatchQueue.main.async {
            guard !self.finished else { return }
            self.cancelled = true
            self.onCancel?()
        }
    }
}
