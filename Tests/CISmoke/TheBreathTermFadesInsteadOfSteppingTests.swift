// TheBreathTermFadesInsteadOfSteppingTests.swift
// Echoel — #434. The guard over the step #433 knowingly bought.
//
// WHAT #433 DID AND WHAT IT COST. `bioNormalized` blends a heart term and a breath term into
// the ONE value a bio automation lane records. #433 stopped folding an UNMEASURED breath in as
// calm — right, because a BLE-strap frame carries `breathRate: 0` and that zero was a
// fabricated number. Its own doc then wrote down the price rather than hiding it: the value now
// JUMPS by |hr − br| / 2 whenever a measurement appears or vanishes. At 120 bpm over the paced
// 6/min resonance rate that is **0.4286**, i.e. 43 % of the lane's range.
//
// ⛔ AND THAT IS NOT THE MAXIMUM. The first draft of this header called 0.4286 "worst at exactly
// the rate the product aims at" — twice wrong. |hr − br| / 2 maxes at **0.5**, when the two
// normalised terms sit on opposite rails (50 bpm with ≥24/min, or 120 bpm with ≤3/min). And the
// pairing is atypical: 120 bpm normally comes with 18–24/min (step 0.143 → 0.000), paced 6/min
// breathing with 55–75 bpm (0.036–0.107). 0.4286 is the number the fix is MEASURED against, not
// the number a body usually produces.
//
// ⭐ WHY THIS IS A GUARD AND NOT JUST A FIX. The naive repair is an age-based weight: full while
// fresh, fading when stale. That removes the step on DROPOUT and leaves it on RE-ACQUISITION —
// the weight snaps back to 1 the moment a frame returns, and every test about dropouts still
// passes. `testResumingMidReleaseDoesNotStep` is the assertion that separates the two designs,
// and it is the reason this file exists as a file.
//
// ⭐ THE TWO THINGS TWO REVIEWERS FOUND IN THE FIRST DRAFT, both of which this file now pins,
// because each was invisible to every test the draft had:
//   1. THE FADE WAS READ ON THE WRONG CLOCK. `weight(at: frame.timestamp)` — but a frame stamp
//      STOPS ADVANCING exactly during the dropout the fade exists for (`CameraRPPGBioPublisher`
//      republishes with `held.timestamp` and `breathRate: 0`, while `usableBio()` keeps that
//      frozen frame alive against the WALL clock). The weight stayed pinned at 1 for the whole
//      hold, then fell to 0 in ONE lane sample: the full step, unmoved, in the main case.
//      `testTheFadeIsReadOnTheReadingClock` is the regression.
//   2. THE COLD START JUMPED. `resumeWeight = … : 1` at the first measurement, argued as "there
//      is no previous value to be continuous with". At the LANE level there is one: takes begin
//      while rPPG is still acquiring, so heart-only samples are recorded first and breath then
//      arrived as the full 0.4286. Measured on eight heart-only frames then breath at 1 Hz:
//      **0.4286** with the exception, **0.1429** without. The evidence that justified it came
//      from a fixture that STARTED at the first measured frame — it could not see its own cost.
//
// ⭐ THE HORIZON IS CHAINED, so this file asserts a RELATIONSHIP and not two constants: full
// weight for the first half of the measurement's source freshness window, a linear fade across
// the second. Camera/BLE (6 s) → 3 s + 3 s; HealthKit/Watch (90 s) → 45 s + 45 s.
// `testAWristReadingIsNotTreatedLikeACameraFrame` is the one that would catch a return to fixed
// constants — and it matters, because under the draft's fixed 2 s + 4 s a wrist breath rate
// counted at weight 0 for ~83 of its 90 usable seconds. Silently disabled, not faded.
//
// MEASURED, not asserted from taste (1 Hz frames, 120 bpm, 6 breaths/min, camera window):
//   · steady measured body, after warm-up ..... max step 0.0000  (identical to pre-#434)
//   · one missed frame ........................ max step 0.0000  (grace absorbs it)
//   · two missed frames ....................... max step 0.0000  (a 3.0 s gap; grace is 3.0)
//   · three or more missed frames ............. max step 0.1429  (was 0.4286)
//   · first acquisition of a take ............. max step 0.1429  (was 0.4286)
// The bound is structural, not a fixture: the weight moves at most 1/`releaseSeconds` per
// second, so the lane moves at most that times |br − hr| / 2. Chaining to the 6 s camera window
// makes the per-frame move 1/3 of the step rather than the draft's 1/4 — a real cost, taken
// because the draft's 4 s was derived against a window belonging to a different signal (the 10 s
// span in `CameraAnalyzer.detectPeaks` is the PULSE peak detector; `RespirationEstimator` has no
// fixed window at all).
//
// ⚠️ WHAT THIS FILE CANNOT SHOW, and it is the first thing to say because the whole slice rests
// on it: nothing here proves any of this is heard or recorded. `RecordController.onStep` opens
// with `guard armed else { return }`, `arm()` has zero callers in `Sources/`, and #204 records
// the controller as doorless. The repair is worth making BECAUSE the path is dormant — the same
// arithmetic behind a door would need a device listen, not a test. And what the lane WRITES is
// this ramp sampled at the transport step rate, so the per-second bound is a property of the
// signal, not of the difference between two adjacent keyframes.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheBreathTermFadesInsteadOfSteppingTests: XCTestCase {

    private let bpm = 120.0
    private let paced = 6.0          // the resonance rate `BreathPattern.curated` paces
    private let framePeriod = 1.0    // the shipped bio cadence, ~1 Hz (BioApplyRateIsTheDedupedRate)
    private let cameraWindow = BioSource.cameraPPG.freshnessWindow

    /// The PRE-#434 expression, reimplemented locally.
    ///
    /// ⚠️ This exists because the obvious comparison is circular. `bioNormalized(bpm:breathRate:)`
    /// now DELEGATES to the three-argument form, so comparing the two measures new code against
    /// new code and would stay green through a rearrangement that changed the arithmetic. Nothing
    /// in the repo holds the old expression any more, so a guard that claims "identical to before"
    /// has to carry it. Same pattern as `TheArousalFloorSitsBelowThePacedBreath.oldBreathTerm`.
    private func legacyBlend(bpm: Double, breathRate: Double) -> Double {
        func n01(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
            if v.isNaN { return 0 }
            if v <= lo { return 0 }
            if v >= hi { return 1 }
            return (v - lo) / (hi - lo)
        }
        let hr = n01(bpm, 50, 120)
        guard (3.0...40.0).contains(breathRate) else { return Double(Float(hr.clamped(to: 0...1))) }
        return Double(Float(((hr + n01(breathRate, 3, 24)) * 0.5).clamped(to: 0...1)))
    }

    /// Drive a hold through a frame sequence and return what the lane would record.
    /// `nil` is a frame WITHOUT a breath measurement — not a frame carrying 0, which is the
    /// fabricated calm #433 removed. The weight is read on the frame's own instant here, which
    /// for a evenly-spaced synthetic sequence IS the reading clock; the case where the two come
    /// apart has its own test.
    private func lane(_ frames: [(t: TimeInterval, breath: Double?)],
                      bpm: Double? = nil,
                      window: TimeInterval? = nil) -> [Double] {
        var hold = BreathHold()
        let win = window ?? cameraWindow
        return frames.map { frame in
            hold.observe(measured: frame.breath, at: frame.t, usableFor: win)
            return Double(bioNormalized(bpm: bpm ?? self.bpm,
                                        heldBreathRate: hold.rate,
                                        blend: hold.weight(at: frame.t)))
        }
    }

    private func maxStep(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        return (1..<values.count).map { abs(values[$0] - values[$0 - 1]) }.max() ?? 0
    }

    /// Frames at the shipped cadence. `nil` where `missing` says so.
    ///
    /// ⚠️ Every tuple in this file is built WITH its labels and with an explicit `Double?`.
    /// `[(Double, Double?)]` and `[(t: TimeInterval, breath: Double?)]` are distinct types once
    /// they are an Array's element, and Array does not convert between them — the lesson
    /// `OneStartControlTests` records by name, and there is no compiler in this session.
    private func frames(count: Int, missing: Set<Int> = []) -> [(t: TimeInterval, breath: Double?)] {
        var out: [(t: TimeInterval, breath: Double?)] = []
        for i in 0..<count {
            out.append((t: Double(i) * framePeriod,
                        breath: missing.contains(i) ? Double?.none : Double?.some(paced)))
        }
        return out
    }

    // MARK: - The counter-weight (runs first on purpose)

    /// THE ASSERTION THAT MAKES THE SLICE SAFE. A body whose breath never drops out must record
    /// exactly what it recorded before #434 — not "close enough" — once the hold is at full
    /// weight. If this ever fails, the fade has started charging a body that never needed it.
    ///
    /// "IDENTICAL" IS A MEASUREMENT HERE, NOT A FIGURE OF SPEECH, and it needed one because the
    /// two expressions are not the same arithmetic: the old body computed `(hr + br) * 0.5`, the
    /// new one `hr + w * (br − hr) * 0.5` with `w = 1`. Algebraically equal, and NOT identical in
    /// IEEE-754 double — swept over 1 178 241 (bpm, rate) pairs the double intermediates differ
    /// on ~4 % of the domain by up to 1.1e-16, which is ONE ulp at 0.5 (the first draft said
    /// "half an ULP"; a reviewer measured it). What makes the claim true is the RETURN TYPE:
    /// `bioNormalized` returns `Float`, and over that same sweep zero pairs differ once rounded —
    /// the `Float` ULP near 0.5 is 5.96e-8, some eight orders larger than the divergence. That is
    /// a rounding margin, not a theorem.
    func testASteadyMeasuredBodyIsBitIdenticalToBefore() {
        let now = lane(frames(count: 20))
        let before = legacyBlend(bpm: bpm, breathRate: paced)

        // The first samples ramp in — deliberately, see the cold-start test. Once at full
        // weight the lane must be flat and must equal the old expression exactly.
        let settled = Array(now.dropFirst(6))
        XCTAssertEqual(maxStep(settled), 0, accuracy: 0, """
            A steady measured body moved by \(maxStep(settled)) after warm-up. Nothing about \
            #434 should be visible when there is no dropout — a fade that fires on an \
            uninterrupted measurement is a low-pass, which is exactly what this design rejected.
            """)
        for (i, value) in settled.enumerated() {
            XCTAssertEqual(value, before, accuracy: 0, """
                Settled frame \(i) recorded \(value) where the pre-#434 expression gives \
                \(before). `blend == 1` has to be that expression EXACTLY, not an approximation \
                — that identity is why every older assertion still measures real maths.
                """)
        }
    }

    // MARK: - The defect

    /// The step #433 bought, and the bound that replaces it. Both numbers are pinned: without
    /// the "before" figure a later session could weaken the fade back toward zero and read a
    /// passing ceiling as proof nothing was lost (#404 slice 2's mistake).
    func testADropoutFadesInsteadOfStepping() {
        let f = frames(count: 25, missing: [10, 11, 12, 13])

        // What the OLD code did on the same frames: a hard branch, no weight.
        let old = f.map { legacyBlend(bpm: bpm, breathRate: $0.breath ?? 0) }
        XCTAssertEqual(maxStep(old), 0.4286, accuracy: 0.001, """
            The pre-#434 step measured \(maxStep(old)), not the 0.4286 this slice was built \
            against. Re-measure the improvement before trusting the ceiling below — a fix \
            justified by a number nobody re-derived is how this repo has been wrong before.
            """)

        let now = maxStep(Array(lane(f).dropFirst(6)))
        XCTAssertLessThanOrEqual(now, 0.15, """
            A dropout still moves the lane by \(now) in one frame. The bound is structural — \
            the weight travels at most 1/releaseSeconds per second, and releaseSeconds is half \
            the source's freshness window — so a failure here means either the horizon shrank \
            or the fade is being bypassed.
            """)
        XCTAssertLessThan(now, maxStep(old) / 2.5, """
            The fade (\(now)) is no longer meaningfully better than the step it replaced \
            (\(maxStep(old))). At that point the added state is cost without benefit.
            """)
    }

    /// ⭐ THE ONE THAT SEPARATES THE TWO DESIGNS. An age-only weight passes every other test in
    /// this file and fails this one: it snaps back to 1 the instant a frame returns. A resumed
    /// run must climb from where the hold already is.
    func testResumingMidReleaseDoesNotStep() {
        var hold = BreathHold()
        for i in 0..<10 { hold.observe(measured: paced, at: Double(i), usableFor: cameraWindow) }

        // Halfway through the release: grace spent, half of the fade gone.
        let resumeAt = 9.0 + hold.graceSeconds + hold.releaseSeconds / 2
        let before = hold.weight(at: resumeAt)
        XCTAssertEqual(before, 0.5, accuracy: 1e-9, """
            Mid-release weight is \(before), not the 0.5 this test is positioned at. The \
            release shape changed — re-derive the resume point before reading the step below.
            """)

        hold.observe(measured: paced, at: resumeAt, usableFor: cameraWindow)
        let after = hold.weight(at: resumeAt)
        XCTAssertEqual(after, before, accuracy: 1e-12, """
            Re-acquisition stepped the weight from \(before) to \(after). A returning \
            measurement must resume the climb from the weight already held; jumping to 1 puts \
            the #433 step back on the OTHER edge, where no dropout test would ever see it.
            """)
    }

    /// ⭐ THE CLOCK. Both halves of this file's first draft passed while the shipped path did
    /// nothing, because the weight was read at `frame.timestamp` — which freezes during exactly
    /// the dropout the fade exists for. Here the hold is fed ONE measurement and then asked on a
    /// clock that keeps running, which is what `RecordController` does.
    func testTheFadeIsReadOnTheReadingClock() {
        var hold = BreathHold()
        hold.observe(measured: paced, at: 100.0, usableFor: cameraWindow)
        // Bring it to full weight the way a run of frames would.
        for i in 1...4 { hold.observe(measured: paced, at: 100.0 + Double(i), usableFor: cameraWindow) }
        XCTAssertEqual(hold.weight(at: 104.0), 1, accuracy: 1e-12, "Warm-up did not reach full weight.")

        // The frame stamp now stands still (a held republish) while the clock runs on.
        XCTAssertEqual(hold.weight(at: 104.0), 1, accuracy: 1e-12)
        XCTAssertEqual(hold.weight(at: 104.0 + hold.graceSeconds + hold.releaseSeconds / 2),
                       0.5, accuracy: 1e-9, """
            Read on a running clock, a measurement half-way through its fade must weigh 0.5. \
            If this reads 1, the weight is being driven by frame ARRIVAL instead of by time, \
            and the whole fade collapses into one lane sample when frames return.
            """)
        XCTAssertEqual(hold.weight(at: 104.0 + hold.horizon), 0, accuracy: 1e-12, """
            The influence must be gone exactly when the frame stops being usable — that \
            equality IS the derivation of the two durations. Anything else and the hold either \
            outlives the bus's trust in the frame or expires before it.
            """)
    }

    /// ⭐ THE CHAIN. A wrist reading and a camera frame must NOT be held for the same time: the
    /// horizon is the source's own freshness window. Under the draft's fixed constants a
    /// HealthKit breath rate counted at weight 0 for ~83 of its 90 usable seconds.
    func testAWristReadingIsNotTreatedLikeACameraFrame() {
        var camera = BreathHold()
        var wrist = BreathHold()
        camera.observe(measured: 14, at: 0, usableFor: BioSource.cameraPPG.freshnessWindow)
        wrist.observe(measured: 14, at: 0, usableFor: BioSource.healthKit.freshnessWindow)

        XCTAssertEqual(camera.weight(at: 20), 0, accuracy: 0, """
            A camera frame 20 s old still carries weight \(camera.weight(at: 20)). Its source \
            expires at 6 s; the hold may not outlive that.
            """)
        XCTAssertGreaterThan(wrist.weight(at: 20), 0.4, """
            A wrist reading 20 s old carries only \(wrist.weight(at: 20)). HealthKit publishes \
            once per NEW sample, minutes apart, inside a 90 s window — fading it on a camera's \
            schedule silently removes breath from the lane entirely, which is worse than the \
            step this slice set out to fix.
            """)
        XCTAssertEqual(wrist.weight(at: BioSource.healthKit.freshnessWindow), 0, accuracy: 1e-12,
                       "The wrist hold must expire with its own window, not before or after.")
    }

    /// The correction two reviewers forced on this slice, independently: a take's first
    /// measurement arrives AFTER heart-only samples are already on the lane, so it must ramp in
    /// like any other re-acquisition. Ramping to full immediately was the 0.4286 step, moved.
    func testTheFirstMeasurementRampsInLikeAnyOther() {
        var hold = BreathHold()
        hold.observe(measured: paced, at: 100.0, usableFor: cameraWindow)
        XCTAssertEqual(hold.weight(at: 100.0), 0, accuracy: 1e-12, """
            The first measurement of a session arrived at weight \(hold.weight(at: 100.0)) \
            instead of ramping in. The lane was already recording the heart term alone — that \
            IS the previous value, and jumping to full weight steps by the whole |hr − br| / 2.
            """)

        let cold = lane(frames(count: 8))
        XCTAssertLessThanOrEqual(maxStep(cold), 0.15, """
            First acquisition moved the lane by \(maxStep(cold)) in one frame. That is the \
            step this slice exists to remove, at the take's most likely moment.
            """)
    }

    /// The grace window earning its keep: missed frames at the shipped cadence must not move the
    /// lane AT ALL, or this becomes the low-pass it was built to avoid. TWO is the claim the
    /// draft made in prose and failed to deliver (its 2 s grace covered a 2 s gap, i.e. ONE
    /// missed frame); the chained horizon gives 3 s, which covers a 3 s gap exactly.
    func testTwoMissedFramesDoNotMoveTheLaneAtAll() {
        let one = maxStep(Array(lane(frames(count: 20, missing: [10])).dropFirst(6)))
        XCTAssertEqual(one, 0, accuracy: 1e-12,
                       "A single missed frame moved the lane by \(one).")

        let two = maxStep(Array(lane(frames(count: 20, missing: [10, 11])).dropFirst(6)))
        XCTAssertEqual(two, 0, accuracy: 1e-12, """
            Two consecutive missed frames moved the lane by \(two). At the ~1 Hz bio cadence \
            that gap is 3.0 s, and the grace window is half the 6 s camera freshness window — \
            so this is the assertion that the prose and the arithmetic agree, which in the first \
            draft they did not.
            """)
    }

    // MARK: - What the hold may never do

    /// It HOLDS a measurement; it never invents one. A frame without breath must leave `rate`
    /// untouched, and a rate outside `BioSampleFrame.plausibleBreathRate` must drop the term no
    /// matter what weight is handed in — a weight cannot resurrect a non-measurement.
    func testAHeldRateIsNeverInvented() {
        var hold = BreathHold()
        hold.observe(measured: 7.5, at: 0, usableFor: cameraWindow)
        hold.observe(measured: nil, at: 1, usableFor: cameraWindow)
        hold.observe(measured: nil, at: 2, usableFor: cameraWindow)
        XCTAssertEqual(hold.rate, 7.5, accuracy: 1e-12, """
            A frame without a breath measurement changed the held rate to \(hold.rate). \
            Holding means the number stays one a body actually breathed; only its weight moves.
            """)

        // Two heart rates, because at 120 bpm `hr` is 1.0 and a blend bug would hide there.
        for heart in [120.0, 85.0] {
            let heartOnly = Double(bioNormalized(bpm: heart, heldBreathRate: 0, blend: 1))
            XCTAssertEqual(heartOnly, legacyBlend(bpm: heart, breathRate: 0), accuracy: 0, """
                At \(heart) bpm a weight of 1 over an implausible rate (0) produced \
                \(heartOnly) instead of the heart term alone. That is the #433 defect returning \
                through the new parameter.
                """)
        }
    }

    /// A wall clock can step BACKWARDS (NTP, user change), and these timestamps ride
    /// `CFAbsoluteTimeGetCurrent`. Without a reset the hold latches: every later frame is older
    /// than `lastMeasuredAt`, so nothing updates again and a stale rate keeps a permanent
    /// partial weight — the fabricated-number failure #433 removed, through the back door.
    func testABackwardsClockDoesNotLatchTheHold() {
        var hold = BreathHold()
        for i in 0..<6 { hold.observe(measured: paced, at: 1000 + Double(i), usableFor: cameraWindow) }
        XCTAssertEqual(hold.weight(at: 1005), 1, accuracy: 1e-12, "Warm-up did not reach full weight.")

        hold.observe(measured: 14, at: 500, usableFor: cameraWindow)
        XCTAssertEqual(hold.rate, 14, accuracy: 1e-12, """
            After the clock stepped back the hold still reports \(hold.rate) — it rejected \
            every frame on the new clock and is pinned to a rate nobody is breathing.
            """)
        for i in 1...6 { hold.observe(measured: 14, at: 500 + Double(i), usableFor: cameraWindow) }
        XCTAssertEqual(hold.weight(at: 506), 1, accuracy: 1e-12,
                       "The hold never recovered full weight on the corrected clock.")
    }

    /// Non-finite input at a bio boundary is an edge case, not an impossibility, and
    /// `min(max(v, 0), 1)` passes NaN straight through (CLAUDE.md's shipped-silence lesson).
    func testNothingNonFiniteReachesTheLane() {
        var hold = BreathHold()
        hold.observe(measured: .nan, at: 0, usableFor: cameraWindow)
        hold.observe(measured: 6, at: .nan, usableFor: cameraWindow)
        hold.observe(measured: 6, at: 1, usableFor: .nan)
        XCTAssertEqual(hold.weight(at: 0), 0, accuracy: 0,
                       "A non-finite frame gave the hold a weight — nothing was measured.")
        XCTAssertEqual(hold.weight(at: .nan), 0, accuracy: 0,
                       "A non-finite `now` produced a weight instead of falling back to none.")

        for value in [bioNormalized(bpm: .nan, heldBreathRate: 6, blend: 1),
                      bioNormalized(bpm: bpm, heldBreathRate: .nan, blend: 1),
                      bioNormalized(bpm: bpm, heldBreathRate: 6, blend: .nan),
                      bioNormalized(bpm: bpm, heldBreathRate: 6, blend: .infinity)] {
            XCTAssertTrue(value.isFinite, "bioNormalized returned a non-finite lane value.")
        }
    }

    // MARK: - Wiring

    /// A correct core with no caller is the same defect with more steps. This is the half that
    /// is a source scan, and it says so: it proves the controller ASKS the hold, not that a
    /// take ever runs.
    ///
    /// ⚠️ Matched against WHITESPACE-COLLAPSED source, not against physical lines. #413 paid for
    /// that lesson on a scan that required two tokens on one line and went red when the source
    /// was re-wrapped; this repo hoists call arguments routinely, and the very call below is
    /// already three lines long.
    func testTheHoldIsWiredIntoTheOnlyCaller() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let path = root.appendingPathComponent("Sources/Echoelmusic/Core/RecordController.swift")
        let text = try String(contentsOf: path, encoding: .utf8)
        let code = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces).hasPrefix("//") ? "" : String($0) }
            .joined(separator: "\n")
        let flat = code.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")

        XCTAssertTrue(flat.contains("breathHold.observe(measured:"), """
            `RecordController` no longer feeds frames to the hold. Without that call the fade \
            never advances and `bioNormalized` is back to stepping — with the core still \
            present and passing every other test in this file.
            """)
        XCTAssertTrue(flat.contains("at: frame.timestamp"), """
            The hold is no longer fed the FRAME's stamp. That stamp is what dedups a held \
            republish; feeding it the reading clock instead would make every republish look \
            like a fresh measurement.
            """)
        XCTAssertTrue(flat.contains("usableFor: frame.source.freshnessWindow"), """
            The horizon is no longer chained to the frame's own source. A constant here \
            compiles, passes, and silently mutes breath for every wrist reading — the whole \
            point of the chain (#426's form: pin the argument that makes the call mean \
            something, not just the call).
            """)
        XCTAssertTrue(flat.contains("blend: breathHold.weight(at: CFAbsoluteTimeGetCurrent())"), """
            The weight is no longer read on the reading clock. Reading it at `frame.timestamp` \
            compiles and passes every behavioural test in this file, and makes the slice a \
            no-op on its main case — that is exactly what the first draft shipped.
            """)
        XCTAssertTrue(flat.contains("frame.hasMeasuredBreath"), """
            The controller no longer uses `hasMeasuredBreath` to decide what counts as a \
            reading. That predicate is the repo's single answer to that question; a second \
            copy at the call site is the #416 double-definition defect.
            """)
    }
}
