//
//  SoundRowsCanReachTheShippedPatchesTests.swift
//  Echoelmusic — CISmoke (blocking bundle)
//
//  #430. The Sound panel is the app's most-used craft surface — the one behind the Sound chip,
//  the one ship-gate item 2 ("Kontrolle") names. SEVENTEEN of its rows went through the two
//  helpers `param`/`knob`, neither of which passed `decimals`, so all seventeen inherited
//  `EchoelValueField`'s own default of 4. Four more rows in the same panel (Swell ↔ Strike,
//  Sub level / presence / heat) called the field directly and did the same. Twenty-one rows
//  showing "0.5000" and "2400.0000 Hz" while every FX parameter, the master level and the
//  weather mixers sit on 2 (#427, #354 A).
//
//  ⭐ `decimals` IS NOT A DISPLAY CHOICE — IT IS THE SNAP GRID. `ScrubPrecision.snapped` rounds
//  every commit to `10^-decimals`, and since #431 the keypad refuses a digit it cannot keep. So
//  the number is two promises at once: what the row SHOWS and what it can HOLD. That is why
//  this guard is not "assert 2 everywhere" — two of the twenty-one rows must be finer, and
//  which two was MEASURED from the shipped patch data, not chosen:
//
//    · `attack`     — the bank ships 0.002 / 0.003 / 0.004 / 0.005 / 0.008 s. On a centisecond
//                     grid the first FOUR collapse to 0.00 — including 0.005, because
//                     `Float(0.005)` is 0.004999999888, BELOW the half-step. An onset a
//                     designer wrote as 2 ms would become no onset. → 3 decimals (millisecond).
//    · `noiseLevel` — 0.006 (`SynthPatch.swift:424`) and 0.008 (`GenrePatches.swift:228`), which
//                     a 2-decimal grid maps onto the SAME 0.01. Two designed noise floors made
//                     indistinguishable, one field over. → 3 decimals.
//
//  And one row must be COARSER: `filterCutoff` spans 20…18000 Hz and all 44 distinct shipped
//  values (160…8000) are whole numbers, so 0 decimals — which is what the app's three OTHER
//  cutoff rows already say (`EchoelFXView:480`, `EchoelStudioView:2474` and `:2502`). A row that
//  reads "2400.0000 Hz" is not more precise, it is less legible.
//
//  ⛔ THE FIRST VERSION OF THIS FILE ASSERTED SOMETHING FALSE, AND THE CAUSE IS A METHOD, NOT A
//  NUMBER. It claimed "0 off-grid, measured" over 496 literals. That 496 covered only
//  `SynthPatch.swift` and `PatchLibrary.swift` — the third source it NAMED,
//  `MusicStyle.synthPatch`, was invisible to the scan twice over: `GenrePatches.patch(...)`
//  passes every field under a DIFFERENT argument name (`d:`, `bright:`, `revDecay:` …), and it
//  COMPUTES two of them (`GenrePatches.swift:363-364` lifts brightness and harmonicLevel
//  adaptively). Re-measured with a paren-matched parse over all 34 `patch(` calls AND with the
//  `SynthPatch.init` defaults filled in for every field a literal omits: 78 patches, 1326
//  value/row pairs, and a completely different picture. Same defect as the #431 count — the
//  METHOD in a sentence is also a claim, and mine did not cover the source it advertised.
//
//  ⭐ WHAT THE HONEST MEASUREMENT FOUND:
//    · ONE authored value was outside its row's RANGE — `Drone Bed`'s `d: 6.0`
//      (`GenrePatches.swift:146`) against a Decay row of 0…5. `snapped` clamps before it
//      rounds, so touching that row rewrote 6.0 s as 5.0 s: a fifth of the row's span, on a
//      value a designer typed. That is the real #427 defect in this bank, and it is fixed by
//      WIDENING the row to 0…10 (the Release row's range) — never by rounding the patch. The
//      #424 lesson, on a different path. No shipped decay exceeds 6.0.
//    · 65 values are off-grid and ALL 65 are COMPUTED: 32 brightnesses and 33 harmonic levels,
//      every one of them from the genre lift. A computed value lands on a finite grid only by
//      luck; demanding otherwise would force rounding into the sound-design code, which changes
//      33 shipped genres by ear-untested amounts. They are excluded from the exactness claim,
//      by SOURCE and FIELD rather than by row — the same two fields are authored literals in
//      the factory bank and the library, and there they must hold exactly.
//    · Every AUTHORED value — all 1260 value/row pairs, 991 hand-written literals plus 269
//      `SynthPatch.init` defaults — is exactly on its row's grid. That is the claim worth
//      having: it is what protects Attack's 0.002…0.008 s and Noise's 0.006/0.008 from being
//      rounded away.
//
//  ⛔ AND THAT SENTENCE READ "all 1261 AUTHORED literals" FOR ONE COMMIT — wrong twice, in the
//  very line that draws the authored/computed border. 1261 is the ON-GRID count (1326 − 65),
//  not the authored count (1326 − 66): the extra one is `Berlin Seq`, whose `bright: 0.40`
//  lifts to exactly 0.43 and lands on the two-decimal grid BY LUCK. Counting it as authored
//  puts a computed value on the authored side of the very border being drawn. And "literals"
//  was wrong a second way: the measurement fills in `SynthPatch.init`'s defaults for every
//  omitted field, so 269 of the 1260 were never written by anybody. Same class as the 496 it
//  replaced — a count is only as true as the sentence describing what was counted.
//
//  ⚠️ WHAT THIS FILE CANNOT DO. It cannot prove the rows RENDER, cannot prove a finger moving
//  across one of them lands where the eye expects (#427's dead-zone figure is simulation), and
//  cannot judge whether 3 decimals is the right feel for an envelope onset. That last one is
//  a listen, and it is on the NEEDS-FOUNDER-VERIFY list rather than asserted here.
//
//  ⚠️ AND IT ONLY EVER SEES PATCHES ECHOEL SHIPS. A patch a USER saved before #430 can hold a
//  fourth decimal (`PatchStore` persists arbitrary `Float`s); that row now DISPLAYS two and
//  rewrites the stored value on first touch. Nothing here measures that, and it is the read-side
//  cousin of the #135/#416/#431 "shows one number, keeps another" condition — accepted as a
//  one-time cost of having a legible grid at all, but stated rather than discovered later.
//

import Foundation
import XCTest
@testable import Echoelmusic

final class SoundRowsCanReachTheShippedPatchesTests: XCTestCase {

    // MARK: - The grid every Sound-panel row offers

    /// One row: its label as rendered, the value it edits, the range it clamps to and the grid
    /// it snaps to. Kept in the SAME order as the panel so a reader can walk the two together.
    private struct Row {
        let label: String
        let range: ClosedRange<Float>
        let decimals: Int
        /// True for the two fields `GenrePatches.patch(...)` COMPUTES rather than takes
        /// verbatim (`GenrePatches.swift:363-364`). Only the genre source is affected; the
        /// same two fields are authored literals in the factory bank and the library.
        let genreLifted: Bool
        let value: (SynthPatch) -> Float

        init(_ label: String, _ range: ClosedRange<Float>, _ decimals: Int,
             genreLifted: Bool = false, _ value: @escaping (SynthPatch) -> Float) {
            self.label = label
            self.range = range
            self.decimals = decimals
            self.genreLifted = genreLifted
            self.value = value
        }
    }

    /// Computed, not a stored `static let`: under Swift 6 language mode a stored static of a
    /// type holding a non-`Sendable` closure is a hard error (SE-0412), and giving the closure
    /// `@Sendable` would be paperwork over a value that is only ever read on one thread here.
    private static var rows: [Row] {
        [
            Row("Brightness",    0...1,      2, genreLifted: true)  { $0.brightness },
            Row("Harmonics",     0...1,      2)                     { $0.harmonicity },
            Row("Harm. level",   0...1,      2, genreLifted: true)  { $0.harmonicLevel },
            Row("Noise",         0...1,      3)                     { $0.noiseLevel },
            Row("Cutoff",        20...18000, 0)                     { $0.filterCutoff },
            Row("Resonance",     0...1,      2)                     { $0.filterResonance },
            Row("LFO→filter",    0...1,      2)                     { $0.lfoToFilterDepth },
            Row("LFO rate",      0...20,     2)                     { $0.filterLFORate },
            Row("LFO depth",     0...1,      2)                     { $0.filterLFODepth },
            Row("Attack",        0...5,      3)                     { $0.attack },
            Row("Decay",         0...10,     2)                     { $0.decay },
            Row("Sustain",       0...1,      2)                     { $0.sustain },
            Row("Release",       0...10,     2)                     { $0.release },
            Row("Reverb mix",    0...1,      2)                     { $0.reverbMix },
            Row("Reverb decay",  0...10,     2)                     { $0.reverbDecay },
            Row("Vibrato rate",  0...12,     2)                     { $0.vibratoRate },
            Row("Vibrato depth", 0...1,      2)                     { $0.vibratoDepth }
        ]
    }

    /// The three sources named separately, because the floor at the bottom of the sweep has to
    /// be able to notice that ONE of them went empty. A single flat count cannot: the factory
    /// bank alone already clears any plausible total.
    private enum Bank: String, CaseIterable {
        case factory = "SynthPatch.factory"
        case library = "PatchLibrary.all"
        case genres  = "MusicStyle.allCases.synthPatch"

        /// Whether values from this bank may be computed rather than authored.
        var isComputed: Bool { self == .genres }

        func patches() -> [SynthPatch] {
            switch self {
            case .factory: return SynthPatch.factory
            case .library: return PatchLibrary.all.map { $0.patch }
            case .genres:  return MusicStyle.allCases.map { $0.synthPatch }
            }
        }
    }

    /// What the row would write if the user nudged it and let go. `EchoelValueField` is generic
    /// over the binding's type, so the round trip goes Float → Double → grid → Float; doing the
    /// comparison in Double alone would hide a conversion that really happens.
    private static func onGrid(_ v: Float, _ row: Row) -> Float {
        Float(ScrubPrecision.snapped(Double(v),
                                     lowerBound: Double(row.range.lowerBound),
                                     upperBound: Double(row.range.upperBound),
                                     decimals: row.decimals))
    }

    // MARK: - Claim 1 — nothing Echoel ships is outside the row that edits it

    /// `snapped` CLAMPS before it rounds, so a value beyond the row's range is not merely
    /// imprecise on first touch — it is moved by the whole overshoot. `Drone Bed`'s 6.0 s decay
    /// against a 0…5 row was exactly that, and widening the row (not rounding the patch) is what
    /// closed it. This test is the thing that says so if a future patch reaches past a row again.
    func testEveryShippedValueIsInsideItsOwnRow() {
        for bank in Bank.allCases {
            for patch in bank.patches() {
                for row in Self.rows {
                    let v = row.value(patch)
                    guard v.isFinite else {
                        XCTFail("\(bank.rawValue) — \(patch.name): \(row.label) is not finite.")
                        continue
                    }
                    XCTAssertTrue(row.range.contains(v), """
                        \(bank.rawValue) — "\(patch.name)": \(row.label) ships \(v), outside the \
                        row's \(row.range.lowerBound)…\(row.range.upperBound). The row clamps \
                        before it rounds, so opening the Sound panel and touching this row \
                        would rewrite the shipped value to the nearest bound. Widen the row — \
                        rounding the patch to fit a control is the #424 mistake.
                        """)
                }
            }
        }
    }

    // MARK: - Claim 2 — every AUTHORED value survives its row bit-for-bit

    /// THE REGRESSION — but read what it is a regression IN. The `rows` table below is this
    /// file's MODEL of the panel; nothing in Swift binds it to the `param(...)`/`knob(...)` call
    /// sites. So this test goes red when the DATA moves under a fixed grid (a new patch authored
    /// with a value its row cannot hold) and when the table alone is coarsened — not when someone
    /// edits `EchoelStudioView.swift`. `testEveryRowStatesItsOwnGridInTheSource` is the half that
    /// covers the panel, and the two together are what make "tidying Attack down to 2 decimals"
    /// impossible to land quietly. Neither half is sufficient alone, which is why both exist.
    ///
    /// ⛔ This doc said "goes red if someone tidies Attack down to 2 decimals" and stopped there,
    /// which was false for the realistic edit. A test that models a surface must say so, or the
    /// next reader trusts a coupling that is not in the language.
    ///
    /// The two genre-lifted fields are excluded ON THE GENRE SOURCE ONLY — the same two fields
    /// are authored literals in the factory bank and the library, and there they must hold
    /// exactly. Their computed drift is measured in the header, not asserted here (see the ⛔
    /// note below for why the assertion that used to live there could not fail).
    func testEveryAuthoredValueIsExactlyOnItsRowsGrid() {
        var checkedPerBank: [Bank: Int] = [:]
        for bank in Bank.allCases {
            for patch in bank.patches() {
                for row in Self.rows where !(bank.isComputed && row.genreLifted) {
                    let v = row.value(patch)
                    guard v.isFinite else { continue }
                    checkedPerBank[bank, default: 0] += 1
                    let snapped = Self.onGrid(v, row)
                    XCTAssertEqual(snapped, v, """
                        \(bank.rawValue) — "\(patch.name)": the \(row.label) row offers \
                        \(row.decimals) decimal(s), so touching it would rewrite the authored \
                        \(v) as \(snapped). Either the patch value or the row's grid is wrong; \
                        a control that cannot reach the product's own values is #427.
                        """)
                }
            }
        }
        // Per-bank, not a single total: `SynthPatch.factory` alone supplies 340 pairs, so a flat
        // floor would stay green with the library and every genre gone.
        for bank in Bank.allCases {
            XCTAssertGreaterThan(checkedPerBank[bank, default: 0], 0, """
                \(bank.rawValue) contributed no values at all, so every assertion above was \
                vacuous for it. Either the bank emptied or this test lost its way to it.
                """)
        }
    }

    // ⛔ THERE WAS A CLAIM 3 HERE FOR ONE COMMIT, AND IT COULD NOT FAIL.
    //
    // `testTheGenreLiftedFieldsRoundByAtMostHalfAGridStep` asserted that the two computed fields
    // move by at most half a grid step, and its doc named two things it guarded. Both were void:
    //
    //   · "a row's grid getting coarser" — the bound was `0.5 * 10^-decimals` and the rounding
    //     used the SAME `decimals`. Both sides scale together, so coarsening can never trip it.
    //   · "a lift big enough to leave the range" — the lift is `min(1, x + k·(1-x))`, which for
    //     x ∈ [0,1] returns a value in [x, 1]. It cannot leave a 0…1 row by construction, and if
    //     it somehow did, claim 1 already covers those exact rows with a better message.
    //
    // So it was a strictly weaker duplicate of claim 1 — the #367 class this file's own scan
    // section warns about. Worse, the ONE way it could ever go red was floating point: the bound
    // is `Float(0.005)` = 0.004999999888 and the measured worst drift is 0.004999995232, a margin
    // of 4.7e-9 against a representation error that already reaches ~3e-8. The only reachable
    // failure was a spurious one. Deleted rather than weakened; the measured drift is recorded in
    // the header, where a number that nothing can check belongs.

    // MARK: - Why two rows are finer than the rest

    /// THE TWO ROWS THAT ARE DELIBERATELY FINER — pinned so the reason cannot be lost.
    ///
    /// Without this, a later cycle reads fourteen rows on 2, two on 3 and one on 0, calls it an
    /// inconsistency, and "fixes" it. Each half asserts BOTH directions: the value exists, AND
    /// it is genuinely unreachable one decimal coarser. The second half is the whole argument,
    /// so it is an assertion and not a comment.
    func testTheFinerGridsAreEarnedByRealValues() throws {
        let all = Bank.allCases.flatMap { $0.patches() }

        for label in ["Attack", "Noise"] {
            let row = try XCTUnwrap(Self.rows.first { $0.label == label }, """
                The \(label) row is gone from this file's model of the panel. Retarget the test \
                rather than deleting it.
                """)
            XCTAssertEqual(row.decimals, 3, "\(label) is no longer the fine row this describes.")

            // One step coarser — read from the row itself, so the bounds cannot drift apart
            // from the ones claim 2 uses (the #416 double-definition defect).
            let coarser = { (v: Float) -> Float in
                Float(ScrubPrecision.snapped(Double(v),
                                             lowerBound: Double(row.range.lowerBound),
                                             upperBound: Double(row.range.upperBound),
                                             decimals: row.decimals - 1))
            }

            let fine = all.map(row.value).filter { $0 > 0 && coarser($0) != $0 }
            XCTAssertFalse(fine.isEmpty, """
                No shipped patch has a \(label) value that a \(row.decimals - 1)-decimal grid \
                would move, so the row's extra decimal is no longer earned by the data. \
                Re-decide it on purpose rather than leaving an unexplained exception. \
                (At #430 the evidence was Attack 0.002/0.003/0.004/0.005/0.008 s — four of \
                them collapsing to zero — and Noise 0.006 and 0.008, which a 2-decimal grid \
                maps onto the same 0.01.)
                """)
        }
    }

    /// THE CUTOFF ROW IS COARSER THAN THE DEFAULT, AND THAT IS THE POINT.
    ///
    /// A whole-Hz grid is only defensible if the bank really is whole-Hz. Measured at #430: all
    /// 44 distinct shipped cutoffs are integers (160…8000).
    func testTheCutoffBankIsWholeHertz() {
        let cutoffs = Set(Bank.allCases.flatMap { $0.patches() }.map { $0.filterCutoff })
        XCTAssertFalse(cutoffs.isEmpty, "No shipped cutoffs found — the sweep found nothing.")
        for c in cutoffs {
            XCTAssertEqual(c.rounded(), c, """
                A shipped filterCutoff of \(c) Hz is not a whole number, but the Cutoff row \
                snaps to 1 Hz. Either give the row a decimal or round the patch.
                """)
        }
    }

    // MARK: - The wiring (source scan)

    /// `param` AND `knob` MUST NOT RE-ACQUIRE A DEFAULT.
    ///
    /// The compiler already forces every call site to state `decimals:` — but only for as long
    /// as the parameter has no default. Re-adding `= 2` would silently restore exactly the
    /// failure this slice removed: an argument nobody writes, so no diff ever shows it, and the
    /// two rows that need 3 quietly become 2. That is the whole mechanism by which seventeen
    /// rows sat on 4 for a month, so the ABSENCE of a default is the thing worth pinning.
    ///
    /// ⚠️ A scan, not a behaviour — it cannot fail for the right reason if the helpers are
    /// renamed. It anchors on the declarations existing FIRST (the #367 trap: a scan that only
    /// forbids a shape is green on a file that lost both shapes).
    func testTheSoundRowHelpersTakeADecimalsArgumentWithNoDefault() throws {
        let url = try repoRoot()
            .appendingPathComponent("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        let text = try String(contentsOf: url, encoding: .utf8)

        for helper in ["param", "knob"] {
            let decl = "private func \(helper)(_ label: String, _ value: Binding<Float>,"
            XCTAssertTrue(text.contains(decl), """
                `\(helper)` no longer has the declaration this guard describes. If the Sound \
                panel's row helper was renamed or removed, retarget this test — do not delete \
                it, the defaulted-argument trap it guards is not specific to the name.
                """)
        }

        XCTAssertTrue(text.contains("decimals: Int) -> some View {"), """
            Neither Sound-panel row helper declares a plain `decimals: Int` any more.
            """)
        XCTAssertFalse(text.contains("decimals: Int = "), """
            A Sound-panel row helper gave `decimals` a DEFAULT again. That is the exact shape \
            of the #430 defect: seventeen rows inherited `EchoelValueField`'s `decimals: 4` \
            because no call site ever had to write the argument, so no review ever saw it. \
            Keep it required and let each row state its own grid.
            """)
    }

    /// THE FOUR ROWS WHOSE NUMBERS ARE NOT THE HOUSE DEFAULT — pinned in the SOURCE, not just in
    /// this file's table.
    ///
    /// Without this the model above can drift from the panel with every test green: coarsen
    /// Attack to 2 in `EchoelStudioView.swift` and nothing here notices, because `rows` is a hand
    /// copy. That is the same gap #427's sibling guard closed with a per-row scan, and the
    /// precedent is why this is a scan and not an argument.
    ///
    /// Only the four rows that DEVIATE are pinned, and deliberately so: asserting all seventeen
    /// would make every ordinary panel edit red for no reason, which is how a guard gets deleted.
    /// Three deviate in `decimals` (each earned by shipped data, see the header) and one in
    /// RANGE — Decay's 0…10 is what makes `Drone Bed`'s 6.0 s reachable, so narrowing it back is
    /// the defect returning, not a style change.
    ///
    /// ⚠️ A scan: it pins the literal text of four call sites and can go red for a harmless
    /// reformat. That is the trade — a false red here costs one edit, a silent drift costs the
    /// two grids the whole slice exists for.
    func testEveryRowStatesItsOwnGridInTheSource() throws {
        let url = try repoRoot()
            .appendingPathComponent("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        let text = try String(contentsOf: url, encoding: .utf8)

        // ⛔ THE RANGE HALF OF THESE PINS MOVED WITH #441 AND THE `why` COLUMN HAD TO MOVE WITH
        // IT. The rows no longer spell a range literal — they read `SynthPatch.Bounds.<field>`,
        // the same constants `SoundPrompt.clamp` uses, because three spellings of one range is
        // what let the prompt cut a value the row could reach. Decay's reason therefore no longer
        // lives at this call site at all; what protects `Drone Bed`'s 6.0 s now is
        // `SynthPatch.Bounds.decay` plus `testEveryShippedValueIsInsideItsOwnRow` above, whose
        // model table stays HAND-WRITTEN on purpose (a guard that reads the constant it guards
        // cannot catch a wrong constant). So this test keeps pinning `decimals` — the thing that
        // is still written here — and pins the BINDING to the shared constant instead of a
        // number. Leaving the old literals in place would have been the easier edit and a lie.
        let pinned: [(row: String, call: String, why: String)] = [
            ("Noise", #"knob("Noise", $currentPatch.noiseLevel, SynthPatch.Bounds.noiseLevel, decimals: 3)"#,
             "0.006 and 0.008 both map onto 0.01 on a 2-decimal grid"),
            ("Cutoff", #"knob("Cutoff", $currentPatch.filterCutoff, SynthPatch.Bounds.filterCutoff, unit: "Hz", decimals: 0)"#,
             "all 44 shipped cutoffs are whole Hz, and the app's three other cutoff rows say 0"),
            ("Attack", #"param("Attack", $currentPatch.attack, SynthPatch.Bounds.attack, unit: "s", decimals: 3)"#,
             "0.002/0.003/0.004/0.005 s all collapse to 0.00 on a 2-decimal grid"),
            ("Decay", #"param("Decay", $currentPatch.decay, SynthPatch.Bounds.decay, unit: "s", decimals: 2)"#,
             "the row must read the shared bound, not a fourth spelling of 0...10")
        ]

        for pin in pinned {
            XCTAssertTrue(text.contains(pin.call), """
                The Sound panel's \(pin.row) row is no longer written as
                    \(pin.call)
                and that number is not decoration — \(pin.why). If the row moved or was \
                reformatted, retarget this pin in the same commit; if the grid or range really \
                changed, the header's measurement has to change with it.
                """)
        }
    }

    // MARK: - Helpers

    private func repoRoot() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path) { return dir }
            dir = dir.deletingLastPathComponent()
        }
        throw XCTSkip("Repo root not found from \(#filePath) — source scan cannot run.")
    }
}
