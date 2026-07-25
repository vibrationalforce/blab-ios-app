// ResolvedPatchTests.swift
// Echoelmusic — the audio-thread contract of patch recall.
//
// `PolySynthVoice` drains its patch queue INSIDE the render block, on purpose: applying
// a patch rewrites each voice's `harmonicAmplitudes`, and doing that from the main actor
// raced the render. But the queue used to carry a `SynthPatch`, whose `apply(to:)` ran
// `allCases` (heap allocation), `caseInsensitiveCompare` (ObjC messaging on a bridged
// String) and `instrumentProfile(_:)` (a fresh 64-tap array per voice) — so the cure for
// the race sat on top of three audio-thread violations. `ResolvedPatch` does that work on
// the control thread. These tests pin BOTH halves: that the resolved form is plain old
// data, and that it still sounds exactly like the old path.

#if canImport(Accelerate)
import XCTest
@testable import Echoelmusic

final class ResolvedPatchTests: XCTestCase {

    // MARK: - The POD contract (the reason the type exists)

    /// COMPILE-TIME guard, and the most important assertion in this file: the queue
    /// element is dequeued on the render thread, so it must contain no String, Array,
    /// or any other reference. Adding one would put ARC traffic — and eventually a
    /// `free()` — back on the audio thread, silently. This stops compiling if it does.
    #if compiler(>=6.0)
    func testResolvedPatchIsBitwiseCopyable() {
        func requireBitwiseCopyable<T: BitwiseCopyable>(_: T.Type) {}
        requireBitwiseCopyable(ResolvedPatch.self)
    }
    #endif

    // MARK: - Resolution happens once, on the control thread

    func testResolvedMatchesEnumRawValuesCaseInsensitively() {
        // Patches store lowercase ("violin"); the DSP enums use display rawValues
        // ("Violin"). An exact `init?(rawValue:)` returned nil and the character was
        // silently dropped — that is why `match` exists at all.
        let p = SynthPatch(name: "T", envelopeCurve: "exponential",
                           noiseColor: "pink", spectralShape: "bright",
                           timbreProfile: "violin", timbreBlend: 0.5)
        let r = p.resolved()
        XCTAssertEqual(r.envelopeCurve, .exponential)
        XCTAssertEqual(r.noiseColor, .pink)
        XCTAssertEqual(r.spectralShape, .bright)
        XCTAssertEqual(r.timbre, .violin)
        XCTAssertEqual(r.timbreBlend, 0.5, accuracy: 1e-6)
    }

    func testUnknownRawValueResolvesToNil_soTheVoiceKeepsItsSetting() {
        // The forward/backward-compatible fallback: an unknown name must not force a
        // default, it must leave the voice alone. `nil` is how that intent survives
        // the control→audio hop.
        let p = SynthPatch(name: "T", envelopeCurve: "no-such-curve",
                           noiseColor: "chartreuse", spectralShape: "???",
                           timbreProfile: "kazoo", timbreBlend: 0.5)
        let r = p.resolved()
        XCTAssertNil(r.envelopeCurve)
        XCTAssertNil(r.noiseColor)
        XCTAssertNil(r.spectralShape)
        XCTAssertNil(r.timbre)

        let synth = EchoelDDSP()
        synth.spectralShape = .metallic
        r.apply(to: synth)
        XCTAssertEqual(synth.spectralShape, .metallic, "an unknown name must not overwrite")
    }

    func testOptionalTrimsAreUnOptionalisedBeforeTheHop() {
        // nil outputLevel = unity, nil warmthDrive = clean. Resolving un-boxes them so
        // the render side never branches on an Optional.
        let bare = SynthPatch(name: "T", outputLevel: nil, warmthDrive: nil).resolved()
        XCTAssertEqual(bare.outputLevel, 1.0, accuracy: 1e-6)
        XCTAssertEqual(bare.warmthDrive, 0.0, accuracy: 1e-6)
    }

    // MARK: - Same sound as before (the refactor must be inaudible)

    func testWriteInstrumentProfileMatchesTheAllocatingGenerator() {
        // `writeInstrumentProfile` is `instrumentProfile` with the allocation removed.
        // If they ever diverge, every timbre-transfer patch changes character.
        for instrument in EchoelDDSP.InstrumentTimbre.allCases {
            let expected = EchoelDDSP.instrumentProfile(instrument, harmonics: 64)
            var actual = [Float](repeating: -1, count: 64)
            actual.withUnsafeMutableBufferPointer {
                EchoelDDSP.writeInstrumentProfile(instrument, into: $0)
            }
            XCTAssertEqual(actual.count, expected.count)
            // EXACT, not approximate: same code over the same buffer, so any drift at
            // all is a real divergence and a tolerance would hide it.
            XCTAssertEqual(actual, expected, "\(instrument) diverged from the allocating generator")
        }
    }

    func testApplyTimbreProducesTheSameSpectrumAsTheOldLoadPath() {
        // The old drain did `loadTimbreProfile(instrumentProfile(t), blend:)` — which
        // ALWAYS generated 64 taps, normalised over 64, then took `prefix(harmonicCount)`.
        // `applyTimbre` normalises over `harmonicCount` instead. Those agree only while
        // each profile's peak harmonic lies inside the first `harmonicCount` taps (it
        // does: the latest peak is the oboe's, at n = 6). Both SHIPPING voice widths are
        // covered here — PolySynthVoice builds 32, BioReactiveSynthVoice 64 — because 32
        // is exactly the configuration where the two normalisation windows could differ.
        for harmonics in [32, 64] {
            for instrument in EchoelDDSP.InstrumentTimbre.allCases {
                let old = EchoelDDSP(harmonicCount: harmonics)
                let new = EchoelDDSP(harmonicCount: harmonics)
                old.spectralShape = .natural
                new.spectralShape = .natural
                old.loadTimbreProfile(EchoelDDSP.instrumentProfile(instrument), blend: 0.6)
                new.applyTimbre(instrument, blend: 0.6)
                XCTAssertEqual(old.harmonicAmplitudes.count, new.harmonicAmplitudes.count)
                for i in 0..<old.harmonicAmplitudes.count {
                    XCTAssertEqual(new.harmonicAmplitudes[i], old.harmonicAmplitudes[i],
                                   accuracy: 1e-6,
                                   "\(instrument) @\(harmonics): harmonic \(i) diverged "
                                   + "from the pre-refactor path")
                }
            }
        }
    }

    func testApplyTimbreNilOrZeroBlendClearsLikeTheOldElseBranch() {
        let synth = EchoelDDSP()
        synth.applyTimbre(.flute, blend: 0.8)
        XCTAssertTrue(synth.hasTimbreProfile)
        XCTAssertNotNil(synth.timbreProfile)

        synth.applyTimbre(nil, blend: 0.8)
        XCTAssertFalse(synth.hasTimbreProfile)
        XCTAssertNil(synth.timbreProfile, "the optional façade must still read as cleared")
        XCTAssertEqual(synth.timbreBlend, 0, accuracy: 1e-6)

        // A named instrument with a zero blend is the same "no timbre" state — the old
        // code's `timbreBlend > 0` half of the condition.
        synth.applyTimbre(.flute, blend: 0)
        XCTAssertFalse(synth.hasTimbreProfile)
    }

    func testFacadeGetterHandsBackACopy_soInPlaceWritesCannotTriggerCOW() {
        // If the getter returned the backing buffer itself, holding the result would
        // make the next `applyTimbre` a copy-on-write heap allocation — on the audio
        // thread. That is the RenderScratch bug class; this pins the mitigation.
        let synth = EchoelDDSP()
        synth.applyTimbre(.trumpet, blend: 1.0)
        guard let held = synth.timbreProfile else { return XCTFail("expected a profile") }
        synth.applyTimbre(.clarinet, blend: 1.0)
        guard let after = synth.timbreProfile else { return XCTFail("expected a profile") }
        XCTAssertNotEqual(held, after, "the earlier read must not alias the live buffer")
    }

    func testResolvedApplyIsEquivalentToApplyingThePatchDirectly() {
        // `SynthPatch.apply(to:)` now just forwards to `resolved().apply(to:)`. This
        // pins that the forward is faithful, so the control-thread convenience and the
        // render-thread path can never drift apart.
        let patch = SynthPatch(name: "Equiv", attack: 0.13, decay: 0.24, sustain: 0.35,
                               release: 1.7, envelopeCurve: "linear",
                               harmonicity: 0.71, harmonicLevel: 0.62, brightness: 0.44,
                               noiseLevel: 0.08, noiseColor: "brown", spectralShape: "natural",
                               filterCutoff: 640, filterResonance: 0.22,
                               vibratoRate: 4.5, vibratoDepth: 0.06,
                               timbreProfile: "oboe", timbreBlend: 0.4,
                               outputLevel: 0.8, warmthDrive: 0.31)
        let direct = EchoelDDSP()
        let viaResolved = EchoelDDSP()
        patch.apply(to: direct)
        patch.resolved().apply(to: viaResolved)

        XCTAssertEqual(viaResolved.attack, direct.attack, accuracy: 1e-6)
        XCTAssertEqual(viaResolved.release, direct.release, accuracy: 1e-6)
        XCTAssertEqual(viaResolved.envelopeCurve, direct.envelopeCurve)
        XCTAssertEqual(viaResolved.brightness, direct.brightness, accuracy: 1e-6)
        XCTAssertEqual(viaResolved.noiseColor, direct.noiseColor)
        XCTAssertEqual(viaResolved.spectralShape, direct.spectralShape)
        XCTAssertEqual(viaResolved.filterCutoff, direct.filterCutoff, accuracy: 1e-6)
        XCTAssertEqual(viaResolved.bioBaseFilterCutoff, direct.bioBaseFilterCutoff, accuracy: 1e-6)
        XCTAssertEqual(viaResolved.vibratoDepth, direct.vibratoDepth, accuracy: 1e-6)
        XCTAssertEqual(viaResolved.warmthDrive, direct.warmthDrive, accuracy: 1e-6)
        XCTAssertEqual(viaResolved.timbreBlend, direct.timbreBlend, accuracy: 1e-6)
        XCTAssertEqual(viaResolved.hasTimbreProfile, direct.hasTimbreProfile)
        for i in 0..<direct.harmonicAmplitudes.count {
            XCTAssertEqual(viaResolved.harmonicAmplitudes[i], direct.harmonicAmplitudes[i],
                           accuracy: 1e-6, "harmonic \(i)")
        }
    }
}
#endif
