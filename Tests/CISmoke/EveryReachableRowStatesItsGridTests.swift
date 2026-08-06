// EveryReachableRowStatesItsGridTests.swift
// Echoel — the closing guard of the #427/#430/#440 decimals family.
//
// WHAT THIS FAMILY WAS ABOUT. `EchoelValueField.decimals` is not a readout preference: it is
// the SNAP GRID (`ScrubPrecision.snapped` clamps, then rounds to 10^-decimals), and since #416
// it is the display too. Its default is 4. Every call site that omits it therefore quietly
// offers four decimal places of resolution — on a 0…1 row that is 10 001 settings where the
// rest of the app offers 101, and the number on screen reads "0.5000" beside a neighbour
// reading "0.50".
//
// #427 fixed the visual panel (6 rows), #430 fixed the sound panel (21 rows, via the `param`
// and `knob` helpers). #440 — this commit — fixes the last two REACHABLE stragglers and pins
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
// ⚠️ AND ONE BLIND SPOT WORTH NAMING RATHER THAN DISCOVERING LATER (#443). The scan walks
// `EchoelValueField(` CALL SITES. Three of them sit inside forwarding helpers — `param` and
// `knob` in `EchoelStudioView`, `field` in `EchoelFXView` — and all three write
// `decimals: decimals`, so the scan counts them as stating their grid and never looks at the
// calls to the helpers themselves. `param`/`knob` are safe: #430 deliberately left `decimals`
// REQUIRED there, so every one of their 17 rows writes it. `field` is not — its signature is
// `decimals: Int = 2`, exactly the defaulted argument #430's guard forbids, one level up.
// Paren-matched over `EchoelFXView` with comments stripped: 43 `field(` call sites, 33 of
// them silent. It is harmless today because 2 is the house grid, so those 33 rows still get
// the right number; but change that one default to 4 and all 33 are coarse again with nothing
// here going red. Registered as #443, not folded in, because removing the default is a
// 33-call-site edit and a judgement call, not a measurement.

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

    /// Comment lines are stripped before any scan. This repo's comments quote the very code
    /// they describe — including the broken forms they warn against — so a scan over raw source
    /// can match prose and report a green (or a red) it did not earn. Same helper, same reason,
    /// as `TheShownNumberIsTheKeptNumberTests` (#432) and the #404 lesson before it.
    private func codeOnly(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// Every `EchoelValueField(` call in `Sources/`, paren-matched, comments stripped, as
    /// (file, 1-based line, whitespace-collapsed argument text).
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

    // MARK: - The allowed set

    /// The ONLY call sites permitted to omit `decimals:` and inherit the default 4, each with
    /// the reason it is allowed. Measured on this tree, not assumed: after #440 the sweep finds
    /// exactly these two and nothing else.
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
    /// · `PianoRollView` — the "Vel" field. UNREACHABLE, not deliberate. The founder removed
    ///   the note editor on 2026-07-26 ("Pianoroll soll raus") and `git grep 'PianoRollView('`
    ///   over `Sources/` outside its own file returns nothing. The struct survives only because
    ///   a test calls its static `occurrencePeriod(forUnit:)`. Nothing a user can reach renders
    ///   this row, so its grid decides nothing — it is listed to keep the count honest, not
    ///   because it is right.
    private static var allowedToOmitDecimals: [String: String] {
        ["Studio/BodyTempoField.swift": "deliberate — locked tempo is exact to 0.0001 BPM",
         "Studio/PianoRollView.swift": "unreachable — the note editor was removed (#178)"]
    }

    /// The whole family, in one assertion: a row that does not state its grid is either on the
    /// allow-list above or a defect. #427 and #430 each landed after a sweep found rows nobody
    /// had looked at; this makes the next one a red test instead of a sweep.
    func testNoNewRowQuietlyInheritsTheDefaultGrid() throws {
        let sites = try valueFieldCallSites()
        XCTAssertGreaterThan(sites.count, 40, """
            Only \(sites.count) `EchoelValueField(` call sites were found. The app had 62 at \
            #440; a collapsed count means the paren matcher or the walk is broken, and every \
            assertion below would then be vacuous.
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
    /// must survive the grid bit-for-bit.
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

        for value in [shipped, Double(Float(0.05)), Double(Float(8.0))] {
            XCTAssertEqual(ScrubPrecision.gridded(value, decimals: 2), value, accuracy: 1e-9, """
                \(value) does not survive a 2-decimal grid. The FX "LFO rate" row would rewrite \
                it on the first touch — either the grid or the shipped value has to change.
                """)
        }

        // The counter-measurement, so the choice is a trade and not a preference: 4 decimals
        // offered ~100× more settings across the same span, and the distinction they buy is
        // below anything a rate can be heard to have. 0.5137 Hz and 0.51 Hz are periods of
        // 1.9467 s and 1.9608 s — 0.72 % apart.
        let coarse = (8.0 - 0.05) / 0.01
        let fine = (8.0 - 0.05) / 0.0001
        XCTAssertEqual(fine / coarse, 100, accuracy: 1e-6, """
            The stated 100× resolution ratio between the old and new grid no longer holds — \
            the range or one of the grids changed, so the justification in the source comment \
            needs re-measuring too.
            """)
    }

    /// Concert pitch A4. The row promised "exact to 0.01 Hz" in its own comment six lines above
    /// while running on the default 4 — so the app offered 0.0001 Hz, and the founder's
    /// 2026-08-02 recording (quoted in that same comment) shows `483.4352` and `500.0000` on
    /// screen after an accidental scroll. This pins BOTH halves: the comment and the grid.
    ///
    /// ⚠️ The 0.005 Hz worst-case snap this introduces is 0.0197 cents at A4 — roughly 250×
    /// below the ~5-cent just-noticeable difference — but it is a WRITE to a persisted value,
    /// which is why it is stated in the source rather than waved through.
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

        // The value the promise is about must survive its own grid.
        XCTAssertEqual(ScrubPrecision.gridded(440.0, decimals: 2), 440.0, accuracy: 1e-9)
    }

    /// The counter-weight, and the reason this file exists rather than a one-line diff: the
    /// locked-tempo row WANTS four decimals, and the tidy-looking next step is a sweep that
    /// sets every remaining site to 2. That sweep would coarsen the one control a performer
    /// uses to match an external clock — silently, because no other test looks at it.
    func testTheLockedTempoStillWantsFourDecimals() throws {
        let text = try source("Sources/Echoelmusic/Studio/BodyTempoField.swift")
        XCTAssertTrue(text.contains("editable to 0.0001 BPM"), """
            `BodyTempoField` no longer documents why it keeps the default grid. That sentence is \
            the only thing standing between the locked tempo and a well-meant "consistency" \
            sweep — if the intent changed, state the new one here AND update \
            `allowedToOmitDecimals` above.
            """)
        XCTAssertFalse(codeOnly(text).contains("decimals:"), """
            The locked-tempo row now states a grid. That may well be right — but it is a \
            deliberate reduction in a performer-facing resolution, not a cleanup, so it has to \
            arrive together with an edit to this test.
            """)
    }
}
