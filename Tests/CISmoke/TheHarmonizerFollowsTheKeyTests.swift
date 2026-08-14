// TheHarmonizerFollowsTheKeyTests.swift
// Echoel — "Follow the key": the harmony voices are diatonic, not fixed. #599b.
//
// WHAT THIS GUARDS. VL2 wired: `DiatonicHarmonyFollower` bridges
// `EngineBus.latestMusical` (loudest sounding note + the published key) through
// `VoiceHarmony` onto every attached chain's `EchoelHarmonizer.interval1/2` at
// ~10 Hz — a third above E in C major is G (+3), not G# (+4). The toggle lives
// in the FX panel's Harmonizer section; while ON the interval rows are HIDDEN
// (the follower rewrites them every tick — a control that lies is worse than
// none), and the OFF action re-fans the view-model's stored intervals (the
// follower holds NO baseline, so a preset recalled mid-follow restores to ITS
// values). Not persisted — following is a performance act.
//
// ⚠️ HONEST LIMITS. 4 tests, 20 `XCTAssert*` statements (hand-counted per test,
// 6+3+3+8; `XCTUnwrap` census: three in test 1, one in test 3 — outside the
// count). Tests 1–3 are END-TO-END BEHAVIOUR on the shipped pure decision
// (`diatonicIntervals`, nonisolated static). Test 4 is SOURCE-TEXT JOINS — the
// follower's tick needs a running bus and chains no test host drives. What no
// test here can prove: that the follow SOUNDS musical at tempo, and that the
// ~10 Hz interval steps do not zipper audibly on a held chord — device probe
// (NEEDS-FOUNDER-VERIFY: FX → Harmonizer → Follow the key, play a melody; the
// harmony must stay in the Tonart on every note).
//
// ⭐ GRADING (§3). Transcribed in Python (stripper re-implemented; needles raw
// vs stripped both trees). Worktree: all reproduce. Against the parent every
// join is FORWARD (this commit creates the type and every anchor) — red by ONE
// absence, reported once (#486); tests 1–3 drive a type the same commit adds,
// so no verdict exists there either (hand-driven against `VoiceHarmony`'s
// algebra instead, which IS on the parent and pinned by
// TheVoiceTuneSnapsToTheSessionKeyTests test 4). Stripper: PROPHYLAKTISCH
// (0 of 8 join verdicts flip — measured, not assumed; the first draft wrote 9
// without counting, in the header whose whole job is the count).

import Foundation
import XCTest
@testable import Echoelmusic

final class TheHarmonizerFollowsTheKeyTests: XCTestCase {

    // MARK: - 1–3. The decision (END-TO-END, shipped pure static)

    /// The core musical truth: the third BREATHES with the key. C4 carries a
    /// major third (+4) in C major, E4 a minor third (+3); the fifth stays +7 on
    /// both. A fixed-interval harmonizer cannot say this sentence.
    func testTheThirdBreathesWithTheKey() throws {
        let c4 = 440.0 * pow(2.0, -9.0 / 12.0)
        let e4 = 440.0 * pow(2.0, -5.0 / 12.0)
        let onC = try XCTUnwrap(DiatonicHarmonyFollower.diatonicIntervals(
            leadHz: c4, a4Hz: 440, rootPitchClass: 0, scaleName: Scale.major.rawValue))
        XCTAssertEqual(onC.third, 4, "C→E in C major: a MAJOR third")
        XCTAssertEqual(onC.fifth, 7)
        let onE = try XCTUnwrap(DiatonicHarmonyFollower.diatonicIntervals(
            leadHz: e4, a4Hz: 440, rootPitchClass: 0, scaleName: Scale.major.rawValue))
        XCTAssertEqual(onE.third, 3, "E→G in C major: a MINOR third — the whole point")
        XCTAssertEqual(onE.fifth, 7)
        let onA = try XCTUnwrap(DiatonicHarmonyFollower.diatonicIntervals(
            leadHz: 440, a4Hz: 440, rootPitchClass: 9, scaleName: Scale.minor.rawValue))
        XCTAssertEqual(onA.third, 3, "A→C in A minor")
        XCTAssertEqual(onA.fifth, 7)
    }

    /// No usable key/lead → nil, and the caller HOLDS rather than guessing: an
    /// unknown scale, a missing root, an unvoiced lead each refuse.
    func testAnUnusableFrameRefusesInsteadOfGuessing() {
        XCTAssertNil(DiatonicHarmonyFollower.diatonicIntervals(
            leadHz: 440, a4Hz: 440, rootPitchClass: 0, scaleName: "no-such-scale"))
        XCTAssertNil(DiatonicHarmonyFollower.diatonicIntervals(
            leadHz: 440, a4Hz: 440, rootPitchClass: -1, scaleName: Scale.major.rawValue))
        XCTAssertNil(DiatonicHarmonyFollower.diatonicIntervals(
            leadHz: 0, a4Hz: 440, rootPitchClass: 0, scaleName: Scale.major.rawValue))
    }

    /// Kammerton-true like everything in this stage: at A4 = 432 the sung 432 Hz
    /// IS the A, and the intervals are the same — the grid moved, not the music.
    func testTheGridMovesWithTheKammerton() throws {
        let iv = try XCTUnwrap(DiatonicHarmonyFollower.diatonicIntervals(
            leadHz: 432, a4Hz: 432, rootPitchClass: 9, scaleName: Scale.minor.rawValue))
        XCTAssertEqual(iv.third, 3)
        XCTAssertEqual(iv.fifth, 7)
        XCTAssertNil(DiatonicHarmonyFollower.diatonicIntervals(
            leadHz: 432, a4Hz: 0, rootPitchClass: 9, scaleName: Scale.minor.rawValue),
            "a dead Kammerton refuses — no silent 440 fallback that would detune the follow")
    }

    // MARK: - 4. The wiring joins (SOURCE-TEXT)

    /// App-owned, two-chain inventory, environment-injected; the toggle pairs
    /// enable with the VM re-fan; the tick writes BOTH voices; the VM's own
    /// fan-out stays the one restore path.
    func testTheFollowerIsWiredAndTheRestoreIsPaired() throws {
        let app = try source("Sources/Echoelmusic/EchoelmusicApp.swift")
        XCTAssertEqual(codeOccurrences(
            of: "harmonyFollower.attach(chains: [polyVoice.fxChain, touchVoice.fxChain]", in: app), 1,
            "SAME two-chain inventory as FXBioModulator (#386 — one body, every "
            + "listening chain); a one-chain attach re-opens the split-reach defect")
        XCTAssertEqual(codeOccurrences(of: ".environment(harmonyFollower)", in: app), 1)
        let fx = try source("Sources/Echoelmusic/Studio/EchoelFXView.swift")
        XCTAssertEqual(codeOccurrences(of: "if !on { vm.refanHarmonizerIntervals() }", in: fx), 1,
                       "the OFF action owns the restore — without this line, turning "
                       + "follow off leaves the last diatonic intervals wedged into "
                       + "the chains while the rows show the user's old values")
        XCTAssertEqual(codeOccurrences(of: "if harmonyFollower.enabled {", in: fx), 1,
                       "the interval rows hide while following — a visible row the "
                       + "follower overwrites every tick would be a lying control")
        let follower = try source("Sources/Echoelmusic/Tools/DiatonicHarmonyFollower.swift")
        XCTAssertEqual(codeOccurrences(of: "c.harmonizer.interval1 = Float(iv.third)", in: follower), 1)
        XCTAssertEqual(codeOccurrences(of: "c.harmonizer.interval2 = Float(iv.fifth)", in: follower), 1)
        XCTAssertEqual(codeOccurrences(of: "if enabled { startTicking() } else { stopTicking() }",
                                       in: follower), 1,
                       "the ~10 Hz task runs ONLY while following — no idle timer")
        XCTAssertEqual(codeOccurrences(of: "c.harmonizer.interval1 = harmInterval1", in: fx), 1,
                       "COUNTERWEIGHT: the VM didSet fan-out survives — it is the "
                       + "restore path AND the manual path; a second loop in the "
                       + "re-fan would be a second spelling of it (#416)")
    }

    // MARK: - helpers (§0/§2 — one stripper, skip on no tree, FAIL on a moved anchor)

    private struct FollowAnchorMissing: Error { let reason: String }

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
            throw FollowAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }
}
