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
//    · `attack`     — `PatchLibrary` and `SynthPatch.factory` ship 0.003 / 0.004 / 0.005 /
//                     0.008 s. A centisecond grid would round four factory onsets, one of them
//                     to zero. → 3 decimals (millisecond).
//    · `noiseLevel` — `SynthPatch.swift:424` ships 0.006. Same defect, one field over.
//                     → 3 decimals.
//
//  And one row must be COARSER: `filterCutoff` spans 20…18000 Hz and every one of the shipped
//  values is a whole number, so 0 decimals — which is what the app's three OTHER cutoff rows
//  already say (`EchoelFXView:480`, `EchoelStudioView:2475` and `:2503`). A row that reads
//  "2400.0000 Hz" is not more precise, it is less legible.
//
//  ⚠️ WHAT THIS FILE CANNOT DO. It cannot prove the rows RENDER, cannot prove a finger moving
//  across one of them lands where the eye expects (#427's dead-zone measurement is simulation),
//  and cannot judge whether 3 decimals is the right feel for an envelope onset. It proves the
//  narrow, checkable thing: no value Echoel SHIPS is off the grid the row that edits it offers.
//  That is the #427 law — a control must be able to reach the values the product already
//  contains — applied to the patch bank instead of the visual presets.
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
        let value: (SynthPatch) -> Float
    }

    private static let rows: [Row] = [
        Row(label: "Brightness",    range: 0...1,        decimals: 2) { $0.brightness },
        Row(label: "Harmonics",     range: 0...1,        decimals: 2) { $0.harmonicity },
        Row(label: "Harm. level",   range: 0...1,        decimals: 2) { $0.harmonicLevel },
        Row(label: "Noise",         range: 0...1,        decimals: 3) { $0.noiseLevel },
        Row(label: "Cutoff",        range: 20...18000,   decimals: 0) { $0.filterCutoff },
        Row(label: "Resonance",     range: 0...1,        decimals: 2) { $0.filterResonance },
        Row(label: "LFO→filter",    range: 0...1,        decimals: 2) { $0.lfoToFilterDepth },
        Row(label: "LFO rate",      range: 0...20,       decimals: 2) { $0.filterLFORate },
        Row(label: "LFO depth",     range: 0...1,        decimals: 2) { $0.filterLFODepth },
        Row(label: "Attack",        range: 0...5,        decimals: 3) { $0.attack },
        Row(label: "Decay",         range: 0...5,        decimals: 2) { $0.decay },
        Row(label: "Sustain",       range: 0...1,        decimals: 2) { $0.sustain },
        Row(label: "Release",       range: 0...10,       decimals: 2) { $0.release },
        Row(label: "Reverb mix",    range: 0...1,        decimals: 2) { $0.reverbMix },
        Row(label: "Reverb decay",  range: 0...10,       decimals: 2) { $0.reverbDecay },
        Row(label: "Vibrato rate",  range: 0...12,       decimals: 2) { $0.vibratoRate },
        Row(label: "Vibrato depth", range: 0...1,        decimals: 2) { $0.vibratoDepth }
    ]

    /// Everything the user can LOAD into those rows: the factory bank, the categorised library
    /// and the per-genre timbre that "Genre default" installs. All three land in `currentPatch`.
    private static func shippedPatches() -> [(source: String, patch: SynthPatch)] {
        // Built with explicit labels throughout: tuple labels are part of the type, so an
        // unlabeled `[(String, SynthPatch)]` does not silently become the labeled array here.
        var out: [(source: String, patch: SynthPatch)] = []
        for p in SynthPatch.factory {
            out.append((source: "SynthPatch.factory", patch: p))
        }
        for lp in PatchLibrary.all {
            out.append((source: "PatchLibrary.all", patch: lp.patch))
        }
        for style in MusicStyle.allCases {
            out.append((source: "MusicStyle.\(style).synthPatch", patch: style.synthPatch))
        }
        return out
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

    // MARK: - The measurement

    /// THE REGRESSION. Every value Echoel ships must survive its own row untouched.
    ///
    /// This is what goes red if someone "tidies" Attack or Noise down to 2 decimals: those two
    /// rows are the only reason this test is not a one-liner, and the four factory onsets plus
    /// the one factory noise floor are the evidence. It also goes red if a new patch is authored
    /// with a value the row cannot hold — which is the cheaper direction to find it.
    func testEveryShippedValueSurvivesItsOwnRow() {
        var checked = 0
        for (source, patch) in Self.shippedPatches() {
            for row in Self.rows {
                let v = row.value(patch)
                guard v.isFinite else {
                    XCTFail("\(source) — \(patch.name): \(row.label) is not finite (\(v)).")
                    continue
                }
                checked += 1
                let snapped = Self.onGrid(v, row)
                XCTAssertEqual(snapped, v, """
                    \(source) — "\(patch.name)": the \(row.label) row offers \
                    \(row.decimals) decimal(s) over \(row.range.lowerBound)…\
                    \(row.range.upperBound), so touching it would rewrite the shipped \(v) \
                    as \(snapped). Either the patch value or the row's grid is wrong; a \
                    control that cannot reach the product's own values is the #427 defect.
                    """)
            }
        }
        // A patch bank that shrank to nothing would make every assertion above vacuous.
        XCTAssertGreaterThanOrEqual(checked, 17 * 20, """
            Only \(checked) value/row pairs were checked. The three shipped sources \
            (SynthPatch.factory, PatchLibrary.all, MusicStyle.allCases) should supply far \
            more than twenty patches between them; if the bank really shrank, lower this \
            floor deliberately rather than letting the sweep pass over almost nothing.
            """)
    }

    /// THE TWO ROWS THAT ARE DELIBERATELY FINER — pinned so the reason cannot be lost.
    ///
    /// Without this, a later cycle reads seventeen rows on 2 and two on 3, calls it an
    /// inconsistency, and "fixes" it. The values below are the ones that make 3 necessary; if
    /// they ever leave the bank, this test says so and the decision can be revisited on purpose.
    func testTheFinerGridsAreEarnedByRealValues() {
        let all = Self.shippedPatches().map(\.patch)

        let subCentisecondAttacks = all.map(\.attack).filter { $0 > 0 && $0 < 0.01 }
        XCTAssertFalse(subCentisecondAttacks.isEmpty, """
            No shipped patch has an attack below 0.01 s any more, so the Attack row's third \
            decimal is no longer earned by the data. Re-decide it rather than leaving an \
            unexplained exception.
            """)

        let subCentisecondNoise = all.map(\.noiseLevel).filter { $0 > 0 && $0 < 0.01 }
        XCTAssertFalse(subCentisecondNoise.isEmpty, """
            No shipped patch has a noise level below 0.01 any more (it was 0.006 in \
            SynthPatch.factory at #430). The Noise row's third decimal is no longer earned.
            """)

        // And the counterweight: those same values are UNREACHABLE on a 2-decimal grid. Stated
        // as an assertion rather than as a comment, because this is the whole argument.
        for a in subCentisecondAttacks {
            let coarse = Float(ScrubPrecision.snapped(Double(a), lowerBound: 0,
                                                      upperBound: 5, decimals: 2))
            XCTAssertNotEqual(coarse, a, """
                Attack \(a) survives a 2-decimal grid, so it is not evidence for the third \
                decimal. Find the value that is, or drop the exception.
                """)
        }
    }

    /// THE CUTOFF ROW IS COARSER THAN THE DEFAULT, AND THAT IS THE POINT.
    ///
    /// A whole-Hz grid is only defensible if the bank really is whole-Hz. Measured at #430: all
    /// 29 distinct shipped cutoffs are integers (160…8000).
    func testTheCutoffBankIsWholeHertz() {
        let cutoffs = Set(Self.shippedPatches().map { $0.patch.filterCutoff })
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
    /// rows sat on 4 for a month, so the absence of a default is the thing worth pinning.
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
