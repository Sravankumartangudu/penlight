// Tests for Writer.swift — run by build.sh before every build.
import Foundation
import CoreGraphics

var failures = 0
func check(_ ok: Bool, _ what: String, line: Int = #line) {
    if !ok { failures += 1; print("✗ line \(line): \(what)") }
}

// Field modes
check(FieldText.read(value: "  \n", selected: nil, cursor: nil).mode == .empty, "blank box is empty")
check(FieldText.read(value: "ok will check tmrw", selected: nil, cursor: nil) == FieldText(mode: .whole, draft: "ok will check tmrw"), "short box is the draft")
check(FieldText.read(value: "hello there friend", selected: "there", cursor: 6) == FieldText(mode: .selection, draft: "there"), "selection wins")
let long = String(repeating: "Earlier thread text. ", count: 80)
let ins = FieldText.read(value: "Hi\n" + long, selected: "", cursor: 3)
check(ins.mode == .insert && ins.box.hasPrefix("Hi\n[cursor]"), "long box inserts at the cursor")
check(FieldText.read(value: long, selected: nil, cursor: 99_999).box.contains("[cursor]"), "cursor past the end is clamped")

// Instructions
check(Writer.instruction("", field: FieldText(), refining: false).contains("next message"), "empty box default")
check(Writer.instruction("", field: FieldText(mode: .whole, draft: "x"), refining: false).contains("finished text"), "draft default")
check(Writer.instruction("Shorter", field: FieldText(), refining: true).contains("shorter"), "chip maps to an instruction")
check(Writer.instruction("make it rhyme", field: FieldText(), refining: false) == "make it rhyme", "free text passes through")

// Prompt
let p = Writer.prompt(ask: "", field: FieldText(mode: .whole, draft: "ok 3pm"), screen: "Ana: can we meet?", app: "Slack", window: "#team")
check(p.contains("Slack, window “#team”") && p.contains("<screen>") && p.contains("<draft>\nok 3pm"), "prompt has place, screen and draft")
check(!Writer.prompt(ask: "x", field: FieldText(), screen: "  ", app: "Notes", window: "Notes").contains("<screen>"), "blank screen is left out")
check(Writer.system(about: "I'm Sam, I sign off with — S").contains("About the user"), "about-me is added")
check(!Writer.system(about: "  ").contains("About the user"), "blank about-me is left out")

// Clean-up
check(Writer.clean("```\nHi Ana\n```") == "Hi Ana", "fence stripped")
check(Writer.clean("```text\nHi Ana\n```") == "Hi Ana", "fence with tag stripped")
check(Writer.clean("Here's a reply:\nSure, 3pm works.") == "Sure, 3pm works.", "preamble stripped")
check(Writer.clean("“Sounds good!”") == "Sounds good!", "wrapping quotes stripped")
check(Writer.clean("\"a\" and \"b\"") == "\"a\" and \"b\"", "inner quotes kept")
check(Writer.clean("Note: bring the file\nThanks") == "Note: bring the file\nThanks", "normal first line kept")

// Picking screen lines
let field = CGRect(x: 300, y: 800, width: 600, height: 40)
let items: [(CGRect, String)] = [
    (CGRect(x: 10, y: 100, width: 200, height: 20), "# sidebar channel"),
    (CGRect(x: 320, y: 300, width: 500, height: 20), "Ana: can we meet at 3? " + String(repeating: "details ", count: 30)),
    (CGRect(x: 320, y: 340, width: 500, height: 20), "Ana: can we meet at 3? " + String(repeating: "details ", count: 30)),
    (CGRect(x: 320, y: 900, width: 500, height: 20), "below the box"),
]
let picked = Writer.pick(items, field: field)
check(picked.contains("Ana") && !picked.contains("sidebar") && !picked.contains("below"), "column above the box only")
check(picked.components(separatedBy: "Ana:").count == 2, "duplicates dropped")
check(Writer.pick(items, field: field, limit: 50).isEmpty || Writer.pick(items, field: field, limit: 50).count <= 50, "limit respected")
check(Writer.pick([(CGRect(x: 0, y: 0, width: 10, height: 10), "only")], field: nil) == "only", "no field keeps everything")

if failures > 0 { print("✗ \(failures) writer test(s) failed"); exit(1) }
print("✓ writer tests passed")
