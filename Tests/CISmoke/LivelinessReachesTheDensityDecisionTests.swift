// LivelinessReachesTheDensityDecisionTests.swift
// Echoel — #418. The Mood panel's Liveliness knob had THREE writers and ZERO reachable
// readers.
//
// ⭐ WHY THIS IS A DEFECT AND NOT A DESIGN. `MoodProfile.liveliness` documents itself as
// "0 sparse/still … 1 busy/active (density)", and the struct's own doc points at
// `composeHarmonic` for the mapping. But every read of it inside the composer sits either in
// the callerless `ambientMelody` or inside `if profile.leadDensity > 0`
// (`BioComposer.swift`, the block containing `lively`, `liftP` and `ornamentP`) — and all 33
// shipped genres set `leadDensity: 0.0`, an invariant `LeadRoleAbsenceTests` pins in this same
// bundle. So the documented mapping was never reachable. Fifteen shipped mood presets carry
// deliberately spread values (0.05 … 0.92) and, until this slice, all fifteen behaved
// identically in this respect — which is the founder's "die Kompositionen klingen gleich"
// complaint at its own source.
//
// ⭐ WHAT THE FIX MAY AND MAY NOT DO. Liveliness now shifts the THRESHOLD at which the two live
// density decisions (the arp step and the inner pulse gap) flip from their sparse step to their
// dense one. It does NOT introduce a new step. That bound is the whole safety argument: the
// worst a knob move can do is pick the other of the two values the genre ALREADY ships, so it
// cannot produce a texture the genre could not already make. And liveliness at its default of
// 0.5 leaves the threshold bit-identical, so the code's own default path is provably unchanged.
//
// ⛔ HONEST LIMITS.
//   · "Does it sound better" is a listening test and this file does not claim it. What it can
//     prove is that the knob is no longer INERT — that two different liveliness values produce
//     two different takes from otherwise identical input.
//   · The shift is bounded, not tuned. `livelinessThresholdSpan` was chosen so the full knob
//     travel covers ±0.15 of the busy axis; whether that is the musically right amount is a
//     founder's ear, and the constant is one line to change.
//   · This does NOT close the whole of #418. `WeatherMood.blend` also steers `liveliness`, so
//     the weather half of #349 becomes audible through this same path — but proving THAT end
//     to end needs the weather provider, which this bundle deliberately does not run.

import Foundation
import XCTest
@testable import Echoelmusic

final class LivelinessReachesTheDensityDecisionTests: XCTestCase {

    // MARK: - The pure threshold

    /// ⭐ THE ONE THAT MAKES THE CHANGE SAFE TO SHIP. At the default the threshold must be the
    /// OLD literal, exactly — not "close enough". Anything else silently re-tunes every genre
    /// for every user who never touched the knob.
    func testTheDefaultLivelinessIsExactlyTodaysThreshold() {
        XCTAssertEqual(BioComposer.densityThreshold(base: 0.6, liveliness: 0.5), 0.6, """
        liveliness 0.5 no longer resolves to the arp's original 0.6 threshold.

        0.5 is `MoodProfile`'s init default, so this is the value in play for anyone who has \
        not touched the knob and for every genre read straight from its profile. If this drifts, \
        the whole shipped catalogue changes density without anyone asking for it.
        """)
        XCTAssertEqual(BioComposer.densityThreshold(base: 0.7, liveliness: 0.5), 0.7,
                       "same for the inner pulse's original 0.7 threshold")
    }

    /// The direction has to match the label. "Liveliness" up means BUSIER, which means the
    /// threshold `busy` has to clear must come DOWN. Getting this backwards would be a knob
    /// that works and lies, which this repo rates worse than a knob that does nothing.
    func testTheKnobMovesTheThresholdInTheDirectionItsLabelPromises() {
        let still = BioComposer.densityThreshold(base: 0.6, liveliness: 0.0)
        let mid = BioComposer.densityThreshold(base: 0.6, liveliness: 0.5)
        let lively = BioComposer.densityThreshold(base: 0.6, liveliness: 1.0)
        XCTAssertGreaterThan(still, mid, "liveliness 0 must make density HARDER to reach")
        XCTAssertLessThan(lively, mid, "liveliness 1 must make density EASIER to reach")
    }

    /// ⭐ THE COUNCIL'S MITIGATION, PINNED. The threshold must stay strictly inside 0…1 across
    /// the whole knob travel. Outside that range one of the two branches becomes unreachable and
    /// the knob stops being a shift and starts being a switch that deletes a genre's other half.
    func testTheShiftNeverStrandsEitherBranch() {
        for base in [Float(0.6), Float(0.7)] {
            for step in 0...100 {
                let l = Float(step) / 100
                let t = BioComposer.densityThreshold(base: base, liveliness: l)
                XCTAssertGreaterThan(t, 0, "threshold \(t) at liveliness \(l) makes 'dense' unconditional")
                XCTAssertLessThan(t, 1, "threshold \(t) at liveliness \(l) makes 'dense' unreachable")
                XCTAssertLessThanOrEqual(abs(t - base), BioComposer.livelinessThresholdSpan / 2 + 1e-6,
                                         "the shift left its declared bound at liveliness \(l)")
            }
        }
    }

    /// Non-finite and out-of-range input must not escape the bound. `WeatherMood.blend` writes
    /// this field from a provider, and a bio/weather boundary is exactly where a NaN arrives.
    func testGarbageLivelinessStaysInsideTheBound() {
        for bad in [Float.nan, .infinity, -.infinity, -5, 5] {
            let t = BioComposer.densityThreshold(base: 0.6, liveliness: bad)
            XCTAssertTrue(t.isFinite, "threshold went non-finite on liveliness \(bad)")
            XCTAssertLessThanOrEqual(abs(t - 0.6), BioComposer.livelinessThresholdSpan / 2 + 1e-6,
                                     "threshold escaped its bound on liveliness \(bad)")
        }
    }

    // MARK: - It reaches a real take

    /// ⭐ THE POINT OF THE WHOLE SLICE. A correct pure function with no caller is the same defect
    /// with more steps — #403 Slice 0 is filed in CLAUDE.md for exactly that. So: same seed, same
    /// body, same genre, ONLY liveliness differs, and at least one offered genre must produce a
    /// different take. Swept across the catalogue rather than asserted on one genre, because
    /// which genres are `arpeggiated` (and therefore reach the arp threshold at all) is a
    /// curation decision that has changed repeatedly.
    func testTwoLivelinessSettingsProduceDifferentTakes() {
        var differing: [MusicStyle] = []
        for style in MusicStyle.offered {
            let still = BioComposer.compose(Self.input(style: style, liveliness: 0.05))
            let lively = BioComposer.compose(Self.input(style: style, liveliness: 0.92))
            if Self.fingerprint(still) != Self.fingerprint(lively) { differing.append(style) }
        }
        XCTAssertFalse(differing.isEmpty, """
        NO offered genre reacts to liveliness — the knob is inert again.

        This is the exact #418 state: three writers (the Mood knob, the mood-pad drag, \
        `WeatherMood.blend`) and no reachable reader. If a refactor moved the density decision, \
        move this assertion with it rather than deleting it; if liveliness was deliberately \
        retired, delete the knob in the SAME commit so no control lies to the user.

        Swept \(MusicStyle.offered.count) offered genres at liveliness 0.05 vs 0.92 with an \
        identical body and seed.
        """)
    }

    /// The mirror of the test above, and the one that keeps the change honest for everyone who
    /// never touches the knob: at the default, a take must be reproducible from the same seed —
    /// liveliness must not have leaked randomness into the path while wiring it up.
    func testTheDefaultTakeIsStillDeterministic() {
        for style in MusicStyle.offered {
            let a = BioComposer.compose(Self.input(style: style, liveliness: 0.5))
            let b = BioComposer.compose(Self.input(style: style, liveliness: 0.5))
            XCTAssertEqual(Self.fingerprint(a), Self.fingerprint(b),
                           "\(style.rawValue) is no longer reproducible from its seed")
        }
    }

    // MARK: - The wiring

    /// Both live call sites must ASK the knob. A source scan, because the behavioural test above
    /// passes as soon as ONE of the two sites is wired — and a half-wired knob that moves the arp
    /// but not the pulse is the kind of partial answer this bundle exists to refuse.
    func testBothDensityDecisionsAskTheKnob() throws {
        let lines = try codeLines("Sources/Echoelmusic/Sequencer/BioComposer.swift")
        let arp = lines.filter { $0.contains("let arpStep =") }
        let pulse = lines.filter { $0.contains("let pulseGap =") }
        XCTAssertEqual(arp.count, 1, "expected exactly one `let arpStep =`, found \(arp.count)")
        XCTAssertEqual(pulse.count, 1, "expected exactly one `let pulseGap =`, found \(pulse.count)")
        for (name, hits) in [("arpStep", arp), ("pulseGap", pulse)] {
            guard let line = hits.first else { continue }
            XCTAssertTrue(line.contains("densityThreshold("), """
            `\(name)` no longer asks `densityThreshold`, so it compares `busy` against a bare \
            literal again and the Liveliness knob stops reaching it.

            The line found was:
            \(line)
            """)
        }
    }

    // MARK: - Fixtures

    /// One body, one seed, one key — so the ONLY difference between two compositions in this
    /// file is the value under test.
    private static func input(style: MusicStyle, liveliness: Float) -> BioComposer.Input {
        var mood = MoodProfile()
        mood.liveliness = liveliness
        return BioComposer.Input(heartRateBPM: 96, hrvNormalized: 0.45, coherence: 0.45,
                                 breathPhase: 0.3, breathDepth: 0.5,
                                 key: MusicalKey(root: 0, scale: .minor), style: style,
                                 mode: .flowFree, lockedTempo: 0, mood: mood, seed: 424_242)
    }

    /// Note identity, order-sensitive. Deliberately NOT just `notes.count`: liveliness can move
    /// WHICH steps are voiced without moving how many, and a count-only fingerprint would call
    /// that "no change" and pass a half-dead knob. `Note.id` is a fresh UUID per composition, so
    /// comparing the values themselves would report a difference for every pair — the reason
    /// this reduces to the three musical fields rather than using `Equatable`.
    private static func fingerprint(_ c: BioComposition) -> String {
        c.notes.map { "\($0.startTick):\($0.pitch):\($0.lengthTicks)" }.joined(separator: "|")
    }

    /// Non-empty lines with comments removed — the source scan above must not be satisfied by the
    /// long doc block that sits directly above `arpStep` and names it repeatedly.
    private func codeLines(_ path: String) throws -> [String] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("source tree not present — this scan cannot report a green")
        }
        let text = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        var out: [String] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(raw)
            if let r = line.range(of: "//") {
                let before = line[line.startIndex..<r.lowerBound]
                if before.filter({ $0 == "\"" }).count % 2 == 0 { line = String(before) }
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { out.append(trimmed) }
        }
        return out
    }
}
