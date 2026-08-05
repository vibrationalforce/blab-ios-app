// LivelinessMovesTheStillnessGateTests.swift
// Echoel — #419. The other half of #418: the Liveliness knob reached the MELODIC path only,
// and the genre a first-run user actually hears is not on it.
//
// ⭐ THE PREMISE, AND IT IS A COUNT, NOT AN IMPRESSION. #418 wired `mood.liveliness` to the
// two live density decisions in `composeHarmonic` — the arp step and the inner pulse gap.
// BOTH sit behind `!profile.sustained`. Eight of the sixteen genres in `MusicStyle.offered`
// are Flächen, and `.selfObservation` — the shipped default, the meditative core of the
// product — is one of them. So the slice that was written to end "die Kompositionen klingen
// gleich" left the default genre exactly as inert as it found it. #418's own header says so
// and files it here rather than hiding it; this file is that follow-up.
//
// ⭐ WHERE THE KNOB LANDS ON A FLÄCHE. A sustained genre's movement does not live in note
// density — it lives in `heartbeatOnsets`: an arousal GATE that decides held-vs-pulsing, and
// two stride steps above it (dotted lilt → tresillo → busier tresillo). Those three literals
// (0.5, 0.68, 0.82) now go through the SAME `densityThreshold` shape #418 introduced, with a
// smaller `stillnessThresholdSpan`. One shape, two spans, five comparisons in total.
//
// ⛔ WHY A SMALLER SPAN — A FOUNDER DOCTRINE, NOT A TASTE. On the melodic path the knob decides
// how densely an already-moving texture is filled. Here it decides whether the Fläche moves AT
// ALL. The 2026-07-09 "Flächen still" call is what the founder liked about the meditative
// genres, and `heartbeatOnsets`' own doc states it as "calm = still, active = alive". So the
// knob may bring movement FORWARD and must never abolish the hold. `testTheHoldIsNever
// AbolishedAtRest` is the assertion that keeps that promise honest, and it sweeps rather than
// samples — a later re-tune of the span would otherwise pass every hand-written case and still
// make a resting body pulse.
//
// ⛔ HONEST LIMITS — what this file CANNOT do.
//   · "Does it sound better", and even "is 0.2 the right travel", are listening calls. What is
//     provable here is that the knob is no longer inert on the default genre, that the neutral
//     setting is bit-identical, and that the hold survives at rest.
//   · The BAND is narrow and that is the point, not a weakness: the shipped default fixture's
//     `busy` (0.4932) happens to sit between the fully-live gate (0.4) and today's (0.5). That
//     is why `testTheDefaultGenreTakeActuallyChanges` recomputes `busy` from
//     `BioComposer.musicalState` and asserts the band FIRST. Without that, a future change to
//     the arousal maths would move `busy` out of the band and the take-level test would go
//     green while proving nothing — the #408 failure mode.
//   · `chordOnsets` gains the parameter but only its `.sustained` delegation consumes it. The
//     skank/stab/comp grids keep their own literals deliberately: those genres already respond
//     through #418's melodic decisions, and their grid IS the genre's identity.
//   · The `liveliness` parameters default to 0.5 so the pure-core tests that predate the knob
//     keep compiling as "at the neutral setting". That default is the one real risk in this
//     slice — a future third caller would silently get neutral — which is exactly what
//     `testEveryProductionCallSitePassesTheKnob` exists to catch.

import Foundation
import XCTest
@testable import Echoelmusic

final class LivelinessMovesTheStillnessGateTests: XCTestCase {

    // MARK: - The premise

    /// Pins the two facts that make #419 a defect rather than a preference. If a later curation
    /// change makes the default genre arpeggiated or non-sustained, this slice's reasoning
    /// changes and this test says so before the rest of the file misleads anyone.
    func testTheDefaultGenreIsAFlaecheTheMelodicKnobCannotReach() {
        let profile = MusicStyle.selfObservation.harmonicProfile
        XCTAssertTrue(profile.sustained,
                      "#419's premise: the shipped default genre is a Fläche")
        XCTAssertFalse(profile.arpeggiated,
                       "…and not arpeggiated, so it takes the chordOnsets path, not arpStep")
        XCTAssertEqual(MusicStyle.selfObservation.chordArticulation, .sustained,
                       "…which delegates to heartbeatOnsets — the path this slice wires")

        let sustainedOffered = MusicStyle.offered.filter { $0.harmonicProfile.sustained }
        XCTAssertGreaterThanOrEqual(
            sustainedOffered.count, 2,
            "A floor, not a hard count: #419 exists because MANY offered genres are Flächen. " +
            "A hard number here would turn the founder's next curation edit into a red gate.")
        XCTAssertTrue(sustainedOffered.contains(.selfObservation))
    }

    // MARK: - The neutral setting is exactly today

    /// ⭐ THE ONE THAT MAKES THE CHANGE SAFE TO SHIP, and it is stricter than its #418 twin
    /// because this path decides silence-vs-movement rather than sparse-vs-dense. At the
    /// `MoodProfile` default every one of the three shifted literals must come back EXACTLY —
    /// not "close enough". Anything else re-tunes every Fläche for every user who never touched
    /// the knob.
    func testTheNeutralSettingReproducesAllThreeShippedLiterals() {
        let span = BioComposer.stillnessThresholdSpan
        XCTAssertEqual(BioComposer.densityThreshold(base: 0.5, liveliness: 0.5, span: span), 0.5)
        XCTAssertEqual(BioComposer.densityThreshold(base: 0.68, liveliness: 0.5, span: span), 0.68)
        XCTAssertEqual(BioComposer.densityThreshold(base: 0.82, liveliness: 0.5, span: span), 0.82)
        XCTAssertEqual(MoodProfile().liveliness, 0.5,
                       "The bit-identity above is only load-bearing while 0.5 IS the default")
    }

    /// The gate itself, read through its own function rather than through the arithmetic — a
    /// correct threshold wired into nothing would pass the test above and change no take.
    func testTheGateAtTheNeutralSettingIsTheShippedArousalLine() {
        XCTAssertTrue(BioComposer.heartbeatActive(energy: 0.5, secLen: 16, liveliness: 0.5))
        XCTAssertFalse(BioComposer.heartbeatActive(energy: 0.49, secLen: 16, liveliness: 0.5))
        XCTAssertFalse(BioComposer.heartbeatActive(energy: 0.9, secLen: 3, liveliness: 1.0),
                       "The length floor is not the knob's to move — a 3-step section cannot " +
                       "carry a pulse at any liveliness")
    }

    // MARK: - The knob actually moves the hold

    /// The core behaviour. One body, one section, three knob positions — and the same body must
    /// hold at the still end and move at the lively end.
    func testALivelyMoodBreaksTheHoldThatAStillOneKeeps() {
        func onsetCount(_ liveliness: Float) -> Int {
            BioComposer.heartbeatOnsets(secStart: 0, secLen: 16, energy: 0.45,
                                        syncopation: 0, liveliness: liveliness).count
        }
        XCTAssertEqual(onsetCount(0.5), 1, "today: busy 0.45 is below the 0.5 gate → held")
        XCTAssertEqual(onsetCount(0.0), 1, "stiller than today → still held")
        XCTAssertGreaterThan(onsetCount(1.0), 1,
                             "livelier than today → the same body breaks the hold")
    }

    /// The ladder must move WITH the gate, not disagree with it. A body already past the gate
    /// gets a busier grouping as the knob rises — otherwise "livelier" would mean two different
    /// things depending on where the body happened to sit.
    func testTheStrideLadderMovesWithTheGate() {
        let neutral = BioComposer.heartbeatOnsets(secStart: 0, secLen: 16, energy: 0.6,
                                                  syncopation: 0, liveliness: 0.5)
        let lively = BioComposer.heartbeatOnsets(secStart: 0, secLen: 16, energy: 0.6,
                                                 syncopation: 0, liveliness: 1.0)
        XCTAssertGreaterThan(neutral.count, 1, "0.6 already clears the neutral gate")
        XCTAssertGreaterThan(lively.count, neutral.count,
                             "past the gate, a livelier mood reaches the tresillo grouping sooner")
    }

    /// ⭐ THE DOCTRINE GUARD. Swept, not sampled: the fix must be incapable of making a RESTING
    /// body pulse at any knob position. A hand-written pair would pass a later span re-tune that
    /// broke exactly this.
    func testTheHoldIsNeverAbolishedAtRest() {
        for i in 0...20 {
            let liveliness = Float(i) / 20
            let onsets = BioComposer.heartbeatOnsets(secStart: 0, secLen: 16, energy: 0.35,
                                                     syncopation: 0, liveliness: liveliness)
            XCTAssertEqual(onsets.count, 1,
                           "liveliness \(liveliness): a resting body must keep the still Fläche")
            XCTAssertEqual(onsets.first?.len, 16, "…and it must be the WHOLE section, held")
        }
    }

    /// The mirror image, and the reason the knob biases rather than vetoes: at the stillest
    /// setting an aroused body must still be able to move the pad. Without this, "still" would
    /// silently become a mute switch for the whole heartbeat layer.
    func testAnArousedBodyStillMovesAtTheStillestSetting() {
        let onsets = BioComposer.heartbeatOnsets(secStart: 0, secLen: 16, energy: 0.85,
                                                 syncopation: 0, liveliness: 0.0)
        XCTAssertGreaterThan(onsets.count, 1,
                             "the knob biases when movement starts; it does not veto movement")
    }

    /// Same law as its #418 twin, and it is here because the SAME mistake was made there: a
    /// non-finite liveliness (a bad weather sample reaching `WeatherMood.blend`) must read as
    /// the neutral 0.5, never as 0 — `clamped(to:)` maps NaN to the LOWER bound, which on this
    /// path would freeze every Fläche into a permanent hold.
    func testANonFiniteLivelinessReadsAsTodaysStillnessLadder() {
        let reference = BioComposer.heartbeatOnsets(secStart: 0, secLen: 16, energy: 0.7,
                                                    syncopation: 0.1, liveliness: 0.5)
        for bad: Float in [.nan, .infinity, -.infinity] {
            let onsets = BioComposer.heartbeatOnsets(secStart: 0, secLen: 16, energy: 0.7,
                                                     syncopation: 0.1, liveliness: bad)
            XCTAssertEqual(onsets.count, reference.count, "non-finite \(bad) must read as neutral")
            XCTAssertEqual(onsets.map(\.start), reference.map(\.start))
        }
    }

    // MARK: - The take, not just the arithmetic

    /// ⭐ THE END-TO-END ONE. A correct pure core with no reachable caller is the same defect
    /// with more steps — this repo has paid for that shape more than once. Two shipped mood
    /// preset extremes (0.05 … 0.92), identical body, identical seed, identical genre: the
    /// DEFAULT genre's take must differ.
    func testTheDefaultGenreTakeActuallyChanges() {
        // The band assertion comes FIRST and is not decoration. This fixture only exercises the
        // gate because its `busy` happens to sit between the fully-live gate and today's. If a
        // later change to the arousal maths moves it out, the comparison below could pass for
        // an unrelated reason — or fail while the knob works fine. Either way the diagnosis
        // must be visible in the failure message, not guessed at.
        let state = BioComposer.musicalState(coherence: 0.45, hrvNormalized: 0.45,
                                             heartRateBPM: 96)
        let livelyGate = BioComposer.densityThreshold(base: 0.5, liveliness: 0.92,
                                                      span: BioComposer.stillnessThresholdSpan)
        let stillGate = BioComposer.densityThreshold(base: 0.5, liveliness: 0.05,
                                                     span: BioComposer.stillnessThresholdSpan)
        XCTAssertTrue(state.busy > livelyGate && state.busy < stillGate,
                      "fixture busy=\(state.busy) must sit between the lively gate " +
                      "(\(livelyGate)) and the still one (\(stillGate)) for this test to mean " +
                      "anything — re-pick the body, do not relax the assertion")

        let still = BioComposer.compose(Self.input(liveliness: 0.05))
        let lively = BioComposer.compose(Self.input(liveliness: 0.92))
        XCTAssertNotEqual(Self.fingerprint(still), Self.fingerprint(lively),
                          "#419: the Liveliness knob must reach the SHIPPED DEFAULT genre")
    }

    // MARK: - Wiring

    /// The scan that earns the defaulted parameter. Every production call to a function that now
    /// takes the knob must pass it — a site that quietly took the neutral default would be the
    /// #418 defect back again, one function deeper, and nothing would look wrong in a diff.
    ///
    /// Comments are stripped first: this file's own vocabulary appears in the doc blocks around
    /// each of these calls, and a scan satisfied by prose proves nothing (the #367 trap).
    func testEveryProductionCallSitePassesTheKnob() throws {
        let lines = try codeLines("Sources/Echoelmusic/Sequencer/BioComposer.swift")
        var checked = 0
        for (i, line) in lines.enumerated() {
            let isCall = (line.contains("chordOnsets(") || line.contains("heartbeatActive(")
                          || line.contains("heartbeatOnsets("))
            guard isCall, !line.contains("static func") else { continue }
            // Follow the BINDING, not the physical line (#413): this file hoists call arguments
            // onto continuation lines deliberately, so anchoring on one line would be red on
            // correct code.
            let end = min(i + 4, lines.count - 1)
            let statement = lines[i...end].joined(separator: "\n")
            XCTAssertTrue(statement.contains("liveliness:"),
                          "call at code-line \(i) does not pass the knob:\n\(statement)")
            checked += 1
        }
        XCTAssertGreaterThanOrEqual(checked, 4,
                                    "expected at least the three chordOnsets sites plus the " +
                                    "trap-pedal heartbeatActive; found \(checked)")
    }

    // MARK: - Fixtures

    private static func input(liveliness: Float) -> BioComposer.Input {
        var mood = MoodProfile()
        mood.liveliness = liveliness
        return BioComposer.Input(heartRateBPM: 96, hrvNormalized: 0.45, coherence: 0.45,
                                 breathPhase: 0.3, breathDepth: 0.5,
                                 key: MusicalKey(root: 0, scale: .minor),
                                 style: .selfObservation,
                                 mode: .flowFree, lockedTempo: 0, mood: mood, seed: 424_242)
    }

    /// Order-sensitive note identity. Deliberately not `notes.count`: the knob can move WHICH
    /// steps are voiced without moving how many, and a count-only fingerprint would call that
    /// "no change" and pass a half-dead knob.
    private static func fingerprint(_ c: BioComposition) -> String {
        c.notes.map { "\($0.startTick):\($0.pitch):\($0.lengthTicks)" }.joined(separator: "|")
    }

    /// Non-empty lines with `//` comments removed — byte-for-byte the helper
    /// `LivelinessReachesTheDensityDecisionTests` uses, including the quote-parity check (a
    /// `//` inside a string literal is not a comment) and the blank-line drop, which is what
    /// makes a fixed-size binding window meaningful.
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
