// PolySynthAutomationBindTests.swift
// DAW#1 — "all parameters automatable". Proves PolySynthVoice.bindAutomatable wires
// EXACTLY the bio-independent, render-effective DDSP params into the router (the
// placebo law: the automation picker offers only these, so no lane moves nothing),
// and that the bio-CONTESTED params are deliberately left out of slice 1.

import XCTest
import Foundation
@testable import Echoelmusic

@MainActor
final class PolySynthAutomationBindTests: XCTestCase {

    /// The exact set bindAutomatable wires, in DDSPParameterCatalog (registry) order.
    private let expected = [
        "ddsp.amp.level",      // → patchOutputLevel (uncontested output level)
        "ddsp.env.attack",
        "ddsp.env.decay",
        "ddsp.env.sustain",
        "ddsp.env.release",
        "ddsp.warmth.drive",
    ]

    private func makeWired() -> (PolySynthVoice, ParameterApplyRouter) {
        let reg = EchoelParameterRegistry()
        reg.register(DDSPParameterCatalog.descriptors)
        let router = ParameterApplyRouter(registry: reg)
        let voice = PolySynthVoice(maxVoices: 4)
        voice.bindAutomatable(into: router)
        return (voice, router)
    }

    func testBindAutomatable_bindsExactlyTheSafeSet() {
        let (_, router) = makeWired()
        // automatableDescriptors returns registry-known bound keyPaths in insertion order.
        XCTAssertEqual(router.automatableDescriptors().map(\.keyPath), expected)
    }

    func testBindAutomatable_excludesBioContestedParams() {
        let (_, router) = makeWired()
        for kp in ["ddsp.osc.harmonicity", "ddsp.osc.noiseLevel", "ddsp.osc.brightness",
                   "ddsp.fx.reverbMix", "ddsp.fx.reverbDecay",
                   "ddsp.mod.vibratoRate", "ddsp.mod.vibratoDepth",
                   "ddsp.filter.cutoff", "ddsp.osc.frequency"] {
            XCTAssertFalse(router.isBound(kp), "\(kp) is bio-contested/unsafe — must NOT be bound in slice 1")
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
