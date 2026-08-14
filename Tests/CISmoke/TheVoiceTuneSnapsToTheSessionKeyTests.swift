// TheVoiceTuneSnapsToTheSessionKeyTests.swift
// Echoel — the optional in-key pitch correction is wired end to end. VL3, #599.
//
// WHAT THIS GUARDS. The founder's ask, answered honestly: `VoicePitchCorrector`
// (VL1) and `VoiceHarmony` (VL2) sat in `Sequencer/` as pure, tested cores with
// ZERO production callers — their own header named the VL3 consumer chain as a
// PLAN. #599 builds exactly that chain on the MONITOR path: mic tap →
// `MonitorTapWindow` (shared with the #595 notch — `copyLatest` copies, two
// readers are legal) → `PitchTracker` (YIN) → `VoicePitchCorrector` →
// `AVAudioUnitTimePitch` between `notchEQ` and `monitorMixer`. OPTIONAL by a
// default-off toggle in the input sheet ("Tune to key"); CHARACTER via the
// retune field (1 = classic hard snap, 0 = gentle drift). Key + Kammerton come
// from the ONE stored definition the studio writes (`StudioDefaultKeys` +
// `SessionContext.a4StorageKey`) — the Echoel edge the corrector's header
// states: the key is KNOWN, never guessed from the signal.
//
// ⚠️ HONEST LIMITS. 7 tests, 25 `XCTAssert*` statements (hand-counted per test,
// 4+3+2+3+5+5+3; one `XCTUnwrap` in test 2, outside the count — the first draft
// wrote 24 with "4" for test 6 from memory; the recount found 5). Tests 1–4 are
// END-TO-END BEHAVIOUR on the shipped pure types (real corrector state machine,
// no mocks). Tests 5–7 are SOURCE-TEXT JOINS — the graph rewire sits on a
// running `AVAudioEngine` no test host can drive. What no test here can prove:
// that the corrected monitor SOUNDS in key on a device, the added latency of
// the time-pitch stage, and CPU of YIN-at-15-Hz on old hardware — device probe
// (NEEDS-FOUNDER-VERIFY: monitoring on, Tune to key on, sing off-pitch — the
// monitor must pull you to the Tonart; Tune 1.00 must give the classic snap).
//
// ⭐ GRADING (§3). Transcribed in Python (stripper re-implemented, needles
// counted raw vs stripped) against BOTH trees. Worktree: all needles reproduce;
// tests 1–4 hand-driven against the corrector's algebra (#442 — targets chosen
// where the cents subtraction is exact). Against the parent: tests 1–4 are
// COUNTERWEIGHTS (the cores shipped long ago — green there, and that is the
// point: #599 wired, it did not reinvent); tests 5–7 are FORWARD (this commit
// creates every anchor) — red there by ONE absence, reported once (#486).
// Stripper: TRAGEND (1 of 13 join-needle verdicts flip — the a4StorageKey
// count-1 finds a SECOND mention in the engine's own member doc-comment when
// run raw; `codeOnly` blanking it is precisely the stripper's job).

import Foundation
import XCTest
@testable import Echoelmusic

final class TheVoiceTuneSnapsToTheSessionKeyTests: XCTestCase {

    // MARK: - 1–4. The correction maths (END-TO-END, shipped pure types)

    /// A note between C and C# in C major snaps DOWN to C (tie resolves lower,
    /// mirroring MusicalKey.quantize), at full strength and instant retune —
    /// the exact −100-cent case where the subtraction is exact (#442).
    func testAnOffKeyNoteSnapsIntoTheKey() {
        let cMajor = MusicalKey(root: 0, scale: .major)
        var corrector = VoicePitchCorrector(key: cMajor, a4Hz: 440,
                                            strength: 1, retuneSpeed: 1)
        // MIDI 61.0 exactly: 440 · 2^((61−69)/12).
        let hz61 = 440.0 * pow(2.0, (61.0 - 69.0) / 12.0)
        let c = corrector.process(detectedHz: hz61, dt: 0.05)
        XCTAssertEqual(c.targetMidi, 60, "61.0 is a tie between C(60) and D(62) — lower wins")
        XCTAssertEqual(c.appliedCents, -100, accuracy: 1e-6,
                       "full strength, instant retune: the whole −100-cent correction lands")
        XCTAssertEqual(Double(c.ratio), pow(2.0, -100.0 / 1200.0), accuracy: 1e-6)
        XCTAssertEqual(c.targetHz ?? 0, 440.0 * pow(2.0, (60.0 - 69.0) / 12.0),
                       accuracy: 1e-9, "the target grid is built on the session Kammerton")
    }

    /// Kammerton-true: at A4 = 432 the sung 432 Hz IS the A — zero correction.
    /// This is the corrector's stated edge over a hardcoded-440 autotune.
    func testTheGridMovesWithTheKammerton() throws {
        let aMinor = MusicalKey(root: 9, scale: .minor)
        var corrector = VoicePitchCorrector(key: aMinor, a4Hz: 432,
                                            strength: 1, retuneSpeed: 1)
        let c = corrector.process(detectedHz: 432, dt: 0.05)
        XCTAssertEqual(c.targetMidi, 69)
        XCTAssertEqual(c.appliedCents, 0, accuracy: 1e-9,
                       "432 Hz at Kammerton 432 is ALREADY the A — a 440 grid would bend it")
        XCTAssertEqual(try XCTUnwrap(c.targetHz), 432, accuracy: 1e-9)
    }

    /// Strength 0 = bypass in effect: the ratio stays 1 whatever is sung.
    /// This is the "optional" half INSIDE the maths — the toggle is the door,
    /// strength is the depth, and both must be able to reach silence-of-effect.
    func testZeroStrengthAppliesNoCorrection() {
        var corrector = VoicePitchCorrector(key: MusicalKey(root: 0, scale: .major),
                                            a4Hz: 440, strength: 0, retuneSpeed: 1)
        let c = corrector.process(detectedHz: 261.0, dt: 0.05)
        XCTAssertEqual(c.appliedCents, 0, accuracy: 1e-9)
        XCTAssertEqual(c.ratio, 1)
    }

    /// VL2 stays true beside VL3: the diatonic third above E in C major is G
    /// (+3), not G# (+4) — the intervals breathe with the key. (Counterweight:
    /// #599 wired VL1; VL2's harmonizer join is the NEXT slice, and this pins
    /// that the maths it will consume did not drift meanwhile.)
    func testDiatonicThirdBreathesWithTheKey() {
        let cMajor = MusicalKey(root: 0, scale: .major)
        XCTAssertEqual(VoiceHarmony.interval(from: 64, degreesUp: 2, key: cMajor), 3)
        XCTAssertEqual(VoiceHarmony.interval(from: 60, degreesUp: 2, key: cMajor), 4)
        XCTAssertEqual(VoiceHarmony.interval(from: 64, degreesUp: -2, key: cMajor), -4)
    }

    // MARK: - 5–7. The wiring joins (SOURCE-TEXT)

    /// The graph: the pitch stage sits between notchEQ and monitorMixer on BOTH
    /// build paths (monitoring-start and live toggle), and BOTH teardown paths
    /// disconnect it — a leaked connection would keep pitching a rebuilt chain.
    func testThePitchStageIsInTheMonitorChainOnly() throws {
        let engine = try source("Sources/Echoelmusic/Audio/AudioEngine.swift")
        XCTAssertEqual(codeOccurrences(
            of: "masterEngine.connect(notchEQ, to: voiceTunePitch, format: inFmt)", in: engine), 2,
            "two build paths: setInputMonitoring(true) with the flag set, and the live rewire")
        XCTAssertEqual(codeOccurrences(
            of: "masterEngine.connect(voiceTunePitch, to: monitorMixer, format: inFmt)", in: engine), 2)
        XCTAssertEqual(codeOccurrences(
            of: "if voiceTuneAttached { masterEngine.disconnectNodeOutput(voiceTunePitch) }", in: engine), 2,
            "both teardowns (restart-failure and monitoring-off) release the stage")
        XCTAssertEqual(codeOccurrences(
            of: "masterEngine.connect(notchEQ, to: monitorMixer, format: inFmt)", in: engine), 2,
            "COUNTERWEIGHT: the plain #595 chain survives — the else of the "
            + "monitoring build and the off branch of the live rewire (the "
            + "pre-#599 tree had exactly 1, the unconditional build); 2 pins "
            + "that OFF restores it on both paths rather than leaving the "
            + "stage wedged in")
        XCTAssertEqual(codeOccurrences(of: "AVAudioUnitTimePitch()", in: engine), 1,
                       "one stage — a second instance would double the latency cost")
    }

    /// The control loop: the guard tick drives YIN over the SHARED window and
    /// writes smoothed cents to the node; key + Kammerton come from the ONE
    /// stored definition (#416) — no second copy of the key that can drift.
    func testTheTickReadsTheOneKeyDefinition() throws {
        let engine = try source("Sources/Echoelmusic/Audio/AudioEngine.swift")
        XCTAssertEqual(codeOccurrences(of: "self.updateVoiceTune()", in: engine), 1,
                       "driven from the same ~15 Hz gate as the notch — no second timer")
        XCTAssertEqual(codeOccurrences(
            of: "PitchTracker.detect(voiceTuneBuffer, sampleRate: monitorTapSampleRate)", in: engine), 1,
            "YIN reads the tap's OWN sample rate — a hardcoded 48 k would be the "
            + "#595-F2 staleness class from birth")
        XCTAssertEqual(codeOccurrences(
            of: "voiceTunePitch.pitch = Float(correction.appliedCents)", in: engine), 1,
            "the smoothed correction reaches the node — without this line the whole "
            + "chain is a pitch-shifter parked at 0 cents")
        XCTAssertEqual(codeOccurrences(of: "StudioDefaultKeys.rootIndex.key", in: engine), 1,
                       "the key is read from the studio's OWN storage key (#416)")
        XCTAssertEqual(codeOccurrences(of: "SessionContext.a4StorageKey", in: engine), 1,
                       "the Kammerton too — a4StorageKey is public FOR external readers")
    }

    /// The door: default OFF (the founder's "optional"), toggled only through
    /// setVoiceTune (which owns the rewire), numeric params on EchoelValueField.
    func testTheDoorIsOptionalAndLawful() throws {
        let engine = try source("Sources/Echoelmusic/Audio/AudioEngine.swift")
        XCTAssertEqual(codeOccurrences(of: "private(set) var voiceTuneEnabled = false", in: engine), 1,
                       "default OFF, and no writer outside setVoiceTune can exist")
        let picker = try source("Sources/Echoelmusic/Studio/AudioInputPickerView.swift")
        XCTAssertEqual(codeOccurrences(of: "audioEngine.setVoiceTune($0)", in: picker), 1,
                       "the toggle goes through the setter that owns the graph rewire")
        XCTAssertEqual(codeOccurrences(of: "audioEngine.voiceTuneRetune = $0", in: picker), 1,
                       "the character control exists — an EchoelValueField binding "
                       + "(the numeric-parameter law; the toggle is the named binary)")
    }

    // MARK: - helpers (§0/§2 — one stripper, skip on no tree, FAIL on a moved anchor)

    private struct TuneAnchorMissing: Error { let reason: String }

    private func codeOccurrences(of needle: String, in stripped: String) -> Int {
        stripped.components(separatedBy: needle).count - 1
    }

    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw TuneAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }
}
