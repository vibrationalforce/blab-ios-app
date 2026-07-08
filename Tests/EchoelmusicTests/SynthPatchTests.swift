// SynthPatchTests.swift
// Echoel — patch round-trip + apply/capture against the DDSP synth.

import XCTest
@testable import Echoelmusic

final class SynthPatchTests: XCTestCase {

    func testCodableRoundTrip() throws {
        let patch = SynthPatch.factory[1] // Bright Lead
        let data = try JSONEncoder().encode(patch)
        let decoded = try JSONDecoder().decode(SynthPatch.self, from: data)
        XCTAssertEqual(decoded, patch)
    }

    func testUnisonRoundTrips() throws {
        var patch = SynthPatch.factory[1]
        patch.unisonVoices = 3
        patch.unisonDetuneCents = 14
        let data = try JSONEncoder().encode(patch)
        let decoded = try JSONDecoder().decode(SynthPatch.self, from: data)
        XCTAssertEqual(decoded.unisonVoices, 3)
        XCTAssertEqual(decoded.unisonDetuneCents, 14)
    }

    func testPreUnisonJSONStillDecodes() throws {
        // A patch JSON saved before unison existed has no unison keys; it must still
        // decode (optional fields → nil = off), so existing user sounds aren't lost.
        let json = """
        {"id":"00000000-0000-0000-0000-0000000000A1","name":"Old Pad",
         "attack":0.5,"decay":0.5,"sustain":0.8,"release":2.0,"envelopeCurve":"exponential",
         "harmonicity":0.88,"harmonicLevel":0.8,"brightness":0.25,"noiseLevel":0.01,
         "noiseColor":"pink","spectralShape":"dark","filterCutoff":220,"filterResonance":0.1,
         "lfoToFilterDepth":0.15,"filterLFORate":0.2,"filterLFODepth":0.3,
         "reverbMix":0.25,"reverbDecay":2.0,"vibratoRate":0,"vibratoDepth":0,
         "timbreProfile":"","timbreBlend":0}
        """
        let decoded = try JSONDecoder().decode(SynthPatch.self, from: Data(json.utf8))
        XCTAssertNil(decoded.unisonVoices, "missing unison key → nil (off)")
        XCTAssertNil(decoded.unisonDetuneCents)
        XCTAssertEqual(decoded.name, "Old Pad")
    }

    func testFactoryIDsAreStable() {
        let a = SynthPatch.factory.map { $0.id }
        let b = SynthPatch.factory.map { $0.id }
        XCTAssertEqual(a, b, "factory ids must be stable across accesses/relaunches")
        XCTAssertEqual(Set(a).count, a.count, "factory ids are unique")
    }

    func testFactoryDrone_isASlowAttackDrone() {
        guard let drone = SynthPatch.factory.first(where: { $0.name == "Drone" }) else {
            return XCTFail("factory must contain a Drone patch")
        }
        // The ambient recipe: seconds-long attack, even longer release,
        // sustained body, and a slow LFO moving the low-pass cutoff.
        XCTAssertGreaterThanOrEqual(drone.attack, 3.0, "drone attack blooms over seconds")
        XCTAssertGreaterThanOrEqual(drone.release, 5.0, "drone release outlasts the attack")
        XCTAssertGreaterThanOrEqual(drone.sustain, 0.8, "drone holds a sustained body")
        XCTAssertLessThanOrEqual(drone.filterLFORate, 0.1, "filter motion is slow (sub-0.1 Hz)")
        XCTAssertGreaterThanOrEqual(drone.filterLFODepth, 0.4, "filter motion is audible")
        XCTAssertGreaterThanOrEqual(drone.reverbMix, 0.5, "drone lives in space")
        XCTAssertEqual(drone.vibratoRate, 0, "no vibrato — stillness is the character")
    }

    func testCommunityIssueURL_isWellFormed_withEmbeddedJSON() {
        let patch = SynthPatch.factory[0]
        guard let url = patch.communityIssueURL() else { return XCTFail("nil URL") }
        XCTAssertEqual(url.host, "github.com")
        XCTAssertTrue(url.path.hasSuffix("/issues/new"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertTrue(items.contains { $0.name == "labels" && $0.value == "patch-submission" })
        XCTAssertTrue(items.contains { $0.name == "title" && ($0.value?.contains(patch.name) ?? false) })
        XCTAssertTrue((items.first { $0.name == "body" }?.value ?? "").contains("\"name\""))
    }

    @MainActor
    func testPatchRanking_favoritesThenRecentsThenNatural() {
        let a = SynthPatch.factory[0], b = SynthPatch.factory[1], c = SynthPatch.factory[2]
        let patches = [a, b, c] // natural order a,b,c
        XCTAssertEqual(PatchStore.ranked(patches, favorites: [], recents: []).map(\.id),
                       [a.id, b.id, c.id])
        XCTAssertEqual(PatchStore.ranked(patches, favorites: [c.id], recents: []).map(\.id),
                       [c.id, a.id, b.id])
        XCTAssertEqual(PatchStore.ranked(patches, favorites: [], recents: [b.id]).map(\.id),
                       [b.id, a.id, c.id])
        XCTAssertEqual(PatchStore.ranked(patches, favorites: [c.id], recents: [b.id]).map(\.id),
                       [c.id, b.id, a.id])
    }
}

#if canImport(Accelerate)
final class SynthPatchApplyTests: XCTestCase {

    func testApplyThenCapture() {
        let synth = EchoelDDSP(sampleRate: 48000)
        var patch = SynthPatch(name: "Test")
        patch.brightness = 0.7
        patch.attack = 0.1
        patch.harmonicity = 0.5
        patch.filterCutoff = 1234
        patch.reverbMix = 0.4
        patch.spectralShape = "bright"

        patch.apply(to: synth)
        XCTAssertEqual(synth.brightness, 0.7, accuracy: 0.001)
        XCTAssertEqual(synth.attack, 0.1, accuracy: 0.001)
        XCTAssertEqual(synth.harmonicity, 0.5, accuracy: 0.001)
        XCTAssertEqual(synth.filterCutoff, 1234, accuracy: 0.5)
        XCTAssertEqual(synth.reverbMix, 0.4, accuracy: 0.001)
        XCTAssertEqual(synth.spectralShape.rawValue, "bright")

        let captured = SynthPatch(name: "Captured", from: synth)
        XCTAssertEqual(captured.brightness, 0.7, accuracy: 0.001)
        XCTAssertEqual(captured.attack, 0.1, accuracy: 0.001)
        XCTAssertEqual(captured.spectralShape, "bright")
    }
}
#endif
