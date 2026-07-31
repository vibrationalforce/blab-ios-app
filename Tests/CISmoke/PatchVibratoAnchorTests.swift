// PatchVibratoAnchorTests.swift
// Echoel — #279. Blocking bundle.
//
// ⭐ THE DEFECT THIS PINS, and its size is the reason it is worth a guard. `EchoelDDSP`
// exposes `vibratoRate`, `vibratoDepth` and `lfoToFilterDepth`; `SynthPatch` stores all three;
// the Sound panel (the live patch editor, ship-gate item 2) offers all three as editable rows;
// and every shipped preset and genre patch sets them deliberately — a musical 4.5–5.5 Hz
// vibrato, or an explicit `vibratoRate: 0, vibratoDepth: 0` for the ones that must not wobble
// (`grep -c 'vibratoRate: 0, vibratoDepth: 0' Sources/Echoelmusic/DSP/SynthPatch.swift` → 3 on
// 2026-07-31; no count is written here without the command that reproduces it).
// Then `applyBioReactive` overwrote all three ~10×/s from raw physiology with ABSOLUTE values:
// `vibratoRate = 0.05 + heartRate * 0.15`. That is 0.05–0.2 Hz. Against a preset's 5 Hz it is
// not a modulation, it is a deletion — a factor of 25 to 100 — applied the moment biofeedback
// runs, which in a bio-reactive instrument is always. The three rows in the Sound panel were
// therefore lying controls: you could set them, and the body silently threw the value away.
//
// ⚠️ WHY A RUNTIME TEST RATHER THAN A SOURCE SCAN. The whole claim is arithmetic on values that
// travel patch → `ResolvedPatch.apply` → `applyBioReactive`, and every one of those is `public`,
// so the real chain runs here. A textual guard would pin the shape of a formula and prove
// nothing about the number that reaches the oscillator.
//
// ⚠️ WHAT IT DOES NOT PROVE. Not that the vibrato is AUDIBLE (nothing in CI listens), and not
// that the Sound panel's rows are wired to the patch this applies — `UnisonRowDefaultsTests`
// and `SoundPanelReflowsTests` guard that half textually. What is proven is the property those
// rows rest on: the value you set is the value the engine plays at rest, and the body moves it
// instead of replacing it.
//
// ⛔ THE SENTINEL IS −1, NOT 0, AND THAT WAS THE ONE REAL TRAP IN THIS FIX. The two older
// anchors (`bioBaseFilterCutoff`, `bioBaseBrightness`) use 0 for "no patch applied", and
// copying that here would have been the obvious move and a silent regression: three shipped
// presets legitimately store `vibratoDepth: 0`, so 0-as-unset would have routed exactly the
// patches that ask for NO vibrato back into the absolute path that hands them one.
// `testPatchWithoutVibratoNeverGainsVibrato` is that trap, pinned.

import Foundation
import XCTest
@testable import Echoelmusic

final class PatchVibratoAnchorTests: XCTestCase {

    /// The neutral resting reading. Every `bioBase*` mapping is centred here, so a resting body
    /// must reproduce the patch EXACTLY — that centring is the law being tested.
    private func applyNeutralBio(to synth: EchoelDDSP) {
        synth.applyBioReactive(coherence: 0.5, hrvVariability: 0.5, heartRate: 0.5,
                               breathPhase: 0.5, breathDepth: 0.5)
    }

    /// Every patch the app can hand the engine without the user typing anything.
    private var shippedPatches: [(label: String, patch: SynthPatch)] {
        SynthPatch.factory.map { (label: "factory “\($0.name)”", patch: $0) }
        + MusicStyle.offered.map { (label: "genre “\($0.rawValue)”", patch: $0.synthPatch) }
    }

    /// First shipped patch matching `match`, searched across BOTH sources.
    ///
    /// ⚠️ Deliberately a function and not an inline `first {…} ?? first {…}` chain: this repo has
    /// a ledgered dead-end where a long inline expression hard-errors the Swift type-checker in
    /// exactly this bundle (`3379bb3`), and a `??` sitting between two trailing closures is the
    /// shape that invites it.
    private func firstShippedPatch(where match: (SynthPatch) -> Bool) -> SynthPatch? {
        if let hit = SynthPatch.factory.first(where: match) { return hit }
        let genrePatches: [SynthPatch] = MusicStyle.offered.map(\.synthPatch)
        return genrePatches.first(where: match)
    }

    // MARK: - The resting body plays the patch

    /// ⭐ THE ONE THAT MATTERS. Across every shipped sound: apply it, run one bio frame at the
    /// neutral reading, and the three parameters must be untouched.
    func testEveryShippedPatchKeepsItsVibratoUnderNeutralBio() {
        for entry in shippedPatches {
            let synth = EchoelDDSP()
            entry.patch.resolved().apply(to: synth)
            applyNeutralBio(to: synth)

            XCTAssertEqual(synth.vibratoRate, entry.patch.vibratoRate, accuracy: 1e-5, """
            \(entry.label) asks for a vibrato rate of \(entry.patch.vibratoRate) Hz, and after ONE \
            bio frame at the resting reading the engine plays \(synth.vibratoRate) Hz.

            Bio must modulate AROUND the patch (the bioBase* law), never overwrite it. If this \
            reads ~0.125 Hz, the absolute mapping is back: `vibratoRate = 0.05 + heartRate * 0.15`.
            """)
            XCTAssertEqual(synth.vibratoDepth, entry.patch.vibratoDepth, accuracy: 1e-5, """
            \(entry.label) asks for a vibrato depth of \(entry.patch.vibratoDepth) semitones and \
            the engine plays \(synth.vibratoDepth) after one neutral bio frame.
            """)
            XCTAssertEqual(synth.lfoToFilterDepth, entry.patch.lfoToFilterDepth, accuracy: 1e-5, """
            \(entry.label) asks for an LFO→filter depth of \(entry.patch.lfoToFilterDepth) and the \
            engine plays \(synth.lfoToFilterDepth) after one neutral bio frame.
            """)
        }
    }

    /// ⛔ THE TRAP THE SENTINEL CHOICE EXISTS FOR. A patch that asks for no vibrato must never
    /// acquire one — at ANY heart rate. The render gate is `vibratoRate > 0 && vibratoDepth > 0`,
    /// so a single value nudged off zero switches the oscillator on.
    func testPatchWithoutVibratoNeverGainsVibrato() {
        let silent = firstShippedPatch { $0.vibratoRate == 0 && $0.vibratoDepth == 0 }
        guard let silent else {
            // Not a pass: if no shipped patch turns vibrato off any more, this guard is
            // measuring nothing and must be re-pointed rather than left green.
            return XCTFail("""
            no shipped patch stores `vibratoRate: 0, vibratoDepth: 0` any more, so this test \
            can no longer see the case it exists for. Point it at a hand-built patch or delete it \
            — do NOT leave it green over an empty search.
            """)
        }

        for hr in stride(from: Float(0), through: 1, by: 0.1) {
            let synth = EchoelDDSP()
            silent.resolved().apply(to: synth)
            synth.applyBioReactive(coherence: 0.5, hrvVariability: 0.5, heartRate: hr,
                                   breathPhase: 0.5, breathDepth: 0.5)
            XCTAssertEqual(synth.vibratoDepth, 0, accuracy: 1e-6, """
            “\(silent.name)” deliberately has no vibrato, and at heart rate \(hr) the engine gives \
            it a depth of \(synth.vibratoDepth). An ADDITIVE deviation does this — the anchored \
            path must stay multiplicative so zero stays zero.
            """)
            XCTAssertEqual(synth.vibratoRate, 0, accuracy: 1e-6, """
            “\(silent.name)” has no vibrato and the engine gives it a rate of \(synth.vibratoRate) \
            Hz at heart rate \(hr).
            """)
        }
    }

    // MARK: - The body still moves it

    /// The fix must not turn the parameter into a constant — that would trade a lying control
    /// for a dead one. An aroused body plays a faster, deeper vibrato than a resting one.
    func testHeartRateStillMovesAVibratoPatch() {
        let patch = firstShippedPatch { $0.vibratoRate > 0 && $0.vibratoDepth > 0 }
        guard let patch else {
            return XCTFail("no shipped patch uses vibrato at all — re-point this guard")
        }

        let calm = EchoelDDSP(); patch.resolved().apply(to: calm)
        calm.applyBioReactive(coherence: 0.5, hrvVariability: 0.5, heartRate: 0,
                              breathPhase: 0.5, breathDepth: 0.5)
        let aroused = EchoelDDSP(); patch.resolved().apply(to: aroused)
        aroused.applyBioReactive(coherence: 0.5, hrvVariability: 0.5, heartRate: 1,
                                 breathPhase: 0.5, breathDepth: 0.5)

        XCTAssertGreaterThan(aroused.vibratoDepth, calm.vibratoDepth, """
        the body no longer changes the vibrato depth at all (\(calm.vibratoDepth) at rest vs \
        \(aroused.vibratoDepth) aroused). Anchoring the parameter must not freeze it — this is a \
        bio-reactive instrument, the deviation is the product.
        """)
        XCTAssertGreaterThan(aroused.vibratoRate, calm.vibratoRate, """
        the body no longer changes the vibrato rate (\(calm.vibratoRate) Hz vs \
        \(aroused.vibratoRate) Hz).
        """)
    }

    /// Breath must still open and close the filter movement of a patch that asks for movement.
    func testBreathStillMovesAnAnchoredFilterLFO() {
        let patch = firstShippedPatch { $0.lfoToFilterDepth > 0 }
        guard let patch else { return XCTFail("no shipped patch uses the filter LFO") }

        let shallow = EchoelDDSP(); patch.resolved().apply(to: shallow)
        shallow.applyBioReactive(coherence: 0.5, hrvVariability: 0.5, heartRate: 0.5,
                                 breathPhase: 0.5, breathDepth: 0)
        let deep = EchoelDDSP(); patch.resolved().apply(to: deep)
        deep.applyBioReactive(coherence: 0.5, hrvVariability: 0.5, heartRate: 0.5,
                              breathPhase: 0.5, breathDepth: 1)

        XCTAssertGreaterThan(deep.lfoToFilterDepth, shallow.lfoToFilterDepth, """
        the breath no longer opens the filter movement (\(shallow.lfoToFilterDepth) shallow vs \
        \(deep.lfoToFilterDepth) deep) — the anchor froze the parameter instead of centring it.
        """)
    }

    // MARK: - The patch-less voice is untouched

    /// The raw bio voice (`BioReactiveSynthVoice`) never receives a patch, so its sentinel stays
    /// −1 and it must keep the legacy absolute mapping EXACTLY. This is the "byte-identical"
    /// half of every bioBase* change, and the half that is easy to claim and never check.
    func testPatchlessVoiceKeepsTheLegacyAbsoluteMapping() {
        for hr in stride(from: Float(0), through: 1, by: 0.25) {
            for breath in stride(from: Float(0), through: 1, by: 0.25) {
                let synth = EchoelDDSP()   // no patch → bioBase* sentinels stay at −1
                synth.applyBioReactive(coherence: 0.5, hrvVariability: 0.5, heartRate: hr,
                                       breathPhase: 0.5, breathDepth: breath)
                XCTAssertEqual(synth.vibratoDepth, 0.004 + hr * 0.02, accuracy: 1e-7, """
                the patch-less bio voice changed its vibrato depth at heart rate \(hr). The \
                sentinel path must stay the legacy `0.004 + heartRate * 0.02` — a raw bio voice \
                has no patch to be anchored to.
                """)
                XCTAssertEqual(synth.vibratoRate, 0.05 + hr * 0.15, accuracy: 1e-7, """
                the patch-less bio voice changed its vibrato rate at heart rate \(hr) \
                (expected the legacy `0.05 + heartRate * 0.15`).
                """)
                XCTAssertEqual(synth.lfoToFilterDepth, 0.05 + breath * 0.3, accuracy: 1e-7, """
                the patch-less bio voice changed its LFO→filter depth at breath depth \(breath) \
                (expected the legacy `0.05 + breathDepth * 0.3`).
                """)
            }
        }
    }

    /// The sentinels themselves. A future `apply(to:)` that forgets one of the three anchors
    /// would leave that parameter on the absolute path while the other two are anchored — the
    /// partial state that is hardest to hear and easiest to ship.
    func testAnchorsDefaultToUnsetAndAreAllSetByApply() {
        let fresh = EchoelDDSP()
        for (name, value) in [("bioBaseVibratoRate", fresh.bioBaseVibratoRate),
                              ("bioBaseVibratoDepth", fresh.bioBaseVibratoDepth),
                              ("bioBaseLFOToFilterDepth", fresh.bioBaseLFOToFilterDepth)] {
            XCTAssertLessThan(value, 0, """
            \(name) must default to a NEGATIVE "unset" sentinel, not 0 — a patch may legitimately \
            store 0 for all three, and 0-as-unset silently hands those patches the absolute \
            mapping they were written to avoid. It reads \(value).
            """)
        }

        let synth = EchoelDDSP()
        SynthPatch.factory[0].resolved().apply(to: synth)
        XCTAssertEqual(synth.bioBaseVibratoRate, SynthPatch.factory[0].vibratoRate, accuracy: 1e-6,
                       "`apply(to:)` did not set the vibrato-rate anchor")
        XCTAssertEqual(synth.bioBaseVibratoDepth, SynthPatch.factory[0].vibratoDepth, accuracy: 1e-6,
                       "`apply(to:)` did not set the vibrato-depth anchor")
        XCTAssertEqual(synth.bioBaseLFOToFilterDepth, SynthPatch.factory[0].lfoToFilterDepth,
                       accuracy: 1e-6, "`apply(to:)` did not set the LFO→filter-depth anchor")
    }
}
