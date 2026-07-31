// SynthPatchValuesResolveTests.swift
// Echoel — #286. `SynthPatch` stores `spectralShape` and `noiseColor` as free STRINGS and the
// engine looks them up case-insensitively (`SynthPatch.match`). Two consequences nobody had
// pinned:
//
//   1. The shipped values disagree on case. `SynthPatch.factory` writes "dark" / "pink";
//      `GenrePatches` writes "Dark" / "Pink". Both sound right, because `match` does not care.
//   2. A SwiftUI `Picker` DOES care — it matches its tag by `==`. Binding one straight to the
//      stored string (which is what the doorless `PatchEditorView` did, before #132 Slice 6
//      deleted it) leaves the control
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

    /// The property the Sound panel's canonicalising getters exist for, pinned where it CANNOT
    /// rot: `SynthPatch`'s own defaults.
    ///
    /// ⛔ THE FIRST VERSION ASSERTED THIS OVER THE SHIPPED ROSTER — "not every patch spells it
    /// exactly" — and that was a trap with a false premise. Review caught both halves. Normalising
    /// the roster's literals would be a legitimate cleanup, and it would have reddened the
    /// BLOCKING bundle with a message inviting someone to retire bindings that are still
    /// load-bearing. Load-bearing because the lowercase lives in the type's API, not the roster:
    /// `init`'s default parameter (`spectralShape: String = "dark"`) — which is what
    /// `SynthPatch(name: "Init")`, this view's starting patch, gets — and the decoder's
    /// `decodeIfPresent(...) ?? "dark"` for every older save. Normalise every literal in the app
    /// and a default-constructed patch STILL needs canonicalising before a Picker can show it.
    func testADefaultPatchDoesNotSpellItsValuesTheWayTheEnumDoes() {
        let probe = SynthPatch(name: "probe")
        let shapes = Set(EchoelDDSP.SpectralShape.allCases.map(\.rawValue))
        let colours = Set(EchoelDDSP.NoiseColor.allCases.map(\.rawValue))
        XCTAssertFalse(shapes.contains(probe.spectralShape),
                       "a default-constructed SynthPatch now spells spectralShape "
                       + "\"\(probe.spectralShape)\" exactly as the enum does. Good — but the "
                       + "Sound panel's canonicalising bindings were justified by this "
                       + "mismatch. Update their reason (older saves still decode to the old "
                       + "spelling) rather than deleting them, and update this test with them.")
        XCTAssertFalse(colours.contains(probe.noiseColor),
                       "same for noiseColor \"\(probe.noiseColor)\".")
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
