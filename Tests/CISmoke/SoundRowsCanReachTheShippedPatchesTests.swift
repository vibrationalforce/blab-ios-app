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
//  ⭐ WHAT THE HONEST MEASUREMENT FOUND, and why this guard is THREE claims and not one:
//    · ONE authored value was outside its row's RANGE — `Drone Bed`'s `d: 6.0`
//      (`GenrePatches.swift:145`) against a Decay row of 0…5. `snapped` clamps before it
//      rounds, so touching that row rewrote 6.0 s as 5.0 s: a fifth of the row's span, on a
//      value a designer typed. That is the real #427 defect in this bank, and it is fixed by
//      WIDENING the row to 0…10 (the Release row's range) — never by rounding the patch. The
//      #424 lesson, on a different path. No shipped decay exceeds 6.0.
//    · 65 values are off-grid and ALL 65 are COMPUTED: 32 brightnesses and 33 harmonic levels,
//      every one of them from the genre lift. A computed value lands on a finite grid only by
//      luck; demanding otherwise would force rounding into the sound-design code, which changes
//      33 shipped genres by ear-untested amounts. They are allowed to round, and claim 3 BOUNDS
//      the rounding instead (measured worst case 0.005 — half a grid step, ~0.5 % of a 0…1
//      timbre control).
//    · Every AUTHORED literal — all 1261 of them — is exactly on its row's grid. That is the
//      claim worth having: it is what protects Attack's 0.002…0.008 s and Noise's 0.006/0.008
//      from being rounded away.
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

    /// THE REGRESSION. This is what goes red if someone "tidies" Attack or Noise down to 2
    /// decimals: those two rows are the only reason this test is not a one-liner, and the four
    /// sub-centisecond onsets plus the two noise floors are the evidence.
    ///
    /// The two genre-lifted fields are excluded ON THE GENRE SOURCE ONLY, and claim 3 covers
    /// them instead. Excluding a whole row would be too coarse — the same two fields are
    /// authored literals in the factory bank and the library, and there they must hold exactly.
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

    // MARK: - Claim 3 — the computed fields may round, but only by half a step

    /// The genre lift (`GenrePatches.swift:363-364`) is arithmetic on an authored number, so it
    /// lands on a two-decimal grid only by luck — 65 of the 66 genre values do not. Forcing them
    /// on-grid would mean rounding inside the sound-design code, changing 33 shipped genres by
    /// amounts nobody has heard. So they are allowed to round, and this bounds the rounding.
    ///
    /// Half a grid step is the arithmetic maximum of rounding to that grid, so this is not a
    /// threshold picked to let the current numbers through (#404 slice 2's mistake) — it is the
    /// definition. What it actually guards is the two ways that stops being true: a row's grid
    /// getting coarser, or a lift big enough to push a value out of range where the clamp, not
    /// the rounding, decides.
    func testTheGenreLiftedFieldsRoundByAtMostHalfAGridStep() {
        var seen = 0
        for row in Self.rows where row.genreLifted {
            let halfStep = Float(0.5 * pow(10.0, -Double(row.decimals)))
            for patch in Bank.genres.patches() {
                let v = row.value(patch)
                guard v.isFinite else { continue }
                seen += 1
                let drift = abs(Self.onGrid(v, row) - v)
                XCTAssertLessThanOrEqual(drift, halfStep, """
                    Genre "\(patch.name)": \(row.label) is \(v) and the row would write \
                    \(Self.onGrid(v, row)) — a move of \(drift), more than the \(halfStep) that \
                    rounding alone can cost. That means the value left the row's range and was \
                    CLAMPED. Widen the row; do not round the lift.
                    """)
            }
        }
        XCTAssertGreaterThan(seen, 0, """
            No genre-lifted values were examined, so this claim proved nothing. If the lift in \
            GenrePatches.patch(...) is gone, drop the `genreLifted` exemption from claim 2 \
            instead of leaving an empty test standing in for it.
            """)
    }

    // MARK: - Why two rows are finer than the rest

    /// THE TWO ROWS THAT ARE DELIBERATELY FINER — pinned so the reason cannot be lost.
    ///
    /// Without this, a later cycle reads fifteen rows on 2 and two on 3, calls it an
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
