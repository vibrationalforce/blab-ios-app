// GenreDelaySyncResolvabilityTests.swift
// ⚠️ RENAMED. It was `GenreDelaySyncAudibilityTests` for one commit, and "audibility" was
// exactly the wrong word — see the header below: nothing in this file is about what anyone
// hears. A test file whose NAME asserts more than its contents do is the same defect class it
// guards against.
// Echoel — a notated note division that cannot RESOLVE at any tempo the genre allows is a lie in
// the source. BLOCKING bundle (Tests/CISmoke), because the other suite cannot fail a merge (#208).
//
// ⛔ READ THIS FIRST — THE FIRST VERSION OF THIS HEADER WAS A PLAYBACK CLAIM AND IT WAS FALSE.
// It said the two genres below "played a flat 2.0 s echo" and called that "the '#81/#125
// everything sounds the same' collapse, on the delay axis". They played no such thing. All three
// sites that stamp a genre/character preset (`EchoelStudioView.applyFX()`, the re-seed path, the
// open-take path) call `applyDelaySync(bpm:)` immediately afterwards over the SAME chain
// inventory, and it writes the view's `@State delaySync` — the user's delay-division picker,
// default dotted 1/8 — over `chain.delay.timeSeconds`.
//
// ⚠️ "The picker is the last writer, ALWAYS" stood here for one commit and is FALSE:
// `EchoelFXView.applyCharacter` is a FOURTH stamp site with no `applyDelaySync` after it, so a
// CHARACTER stamp from the FX panel wins instead (and writes only `synth.fxChain`, never
// `touchSynth`'s). No genre preset is involved there — `.auto` is filtered out of that menu — so
// the claim about GENRE divisions survives; the absolute did not. Correcting a false absolute
// with another one is how this file got here.
// That is the deliberate resolution of #240, guarded by `DelayReachesEveryChainTests` in this
// same bundle, which states it plainly. Asserting the opposite two files away is exactly the
// "a surviving copy reads as independent confirmation" failure this repo keeps paying for.
//
// SO WHAT THIS FILE GUARDS IS A SOURCE-LEVEL CONTRACT, NOT AN AUDIBLE ONE: the per-genre
// divisions must be resolvable and distinct, so that they are correct on the day the routing is
// fixed. `GenreFXPreset.apply(to:bpm:)`'s doc carries the routing finding; the honest summary is
// that 29 authored divisions currently reach nothing and every genre shares whichever one the
// picker holds — a far bigger delay-axis collapse than any preset tuning, and a founder decision.
//
// THE SOURCE DEFECT THIS FILE WAS WRITTEN FOR. `apply(to:bpm:)` resolves `delaySync` against the
// BPM and clamps to `maxDelaySeconds` = 2.0. Two genres authored divisions over that clamp at
// EVERY tempo in their own `tempoRange`, so the notated value could not resolve anywhere:
//
//   · deepDrone      `.whole`         40…58 BPM → 6.00…4.14 s
//   · contemplation  `.half, .dotted` 44…66 BPM → 4.09…2.73 s
//
// Re-authored to `.half, .triplet` and `.quarter`, both un-clamped across their whole windows.
// The ceiling was deliberately NOT raised — but not for the reason first written here either:
// see `GenreFXPreset.maxDelaySeconds`, where three unlinked `2.0` literals are separated and
// only one of them sizes a buffer.
//
// WHAT THIS FILE CANNOT CATCH, stated so the coverage is not overread:
//   · anything a user hears — see above; that is the routing question, not this one;
//   · whether the new times would sound good once routed — a founder listening call;
//   · `FXCharacter` presets, which have no tempo window of their own (they are stamped at
//     whatever BPM is running) so "cannot resolve at any allowed tempo" is undefined for them;
//   · a genre whose division resolves in only a sliver of its window. Test 3 bounds how many
//     genres may be clamped AT THEIR DEFAULT TEMPO, which is the tempo a fresh take starts on,
//     but a window is not swept for the untouched presets on purpose — tightening that would
//     force a retune of presets that already resolve as authored over most of their range.

import Foundation
import XCTest
@testable import Echoelmusic

final class GenreDelaySyncResolvabilityTests: XCTestCase {

    /// One reusable chain per TEST METHOD (XCTest builds a fresh instance for each, which is
    /// what makes this bleed-free across methods — the property does the sharing, not a static).
    /// A fresh `EchoelFXChain` allocates ≥1 MB of delay-line buffers plus tape/chorus/flanger/
    /// harmonizer/reverb lines, and the sweeps below call `stamped` ~90 times: 90 chains would
    /// churn ~100 MB inside the bundle that gates every merge, for no added coverage.
    ///
    /// ⚠️ EQUIVALENT FOR WHAT THIS FILE READS, AND NOT IN GENERAL — the first version claimed
    /// "exactly equivalent to a fresh one", which is only true of `delay.timeSeconds`, the single
    /// field measured here (`apply` writes it unconditionally, and it is a plain stored property
    /// with no smoothing on the read path). Reuse DOES carry over `EchoelDelay.timeSmoothed`, the
    /// ring buffers, filter states and LFO phases, and the `delayEnabled` rising-edge reset now
    /// fires only on the first `apply` because every genre preset sets it true. A sixth test that
    /// calls `processStereo` or asserts on a settled value must build its own chain.
    private let chain = EchoelFXChain(sampleRate: 48000)

    /// The stamped delay time and the time the preset ASKED for, at one BPM.
    /// Measured through `apply` rather than by reading the private ceiling constant — the
    /// observable form, and it tracks the constant automatically if it ever moves.
    private func stamped(_ style: MusicStyle, bpm: Double) -> (got: Double, authored: Double) {
        let preset = style.fxPreset
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
    /// ⚠️ NAMED POSITIVELY ON PURPOSE. It was `testNoGenresDelayDivisionIsInaudible…` and then
    /// `…FailsToResolveAtEveryTempo…` — a double negative with a second, equally grammatical
    /// reading ("every division resolves at every allowed tempo") that is FALSE and that test 3
    /// explicitly permits. A name must not assert more than the body; that is why this file was
    /// renamed, so the method name has to obey it too.
    func testEveryGenresDivisionResolvesAtItsFastestAllowedTempo() {
        for style in MusicStyle.allCases {
            let preset = style.fxPreset
            guard preset.delayEnabled else { continue }

            let fastest = style.tempoRange.upperBound
            let r = stamped(style, bpm: fastest)
            XCTAssertEqual(r.got, r.authored, accuracy: 1e-4,
                "\(style): `\(preset.delaySync.label)` is \(String(format: "%.3f", r.authored)) s "
                + "even at its FASTEST allowed tempo (\(fastest) BPM), so the delay-line ceiling "
                + "truncates it to \(String(format: "%.3f", r.got)) s at every tempo in "
                + "\(style.tempoRange) — the notated division can never RESOLVE, and the genre "
                + "sits on the clamp next to every other genre that overruns it. Author a "
                + "SHORTER division; do not raise the ceiling (see GenreFXPreset.maxDelaySeconds).")
        }
    }

    /// The two genres this slice repaired, held to the STRONGER bar the fix actually met: not
    /// merely resolvable somewhere, but un-clamped across the ENTIRE window, so the resolved time
    /// tracks tempo everywhere a body can take them. Swept at 1 BPM, which covers both ends.
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
    /// ceiling at 58 BPM, left alone on purpose because its division DOES resolve over most of
    /// its window, so re-authoring it would change a preset that already resolves as authored.
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
            + "one of them resolves to the SAME flat time regardless of what it notated. That is "
            + "a source-level collapse of the delay axis (what a LISTENER hears is a separate, "
            + "open routing question — see this file's header). Give the new one a division that "
            + "fits its window.")
    }

    /// The positive form of the same claim: the drum-free offered genres must actually OCCUPY the
    /// delay axis. Clustered at 5% relative distance because two times 1% apart are one echo to
    /// an ear, not two — a distinct-values count would score the pre-fix state 4 and call it
    /// spread.
    ///
    /// ⚠️ 5 clusters, not 7 (there are 7 such genres), and the two ties are MEASURED and
    /// deliberate: `selfObservation` 2.000 s (clamped) ≈ `stillMeditation` 2.000 s (a half
    /// note at 60 BPM, exactly on the ceiling, so no clamp fires) coincide by AUTHORSHIP — same
    /// division, near-identical default tempo; and `ambientPulse` 0.706 s ≈ `classical` 0.714 s
    /// are both straight quarters whose windows happen to meet. Neither is a clamp artefact, so
    /// neither is this slice's to fix. Before the fix this metric was 3.
    ///
    /// ⚠️ THIS SITS EXACTLY ON ITS BOUND — 5 is the measured value, not a floor with slack. Any
    /// merge of two clusters reddens it, which is the point (it is a ratchet against re-collapse,
    /// not a quality bar). Do not read the 5 as comfortable: the tightest surviving split is
    /// `deepDrone` 1.667 vs `drift` 1.500, only 11% apart, and 5% at ~1.6 s is 80 ms, which is
    /// not two echoes to an ear. If this is ever to become a real quality bar rather than a
    /// regression latch, raise the distance to 10% and assert whatever count that yields —
    /// deliberately NOT done here, because it would demand retuning presets on taste.
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

        // `guard` and not just the assertion above: `XCTAssert*` does not halt the method, and
        // `1..<0` TRAPS ("Range requires lowerBound <= upperBound"). A future `beatArchetype`
        // edit that emptied this set would crash the test process and take the rest of the
        // bundle's tests with it instead of printing the diagnostic written above.
        guard times.count > 1 else {
            return XCTFail("fewer than two drum-free offered genres carry a delay — there is no "
                           + "axis left to measure; fix the set, not this test")
        }

        var clusters = 1
        for i in 1..<times.count where times[i] > times[i - 1] * 1.05 { clusters += 1 }

        XCTAssertGreaterThanOrEqual(clusters, 5,
            "the drum-free genres resolve to only \(clusters) audibly distinct echo times "
            + "(\(times.map { String(format: "%.3f", $0) })). The calm family is collapsing onto "
            + "one echo again — check whether a division started clamping before retuning "
            + "anything by ear.")
    }

    // MARK: - Anti-vacuity

    /// ⛔ WITHOUT THIS, EVERY TEST ABOVE PASSES BY RAISING THE CEILING. A 100 s clamp makes
    /// "nothing clamps" trivially true while changing nothing about what any genre notates.
    ///
    /// ⚠️ THIS PINS ONE OF THREE UNLINKED `2.0` LITERALS, and the first version of this comment
    /// wrongly treated them as one. It pins `GenreFXPreset.maxDelaySeconds`, a pure clamp that
    /// allocates nothing. The other two are UNGUARDED here:
    ///   · `EchoelDelay.init(maxDelaySeconds: Float = 2.0)` — the one that SIZES the buffer, and
    ///     the one `EchoelFXChain` actually uses. Usable line is `capacity - 2` = 131 070 =
    ///     2.7306 s at 48 kHz, so the clamp this test pins is already 0.73 s below the hardware.
    ///   · `EchoelStudioView.applyDelaySync(bpm:)`'s hardcoded `0.001...2.0`, for the USER's
    ///     delay-division picker — which per this file's header is the value a listener actually
    ///     meets, and whose own menu (`TempoSyncOption.common`) offers 1/1 straight/dotted/
    ///     triplet. On `deepDrone` at 40 BPM the picker's own 1/1 is 6.0 s and truncates to 2.0:
    ///     the very defect class this file exists for, one surface over, untested.
    ///
    /// So if you are here because this went red: moving this constant alone is cheap (free up to
    /// ~2.73 s) but changes nothing a user hears. Read `GenreFXPreset.maxDelaySeconds`' doc for
    /// which literal does what before moving any of them, and note that
    /// `PolySynthVoice.idleFrameThreshold`'s 2.5 s derives from `EchoelDelay`'s ceiling — and is
    /// already violable via `FXPreset`'s unbounded `delayTime` decode.
    func testTheDelayCeilingIsStillTwoSecondsAndStillEngages() {
        let probe = GenreFXPreset(delayEnabled: true, delaySync: TempoSyncOption(.whole))
        probe.apply(to: chain, bpm: 40)          // a whole note at 40 BPM = 6.0 s

        XCTAssertEqual(probe.delaySync.seconds(bpm: 40), 6.0, accuracy: 1e-9,
                       "the note-division math changed — re-derive this probe before trusting "
                       + "the ceiling measurement below")
        XCTAssertEqual(Double(chain.delay.timeSeconds), 2.0, accuracy: 1e-4,
            "GenreFXPreset.maxDelaySeconds is no longer 2.0 s. If it was RAISED past ~2.73 s the "
            + "delay LINE truncates instead (EchoelDelayLine.read), so the authored value still "
            + "does not resolve — it just fails one layer down where nothing checks it. If it was "
            + "LOWERED, presets that resolved before now clamp.")
    }
}
