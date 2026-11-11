# Changelog

## 1.1.0 — 2026-11-11

- Works in every app you can type in. Slack, code editors, launchers and terminals are all on now. Only password managers start switched off, and password fields are still always skipped.
- **Settings › Apps** lists every app on your Mac with an on/off switch, plus a search box, **Turn all on** and **Reset to defaults**.
- Terminals: Penlight reads the recent output and writes a command at the prompt. Chips: Next command, Fix the last error, Undo that. Pressing ↩ with nothing typed suggests the next command. Return is never pressed for you.
- Lists saved by 1.0.0 are reset once to the new defaults.

## 1.0.0 — 2026-11-11

First release.

- ✒️ A small button beside any text box you click into, in any app. Or press ⌃⌥Space.
- Reads the conversation above the box through Accessibility. For apps that hide their text, it reads the window's pixels on your Mac instead.
- Writes a reply, or rewrites what you typed: Polish, Shorter, More formal, Friendlier, Fix spelling, In English. With a selection, only that part is rewritten.
- Streams the text as it's written. Type a change and press ↩ to refine it, or press ↩ on an empty line to insert it.
- Pastes into the real box and puts your clipboard back. If an app refuses pasted text, Penlight writes it in through Accessibility, or leaves it on the clipboard and tells you.
- AI choices: Claude Code, Apple Intelligence, Anthropic, OpenAI, Gemini, OpenRouter, Ollama, and any OpenAI-compatible server. Keys are kept in the Keychain.
- Never shows on password fields. Terminals, code editors and password managers are skipped by default.
- System, Light or Dark appearance. Liquid Glass on macOS 26.
