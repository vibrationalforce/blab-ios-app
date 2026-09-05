// PolySynthAutomationBindTests.swift
// DAW#1 — "all parameters automatable". Proves PolySynthVoice.bindAutomatable wires
// EXACTLY the params it DECLARES in `automatableBases` into the router (the placebo law:
// the automation picker offers only bound params, so no lane moves nothing), and that
// nothing the catalog knows but the voice does not declare gets a setter behind its back.

import XCTest
import Foundation
@testable import Echoelmusic

@MainActor
final class PolySynthAutomationBindTests: XCTestCase {

    // ⛔ #1009 — THIS FILE PINNED A SIX-ITEM LITERAL AND A NINE-ITEM EXCLUSION LIST, AND
    // BOTH HAD BEEN WRONG SINCE #557. `automatableBases` is ELEVEN today: #557 bound the
    // harmonicity and noise-level ANCHORS, #558 the two vibrato anchors, #564 the brightness
    // anchor (after fixing its in-range sentinel). So `bindsExactlyTheSafeSet` asserted six
    // against eleven, and `excludesBioContestedParams` asserted five of those same eleven were
    // NOT bound. Two red tests, invisible behind `full-tests.yml`'s `continue-on-error`.
    //
    // ⭐ THE REPAIR IS AGREEMENT, NOT A NEW LITERAL, and that is the whole lesson. A second
    // hand-written copy of the shipped list is a copy that can go stale again — this one did,
    // silently, across the three deliberate commits that moved the real list. The claims below derive
    // what they expect from `PolySynthVoice.automatableBases` and from the catalog, so the next
    // deliberate binding needs no edit here, and an ACCIDENTAL one still goes red because the
    // declared list and the bound list must match in both directions.
    //
    // ⚠️ THIS FILE DOES NOT OWN THE LAW, only the WIRING (#416). Whether a parameter MAY be
    // automatable — the one-writer rule, the anchors, the sentinels, the filter's single
    // address — lives in `Tests/CISmoke/TheAutomatableSetHasOneWriterTests` in the blocking
    // bundle. Restating it here would be a second opinion that can drift from the first.

    private func makeWired() -> (PolySynthVoice, ParameterApplyRouter) {
        let reg = EchoelParameterRegistry()
        reg.register(DDSPParameterCatalog.descriptors)
        let router = ParameterApplyRouter(registry: reg)
        let voice = PolySynthVoice(maxVoices: 4)
        voice.bindAutomatable(into: router)
        return (voice, router)
    }

    /// Every declared base gets a live setter, and nothing else does. Both directions matter:
    /// a base with no setter is a picker entry that moves nothing (the placebo law), and a
    /// setter with no declared base is a control nobody reviewed.
    func testBindAutomatable_bindsExactlyWhatItDeclares() {
        let (_, router) = makeWired()
        XCTAssertEqual(router.boundKeyPaths, Set(PolySynthVoice.automatableBases), """
        the bound setters and `PolySynthVoice.automatableBases` disagree.

        declared but unbound: \(Set(PolySynthVoice.automatableBases).subtracting(router.boundKeyPaths).sorted())
        bound but undeclared: \(router.boundKeyPaths.subtracting(PolySynthVoice.automatableBases).sorted())

        A declared base with no setter offers a lane that moves nothing; a setter with no \
        declaration is a control that skipped the one-writer review in \
        `TheAutomatableSetHasOneWriterTests`.
        """)
    }

    /// The picker's ORDER is the registry's, not the bind order — `automatableDescriptors()`
    /// filters `registry.all()`. Derived from the catalog so no literal can rot.
    func testAutomatableDescriptors_followRegistryOrder() {
        let (_, router) = makeWired()
        let expected = DDSPParameterCatalog.descriptors
            .map(\.keyPath)
            .filter { PolySynthVoice.automatableBases.contains($0) }
        XCTAssertEqual(router.automatableDescriptors().map(\.keyPath), expected)
    }

    /// The catalog parameters deliberately left OUT. Derived, not typed: whatever the catalog
    /// knows and the voice does not declare must have no setter. Today that is the two reverb
    /// params (the convolution stage is gated off, #546), `ddsp.osc.frequency` (owned per note
    /// by the note engine) and `ddsp.filter.cutoff` (automation already has one address,
    /// `ddsp.filter.cutoffScale`) — but the assertion holds whatever that set becomes.
    func testBindAutomatable_bindsNothingTheCatalogKnowsButTheVoiceDoesNotDeclare() {
        let (_, router) = makeWired()
        let excluded = DDSPParameterCatalog.descriptors
            .map(\.keyPath)
            .filter { !PolySynthVoice.automatableBases.contains($0) }
        XCTAssertFalse(excluded.isEmpty,
                       "the catalog and the declared set became identical; this claim can no longer fail")
        for keyPath in excluded {
            XCTAssertFalse(router.isBound(keyPath), """
            \(keyPath) has a live setter but is not in `PolySynthVoice.automatableBases`.

            Binding without declaring bypasses the one-writer review — see the anchor/sentinel \
            reasoning above `automatableBases` and its guard in the blocking bundle.
            """)
        }
    }

    /// The automation playback path (applyNormalized) reaches a bound setter and
    /// returns the denormalized real value — i.e. a drawn 0…1 lane moves real units.
    func testBoundParam_appliesDenormalizedRealValue() {
        let reg = EchoelParameterRegistry()
        reg.register(DDSPParameterCatalog.descriptors)
        let router = ParameterApplyRouter(registry: reg)
        let voice = PolySynthVoice(maxVoices: 4)
        voice.bindAutomatable(into: router)
        // env.attack is 0.001…10 s → 0.5 normalized ≈ 5.0005 s; the setter runs without crash.
        let applied = router.applyNormalized("ddsp.env.attack", 0.5)
        XCTAssertEqual(applied, reg.descriptor(for: "ddsp.env.attack")!.denormalized(0.5))
    }
}
