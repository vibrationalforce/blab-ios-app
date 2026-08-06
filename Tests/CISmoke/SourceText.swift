// SourceText.swift
// Echoel — #453. ONE definition of "code, not prose" for the source-scanning guards.
//
// WHY THIS EXISTS. A large share of the blocking bundle asserts on SOURCE TEXT: does this row
// state its grid, does this file still bind that hook, has this literal been inlined again.
// Every such guard has to strip comments first, because this repo writes very long ⛔/⭐ blocks
// that quote the exact tokens the guards forbid — #404 already had to solve "a scan cannot tell
// code from prose" on the source side.
//
// ⛔ IT WAS SOLVED ELEVEN TIMES. Counted 2026-08-06 across `Tests/CISmoke`: eleven private
// `codeOnly` helpers, in FIVE materially different shapes —
//   1. drop the whole line            (`filter { !hasPrefix("//") }`)  · 3 files
//   2. blank the whole line           (`map { … ? "" : line }`)        · 1 file
//   3. truncate at the first `//`                                      · 4 files
//   4. trim leading spaces, then blank-or-truncate                     · 1 file
//   5. strip `/* … */` FIRST, then truncate at `//`                    · 2 files
// This is the #416 defect at its widest: one decision, eleven places to edit, and nothing that
// notices when they drift apart. Two of them already scan the SAME file (`RespirationEstimator`)
// with different shapes.
//
// ⚠️ AND THE MEASUREMENT MATTERS MORE THAN THE COUNT: on today's tree the eleven AGREE for every
// `contains`-style assertion. No file any of them scans holds a real `/* … */`, and no scanned
// line holds `//` inside a string literal. So this is a latent defect, not a live one, and the
// migration below is prophylactic — said plainly rather than dressed up as a bug fix.
//
// ⭐ THE PART THAT IS NOT PROPHYLACTIC: shape 5 — the one that looks most careful — is the
// DANGEROUS one, and in the opposite direction from the others. It strips `/* … */` BEFORE line
// comments, so a `/*` that is not a block opener at all (inside a `///` doc line, inside a string)
// opens a phantom block and swallows every line down to the next `*/`. `Sources/` already holds
// **8 such `/*` across 6 files** — e.g. `` `/echoelmusic/bio/breath/*` `` in a doc comment. The
// day one of those files becomes a scan target, a positive scan goes red and a negative scan goes
// GREEN ON NOTHING, which is the failure mode the blocking bundle exists to prevent.
//
// ⭐ SO THE ORDER IS THE FIX, not the thoroughness. This scanner walks each line once, in the
// order the compiler does: a `//` outside a string ends the line, a `/*` outside a string opens a
// block, and a `"` toggles string state so neither token can fire from inside a literal. Line
// COUNT is preserved (comments become empty text, never deleted lines) because several guards
// assert on the relative ORDER of two matches.
//
// ⚠️ WHAT IT DOES NOT HANDLE, so nobody assumes more than it does: raw strings (`#"…"#`) are
// treated as ordinary strings, so a `//` inside one still ends the line. No scanned file uses one
// today. Nested `/* /* */ */` — legal in Swift — is treated as a single block, so the outer `*/`
// leaks. Both are cheap to add the day a scan target needs them; neither is invented ahead of a
// real case (#367: a guard should be able to fail for a reason that exists).

import Foundation

enum SourceText {

    /// Everything in `text` that the compiler would see, with comments blanked.
    ///
    /// Line count is preserved. A `//` or `/*` inside a string literal is NOT a comment.
    static func codeOnly(_ text: String) -> String {
        var out: [String] = []
        var inBlock = false
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let result = stripLine(String(raw), inBlock: inBlock)
            inBlock = result.stillInBlock
            out.append(result.code)
        }
        return out.joined(separator: "\n")
    }

    private static func stripLine(_ line: String,
                                  inBlock: Bool) -> (code: String, stillInBlock: Bool) {
        var out = ""
        var block = inBlock
        var inString = false
        var i = line.startIndex

        while i < line.endIndex {
            let c = line[i]
            let next = line.index(after: i)
            let hasPair = next < line.endIndex
            let pairIsSlashSlash = hasPair && c == "/" && line[next] == "/"
            let pairIsBlockOpen = hasPair && c == "/" && line[next] == "*"
            let pairIsBlockClose = hasPair && c == "*" && line[next] == "/"

            if block {
                if pairIsBlockClose {
                    block = false
                    i = line.index(after: next)
                } else {
                    i = next
                }
                continue
            }

            if inString {
                // A backslash escape consumes the next character, so `\"` does not close the
                // literal. Without this, a line holding `"\""` would leave string state wrong
                // and a later `//` would survive as code.
                if c == "\\", hasPair {
                    out.append(c)
                    out.append(line[next])
                    i = line.index(after: next)
                    continue
                }
                if c == "\"" { inString = false }
                out.append(c)
                i = next
                continue
            }

            if pairIsSlashSlash { break }

            if pairIsBlockOpen {
                block = true
                i = line.index(after: next)
                continue
            }

            if c == "\"" { inString = true }
            out.append(c)
            i = next
        }

        return (out, block)
    }
}
