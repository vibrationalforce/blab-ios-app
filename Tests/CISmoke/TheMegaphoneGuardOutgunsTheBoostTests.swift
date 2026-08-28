// TheMegaphoneGuardOutgunsTheBoostTests — pins #829, Megaphone Mode.
//
// FOUNDER ASK (2026-08-25, verbatim): "On Device mic directly Verstärkung mit
// intelligenter Rückkopplungsunterdrückung: Megaphone Mode." The build: the monitored
// mic is boosted by `AudioEngine.megaphoneBoostDB` through the EXISTING notchEQ's
// `globalGain` (a parameter on a node already in the monitor chain — no graph change,
// the music never passes it), and while boosted the feedback guard is TIGHTENED:
// lower ceiling (reacts earlier) and duck authority of
// `FeedbackGuard.defaultMaxReductionDB + megaphoneBoostDB`.
//
// THE AUTHORITY LAW this file exists for: the guard must always be able to undo MORE
// than the boost. If the duck's clamp were only the default 12 dB against a 12 dB
// boost, an amplified howl would saturate at unity gain and never come down.
//
// Claim kinds per §1: tests 1–3 are END-TO-END BEHAVIOUR (FeedbackGuard is public,
// pure, Foundation-only); tests 4–5 are SOURCE-TEXT SCANS. The audible outcome —
// megaphone range, duck musicality on a real speaker — is a DEVICE PROBE and open.
//
// #364: nothing here pins the boost's VALUE (a designer may retune 12); pinned are
// RELATIONS (authority > boost, earlier ceiling) and derivations (#416 — the copy and
// the duck call derive from the one constant instead of restating a literal).

import Foundation
import XCTest
@testable import Echoelmusic

final class TheMegaphoneGuardOutgunsTheBoostTests: XCTestCase {

    private var megaphoneAuthorityDB: Float {
        FeedbackGuard.defaultMaxReductionDB + AudioEngine.megaphoneBoostDB
    }

    // MARK: - 1. The duck can undo more than the boost (END-TO-END)

    func testARunawayUnderBoostIsDuckedDeeperThanTheBoost() {
        // A classic howl signature: rising fast, well over the megaphone ceiling.
        let duck = FeedbackGuard.gainReductionDB(rmsHistory: [0.5, 0.8, 0.99],
                                                 ceiling: AudioEngine.megaphoneDuckCeiling,
                                                 maxReductionDB: megaphoneAuthorityDB)
        XCTAssertGreaterThan(duck, AudioEngine.megaphoneBoostDB, """
            A hard runaway under Megaphone Mode ducks LESS than the boost itself \
            (\(duck) dB vs +\(AudioEngine.megaphoneBoostDB) dB). The net gain stays \
            positive and the howl keeps feeding itself — the authority law is broken. \
            Either the ceiling rose, the authority derivation lost a term, or the \
            detector's proportional curve changed; re-derive before shipping.
            """)
        XCTAssertLessThanOrEqual(duck, megaphoneAuthorityDB,
                                 "The duck exceeded its own clamp — the clamp is broken.")
    }

    // MARK: - 2. Boosted, the guard reacts EARLIER (END-TO-END)

    func testTheBoostedCeilingFiresWhereTheDefaultStaysQuiet() {
        let history: [Float] = [0.5, 0.8, 0.84]   // rising, just under the default ceiling
        let boosted = FeedbackGuard.gainReductionDB(rmsHistory: history,
                                                    ceiling: AudioEngine.megaphoneDuckCeiling,
                                                    maxReductionDB: megaphoneAuthorityDB)
        let normal = FeedbackGuard.gainReductionDB(rmsHistory: history)
        XCTAssertGreaterThan(boosted, 0, """
            A rising level between the two ceilings no longer ducks under Megaphone \
            Mode — the 'listens earlier' half of the tightening is gone.
            """)
        XCTAssertEqual(normal, 0, """
            The same level now ducks WITHOUT the boost — the default guard got \
            stricter, which would audibly pump ordinary (unboosted) monitoring. If \
            that is a deliberate retune of the default ceiling, update this test and \
            the FeedbackGuard doc in the same commit.
            """)
        XCTAssertLessThan(AudioEngine.megaphoneDuckCeiling, 0.84, """
            The megaphone ceiling rose past this test's fixture — the 'earlier' \
            relation can no longer be shown with these values. Retune the fixture \
            together with the ceiling, and keep ceiling < default ceiling.
            """)
    }

    // MARK: - 3. Quiet boosted speech is never ducked (END-TO-END)

    func testSpeechBelowTheBoostedCeilingIsUntouched() {
        let duck = FeedbackGuard.gainReductionDB(rmsHistory: [0.5, 0.6, 0.65],
                                                 ceiling: AudioEngine.megaphoneDuckCeiling,
                                                 maxReductionDB: megaphoneAuthorityDB)
        XCTAssertEqual(duck, 0, """
            Rising-but-quiet speech is ducked under Megaphone Mode. The guard exists \
            for runaway feedback, not for a voice getting louder — a megaphone that \
            pulls your voice down while you speak up is broken by definition.
            """)
    }

    // MARK: - 4. The wiring derives, applies and resets the boost (SOURCE SCAN)

    private func code(_ repoRelative: String) -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(repoRelative)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: \(repoRelative) could not be read — fail, not skip (§4)")
            return ""
        }
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    func testTheEngineAppliesAndResetsTheBoostAndDerivesTheAuthority() {
        let engine = code("Sources/Echoelmusic/Audio/AudioEngine.swift")
        guard !engine.isEmpty else { return }
        XCTAssertEqual(engine.components(
            separatedBy: "notchEQ.globalGain = megaphoneMode ? Self.megaphoneBoostDB : 0")
            .count - 1, 2, """
            The boost is no longer applied at exactly its two sites (the megaphoneMode \
            didSet and the monitoring-ON path). One site missing means a stale boost \
            state after an OFF→ON cycle; a third site is a second owner.
            """)
        // #367: the bare needle `notchEQ.globalGain = 0` also matches the notch-attach
        // INIT line, and `isInputMonitoring = false` matches the DECLARATION first —
        // both anchors were tried and both were the #367 prototype. `setVoiceTune(false)`
        // occurs exactly ONCE, at the end of the OFF path's reset block (driven on both
        // trees before shipping): the reset must sit in the window just BEFORE it.
        if let offTail = engine.range(of: "setVoiceTune(false)") {
            let start = engine.index(offTail.lowerBound,
                                     offsetBy: -400,
                                     limitedBy: engine.startIndex) ?? engine.startIndex
            let offWindow = String(engine[start..<offTail.lowerBound])
            XCTAssertTrue(offWindow.contains("notchEQ.globalGain = 0"), """
                The monitoring-OFF path no longer resets globalGain — the boost would \
                survive into the next monitoring session invisibly. (The init-time \
                reset at notch attach is a different site and does not cover this.)
                """)
        } else {
            XCTFail("The monitoring-OFF anchor `setVoiceTune(false)` is gone — "
                    + "re-anchor this claim in the same commit (§4).")
        }
        guard let duckSite = engine.range(of: "let duckDB = megaphoneMode") else {
            XCTFail("The megaphone-aware duck call is gone — the guard runs at default "
                    + "depth against a boosted signal, breaking the authority law.")
            return
        }
        let window = String(engine[duckSite.lowerBound...].prefix(600))
        XCTAssertTrue(window.contains("FeedbackGuard.defaultMaxReductionDB")
                      && window.contains("+ Self.megaphoneBoostDB")
                      && window.contains("+ voicePresenceDB"), """
            The duck authority is no longer DERIVED (default + boost + presence, \
            #856b). A literal here is a second spelling (#416) that silently \
            decouples from a retuned boost, and a derivation missing the presence \
            term lets the stacked boost (megaphone + band-4 peak) outgrow the \
            guard's worst-case depth — the exact path back to a guard that cannot \
            undo the amplification.
            """)
    }

    // MARK: - 5. The door exists and its copy derives the number (SOURCE SCAN)

    func testTheToggleExistsAndItsCopyDerivesTheBoost() {
        let picker = code("Sources/Echoelmusic/Studio/AudioInputPickerView.swift")
        guard !picker.isEmpty else { return }
        XCTAssertTrue(picker.contains("audioEngine.megaphoneMode"), """
            The Megaphone toggle is gone from the Input sheet — a mode nothing can \
            set is the doorless-state defect (#204): the capability silently vanishes.
            """)
        XCTAssertTrue(picker.contains("\\(Int(AudioEngine.megaphoneBoostDB)) dB"), """
            The toggle's copy no longer derives the boost from the one constant — a \
            re-typed number goes stale the day the boost is retuned (#416).
            """)
    }
}
