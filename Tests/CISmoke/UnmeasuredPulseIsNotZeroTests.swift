// UnmeasuredPulseIsNotZeroTests.swift
// Echoel — a heart that has not been read yet is not a heart at zero. BLOCKING bundle.
//
// ⛔ THE DEFECT, measured on device (log 2476, v10.79.359, build 2476):
//
//     1785362582.450  transport play (generate) tempo=44
//
// 44 is the FLOOR of Contemplation's window (44…66). The founder's one product claim is "your
// body plays it". It played the floor — for the whole ~13 s the camera needs to lock, because the
// settling branch only keeps the running tempo when it is already `>= 50`, and 44 is not.
//
// THE CHAIN, all three links verified against source and executed below in pure code:
//
//   1. Camera rPPG reports `bpm=0` until it locks (same log: `bpm=0 conf=0.00` for six frames)
//      and again whenever it loses lock.
//   2. `EchoelStudioView`'s `fin(_:_:)` substitutes a neutral only for nil or NON-FINITE values.
//      Zero is finite, so it passed through as a measurement — as if the heart had stopped.
//      (`heldCoh`, a few lines above in the same function, already applies the `> 0` rule to
//      coherence, and the comment on the very next line describes exactly this bug for HRV. Heart
//      rate was the one field left unguarded — and the one that sets the tempo.)
//   3. `BioComposer.tempo(for:)` in `.flowFree` computes `hr·(1−calm) + 72·calm`, so a zero heart
//      at zero coherence yields 0, which its own `min(max(·, 40), 160)` lifts to 40.
//      `StudioCalculator.genreTempo(40, into: 44...66)` folds 40 up to 80, finds 80 above the
//      ceiling, and picks the FLOOR because 80 sits proportionally further above 66 than 44 does
//      above 40. Result: exactly 44.
//
// ⚠️ AND THE OBVIOUS SUMMARY IS WRONG, which is why the numbers are computed here instead of
// described. "An unread body makes the music too slow" holds for Contemplation and for NOTHING
// ELSE. The direction is genre-dependent, because the fold's crossover moves with the window:
// on `.selfObservation` (46…78 — the DEFAULT genre) a zero body produced 78, the CEILING, so the
// bug made the default genre too FAST. On `.jazz` and `.oriental` it produced 80 where a resting
// pulse gives 140. My first draft of this file asserted "no genre is entered at its floor" and
// would have failed on Psytrance, where 70 bpm doubles to exactly 140 and the floor IS the honest
// answer. The invariant is not about floors — it is that THE READING MUST MATTER.
//
// AND IT WAS NEVER ONLY THE TEMPO. `BioComposer.musicalState` maps `energy` over 50…120 bpm, so a
// zero clamps to minimum cardiac drive: the composer also built a lower-energy, sparser take for a
// body it had simply not read yet. That half is not asserted here (it is `internal` and covered in
// the non-blocking suite); it is recorded so the fix is not mistaken for a tempo-only change.
//
// WHY BEHAVIOURAL AND NOT A SOURCE SCAN: `tempo(for:)` is `public static` on a pure enum and
// `genreTempo` is pure, so the whole chain runs here. Only the call-site guard needs text, because
// it is a local `func` inside a `private` method on a SwiftUI `View` with no seam.

import Foundation
import XCTest
@testable import Echoelmusic

final class UnmeasuredPulseIsNotZeroTests: XCTestCase {

    /// A body that has never been read. 70 bpm is the resting neutral the call site substitutes.
    private func mapped(hr: Float, _ style: MusicStyle) -> Double {
        StudioCalculator.genreTempo(
            BioComposer.tempo(for: .init(heartRateBPM: hr, coherence: 0,
                                         style: style, mode: .flowFree)),
            into: style.tempoRange)
    }

    // MARK: - The device log, reproduced

    /// ⛔ THE 44, EXACTLY. Reproduced from the two pure functions, so the device evidence and the
    /// code are pinned to each other. If this stops holding, the log no longer explains the code
    /// and this file's rationale must be rewritten — not the number adjusted.
    func testTheDeviceLogsFortyFourIsReproducible() {
        XCTAssertEqual(BioComposer.tempo(for: .init(heartRateBPM: 0, coherence: 0,
                                                    style: .contemplation, mode: .flowFree)),
                       40, accuracy: 0.001,
                       "the mapping's own clamp floor is what a zero heart becomes")
        XCTAssertEqual(mapped(hr: 0, .contemplation), 44, accuracy: 0.001,
                       "device log 2476 read `tempo=44` on Contemplation (44…66) — that is a "
                       + "zero heart rate folded onto the genre floor, not a musical decision")
    }

    /// …and the resting neutral lands at the other end of the same window: 66. A resting body is
    /// at the fast end of a contemplative window, which is the honest answer — the convergence
    /// then walks the tempo down as the real (slower) pulse arrives, continuously, with no jump.
    func testTheRestingNeutralLandsAtTheOppositeEnd() {
        XCTAssertEqual(mapped(hr: 70, .contemplation), 66, accuracy: 0.001)
        XCTAssertEqual(mapped(hr: 70, .contemplation) / mapped(hr: 0, .contemplation),
                       1.5, accuracy: 0.001,
                       "44 → 66 bpm is the audible size of the defect on the genre the founder "
                       + "was actually using — a factor of 1.5, not a nuance")
    }

    /// ⚠️ THE DEFAULT GENRE WENT THE OTHER WAY, and this is the assertion that stops the fix from
    /// being remembered as "it was too slow". On `.selfObservation` (46…78) a zero body produced
    /// the CEILING. Whatever genre you were on, the tempo was decided by a sentinel instead of by
    /// a body — sometimes too slow, sometimes too fast.
    func testOnTheDefaultGenreTheSameBugMadeItTooFast() {
        XCTAssertEqual(mapped(hr: 0, .selfObservation), 78, accuracy: 0.001,
                       "a zero heart hit .selfObservation's CEILING, not its floor")
        XCTAssertEqual(mapped(hr: 70, .selfObservation), 70, accuracy: 0.001,
                       "a resting body lands inside the window at its own pulse")
        XCTAssertGreaterThan(mapped(hr: 0, .selfObservation), mapped(hr: 70, .selfObservation),
                             "the direction of the error is genre-dependent — do not describe "
                             + "this defect as 'the music was too slow'")
    }

    // MARK: - The invariant that actually holds everywhere

    /// THE READING MUST MATTER. For most genres a zero body and a resting body produce different
    /// tempi, which is the whole point; the window still contains the result in every case.
    ///
    /// The bound is a LOWER bound, not an exact count, and deliberately so: SOME windows are
    /// arranged such that both inputs fold to the same tempo (dubTechno, eighties, disco,
    /// synthwave, stillMeditation, punk, rocksteady, and since #254 batch 2 also deepDrone,
    /// whose 40…58 window maps both a zero body and a resting 70 to its 40 floor — verified, not
    /// guessed). No totals are quoted: they moved twice in one day as genres were added, and the
    /// lower bound is the claim that matters. On those the fix is a no-op, which is correct rather than a miss. Pinning an
    /// exact count would redden this gate the first time a genre is re-voiced for musical reasons.
    func testTheReadingMattersForMostGenresAndTheWindowAlwaysHolds() {
        var differ = 0
        for style in MusicStyle.allCases {
            let zero = mapped(hr: 0, style)
            let rest = mapped(hr: 70, style)
            XCTAssertTrue(style.tempoRange.contains(zero),
                          "\(style): \(zero) escaped \(style.tempoRange)")
            XCTAssertTrue(style.tempoRange.contains(rest),
                          "\(style): \(rest) escaped \(style.tempoRange)")
            if abs(zero - rest) > 0.001 { differ += 1 }
        }
        XCTAssertGreaterThanOrEqual(differ, 15,
                                    "only \(differ) of \(MusicStyle.allCases.count) genres "
                                    + "distinguish an unread body from a resting one. Either the "
                                    + "fold or the windows changed shape — check whether the "
                                    + "sentinel still matters at all before relaxing this.")
    }

    // MARK: - The zero can no longer be built

    /// ⛔ THE GUARD ON THE FIX ITSELF. The tests above prove what a zero DOES; this one proves a
    /// zero can no longer reach the composer. Source text because the guard is a local `func`
    /// inside a `private` method on a SwiftUI `View` — no seam, no local toolchain.
    func testTheHeartRateInputCannotBeAnUnmeasuredZero() throws {
        let text = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        let squashed = text.components(separatedBy: .whitespacesAndNewlines).joined()

        XCTAssertTrue(squashed.contains("guardletv,v.isFinite,v>0else{returnnil}"),
                      "the `measured(_:)` guard no longer rejects a finite zero, so an unlocked "
                      + "rPPG's `bpm=0` reaches the composer as a measurement again (#236).")

        // …and the heart-rate field actually USES it. A guard nobody calls is the shape this
        // defect already had: `fin` existed, `heldCoh` existed, and the one field that mattered
        // went through neither.
        let lines = text.components(separatedBy: .newlines)
        guard let hrLine = lines.first(where: { $0.contains("heartRateBPM: fin(") }) else {
            return XCTFail("the composer's `heartRateBPM:` argument was renamed or restructured — "
                           + "re-point this guard rather than deleting it")
        }
        XCTAssertTrue(hrLine.contains("measured("),
                      "the composer's heart rate is built without the zero guard: "
                      + hrLine.trimmingCharacters(in: .whitespaces))
    }

    /// Guards the PREMISE: `fin` must still be the non-finite guard ONLY. If it ever starts
    /// rejecting zero itself, `measured` is redundant and this file's story is wrong — better to
    /// fail loudly than to keep a stale explanation alive beside working code.
    func testFinStillOnlyGuardsNonFinite() throws {
        let squashed = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
            .components(separatedBy: .whitespacesAndNewlines).joined()
        XCTAssertTrue(squashed.contains("guardletv,v.isFiniteelse{returnd}"),
                      "`fin(_:_:)` changed shape. That may be an improvement, but this whole file "
                      + "explains the defect as 'zero is finite, so `fin` waved it through' — "
                      + "reconcile the two rather than leaving one of them lying.")
    }

    // MARK: - Reading the source

    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // CISmoke
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo
        guard FileManager.default.fileExists(atPath:
                root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("source tree not present — this test inspects source text, so it "
                          + "SKIPS rather than reporting a green it did not earn")
        }
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
