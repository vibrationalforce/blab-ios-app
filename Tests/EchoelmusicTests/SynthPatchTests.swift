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
        // This JSON also predates outputLevel + warmthDrive: the decode succeeding
        // at all proves any later field stayed OPTIONAL (a non-optional addition
        // would throw here). Lock their computed fallbacks too, so a change to the
        // fallback is caught rather than silently altering every old patch.
        XCTAssertNil(decoded.outputLevel)
        XCTAssertNil(decoded.warmthDrive)
        XCTAssertEqual(decoded.level, 1.0, accuracy: 1e-6, "no outputLevel → unity")
        XCTAssertEqual(decoded.warmth, 0, accuracy: 1e-6, "no warmthDrive → dry")
    }

    func testFactoryIDsAreStable() {
        let a = SynthPatch.factory.map { $0.id }
        let b = SynthPatch.factory.map { $0.id }
        XCTAssertEqual(a, b, "factory ids must be stable across accesses/relaunches")
        XCTAssertEqual(Set(a).count, a.count, "factory ids are unique")
    }

    func testEchoelSynth_isTheResponsivePlaySurfaceDefault() {
        guard let touch = SynthPatch.factory.first(where: { $0.id == SynthPatch.touchDefaultID }) else {
            return XCTFail("factory must contain the Echoel Synth play-surface default")
        }
        XCTAssertEqual(touch.name, "Echoel Synth")
        // The point of this patch: PLAYABLE under a finger — a quick attack (not the
        // old 0.5 s Warm Pad mush) with unison width for an organic pad.
        XCTAssertLessThanOrEqual(touch.attack, 0.1, "touch default answers a finger immediately")
        XCTAssertGreaterThan(touch.release, 0.5, "still a pad — it rings, doesn't clip off")
        XCTAssertEqual(touch.unisonVoices, 2, "a little width for organic body")
        XCTAssertNotNil(touch.unisonDetuneCents)
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

    // MARK: - Defensive decoding (the #95 data-loss fix)
    // Pure Codable — kept in the UNGUARDED class (like testPreUnisonJSONStillDecodes) so this
    // platform-independent data-loss regression guard runs even under a future Linux swift-test.

    func testDecode_missingTimbreFields_usesDefaults_doesNotThrow() throws {
        // A patch JSON saved BEFORE timbreProfile/timbreBlend existed (2026-07-11): those keys
        // are absent. Before the custom decoder this threw keyNotFound and PatchStore's `?? []`
        // wiped the whole user library. It must now decode with defaults.
        let json = Data("""
        {"id":"3B1F0C2E-0000-4000-8000-000000000001","name":"Old Patch",
         "attack":0.5,"decay":0.5,"sustain":0.8,"release":2.0,"envelopeCurve":"exponential",
         "harmonicity":0.88,"harmonicLevel":0.8,"brightness":0.25,"noiseLevel":0.01,
         "noiseColor":"pink","spectralShape":"dark","filterCutoff":220,"filterResonance":0.1,
         "lfoToFilterDepth":0.15,"filterLFORate":0.2,"filterLFODepth":0.3,"reverbMix":0.25,
         "reverbDecay":2.0,"vibratoRate":0,"vibratoDepth":0}
        """.utf8)
        let p = try JSONDecoder().decode(SynthPatch.self, from: json)
        XCTAssertEqual(p.name, "Old Patch")
        XCTAssertEqual(p.timbreProfile, "", "absent timbreProfile must default, not throw")
        XCTAssertEqual(p.timbreBlend, 0)
    }

    func testDecode_minimalJSON_fillsEveryDefault() throws {
        // Even a near-empty object must decode (bulletproof against any future field add).
        let p = try JSONDecoder().decode(SynthPatch.self, from: Data(#"{"name":"Minimal"}"#.utf8))
        XCTAssertEqual(p.name, "Minimal")
        XCTAssertEqual(p.attack, 0.5)            // memberwise default
        XCTAssertEqual(p.spectralShape, "dark")
        XCTAssertNil(p.unisonVoices)             // optionals stay nil
        XCTAssertNil(p.warmthDrive)
    }

    func testDecode_patchArray_oneOldPatchDoesNotNukeTheWholeLibrary() throws {
        // The real PatchStore failure mode: decoding [SynthPatch]; before the fix one old
        // (pre-timbre) patch threw and the array load fell back to empty. Now all survive.
        let old = #"{"name":"Old"}"#
        let patches = try JSONDecoder().decode([SynthPatch].self,
                                               from: Data("[\(old),\(old),\(old)]".utf8))
        XCTAssertEqual(patches.count, 3, "one legacy patch must not drop the whole library")
    }

    func testDecode_fullPatch_roundTripsIdentically() throws {
        // Regression guard: for JSON that HAS every field, the custom decoder is bit-identical
        // to the synthesized one — a full round-trip is identity.
        let original = SynthPatch(name: "RT", attack: 0.11, timbreProfile: "violin",
                                  timbreBlend: 0.7, unisonVoices: 3, unisonDetuneCents: 12,
                                  outputLevel: 0.8, warmthDrive: 0.3)
        let decoded = try JSONDecoder().decode(SynthPatch.self,
                                               from: try JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
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
        // SynthPatch.match is deliberately case-INSENSITIVE (forward/backward compat
        // with older saved patches), but EchoelDDSP.SpectralShape's rawValues are
        // Title Case ("Bright", not "bright") — assert against the real rawValue.
        patch.spectralShape = "Bright"

        patch.apply(to: synth)
        XCTAssertEqual(synth.brightness, 0.7, accuracy: 0.001)
        XCTAssertEqual(synth.attack, 0.1, accuracy: 0.001)
        XCTAssertEqual(synth.harmonicity, 0.5, accuracy: 0.001)
        XCTAssertEqual(synth.filterCutoff, 1234, accuracy: 0.5)
        XCTAssertEqual(synth.reverbMix, 0.4, accuracy: 0.001)
        XCTAssertEqual(synth.spectralShape.rawValue, "Bright")

        let captured = SynthPatch(name: "Captured", from: synth)
        XCTAssertEqual(captured.brightness, 0.7, accuracy: 0.001)
        XCTAssertEqual(captured.attack, 0.1, accuracy: 0.001)
        XCTAssertEqual(captured.spectralShape, "Bright")
    }
}
#endif
