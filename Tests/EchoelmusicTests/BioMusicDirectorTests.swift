// BioMusicDirectorTests.swift
// Echoelmusic — bio→music direction (privacy-safe summary + deterministic fallback).
// The on-device LLM path is iOS 26-only and device-gated; these cover the always-
// available, no-LLM logic that the feature degrades to on iOS 18.

import XCTest
@testable import Echoelmusic

final class BioMusicDirectorTests: XCTestCase {

    /// ⛔ THE SOURCE WAS `.fallback` UNTIL #634b, AND THAT MADE TWO ASSERTIONS BELOW WRONG.
    /// `BioExplanation` now names the origin: a `.fallback` frame narrates "from the demo
    /// signal", not "from your live signal", so `testTailCreditsTheBodyWhenSomethingWasRead`
    /// and its breath-only sibling asserted a phrase the function can no longer produce for
    /// this frame. `.cameraPPG` is a real measured source and is what those two tests always
    /// MEANT — the old value was an arbitrary pick from before provenance existed.
    ///
    /// ⚠️ This file is in `Tests/EchoelmusicTests`, which NO gate compiles (#208), so nothing
    /// would have gone red; it would simply have been wrong the first day someone ran it.
    /// The blocking bundle's twin (`Tests/CISmoke/TheNarrationCannotClaimABodyItDidNotReadTests`)
    /// already used `.cameraPPG` and needed no change.
    private func frame(hr: Float, coherence: Float, breath: Float,
                       source: BioSource = .cameraPPG) -> BioSampleFrame {
        BioSampleFrame(
            timestamp: 0, heartRateBPM: hr, hrvNormalized: 0.5,
            breathRate: breath, breathPhase: 0, coherence: coherence,
            motionEnergy: 0, source: source)
    }

    /// #634b — the demo source must not be narrated as the listener's body.
    func testTheDemoSourceIsNamedInsteadOfClaimedAsYours() {
        let t = BioExplanation.text(for: frame(hr: 62, coherence: 0.8, breath: 6,
                                               source: .fallback), tempo: 120)
        XCTAssertTrue(t.contains("from the demo signal"),
                      "a .fallback frame must credit the demo, not the listener")
        XCTAssertFalse(t.contains("from your live signal"),
                       "…and must never use the possessive form for a fabricated pulse")
        XCTAssertTrue(t.hasPrefix("EchoelAI (demo signal) — "), """
            the marker must LEAD. This is a running sentence, not a cell — a qualifier placed \
            after "heart rate 62 BPM sets a flowing tempo" corrects a claim the reader has \
            already accepted.
            """)
    }

    func testSummaryBucketsArousalSteadinessBreath() {
        let calm = BioStateSummary(from: frame(hr: 55, coherence: 0.8, breath: 6))
        XCTAssertEqual(calm.arousal, "low")
        XCTAssertEqual(calm.steadiness, "steady and coherent")
        XCTAssertEqual(calm.breath, "slow")

        let amped = BioStateSummary(from: frame(hr: 120, coherence: 0.1, breath: 22))
        XCTAssertEqual(amped.arousal, "high")
        XCTAssertEqual(amped.steadiness, "restless")
        XCTAssertEqual(amped.breath, "fast")
    }

    // MARK: - Unmeasured fields are never described

    func testSummary_unmeasuredFieldsAreNil_notTheLowEndOfTheScale() {
        // A HealthKit session: real heart rate, but that source never computes coherence
        // and only has a respiratory rate if the user tracks sleep. Both arrive as 0.
        let healthKit = BioStateSummary(from: frame(hr: 62, coherence: 0, breath: 0))
        XCTAssertEqual(healthKit.arousal, "low", "a real heart rate is still described")
        XCTAssertNil(healthKit.steadiness, "coherence 0 must not become 'restless'")
        XCTAssertNil(healthKit.breath, "breath rate 0 must not become 'slow'")

        // No pulse lock at all.
        let noBody = BioStateSummary(from: frame(hr: 0, coherence: 0, breath: 0))
        XCTAssertNil(noBody.arousal)
        XCTAssertEqual(noBody.prompt, "Body state: not measured yet.")
    }

    func testExplanation_saysNothingAboutWhatItDidNotMeasure() {
        let t = BioExplanation.text(for: frame(hr: 62, coherence: 0, breath: 0), tempo: 90)
        // Assert against the strings the code ACTUALLY emits. The bucket label is
        // "restless", but `text()` renders it as "an unsteady signal…" — screening for
        // "restless" here would be unfalsifiable and would have missed the shipped bug.
        XCTAssertFalse(t.contains("unsteady signal"),
                       "narrated an unsteady body from a coherence that was never measured")
        XCTAssertFalse(t.contains("breathing"),
                       "narrated breathing from a rate that was never measured")
        // What IS measured still gets said, so the caption stays useful rather than empty.
        XCTAssertTrue(t.contains("62 BPM"))
        XCTAssertTrue(t.contains("90 BPM"))
    }

    func testExplanation_withNoBodyAtAll_makesNoClaimAboutThePerson() {
        let t = BioExplanation.text(for: frame(hr: 0, coherence: 0, breath: 0), tempo: 120)
        XCTAssertTrue(t.contains("no pulse measured yet"))
        for fabricated in ["unsteady signal", "breathing", "coherence"] {
            XCTAssertFalse(t.contains(fabricated), "leaked '\(fabricated)' with nothing measured")
        }
        // The tail must not claim a signal it just said does not exist.
        XCTAssertFalse(t.contains("from your live signal"),
                       "promised music 'from your live signal' one sentence after 'no pulse measured yet'")
    }

    func testExplanation_withAMeasuredBody_stillCreditsTheLiveSignal() {
        // The counterpart to the test above: dropping that phrase unconditionally would
        // also pass there, so pin that a real body DOES get told its signal is driving.
        let t = BioExplanation.text(for: frame(hr: 62, coherence: 0.8, breath: 6), tempo: 90)
        XCTAssertTrue(t.contains("from your live signal"))
        XCTAssertTrue(t.contains("slow breathing"))
    }

    func testExplanation_breathWithoutAPulse_isStillCredited() {
        // The mixed path, and the only exerciser of the breath clause without arousal.
        // Without this, narrowing `measuredAnything` to just `arousal != nil` passes the
        // two tests above (their frames measure everything or nothing) while silently
        // dropping the live-signal credit from a body that IS being read.
        let t = BioExplanation.text(for: frame(hr: 0, coherence: 0, breath: 12), tempo: 100)
        XCTAssertTrue(t.contains("relaxed breathing shapes the swell"))
        XCTAssertTrue(t.contains("from your live signal"))
        XCTAssertTrue(t.contains("no pulse measured yet"))
        // Reverb is HRV-driven (`reverbMix` in EchoelDDSP.applyBioReactive), never breath.
        XCTAssertFalse(t.contains("reverb"), "credited breathing for a space it does not set")
    }

    func testExplanation_neverPromisesATempoTheLockWillNotDeliver() {
        // "…until a pulse is measured" was a prediction the tempo lock falsifies: with
        // lockBPM on, tempo resolves from lockedBPM and never moves to the pulse.
        let t = BioExplanation.text(for: frame(hr: 0, coherence: 0, breath: 0), tempo: 120)
        XCTAssertFalse(t.contains("until a pulse"))
        XCTAssertTrue(t.contains("no pulse measured yet"))
    }

    func testFallback_unmeasuredCoherenceCannotSelectTheTenseExtreme() {
        // "tense" is reachable only from "restless", which is now unreachable without a
        // real reading. The direction must still be a complete, playable choice.
        let d = BioDirectionFallback.direction(for: frame(hr: 100, coherence: 0, breath: 0))
        XCTAssertNotEqual(d.mood, "tense")
        // A REAL low coherence still reaches it — the gate is "measured", not "high".
        XCTAssertEqual(BioDirectionFallback.direction(for: frame(hr: 100, coherence: 0.05, breath: 12)).mood,
                       "tense")
    }

    func testSummaryPromptIsAdjectivesOnly_noBiometrics() {
        // The prompt handed to the model must not leak raw numbers/identifiers.
        let p = BioStateSummary(from: frame(hr: 123, coherence: 0.42, breath: 17)).prompt
        XCTAssertFalse(p.contains("123"))
        XCTAssertFalse(p.contains("17"))
        XCTAssertTrue(p.contains("arousal"))
    }

    func testFallbackIsDeterministicAndInRange() {
        let f = frame(hr: 58, coherence: 0.7, breath: 6)
        let a = BioDirectionFallback.direction(for: f)
        let b = BioDirectionFallback.direction(for: f)
        XCTAssertEqual(a, b)                      // pure / deterministic
        XCTAssertEqual(a.genre, "deep ambient")  // low arousal → ambient
        XCTAssertEqual(a.space, "hall")
    }

    func testFallbackHighArousalIsEnergetic() {
        let d = BioDirectionFallback.direction(for: frame(hr: 130, coherence: 0.2, breath: 24))
        XCTAssertEqual(d.genre, "psytrance")
        XCTAssertEqual(d.mood, "tense")          // restless → tense
        XCTAssertEqual(d.space, "room")
    }

    func testGateOffByDefaultInTestEnvironment() throws {
        // CI-VERIFIED HOST-DEPENDENT (2026-07-21, run 29825653117 on macos-26/
        // Xcode 26.2): this assertion fails FAST and cleanly (0.012s — a real
        // assertion failure, not a hang/timeout/crash), i.e.
        // OnDeviceModelGate.isOnDeviceLLMAvailable actually evaluates `true` on
        // that CI simulator. The original comment's premise ("simulator/test
        // host has no on-device model") is false for iOS 26+ simulators: Apple's
        // Foundation Models framework docs state the iOS/visionOS SIMULATOR does
        // NOT carry its own model — it runs `SystemLanguageModel.default` against
        // whatever Apple Intelligence state the HOST Mac reports, since the
        // simulator shares the host macOS's model store rather than having a
        // simulated per-device one. (Xcode 26 even ships a scheme-level
        // "Foundation Models Availability" override specifically so tests can
        // force `.unavailable` — implying host-inherited availability is the
        // unpredictable DEFAULT they expect developers to need to override.)
        // So on a `macos-26` GitHub Actions runner whose host OS happens to
        // report Apple Intelligence available, `OnDeviceModelGate` is behaving
        // CORRECTLY (there genuinely is a model available in that process) —
        // this is a CI-host configuration variable, not something
        // Sources/Core/OnDeviceModelGate.swift can or should special-case.
        // Skipping rather than asserting a host-dependent value; if this needs
        // a deterministic CI value, the fix is a scheme-level Foundation Models
        // Availability override in project.yml/testflight harness, not a Tests
        // or Sources change.
        throw XCTSkip("OnDeviceModelGate.isOnDeviceLLMAvailable follows the CI host Mac's Apple Intelligence state on iOS 26+ simulators (Apple: simulator shares the host's model store) — not deterministically closed in CI")
    }
}
