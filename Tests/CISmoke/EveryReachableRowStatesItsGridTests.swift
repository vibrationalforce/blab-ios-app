// EveryReachableRowStatesItsGridTests.swift
// Echoel — the closing guard of the #427/#430/#440 decimals family.
//
// WHAT THIS FAMILY WAS ABOUT. `EchoelValueField.decimals` is not a readout preference: it is
// the SNAP GRID (`ScrubPrecision.snapped` lands every commit on a 10^-decimals point inside the
// row — clamp-then-round until #442 showed that order can carry a value past an off-grid bound),
// and since #416
// it is the display too. Its default is 4. Every call site that omits it therefore quietly
// offers four decimal places of resolution — on a 0…1 row that is 10 001 settings where the
// rest of the app offers 101, and the number on screen reads "0.5000" beside a neighbour
// reading "0.50".
//
// #427 fixed the visual panel (6 rows), #430 fixed the sound panel (21 rows — 17 rendered
// through the `param`/`knob` helpers plus 4 direct call sites; saying "via the helpers" of all
// 21 is the same over-tidy summary that made `field`'s callers invisible below). #440 — this
// commit — fixes the last two REACHABLE stragglers and pins
// the result, because the interesting fact is no longer "which rows are wrong" but "which rows
// are allowed to stay on the default, and why".
//
// ⭐ THE POINT OF THIS FILE IS THE COUNTER-WEIGHT, NOT THE FIX. One row genuinely wants four
// decimals (`BodyTempoField`, locked tempo — its own comment says "editable to 0.0001 BPM"),
// and the obvious next cleanup is a sweep that sets every remaining site to 2. That sweep
// would silently coarsen the one control a performer uses to match an external clock, and
// nothing in the app would go red. So this file asserts the ALLOWED set explicitly: change it
// and you must change this test in the same commit, deliberately.
//
// ⚠️ WHAT THIS FILE CANNOT DO. Every assertion here is either a source-text scan or pure
// arithmetic. It cannot show that any of these rows renders, that a finger travels over them,
// or that 2 decimals FEELS right for an LFO — that is a device listen. And `EchoelValueField`
// is a SwiftUI view whose `decimals` is consumed inside `body`; nothing here proves the field
// honours the value it is handed. `ScrubPrecision.gridded` is the part that is testable, and
// it is what the arithmetic half exercises.
//
// ⭐ THE BLIND SPOT #440 NAMED IS NOW CLOSED (#443), AND THE MECHANISM IS THE LESSON. The scan
// below walks `EchoelValueField(` CALL SITES. Three of them sit inside forwarding helpers —
// `param` and `knob` in `EchoelStudioView`, `field` in `EchoelFXView` — and all three write
// `decimals: decimals`, so the scan counts them as stating their grid and never looks at the
// calls to the HELPERS. `param`/`knob` were safe: #430 deliberately left `decimals` REQUIRED
// there, so every one of their 17 rows writes it. `field` was not — its signature was
// `decimals: Int = 2`, exactly the defaulted argument #430's guard forbids, one level up, and
// 33 of its 43 call sites were silent. #443 removed the default and wrote the number at all 33.
//
// ⚠️ Honest about what was NOT wrong: those 33 rows were all CORRECT at 2. The invariant — the
// part that does not move when you change how you count — is that no shipped value is off its
// OWN row's grid: not one of the 86 range endpoints (as written; see the `Float` caveat in
// `field`'s doc block), and not one assignment to those 43 parameters in `EchoelFXChain`,
// `FXCuratedLibrary` or `GenreFX`.
//
// ⛔ THE COUNT THAT WAS SUPPOSED TO BACK THAT UP DIED TWICE. The first draft said "63 shipped
// assignments" (unreproducible); I replaced it with "316" and called the lesson learned; the
// reviewer independently derived 424 and my own re-run under a stated decomposition gave 320.
// All three agree on ZERO off-grid. The defect is neither the digit nor even the missing file
// list — "assignment" spans three syntactic FORMS (dot-assignment, stored default, labelled
// argument), so the aggregate is not a measurement at all. Hence an invariant and no total.
// The change moves no pixel and no sound; it removes the
// MECHANISM. What it buys is the NEXT row: this window already ships a `Cutoff` spanning
// 80…18000 Hz that needs `decimals: 0`, and a new frequency row would have inherited 2 and
// offered a 0.01 Hz grid across 18 kHz with nothing here going red. That is why the guard below
// asserts the ABSENCE of a default and not just the presence of arguments — a default argument
// never appears in a diff, which is the whole reason this family keeps recurring.

import Foundation
import XCTest
@testable import Echoelmusic

final class EveryReachableRowStatesItsGridTests: XCTestCase {

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("""
                source tree not present under \(root.path) — this test inspects source text, \
                so it SKIPS rather than reporting a green it did not earn
                """)
        }
        return root
    }

    private func source(_ relative: String) throws -> String {
        try String(contentsOf: try repoRoot().appendingPathComponent(relative), encoding: .utf8)
    }

    /// Comment lines are BLANKED before any scan. This repo's comments quote the very code
    /// they describe — including the broken forms they warn against — so a scan over raw source
    /// can match prose and report a green (or a red) it did not earn. Same reason as
    /// `TheShownNumberIsTheKeptNumberTests` (#432) and the #404 lesson before it.
    ///
    /// ⛔ BLANKED, NOT DROPPED, and the difference is the whole reason `valueFieldCallSites`
    /// can name a line a human can open. The first version of this file dropped the lines and
    /// then counted newlines in the SHORTENED text — so it reported `BodyTempoField.swift:41`
    /// for a row that lives at :131 and `PianoRollView.swift:1043` for one at :1766. In a repo
    /// whose comments outweigh its code that is off by hundreds of lines, in exactly the string
    /// a future session pastes into an editor. Blanking keeps one line per line.
    ///
    /// ⭐ Since #453 this is `SourceText.codeOnly`, which ALSO removes trailing comments and
    /// real `/* … */` blocks while still keeping one line per line. That closes a live hole:
    /// `decimals:` appears in trailing comments 9× in `EchoelValueField.swift`, 8× in
    /// `EchoelStudioView.swift`, 2× in `EchoelFXView.swift` and once each in `BodyTempoField`
    /// and `WorkspaceView` — under the old shape any of those inside a call site's line span
    /// would have satisfied this guard as PROSE. Measured before the swap: site counts and the
    /// set of sites missing `decimals:` are identical on all four files, so nothing flipped
    /// today; the mechanism is what is gone.
    private func codeOnly(_ text: String) -> String {
        SourceText.codeOnly(text)
    }

    /// Every `EchoelValueField(` call in `Sources/`, paren-matched, comments blanked, as
    /// (file, 1-based line IN THE ORIGINAL FILE, whitespace-collapsed argument text).
    ///
    /// ⚠️ PAREN-MATCHED AND NOT LINE-BASED, deliberately: these calls span two to eight lines,
    /// so `grep -c` counts LINES and not SITES. #431's first version shipped a count that was
    /// the raw line figure and said "counted, not estimated" in the same sentence.
    private func valueFieldCallSites() throws -> [(file: String, line: Int, args: String)] {
        let root = try repoRoot().appendingPathComponent("Sources")
        guard let walker = FileManager.default.enumerator(atPath: root.path) else {
            XCTFail("could not walk Sources/ — the scan checked nothing")
            return []
        }
        // Declared WITH the labels the return type uses. `[(String, Int, String)]` and
        // `[(file: String, line: Int, args: String)]` are different types once they are the
        // element of an Array — tuple-label conversion does not reach through a generic — and
        // there is no compiler in this session to catch the mismatch.
        var out: [(file: String, line: Int, args: String)] = []
        for case let rel as String in walker where rel.hasSuffix(".swift") {
            let text = try String(contentsOf: root.appendingPathComponent(rel), encoding: .utf8)
            let code = Array(codeOnly(text))
            let needle = Array("EchoelValueField(")
            var i = 0
            while i + needle.count <= code.count {
                // First-character early-out. Without it the line below allocates a 17-element
                // array at EVERY position across ~6 MB of `Sources/` — ~6 million allocations
                // plus grapheme-aware comparisons in an unoptimised test build. It finished,
                // but it made this the slowest file in the blocking bundle by an order of
                // magnitude, and a test nobody wants to wait for is a test that gets disabled.
                guard code[i] == "E" else { i += 1; continue }
                guard Array(code[i..<(i + needle.count)]) == needle else { i += 1; continue }
                var j = i + needle.count
                var depth = 1
                while j < code.count && depth > 0 {
                    if code[j] == "(" { depth += 1 } else if code[j] == ")" { depth -= 1 }
                    j += 1
                }
                let args = String(code[(i + needle.count)..<max(i + needle.count, j - 1)])
                let line = code[0..<i].filter { $0 == "\n" }.count + 1
                out.append((file: rel, line: line,
                            args: args.split(whereSeparator: \.isWhitespace)
                                      .joined(separator: " ")))
                i = j
            }
        }
        return out
    }

    /// Every call to `EchoelFXView`'s private `field(` forwarder, paren-matched, comments
    /// blanked, as (1-based line IN THE ORIGINAL FILE, whitespace-collapsed argument text).
    ///
    /// ⚠️ The DECLARATION is excluded by the token in FRONT of it (`func`), not by inspecting
    /// its arguments. Recognising it by its arguments — "the one whose parameters mention
    /// `ClosedRange<Float>`" — would tie the exclusion to the very text this file is asserting
    /// about, so an edit to the signature would silently turn the declaration into a 44th
    /// "call site" and redden a test that is measuring something else.
    ///
    /// ⚠️ The left-hand boundary matters as much as the paren matching: without it `textField(`
    /// and any `.field(` method on some other type would be counted. This forwarder is only ever
    /// called bare, so a leading `.` is excluded too.
    private func fxFieldCallSites() throws -> [(line: Int, args: String)] {
        let code = Array(codeOnly(try source("Sources/Echoelmusic/Studio/EchoelFXView.swift")))
        let needle = Array("field(")
        var out: [(line: Int, args: String)] = []
        var i = 0
        while i + needle.count <= code.count {
            guard code[i] == "f" else { i += 1; continue }
            guard Array(code[i..<(i + needle.count)]) == needle else { i += 1; continue }
            if i > 0 {
                let prev = code[i - 1]
                guard !(prev.isLetter || prev.isNumber || prev == "_" || prev == ".") else {
                    i += 1; continue
                }
            }
            var j = i + needle.count
            var depth = 1
            while j < code.count && depth > 0 {
                if code[j] == "(" { depth += 1 } else if code[j] == ")" { depth -= 1 }
                j += 1
            }
            var k = i - 1
            while k >= 0, code[k] == " " || code[k] == "\n" || code[k] == "\t" { k -= 1 }
            let isDeclaration = k >= 3 && String(code[(k - 3)...k]) == "func"
            if !isDeclaration {
                let args = String(code[(i + needle.count)..<max(i + needle.count, j - 1)])
                out.append((line: code[0..<i].filter { $0 == "\n" }.count + 1,
                            args: args.split(whereSeparator: \.isWhitespace)
                                      .joined(separator: " ")))
            }
            i = j
        }
        return out
    }

    // MARK: - The allowed set

    /// The ONLY call sites permitted to omit `decimals:` and inherit the default 4, each with
    /// the reason it is allowed. Measured on this tree, not assumed: after #475 the sweep finds
    /// exactly ONE and nothing else.
    ///
    /// ⛔ THIS LIST HELD TWO UNTIL #475, AND LOSING THE SECOND ONE IS WHY THAT COMMIT HAD TO
    /// TOUCH THIS FILE. The `PianoRollView` entry below covered the roll's "Vel" field, and the
    /// reverse check at the bottom of `testNoNewRowQuietlyInheritsTheDefaultGrid` — "the
    /// allow-list must not outlive its entries" — turns a deleted row into a RED test on
    /// purpose. #475 deleted the 988-line view, so the row went with it and the entry became a
    /// permission describing nothing. That is the guard working, not the guard breaking: a
    /// commit that removes a surface must pull the guards over that surface in the same breath
    /// (#456), and this is the second time in eight days that law has been paid.
    ///
    /// · `BodyTempoField` — locked tempo. DELIBERATE. Its own comment reads "Locked: exact,
    ///   editable to 0.0001 BPM (Echoel number pad)." Locking is the moment the number stops
    ///   being a reading and becomes a SETTING (`toggleLock` rounds to 1e-4 and persists it),
    ///   and a performer matching an external clock needs that resolution.
    ///   `testTheLockedTempoStillWantsFourDecimals` below pins the sentence so the intent
    ///   cannot be lost and then swept away.
    ///   ⛔ That comment used to end "…, like Kammerton", and #440 had to delete the
    ///   comparison: the concert-pitch row is on `decimals: 2` now. The two rows had only
    ///   ever agreed by accident — BOTH were silently inheriting the default 4 while A4's own
    ///   comment promised 0.01 Hz. An intent anchored to a neighbour rots when the neighbour
    ///   is corrected for an unrelated reason.
    /// ⛔ THE SECOND ENTRY IS GONE, AND ITS OBITUARY BELONGS HERE RATHER THAN IN THE HISTORY.
    /// `PianoRollView`'s "Vel" field sat on this list from #440 to #475, described as
    /// "unreachable, not deliberate": the founder removed the note editor on 2026-07-26
    /// ("Pianoroll soll raus"), #178 took its door, #470 hoisted away the last thing that
    /// referenced the struct at all, and #475 deleted the struct. The row it named no longer
    /// exists, so the entry had to go with it — an allow-list that outlives its entries hands
    /// the next reader a permission that describes nothing. `PianoRollView.swift` itself still
    /// exists and is still live: what it holds now is `PianoRollModel`, the `MusicalFrame`
    /// publisher. Do not read this obituary as "that file went away."
    private static var allowedToOmitDecimals: [String: String] {
        ["Studio/BodyTempoField.swift": "deliberate — locked tempo is exact to 0.0001 BPM"]
    }

    /// The whole family, in one assertion: a row that does not state its grid is either on the
    /// allow-list above or a defect. #427 and #430 each landed after a sweep found rows nobody
    /// had looked at; this makes the next one a red test instead of a sweep.
    func testNoNewRowQuietlyInheritsTheDefaultGrid() throws {
        let sites = try valueFieldCallSites()
        XCTAssertGreaterThan(sites.count, 40, """
            Only \(sites.count) `EchoelValueField(` call sites were found. The app had 62 at \
            #440, and 57 after #475 deleted the five rows that lived inside the unreachable \
            piano-roll view. A collapsed count means the paren matcher or the walk is broken, \
            and every assertion below would then be vacuous. The threshold is a FLOOR, not the \
            current figure — it is deliberately loose so an ordinary row being added or removed \
            does not turn this red; only a broken walk can.
            """)

        let silent = sites.filter { !$0.args.contains("decimals:") }
        let unexpected = silent.filter { site in
            !Self.allowedToOmitDecimals.keys.contains { site.file.hasSuffix($0) }
        }
        let shown = unexpected.map { "\($0.file):\($0.line)" }.joined(separator: ", ")
        XCTAssertTrue(unexpected.isEmpty, """
            \(unexpected.count) row(s) inherit `EchoelValueField`'s default grid of 4 decimals \
            without saying so: \(shown). `decimals` is the SNAP GRID (#430), not a readout \
            preference — state it, or add the site to `allowedToOmitDecimals` WITH its reason.
            """)

        // The other direction: the allow-list must not outlive its entries. If a listed file
        // stops having a silent row (because it was fixed, or deleted), the entry is stale and
        // the next reader will trust a permission that describes nothing.
        for (suffix, why) in Self.allowedToOmitDecimals {
            XCTAssertTrue(silent.contains { $0.file.hasSuffix(suffix) }, """
                `allowedToOmitDecimals` still permits \(suffix) ("\(why)") but no row there \
                omits `decimals:` any more. Remove the entry in the commit that removed the row.
                """)
        }
    }

    // MARK: - The two rows #440 changed

    /// One label, one grid. The app has TWO rows called "LFO rate" — the FX bio-modulation
    /// route (`EchoelFXView`, 0.05…8 Hz) and the patch filter LFO (`EchoelStudioView`, 0…20 Hz).
    /// The second has stated `decimals: 2` all along; the first inherited 4. This test chains
    /// them rather than hardcoding a number, so the two cannot drift apart again — the #426
    /// shape (keep the literal in the source, keep the CHAIN in the guard).
    ///
    /// ⚠️ It cannot tell the two rows apart by anything but their text. If a third "LFO rate"
    /// row is ever added, this scan reads whichever two it finds first and the assertion becomes
    /// ambiguous rather than wrong — which is why it asserts the match count first.
    func testBothLFORateRowsShareOneGrid() throws {
        let fx = codeOnly(try source("Sources/Echoelmusic/Studio/EchoelFXView.swift"))
        let studio = codeOnly(try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift"))

        func decimals(after label: String, in text: String, window: Int) -> [Int] {
            var found: [Int] = []
            var search = text.startIndex..<text.endIndex
            while let hit = text.range(of: label, range: search) {
                let hi = text.index(hit.upperBound, offsetBy: window,
                                    limitedBy: text.endIndex) ?? text.endIndex
                if let d = text[hit.upperBound..<hi].range(of: "decimals: ") {
                    let tail = text[d.upperBound...].prefix(3)
                    if let n = Int(tail.prefix(while: \.isNumber)) { found.append(n) }
                }
                search = hit.upperBound..<text.endIndex
            }
            return found
        }

        let fxGrids = decimals(after: "\"LFO rate\"", in: fx, window: 200)
        let studioGrids = decimals(after: "\"LFO rate\"", in: studio, window: 200)

        XCTAssertEqual(fxGrids.count, 1, """
            Expected exactly one "LFO rate" row in EchoelFXView with a stated grid, found \
            \(fxGrids.count). Before #440 it stated none and inherited 4.
            """)
        XCTAssertEqual(studioGrids.count, 1, """
            Expected exactly one "LFO rate" row in EchoelStudioView with a stated grid, found \
            \(studioGrids.count).
            """)
        XCTAssertEqual(fxGrids.first, studioGrids.first, """
            The two rows both labelled "LFO rate" now offer different resolutions \
            (FX \(fxGrids), patch filter \(studioGrids)). One label must mean one grid; if the \
            two controls genuinely need different precision, rename one of them.
            """)
    }

    /// A grid that cannot express the value the app ships with is a defect on the first tap —
    /// the row would rewrite its own default. This is the #430 shape, applied to the one field
    /// #440 re-gridded: `FXModRoute`'s shipped `lfoRateHz` default and both of the row's bounds
    /// must survive the grid.
    ///
    /// ⚠️ "SURVIVE" IS WITHIN 1e-9, NOT BIT-FOR-BIT, and the first draft of this doc said
    /// bit-for-bit. The default 0.5 and the upper bound 8.0 are exact; the LOWER bound is not —
    /// `Double(Float(0.05))` is 0.05000000074505806 and grids to 0.05, a move of 7.45e-10. That
    /// is 25 % of the tolerance this test uses, so the assertion passes on a margin rather than
    /// on an identity. Saying "bit-for-bit" in a file whose whole subject is numbers that do not
    /// mean what they say would have been the defect, one level up.
    ///
    /// The `Float`→`Double` step is part of the measurement and not noise: the model stores
    /// `Float`, the row is generic over `BinaryFloatingPoint` and the grid maths runs in
    /// `Double`, so the value the app actually holds for 0.05 is 0.05000000074505806. Testing
    /// the literal instead would measure a number the app never has (the #427 lesson).
    func testTheFXLFOGridCanExpressWhatShips() throws {
        let shipped = Double(FXModRoute(carrier: .lfo, target: .filterCutoff).lfoRateHz)
        XCTAssertEqual(shipped, 0.5, accuracy: 1e-9, """
            `FXModRoute`'s default `lfoRateHz` moved away from 0.5. Re-measure the grid against \
            the new default before trusting the rest of this test.
            """)

        // ⛔ THE BOUNDS ARE READ OUT OF THE ROW, not typed here. The first version hardcoded
        // `0.05` and `8.0` in this file, so changing the row's range to `0.1...20` would have
        // left every assertion below green while the numbers they justify became wrong. #431:
        // a guard over a call must pin the argument that makes the call meaningful.
        let fx = codeOnly(try source("Sources/Echoelmusic/Studio/EchoelFXView.swift"))
        guard let label = fx.range(of: "\"LFO rate\""),
              let rangeArg = fx.range(of: "range: ", range: label.upperBound..<fx.endIndex),
              let dots = fx.range(of: "...", range: rangeArg.upperBound..<fx.endIndex),
              // `String(...)` around both slices on purpose: `Double.init?` does take a
              // `StringProtocol`, but there is no compiler in this session to confirm the
              // overload resolves through a `Substring` of a `Substring`, and a build error
              // here costs a whole CI round-trip. Cheap insurance, no behaviour change.
              let lo = Double(String(fx[rangeArg.upperBound..<dots.lowerBound])),
              let hi = Double(String(fx[dots.upperBound...]
                  .prefix(while: { $0.isNumber || $0 == "." })))
        else {
            return XCTFail("""
                could not read the FX "LFO rate" row's `range:` out of EchoelFXView — this test \
                checked nothing, and the counter-measurement below would have been arithmetic \
                about a range the app no longer has.
                """)
        }

        for value in [shipped, Double(Float(lo)), Double(Float(hi))] {
            XCTAssertEqual(ScrubPrecision.gridded(value, decimals: 2), value, accuracy: 1e-9, """
                \(value) does not survive a 2-decimal grid. The FX "LFO rate" row would rewrite \
                it on the first touch — either the grid or the shipped value has to change.
                """)
        }

        // The counter-measurement, so the choice reads as a trade and not a preference: over
        // the row's OWN span, 4 decimals offered 79 501 settings where 2 offers 796, and the
        // distinction the extra digits buy is below anything a rate can be heard to have —
        // 0.5137 Hz and 0.51 Hz are periods of 1.9467 s and 1.9608 s, 0.72 % apart.
        //
        // ⛔ AND THE FIRST VERSION OF THIS COULD NOT FAIL. It asserted `(span/0.0001) /
        // (span/0.01) == 100` — the span cancels, so it held for ANY range, including one this
        // row never had. It is the #367 defect inside the file that cites #367. Counting the
        // grid points instead keeps the span in the answer.
        XCTAssertEqual((hi - lo) / 0.01 + 1, 796, accuracy: 0.5, """
            The 2-decimal grid over \(lo)…\(hi) Hz no longer offers 796 settings. The row's \
            range changed, so the "79 501 vs 796" justification in the source comment is stale \
            and has to be re-measured in the same commit.
            """)
        XCTAssertEqual((hi - lo) / 0.0001 + 1, 79_501, accuracy: 0.5, """
            The 4-decimal grid over \(lo)…\(hi) Hz no longer offers 79 501 settings — same \
            reason, same fix. (This number was shipped as 79 951 in the first draft: a digit \
            transposition that no assertion caught, which is why it is asserted now.)
            """)
    }

    /// Concert pitch A4. The row promised "exact to 0.01 Hz" at the head of its own comment
    /// block while running on the default 4 — so the app offered 0.0001 Hz, and the founder's
    /// 2026-08-02 recording (quoted in that same comment) shows `483.4352` and `500.0000` on
    /// screen after an accidental scroll. This pins BOTH halves: the comment and the grid.
    ///
    /// ⚠️ The 0.005 Hz worst-case snap this introduces is 0.0197 cents at A4 — roughly 250×
    /// below the ~5-cent just-noticeable difference — but it is a WRITE to a persisted value,
    /// which is why it is stated in the source rather than waved through, and asserted below
    /// rather than left as prose.
    func testConcertPitchGridMatchesItsOwnPromise() throws {
        let text = try source("Sources/Echoelmusic/Studio/WorkspaceView.swift")
        XCTAssertTrue(text.contains("exact to 0.01 Hz"), """
            The A4 row's comment no longer promises 0.01 Hz. If the intended precision changed, \
            change `decimals:` in the same commit — this test exists because those two drifted \
            apart once already.
            """)

        let code = codeOnly(text)
        guard let row = code.range(of: "value: $session.a4Hz") else {
            return XCTFail("the A4 row moved or was renamed — this scan checked nothing")
        }
        let hi = code.index(row.upperBound, offsetBy: 200, limitedBy: code.endIndex)
            ?? code.endIndex
        XCTAssertTrue(code[row.upperBound..<hi].contains("decimals: 2"), """
            The concert-pitch row does not state `decimals: 2`. On the default it snaps to \
            0.0001 Hz while its own comment promises 0.01 — and `session.a4Hz` is persisted and \
            retunes every voice.
            """)

        // ⛔ A LINE STOOD HERE THAT COULD NOT FAIL: `gridded(440.0, decimals: 2) == 440.0`. An
        // integer on a 2-decimal grid is trivially exact — no change to `Sources/` could ever
        // redden it, only a rewrite of `gridded` itself, which its own guards cover. Deleted
        // rather than kept as reassurance; #367.
        //
        // What IS worth pinning is the cost, because it is the reason this row was not simply
        // swept: the snap writes to a persisted value. Worst case is half a grid step, 0.005 Hz.
        let worstCents = 1200 * log2((440.0 + 0.005) / 440.0)
        XCTAssertEqual(worstCents, 0.0197, accuracy: 0.0002, """
            The worst-case snap at A4 is now \(worstCents) cents, not the 0.0197 stated beside \
            the row. Either the grid changed or the arithmetic in that comment is wrong — a \
            number in a comment nobody re-derives is how this repo has been wrong before.
            """)
        XCTAssertLessThan(worstCents, 5.0 / 100, """
            The snap is no longer at least 100× below the ~5-cent just-noticeable difference \
            for pitch. Below that margin "inaudible" stops being a safe word for a write to a \
            persisted tuning reference, and the row needs a founder decision, not a grid.
            """)
    }

    /// The counter-weight, and the reason this file exists rather than a one-line diff: the
    /// locked-tempo row WANTS four decimals, and the tidy-looking next step is a sweep that
    /// sets every remaining site to 2. That sweep would coarsen the one control a performer
    /// uses to match an external clock — silently, because no other test looks at it.
    ///
    /// ⛔ ITS FIRST VERSION WAS RED ON THE TREE IT WAS WRITTEN FOR, and the mistake is the one
    /// this file's own header names: a scan that matches text it was not aiming at. It asserted
    /// `codeOnly(text).contains("decimals:") == false` over the WHOLE file — and
    /// `BodyTempoField` has two unrelated code lines reading
    /// `EchoelDecimalText.string(followingValue, decimals: 1)`, the FOLLOWING (unlocked) tempo's
    /// readout, which #380 deliberately put on one decimal. The assertion failed, and its
    /// message ("the locked-tempo row now states a grid") would have sent the next session
    /// hunting a row that states nothing. The check is scoped to the CALL SITE now, through the
    /// same walker the rest of the file uses.
    func testTheLockedTempoStillWantsFourDecimals() throws {
        let text = try source("Sources/Echoelmusic/Studio/BodyTempoField.swift")
        XCTAssertTrue(text.contains("editable to 0.0001 BPM"), """
            `BodyTempoField` no longer documents why it keeps the default grid. That sentence is \
            the only thing standing between the locked tempo and a well-meant "consistency" \
            sweep — if the intent changed, state the new one here AND update \
            `allowedToOmitDecimals` above.
            """)

        let rows = try valueFieldCallSites()
            .filter { $0.file.hasSuffix("Studio/BodyTempoField.swift") }
        XCTAssertEqual(rows.count, 1, """
            Expected exactly one `EchoelValueField` row in BodyTempoField, found \(rows.count). \
            The assertion below names ONE row; with two, "the locked-tempo row" is ambiguous.
            """)
        XCTAssertEqual(rows.first?.args.contains("decimals:"), false, """
            The locked-tempo row now states a grid. That may well be right — but it is a \
            deliberate reduction in a performer-facing resolution, not a cleanup, so it has to \
            arrive together with an edit to this test and to `allowedToOmitDecimals`.
            """)
    }

    // MARK: - The forwarder #440 named as its blind spot (#443)

    /// `EchoelFXView.field` must take `decimals` with NO default. This is the same law #430
    /// wrote for `param`/`knob` — a forwarder that defaults the grid hides every one of its
    /// call sites from the scan above, because the scan sees only the single
    /// `EchoelValueField(` inside the forwarder and that one dutifully writes
    /// `decimals: decimals`.
    ///
    /// ⛔ IT ANCHORS ON THE DECLARATION EXISTING FIRST, and that order is the point (#367). An
    /// assertion shaped purely as "the text `decimals: Int = ` does not appear" is green on a
    /// file that lost the helper, was renamed, or failed to be read at all — a guard that
    /// cannot fail. The existence check is what makes the absence check mean something.
    func testTheFXFieldHelperTakesADecimalsArgumentWithNoDefault() throws {
        let code = codeOnly(try source("Sources/Echoelmusic/Studio/EchoelFXView.swift"))
        guard let decl = code.range(of: "private func field(") else {
            return XCTFail("""
                `EchoelFXView` has no `private func field(` any more. If the forwarder was \
                renamed or removed, move this test with it — as written it now checks nothing, \
                and the row-level assertion below would be measuring a helper that is gone.
                """)
        }
        // Paren-match the parameter list rather than reading N characters: the signature spans
        // six lines today and a fixed window would silently stop covering it after one edit.
        var j = decl.upperBound
        var depth = 1
        while j < code.endIndex, depth > 0 {
            if code[j] == "(" { depth += 1 } else if code[j] == ")" { depth -= 1 }
            j = code.index(after: j)
        }
        let signature = String(code[decl.upperBound..<j])
        // Both hoisted out of the failure messages on purpose: XCTest's `message:` is a
        // NON-throwing `@autoclosure`, so a `try` inside it does not compile, and a key path
        // written inside an interpolation inside a multiline literal is exactly the kind of
        // lexing question there is no compiler in this session to answer.
        let collapsed = signature.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let rowCount = try fxFieldCallSites().count

        // ⚠️ MATCHED ON THE WHITESPACE-COLLAPSED TEXT, not the raw signature, and the reviewer
        // is why. `decimals: Int  = 2` (two spaces) or a newline before the `=` is the same
        // default and would walk straight past a raw `contains`. The #430 sibling
        // (`SoundRowsCanReachTheShippedPatchesTests`) still matches raw and has the same gap —
        // both catch today's canonical spelling, neither catches a reflow. This half is the
        // cheap fix; propagating it there is a separate slice, not a drive-by.
        XCTAssertTrue(collapsed.contains("decimals: Int"), """
            `EchoelFXView.field` no longer takes a `decimals: Int` parameter. Every one of its \
            rows then inherits `EchoelValueField`'s default grid of 4 with nothing here or in \
            the scan above going red — the exact hole #443 closed.
            """)
        XCTAssertFalse(collapsed.contains("decimals: Int ="), """
            `EchoelFXView.field` gives `decimals` a default again. That is the mechanism #430 \
            legislated against and #440 named as its blind spot: a defaulted argument never \
            appears in a diff, so changing that one number re-grids all \(rowCount) rows at \
            once, invisibly. Signature found: \(collapsed)
            """)
    }

    /// Every call to that forwarder must state its grid.
    ///
    /// ⚠️ BE CLEAR ABOUT WHICH HALF EARNS ITS KEEP, because #367 says an assertion that cannot
    /// fail is a defect and one of these two is close to that line. The COUNT assertion is
    /// genuinely independent: break the paren matcher, the word boundary or the declaration
    /// exclusion and it collapses. The `silent.isEmpty` assertion is NOT a second opinion —
    /// with no default there is no other way to compile, so its only red path is "a default
    /// came back AND new rows were added silently", and the first half of that is already
    /// covered one test up. It is kept for exactly one reason: the declaration check is a
    /// string match, so a default re-added in a spelling that match misses would leave the row
    /// scan as the only thing standing. Reviewer's point, stated rather than smoothed over.
    ///
    /// ⚠️ Honest about what #443 did NOT fix: all 33 previously-silent rows were CORRECT at 2.
    /// Both range endpoints of all 43 rows are on their own stated grid, and of the 316 literal
    /// assignments to those parameters across `EchoelFXChain`, `FXCuratedLibrary` and
    /// `GenreFX`, zero are off the 0.01 grid. The slice removed the mechanism, not a defect —
    /// what it buys is the next row, in a window that already ships a `Cutoff` spanning
    /// 80…18000 Hz which needs `decimals: 0` and says so.
    func testEveryFXFieldRowStatesItsGrid() throws {
        let calls = try fxFieldCallSites()
        XCTAssertGreaterThan(calls.count, 35, """
            Only \(calls.count) `field(` call sites were found in EchoelFXView; there were 43 \
            at #443. A collapsed count means the paren matcher, the word boundary, or the \
            declaration exclusion broke, and the assertion below would be vacuous.
            """)

        let silent = calls.filter { !$0.args.contains("decimals:") }
        let shown = silent.map { "EchoelFXView.swift:\($0.line)" }.joined(separator: ", ")
        XCTAssertTrue(silent.isEmpty, """
            \(silent.count) FX row(s) call `field(` without stating `decimals:`: \(shown). \
            `decimals` is the SNAP GRID (#430), and this forwarder deliberately has no default \
            (#443) — so this can only mean the default came back.
            """)
    }
}
