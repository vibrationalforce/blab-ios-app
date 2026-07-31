// SynthPatchValuesResolveTests.swift
// Echoel — #286. `SynthPatch` stores `spectralShape` and `noiseColor` as free STRINGS and the
// engine looks them up case-insensitively (`SynthPatch.match`). Two consequences nobody had
// pinned:
//
//   1. The shipped values disagree on case. `SynthPatch.factory` writes "dark" / "pink";
//      `GenrePatches` writes "Dark" / "Pink". Both sound right, because `match` does not care.
//   2. A SwiftUI `Picker` DOES care — it matches its tag by `==`. Binding one straight to the
//      stored string (which is what the doorless `PatchEditorView` does) leaves the control
//      blank for every patch spelled the other way. The Sound panel's ported rows therefore
//      canonicalise through the enum before displaying.
//
// ⭐ WHAT THIS FILE PINS, and it is a REAL runtime check rather than a source scan — `SynthPatch`,
// `resolved()` and `ResolvedPatch` are all `public`, so the actual lookup runs here. Every sound
// the app can hand the engine must resolve BOTH fields to a real case. A `nil` is not a crash:
// `ResolvedPatch.apply` then leaves the voice's previous setting in place, so the patch quietly
// inherits the character of whatever played before it — a wrong sound with no error anywhere,
// and the exact failure a typo in one of ~50 string literals produces.
//
// ⚠️ It does NOT prove the pickers render, or that the canonicalising bindings are wired. Those
// live in `private` members of a view this bundle cannot instantiate; `UnisonRowDefaultsTests`
// guards their presence textually. What is proven here is the property those bindings' fallback
// arms rest on: that the fallback is unreachable from any shipped sound.

import Foundation
import XCTest
@testable import Echoelmusic

final class SynthPatchValuesResolveTests: XCTestCase {

    /// Every patch the app can hand the engine without the user typing anything.
    private var shippedPatches: [(label: String, patch: SynthPatch)] {
        SynthPatch.factory.map { (label: "factory “\($0.name)”", patch: $0) }
        + MusicStyle.offered.map { (label: "genre “\($0.rawValue)”", patch: $0.synthPatch) }
    }

    /// ⭐ THE ONE THAT MATTERS. A `nil` here is silent: the note still sounds, with the previous
    /// patch's spectrum. No log, no crash, no red anywhere else.
    func testEveryShippedPatchResolvesItsSpectralShape() {
        for entry in shippedPatches {
            XCTAssertNotNil(entry.patch.resolved().spectralShape,
                            "\(entry.label) stores spectralShape \"\(entry.patch.spectralShape)\", "
                            + "which names no `EchoelDDSP.SpectralShape` case. `apply` leaves the "
                            + "voice's PREVIOUS shape in place, so this patch inherits whatever "
                            + "played before it — audible, and invisible to every other test.")
        }
    }

    func testEveryShippedPatchResolvesItsNoiseColour() {
        for entry in shippedPatches {
            XCTAssertNotNil(entry.patch.resolved().noiseColor,
                            "\(entry.label) stores noiseColor \"\(entry.patch.noiseColor)\", which "
                            + "names no `EchoelDDSP.NoiseColor` case — same silent inheritance as "
                            + "an unresolved shape.")
        }
    }

    /// The property the Sound panel's canonicalising getters exist for. If the shipped strings
    /// were ever normalised to the enum's own spelling this test would go green trivially and
    /// could be deleted — but until then it is the reason a `Picker` cannot bind to the raw
    /// field, and stating it as an assertion stops that reason from being forgotten and the
    /// bindings from being "simplified" away.
    func testTheShippedSpellingsDoNotAllMatchTheEnumExactly() {
        let exact = Set(EchoelDDSP.SpectralShape.allCases.map(\.rawValue))
        let mismatched = shippedPatches.filter { !exact.contains($0.patch.spectralShape) }
        XCTAssertFalse(mismatched.isEmpty,
                       "every shipped patch now spells its spectralShape exactly as the enum "
                       + "does. That is an improvement — but the Sound panel's canonicalising "
                       + "bindings were justified by this mismatch, so either keep them with an "
                       + "updated reason (a hand-edited or older saved patch can still differ) "
                       + "or retire them deliberately. Do not let the justification rot.")
    }

    /// And the mechanism the whole scheme rests on. If `match` ever became case-SENSITIVE, the
    /// two tests above would fail — but only for the half of the roster spelled the other way,
    /// which reads like "those patches are broken" rather than "the lookup rule changed".
    func testTheLookupIsCaseInsensitive() {
        var p = SynthPatch(name: "Probe")
        for spelling in ["bell", "BELL", "Bell", "bElL"] {
            p.spectralShape = spelling
            XCTAssertEqual(p.resolved().spectralShape, .bell,
                           "\"\(spelling)\" no longer resolves to .bell — `SynthPatch.match` has "
                           + "stopped comparing case-insensitively. Half the shipped roster is "
                           + "spelled lowercase and half capitalised; that rule is what makes "
                           + "both sound correct.")
        }
    }
}
