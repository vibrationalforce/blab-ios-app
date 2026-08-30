// SourceText.swift
// Echoel — #453. ONE definition of "code, not prose" for the source-scanning guards.
//
// WHY THIS EXISTS. A large share of the blocking bundle asserts on SOURCE TEXT: does this row
// state its grid, does this file still bind that hook, has this literal been inlined again.
// Every such guard has to strip comments first, because this repo writes very long ⛔/⭐ blocks
// that quote the exact tokens the guards forbid — #404 already had to solve "a scan cannot tell
// code from prose" on the source side.
//
// ⛔ IT WAS SOLVED TWELVE TIMES, AND THE COUNT BELOW SAID ELEVEN FOR A DAY. The survey that
// produced "eleven" ran on 2026-08-06; the guard this slice shipped alongside it
// (`OneDefinitionOfCodeNotProseTests.testNoUnlistedFileDeclaresItsOwnStripper`) disagrees:
// its anchor selects a twelfth deterministically — `TimingVerdictReachesTheScreenTests` (#408),
// which predates this file. ⚠️ Precisely: it WOULD have failed on any run that reached it, and
// whether any run reached it is unknowable, because #396 kills a simulator clone mid-suite and
// the surviving one flushes a non-deterministic subset of the log (#445). #477 folded it in.
// ⭐ THE LESSON IS ABOUT PRECEDENCE, not carefulness: when a hand survey and an executable
// guard disagree, the guard is the measurement and the survey is a memory of one. This file
// spent a paragraph warning that eleven shapes drift apart without anything noticing — and
// then shipped a count that a check in the same commit already contradicted.
//
// ⚠️ AND THE TRUE COPY COUNT IS HIGHER STILL, because the guard detects by NAME. Measured
// 2026-08-07: 8 files declare `stripComment`, 3 declare `stripComments`, 2 `sourceLines`, and
// 60 declare `codeLines` — 58 of which strip comments themselves and none of which delegate.
// That is #460; widening the anchor would red ~70 files at once and is a migration, not a
// guard change. The twelve below are the `codeOnly` family only.
//
// The twelve were, in FIVE materially different shapes —
//   1. drop the whole line            (`filter { !hasPrefix("//") }`)  · 3 files
//   2. blank the whole line           (`map { … ? "" : line }`)        · 1 file
//   3. truncate at the first `//`                                      · 5 files
//   4. trim leading spaces, then blank-or-truncate                     · 1 file
//   5. strip `/* … */` FIRST, then truncate at `//`                    · 2 files
// This is the #416 defect at its widest: one decision, twelve places to edit, and nothing that
// notices when they drift apart. Two of them already scan the SAME file (`RespirationEstimator`)
// with different shapes.
//
// ⚠️ AND THE MEASUREMENT MATTERS MORE THAN THE COUNT: on today's tree all twelve AGREE for every
// `contains`-style assertion. So this is a latent defect, not a live one, and the migration
// below is prophylactic — said plainly rather than dressed up as a bug fix.
//
// ⛔ BUT THE REASON GIVEN FOR THAT AGREEMENT WAS FALSE, and the twelfth copy is what proves it.
// This paragraph used to say "no scanned line holds `//` inside a string literal". One does:
// `EchoelStudioView.swift:3096` carries the WeatherKit attribution
// `URL(string: "https://developer.apple.com/…")`, and `TimingVerdictReachesTheScreenTests`
// scans that file. Its shape-3 stripper truncated the line at the `//` inside the literal;
// this scanner keeps it. Measured before the #477 migration: `AudioEngine.swift` differs on
// 0 lines under the two shapes, `EchoelStudioView.swift` on exactly that 1. Still
// verdict-neutral, because that line holds none of that file's four anchors — so the
// CONCLUSION survives and the PREMISE does not. The honest statement is "they agree on every
// assertion made today", which is a claim about the anchors, not about the sources.
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
//
// ⛔ AND THE LIST ABOVE OMITTED THE BIGGEST CASE FOR ITS WHOLE LIFE (#659): a Swift MULTI-LINE
// string literal, `"""`. String state is local to `stripLine`, so it resets at every newline —
// nothing a `"""` opens survives the line it sits on, and every line INSIDE such a literal is
// scanned as CODE. A `//` in that body ends the line; a `/*` in it opens a block. The contract
// sentence on `codeOnly` below — "everything the compiler would see" — is therefore FALSE for a
// multi-line body, and this block is where that should always have been said.
//
// ⭐ IT IS DELIBERATELY NOT FIXED, and the measurement is the reason rather than the effort.
// Over the 366 `.swift` files under `Sources/Echoelmusic` on 2026-08-20: NINE carry a `"""`, and
// the shipped shape disagrees with a `"""`-aware one on exactly ONE of them —
// `Views/MetalBioView.swift`, on 337 lines — and NO ASSERTION in the four guards that read that
// file changes verdict under either shape.
// ⛔ Read those numbers with the operation attached, because the first draft did not:
// 337 is DISAGREEING LINES (the shader literal itself runs 1235→1898, i.e. 662 lines, and was
// mislabelled "the 337-line Metal shader" in four places); 368 is `Sources/` as a whole while
// the guard walks 366. The conclusion survives, the descriptions did not.
// ⛔ AND THE NEEDLE HALF IS RETRACTED OUTRIGHT (#661), not re-labelled. It read "the count of
// NONE of the 36 distinct literal needles". `36` was a regex yield over four guard FILES that
// nobody reproduced; the needles actually AIMED at that file are **22** distinct strings. And
// the re-driving found the sentence false in its own terms: over a 168-literal SUPERSET, SIX
// counts do change — `0.82` 1→2, `fix` 1→11, `off` 0→6, `close` 0→1, `Bunter` 0→1, ` vs ` 0→2.
// Read at their use sites: `0.82` is a `///` doc comment, ` vs ` is a `joined(separator:)`
// argument, the rest are comment or message prose. So the CONCLUSION (no assertion moves)
// stands — but "no needle differs" was never true, and it was the form that made the claim feel
// checked. A count in a note is only worth what its operation is; when the operation is
// unrecorded, retract the count and keep the finding. The two operations are recorded in
// `TheStripperDoesNotKnowATripleQuoteTests`'s header, in ONE place (#416), not restated here.
// The 337 are shader lines carrying a `//` or `/*`, and those markers are REAL comments to the
// compiler that actually reads them. So for the single file where the
// two shapes differ, today's behaviour is the one a source scanner wants, and teaching this
// scanner about `"""` would begin handing shader PROSE to `GlitterCannotBecomeAFlashTests` — the
// WCAG-3-Hz flash-safety guard — as though it were shader code. Latent, one file, benign today,
// and the obvious repair is wrong for the only case that exists.
//   ⛔ The first draft of this block put a shell recipe here and mangled its own quoting, which
//   is the #480 failure — a recipe you cannot run is worse than none, because it reads as
//   evidence. The executable form is the guard, and it is the only form kept:
//   `TheStripperDoesNotKnowATripleQuoteTests` re-derives the census on every run and
//   goes red the day a SECOND file joins the disagreeing set — that is the day a human, not a
//   rule, has to make this call again. Its `tripleQuoteAwareCodeOnly` helper IS the second shape.

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

    /// The next `lines` lines that actually carry CODE, starting at `start`.
    ///
    /// ⛔ #898 — WHY THIS EXISTS. `codeOnly` blanks a comment's TEXT but KEEPS its leading
    /// whitespace (it has to: several guards assert on the relative ORDER of two matches, so
    /// lines are preserved, not deleted). A stripped doc line therefore still costs its
    /// indentation, so a `…[anchor...].prefix(N)` window is measured in WHITESPACE as much as
    /// in code, and adding prose above the thing being asserted walks the needle out of the
    /// window. The failure is the worst shape available: RED ON CORRECT CODE, during unrelated
    /// work, pointing at the wrong culprit. Found in #897, where a new claim was red on its own
    /// correct code.
    ///
    /// ⛔ #899 CORRECTED THREE THINGS #898 CLAIMED, all in the direction of overstating. They
    /// are corrected rather than trimmed because each is the sentence a next session quotes.
    ///
    /// · **"a fault line under 37 windows in this bundle" was ~2× too wide.** The census of 37
    ///   is right as a count of the SHAPE; the MECHANISM needs the file to use `codeOnly`.
    ///   Classified: **16** of the 35 unconverted sites do, plus the converted MIDI one. The
    ///   rest sit over a local stripper that DELETES whole comment lines (a comment costs zero
    ///   there) or over unstripped text. ⚠️ Only the 16 is firm — it is the same under two
    ///   independent classifications; the split of the remainder is heuristic and the two
    ///   disagreed on it, so no number is quoted for it here.
    /// · **"8 to 28 characters" was wrong.** Measured over every blanked line of the two files
    ///   this slice touched: the MODAL width is **4**, and the range is 0–30. Re-derive with
    ///   the width histogram rather than trusting this line.
    /// · **"five to ten comment lines from red" was derived from that wrong width** and
    ///   under-counted by several times. No comment-line figure is quoted any more: it depends
    ///   on the indent at the site, so it is not a property of the defect at all.
    ///
    /// ⚠️ AND THE MEASUREMENT IS PARTIAL, which #898 did not say here: the script resolves
    /// **5 of 35** sites. "Unresolved" means the TOOL could not read the site — never that the
    /// site is safe. Any unresolved window may be thinner than the two that were converted.
    ///
    /// ⭐ The two converted here had margins of 140 and 176 characters. The rest are a
    /// MIGRATION, not a slice (#460); `scripts/window-margins.py` is what makes that migration
    /// a list rather than a hunt.
    ///
    /// ⚠️ A LINE BUDGET IS STILL A GUESS — it is just a guess about the right QUANTITY. Where a
    /// real boundary exists (a closing brace, the next branch), anchor on it instead; that is
    /// strictly better and is what `TheVoiceDoorFeedsTheCaptureTests` does. This is for windows
    /// whose end has no stable anchor to name.
    ///
    /// ⛔ #899 — AND A TIGHTER WINDOW CAN WEAKEN A GUARD. A window has TWO failure directions
    /// and #898 reasoned about one. Skipping the blanked padding also removes the distance that
    /// kept an AMBIGUOUS needle away from a second occurrence: converting the MIDI re-arm guard
    /// cut its false-GREEN headroom from ~9 code lines to ONE, because `startIfNeeded()` also
    /// matches its own declaration below. The repair there was the NEEDLE, not the budget.
    /// Before converting a site, check what else in reach can satisfy its needles.
    ///
    /// ⚠️ TWO PROPERTIES THIS DELIBERATELY DOES NOT KEEP, and `codeOnly` does: it JOINS
    /// non-adjacent code lines, so a multi-line needle that today fails BECAUSE something sits
    /// between its halves would pass here; and it preserves neither line count nor offsets, so
    /// a guard doing index arithmetic on the window gets different numbers. Both matter only
    /// on migration — the two current callers do `contains` on adjacent code.
    static func codeWindow(_ text: String, from start: String.Index, lines: Int) -> String {
        // #899: `>= lines` is checked AFTER the append, so without this a budget of 0 returned
        // ONE line. Unreachable from today's callers; a silent off-by-one in a helper the doc
        // nominates for 35 more sites is not worth leaving for someone to trip over.
        guard lines > 0 else { return "" }
        var kept: [Substring] = []
        for line in text[start...].split(separator: "\n", omittingEmptySubsequences: false) {
            // #899: `.whitespacesAndNewlines`, not `.whitespaces` — the latter is Zs plus TAB
            // and EXCLUDES carriage return, so under CRLF a comment-only line trims to "\r",
            // counts as code, and the helper quietly reverts to burning its budget on exactly
            // the whitespace it exists to skip. No CRLF in the tree today and no `.gitattributes`
            // keeping it that way, which is the whole reason to close it now.
            if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                kept.append(line)
                if kept.count >= lines { break }
            }
        }
        return kept.joined(separator: "\n")
    }
}
