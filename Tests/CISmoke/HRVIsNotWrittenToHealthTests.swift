// HRVIsNotWrittenToHealthTests.swift
// Echoel — #463. A correct decision was defended with a refutable reason.
//
// ⭐ THE DEFECT WAS PROSE, NOT BEHAVIOUR. Echoel does not write HRV to Apple Health, and that
// is right. But the REASON written next to the decision was refutable, in two files at once —
// and the two failed DIFFERENTLY, which is the part worth keeping. `HealthKitWriter`'s header
// said "we don't have real SDNN ms": flatly false. `HealthWritePolicy` said "our
// `hrvNormalized` is a 0…1 control value, not SDNN in ms": literally TRUE, and misleading only
// by implicature — it named the one HRV field that is NOT in milliseconds and let a reader
// conclude there was no other. "Both were false" is the flattering version; a true sentence
// standing in for a reason is the harder one to catch, because nothing contradicts it.
// Three producers of a MEASURED value write real SDNN in milliseconds into
// `BioSampleFrame.hrvSDNNms` — camera, Polar strap, HealthKit's native — and Apple's own
// quantity type is literally `heartRateVariabilitySDNN` in ms. (⚠️ "Three" counts MEASURED
// producers. `git grep -n "hrvSDNNms:" -- Sources` returns FIVE construction sites: the other
// two are `BioSimulator`, which derives a synthetic value from its own walk (#464), and the
// camera's dropout hold-repeat, which forwards `held.hrvSDNNms`. Written out because a bare
// "three" beside a grep that says five is the enumeration defect #461 retracted twice.)
// CLAUDE.md names this class: a "do NOT do X" note with a
// refutable reason is worse than no note, because the next session refutes the reason and then
// does X. The danger is one-way and concrete — a camera-derived number in a health record.
//
// ⭐ WHAT THIS FILE IS FOR. The prose is now correct (the real reason: SDNN is an INTERVAL
// statistic stamped `start == end` by `HealthKitWriter.write`, and our two producers do not
// compute the same quantity — different window LENGTH, a strap window that is beat-counted
// rather than timed, and different ESTIMATORS, `sdnn(rrMs:)` flat vs `sdnn(segments:)`
// excluding isolated beats; #458). Prose does not go red. These claims do.
//
// ⛔ HONEST GRADING, BECAUSE THE FLATTERING VERSION IS AVAILABLE AND WRONG: **NONE of the five
// tests below is a regression.** Every one of them is green on the pre-#463 tree too — SDNN
// already existed (that is precisely why the old comment was false), and the write path already
// omitted HRV. This slice corrects prose and installs FORWARD guards; it fixes no runtime
// behaviour and pretending otherwise would be the #433 defect. What the guards buy is that the
// next attempt to act on the retracted reasoning goes red instead of shipping.
//
// ⚠️ WHAT THESE TESTS CANNOT DO.
//   · They never call HealthKit. `HealthKitWriter` lives inside `#if canImport(HealthKit)` and
//     needs a device to prove anything about a stored sample. The write-path claims here are
//     SOURCE SCANS, and a scan can only assert the shape somebody already chose.
//   · They cannot show that adding HRV would be WRONG for a user. That argument is in
//     `HealthWritePolicy` rule 2 and rests on the window-length dependence of SDNN; its
//     DIRECTION is structural (a 10 s window cannot hold an oscillation slower than 0.1 Hz),
//     its MAGNITUDE is unmeasured in this repo and no number here implies one.
//   · `testTheWrittenValuesAreStillAPairOfPhysicalReadings` is a COMPILE-time pin wearing a
//     test's clothes: it fails by not building, not by asserting. Said out loud so nobody reads
//     its green as a runtime fact.
//
// ⭐ THE COUNTERWEIGHT IS THE HALF THAT MATTERS. A bare "the HRV identifier is absent" scan is
// also green on a file that lost its whole write path — the #343 trap. So the same scan pins
// that the two types we DO write are still requested, and a separate claim pins that real SDNN
// still exists at all: if a later slice deleted `HRVMetrics.sdnn`, the retracted comment would
// become TRUE again and the new one false, and this file would be the only thing that noticed.
//
// ⚠️ `SourceText.codeOnly` is LOAD-BEARING here, not prophylaxis (#453): the corrected
// `HealthKitWriter` header names `heartRateVariabilitySDNN` in prose on purpose — it is the
// signpost for the next session — so a raw-text scan for that identifier would fail on correct
// code.

import Foundation
import XCTest
@testable import Echoelmusic

final class HRVIsNotWrittenToHealthTests: XCTestCase {

    // MARK: - The decision, pinned where a future session would undo it

    /// The authorization request must not ask to SHARE an HRV type, and the writer must not
    /// build an HRV sample. Pinned on the exact identifier Apple uses.
    func testNoHRVTypeIsRequestedOrWritten() throws {
        let code = try writerSource()
        XCTAssertFalse(code.contains("heartRateVariabilitySDNN"), """
            HealthKitWriter names `heartRateVariabilitySDNN` in CODE (not prose). Echoel \
            deliberately does not contribute to Apple Health's HRV series — the reason is \
            HealthWritePolicy rule 2, and it is about SDNN being an interval statistic our \
            writer stamps as instantaneous, computed over two different windows (#458). If \
            that decision is being reversed on purpose, change rule 2 and this test in the \
            same commit; do not delete the check.
            """)
    }

    /// COUNTERWEIGHT to the claim above: a negative scan is also green on a file that lost its
    /// write path entirely. Pin what we DO write, and pin it as the whole `toShare:` list so a
    /// third element cannot slip in beside the two.
    ///
    /// ⚠️ THE LIST PIN ALONE IS NOT ENOUGH, and saying otherwise would overstate it: the needle
    /// ends in `]`, so a third element INSIDE this array breaks it — but a SECOND
    /// `requestAuthorization(toShare:)` call elsewhere in the file leaves it green. The claims
    /// are jointly load-bearing: this one pins the shape of the call we have,
    /// `testNoHRVTypeIsRequestedOrWritten` catches the HRV type wherever it appears.
    ///
    /// ⚠️ AND THE TWO TYPE NEEDLES ARE NOT UNIQUE TO THE WRITE PATH — they appear once in
    /// `requestAuthorization` and again in `write(_:)`, so deleting the whole sample-building
    /// half would leave both green: exactly the #343 hole this test exists to close, reopened
    /// one level down. The last two assertions anchor on tokens that occur ONLY inside
    /// `write(_:)`.
    func testTheTwoTypesWeDoWriteAreStillRequested() throws {
        let code = try writerSource()
        XCTAssertTrue(code.contains("quantityType(forIdentifier: .heartRate)"),
                      "the heart-rate write disappeared — the HRV scan above is then vacuous")
        XCTAssertTrue(code.contains("quantityType(forIdentifier: .respiratoryRate)"),
                      "the respiratory-rate write disappeared — #426 exists for that value")
        XCTAssertTrue(code.contains("toShare: [hr, resp]"), """
            the authorization request is no longer exactly the two physical readings. Adding a \
            third share type is the move rule 2 argues against; removing one silently drops a \
            measurement the user opted in to.
            """)
        XCTAssertTrue(code.contains("HealthWritePolicy.values(for: frame)"), """
            the writer no longer asks the pure policy layer what to write. Rule 2 is enforced \
            in `values(for:)`; a writer that builds its own quantities has routed around it.
            """)
        XCTAssertTrue(code.contains("store.save(samples)"), """
            nothing is saved any more — the two type scans above are then green over a writer \
            that authorizes and writes nothing, which is the #343 shape of a vacuous guard.
            """)
    }

    /// The pure decision layer hands back exactly two physical readings. This is a COMPILE-time
    /// pin: a third tuple component stops this file building, which is the point — the shape is
    /// the decision.
    func testTheWrittenValuesAreStillAPairOfPhysicalReadings() {
        // The first eight arguments have NO defaults — `breathPhase` and `motionEnergy` are not
        // optional here, and omitting them is the exact mistake #403 Slice 3 paid for.
        let frame = BioSampleFrame(timestamp: 1, heartRateBPM: 62, hrvNormalized: 0.5,
                                   breathRate: 12, breathPhase: 0, coherence: 0.4,
                                   motionEnergy: 0, source: .cameraPPG)
        let values: (heartRate: Double, respiratoryRate: Double?) = HealthWritePolicy.values(for: frame)
        XCTAssertEqual(values.heartRate, 62, accuracy: 1e-9)
        XCTAssertEqual(values.respiratoryRate ?? -1, 12, accuracy: 1e-9)
    }

    // MARK: - The retracted premise, pinned so it cannot quietly become true again

    /// "We don't have real SDNN ms" was false. Both producers compute a real millisecond spread;
    /// if either were deleted, the retracted comment would become true and the corrected one
    /// false. Same series through both entry points, so the numbers are comparable.
    func testRealSDNNInMillisecondsExists() {
        let rr: [Double] = [820, 860, 800, 880, 840, 900, 810, 870]
        let flat = HRVMetrics.sdnn(rrMs: rr)
        let pooled = HRVMetrics.sdnn(segments: [rr])
        XCTAssertGreaterThan(flat, 0, """
            HRVMetrics.sdnn(rrMs:) no longer produces a millisecond spread. HealthWritePolicy \
            rule 2 retracts "we don't have real SDNN ms" on the strength of this — if SDNN is \
            really gone, rule 2's ⛔ block has to be rewritten, not left standing.
            """)
        // ⚠️ HONEST ABOUT WHAT THIS SECOND ASSERTION IS: `sdnn(segments:)` is literally
        // `sdnn(rrMs: segments.filter { $0.count >= 2 }.flatMap { $0 })`, so for ONE un-gapped
        // segment the filter and flatMap are the identity and the two agree BIT-FOR-BIT, not
        // within a tolerance. It is a premise test that the delegation still exists — it cannot
        // see a change to the multi-segment arithmetic, which is what #425 actually cares about.
        XCTAssertEqual(pooled, flat, accuracy: 1e-9, """
            one un-gapped segment no longer delegates to the flat reading. That delegation is \
            the ONLY thing this assertion sees — it is deliberately blind to the difference \
            #458 is actually about, which shows up only when a segment list has GAPS: the \
            camera publishes `sdnn(rrMs:)` flat, the strap publishes `sdnn(segments:)`, which \
            excludes isolated beats. Do not read a green here as the two agreeing.
            """)
    }

    /// The field the three producers write into still exists and is still a millisecond `Float`.
    /// The explicitly typed key path is the real claim — renaming or re-typing `hrvSDNNms` stops
    /// this file BUILDING, which is stronger than any value assertion could be here.
    func testTheFrameStillCarriesAMillisecondSDNNField() {
        let path: KeyPath<BioSampleFrame, Float> = \.hrvSDNNms
        let frame = BioSampleFrame(timestamp: 1, heartRateBPM: 62, hrvNormalized: 0.5,
                                   breathRate: 12, breathPhase: 0, coherence: 0.4,
                                   motionEnergy: 0, source: .cameraPPG, hrvSDNNms: 42)
        XCTAssertEqual(frame[keyPath: path], 42, accuracy: 1e-6)
    }

    // MARK: - Helpers

    private func writerSource() throws -> String {
        let url = try repoRoot()
            .appendingPathComponent("Sources/Echoelmusic/Bio/HealthKitWriter.swift")
        return SourceText.codeOnly(try String(contentsOf: url, encoding: .utf8))
    }

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("""
                source tree not present at \(sources.path) — this test inspects source text, so \
                it SKIPS rather than reporting a green it did not earn
                """)
        }
        return root
    }
}
