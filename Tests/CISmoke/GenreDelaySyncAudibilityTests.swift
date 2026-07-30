// GenreDelaySyncAudibilityTests.swift
// Echoel — a notated note division that can never be heard at any tempo the genre allows is a
// lie in the source, and it is the mechanism behind one half of "die Genres klingen gleich".
// BLOCKING bundle (Tests/CISmoke), because the other suite cannot fail a merge (#208).
//
// THE DEFECT. `GenreFXPreset.apply(to:bpm:)` resolves `delaySync` against the live BPM and then
// CLAMPS the result to the delay line's 2.0 s capacity. Two genres authored divisions whose
// resolved time was over that ceiling at EVERY tempo in their own `tempoRange`:
//
//   · deepDrone      `.whole`        40…58 BPM → 6.00…4.14 s  → always clamped
//   · contemplation  `.half, .dotted` 44…66 BPM → 4.09…2.73 s  → always clamped
//
// So both played a flat 2.0 s echo that neither tracked tempo nor matched what the source said —
// and landed on the SAME 2.0 s as `selfObservation` and `esotericMeditation`. Four of the offered
// drum-free genres shared one echo time, on an axis their own comments claimed differentiated
// them. Fixed by re-authoring the two divisions (deepDrone `.half, .triplet`, contemplation
// `.quarter`) — NOT by raising the ceiling, which is load-bearing for
// `PolySynthVoice.idleFrameThreshold` (see `GenreFXPreset.maxDelaySeconds`' own doc).
//
// WHAT THIS FILE CANNOT CATCH, stated so the coverage is not overread:
//   · whether the new echo times sound good — that is a founder listening call;
//   · `FXCharacter` presets, which have no tempo window of their own (they are stamped at
//     whatever BPM is running) so "inaudible at every allowed tempo" is undefined for them;
//   · a genre whose division is audible in only a sliver of its window. Test 3 bounds how many
//     genres may be clamped AT THEIR DEFAULT TEMPO, which is the tempo a fresh take starts on,
//     but a window is not swept for the untouched presets on purpose — tightening that would
//     force a retune of shipped presets that already sound as authored.

import Foundation
import XCTest
@testable import Echoelmusic

final class GenreDelaySyncAudibilityTests: XCTestCase {

    /// The stamped delay time and the time the preset ASKED for, at one BPM.
    /// Measured through `apply` rather than by reading the private ceiling constant — the
    /// observable form, and it tracks the constant automatically if it ever moves.
    private func stamped(_ style: MusicStyle, bpm: Double) -> (got: Double, authored: Double) {
        let preset = style.fxPreset
        let chain = EchoelFXChain(sampleRate: 48000)
        preset.apply(to: chain, bpm: bpm)
        return (Double(chain.delay.timeSeconds), preset.delaySync.seconds(bpm: bpm))
    }

    /// True when the chain refused the authored time at `bpm`.
    private func isClamped(_ style: MusicStyle, bpm: Double) -> Bool {
        let r = stamped(style, bpm: bpm)
        return r.got < r.authored - 1e-4
    }

    // MARK: - The invariant

    /// ⛔ THE ONE THAT MATTERS. Every genre's division must resolve un-clamped at the FASTEST
    /// tempo its own window allows — the tempo at which the resolved time is SHORTEST, so if it
    /// does not fit there it fits nowhere and the notated value is unreachable.
    ///
    /// Swept over `allCases`, not `offered`: a genre curated out of the picker today can be
    /// re-offered tomorrow (seven of them are waiting), and it should not carry a dead division
    /// in when it comes.
    func testNoGenresDelayDivisionIsInaudibleAtEveryTempoItAllows() {
        for style in MusicStyle.allCases {
            let preset = style.fxPreset
            guard preset.delayEnabled else { continue }

            let fastest = style.tempoRange.upperBound
            let r = stamped(style, bpm: fastest)
            XCTAssertEqual(r.got, r.authored, accuracy: 1e-4,
                "\(style): `\(preset.delaySync.label)` is \(String(format: "%.3f", r.authored)) s "
                + "even at its FASTEST allowed tempo (\(fastest) BPM), so the delay-line ceiling "
                + "truncates it to \(String(format: "%.3f", r.got)) s at every tempo in "
                + "\(style.tempoRange) — the notated division can never be heard and the genre "
                + "sits on the ceiling next to every other genre that overruns it. Author a "
                + "SHORTER division; do not raise the ceiling (see GenreFXPreset.maxDelaySeconds).")
        }
    }

    /// The two genres this slice repaired, held to the STRONGER bar the fix actually met: not
    /// merely audible somewhere, but un-clamped across the ENTIRE window, so the echo tracks
    /// tempo everywhere a body can take them. Swept at 1 BPM, which covers both ends.
    func testTheTwoRepairedGenresResolveUnclampedAcrossTheirEntireWindow() {
        for style in [MusicStyle.deepDrone, .contemplation] {
            let range = style.tempoRange
            var bpm = range.lowerBound
            while bpm <= range.upperBound {
                let r = stamped(style, bpm: bpm)
                XCTAssertEqual(r.got, r.authored, accuracy: 1e-4,
                    "\(style) at \(bpm) BPM: authored \(String(format: "%.3f", r.authored)) s, "
                    + "stamped \(String(format: "%.3f", r.got)) s. This genre was re-authored "
                    + "specifically so the clamp never fires inside its own window — a division "
                    + "that clamps again means the window moved or the division did.")
                bpm += 1
            }
        }
    }

    // MARK: - The collapse itself

    /// The clamp must not be what makes two offered genres share an echo. Exactly ONE is
    /// permitted to truncate at its default tempo: `selfObservation`, a half note 3.5% over the
    /// ceiling at 58 BPM, left alone on purpose because its division IS audible over most of its
    /// window and re-authoring it would change a preset that already sounds as written.
    ///
    /// Written as a COUNT rather than a name so re-voicing selfObservation cannot redden it —
    /// what must not happen is a SECOND genre joining it on the ceiling, which is how four of
    /// them ended up there.
    func testAtMostOneOfferedGenreIsTruncatedAtItsDefaultTempo() {
        let truncated = MusicStyle.offered.filter { style in
            style.fxPreset.delayEnabled && isClamped(style, bpm: style.defaultTempo)
        }
        XCTAssertLessThanOrEqual(truncated.count, 1,
            "\(truncated.count) offered genres have their echo truncated by the delay-line "
            + "ceiling at their own default tempo (\(truncated.map { "\($0)" }.sorted())). Every "
            + "one of them lands on the SAME flat time regardless of what it notated — that is "
            + "the '#81/#125 everything sounds the same' collapse, on the delay axis. Give the "
            + "new one a division that fits its window.")
    }

    /// The positive form of the same claim: the drum-free offered genres must actually OCCUPY the
    /// delay axis. Clustered at 5% relative distance because two times 1% apart are one echo to
    /// an ear, not two — a distinct-values count would score the pre-fix state 4 and call it
    /// spread.
    ///
    /// ⚠️ 5 clusters, not 7 (there are 7 such genres), and the two ties are MEASURED and
    /// deliberate: `selfObservation` 2.000 s (clamped) ≈ `esotericMeditation` 2.000 s (a half
    /// note at 60 BPM, exactly on the ceiling, so no clamp fires) coincide by AUTHORSHIP — same
    /// division, near-identical default tempo; and `ambientPulse` 0.706 s ≈ `classical` 0.714 s
    /// are both straight quarters whose windows happen to meet. Neither is a clamp artefact, so
    /// neither is this slice's to fix. Before the fix this metric was 3.
    func testTheDrumFreeOfferedGenresOccupyTheDelayAxis() {
        let drumFree = MusicStyle.offered.filter { $0.beatArchetype == .none }
        XCTAssertGreaterThanOrEqual(drumFree.count, 6,
            "too few drum-free offered genres for this measurement to mean anything")

        let times = drumFree
            .filter { $0.fxPreset.delayEnabled }
            .map { stamped($0, bpm: $0.defaultTempo).got }
            .sorted()
        XCTAssertEqual(times.count, drumFree.count,
                       "a drum-free genre with no delay at all would silently shrink this metric")

        var clusters = 1
        for i in 1..<times.count where times[i] > times[i - 1] * 1.05 { clusters += 1 }

        XCTAssertGreaterThanOrEqual(clusters, 5,
            "the drum-free genres resolve to only \(clusters) audibly distinct echo times "
            + "(\(times.map { String(format: "%.3f", $0) })). The calm family is collapsing onto "
            + "one echo again — check whether a division started clamping before retuning "
            + "anything by ear.")
    }

    // MARK: - Anti-vacuity

    /// ⛔ WITHOUT THIS, EVERY TEST ABOVE PASSES BY RAISING THE CEILING. A 100 s delay line makes
    /// "nothing clamps" trivially true and quietly re-collapses nothing — but it also forces
    /// `PolySynthVoice.idleFrameThreshold` past 100 s (its doc derives the 2.5 s from this
    /// ceiling: the render may only sleep after a window longer than the longest possible echo
    /// gap, or a sparse repeat freezes mid-train) and multiplies the delay buffer, which rounds
    /// up to a power of two per channel per chain.
    ///
    /// So this pins the ceiling at 2.0 s deliberately, as a TRIPWIRE rather than a fact worth
    /// asserting for its own sake. If you are here because this went red: raising it is a real
    /// option, but it costs the idle-render saving on exactly the sparse ambient material that
    /// wanted the long echo. Read `GenreFXPreset.maxDelaySeconds` and
    /// `PolySynthVoice.idleFrameThreshold` together, move both, and say so in the commit.
    func testTheDelayCeilingIsStillTwoSecondsAndStillEngages() {
        let probe = GenreFXPreset(delayEnabled: true, delaySync: TempoSyncOption(.whole))
        let chain = EchoelFXChain(sampleRate: 48000)
        probe.apply(to: chain, bpm: 40)          // a whole note at 40 BPM = 6.0 s

        XCTAssertEqual(probe.delaySync.seconds(bpm: 40), 6.0, accuracy: 1e-9,
                       "the note-division math changed — re-derive this probe before trusting "
                       + "the ceiling measurement below")
        XCTAssertEqual(Double(chain.delay.timeSeconds), 2.0, accuracy: 1e-4,
            "the delay-line ceiling is no longer 2.0 s. If it was RAISED, "
            + "PolySynthVoice.idleFrameThreshold (2.5 s, derived from this) must move above it in "
            + "the same change or a sparse echo train freezes mid-ring; if it was LOWERED, "
            + "presets that fit before may now truncate.")
    }
}
