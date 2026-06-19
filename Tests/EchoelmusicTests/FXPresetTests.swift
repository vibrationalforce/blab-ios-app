// FXPresetTests.swift
// Echoel — the shareable FX preset format. Verifies a captured chain round-trips
// exactly through apply(), survives JSON encode/decode, and decodes leniently
// from a partial file (forward/backward compatible).

#if canImport(Accelerate)
import XCTest
@testable import Echoelmusic

final class FXPresetTests: XCTestCase {

    /// Build a chain with distinctive, non-default values across several stages.
    private func makeDistinctiveChain() -> EchoelFXChain {
        let c = EchoelFXChain()
        c.filterEnabled = true
        c.setFilter(mode: .bandpass, cutoff: 1234, resonance: 0.42)
        c.saturationDrive = 0.7
        c.saturationMix = 0.33
        c.delayEnabled = true
        c.delay.mode = .tape
        c.delay.timeSeconds = 0.375
        c.delay.feedback = 0.6
        c.delay.tone = 0.25
        c.phaserEnabled = true
        c.phaser.rate = 1.5
        c.phaser.depth = 0.8
        c.tremoloEnabled = true
        c.tremolo.stereoPan = true
        c.compressorEnabled = true
        c.compressor.thresholdDb = -24
        c.compressor.ratio = 6
        c.reverbEnabled = true
        c.reverb.roomSize = 0.9
        c.reverb.mix = 0.4
        c.reverb.width = 0.7
        c.harmonizerEnabled = true
        c.harmonizer.interval1 = 3
        c.harmonizer.mix = 0.6
        return c
    }

    func testCaptureThenApply_restoresEveryParameter() {
        let source = makeDistinctiveChain()
        let preset = FXPreset.capture(from: source, fxEnabled: true, name: "Test")

        let dest = EchoelFXChain()
        preset.apply(to: dest)

        XCTAssertTrue(dest.filterEnabled)
        XCTAssertEqual(dest.filterL.mode, .bandpass)
        XCTAssertEqual(dest.filterL.cutoff, 1234, accuracy: 1e-2)
        XCTAssertEqual(dest.filterR.cutoff, 1234, accuracy: 1e-2, "both channels set")
        XCTAssertEqual(dest.filterL.resonance, 0.42, accuracy: 1e-5)
        XCTAssertEqual(dest.saturationDrive, 0.7, accuracy: 1e-5)
        XCTAssertEqual(dest.saturationMix, 0.33, accuracy: 1e-5)
        XCTAssertTrue(dest.delayEnabled)
        XCTAssertEqual(dest.delay.mode, .tape)
        XCTAssertEqual(dest.delay.timeSeconds, 0.375, accuracy: 1e-5)
        XCTAssertEqual(dest.delay.feedback, 0.6, accuracy: 1e-5)
        XCTAssertEqual(dest.delay.tone, 0.25, accuracy: 1e-5)
        XCTAssertTrue(dest.phaserEnabled)
        XCTAssertEqual(dest.phaser.rate, 1.5, accuracy: 1e-5)
        XCTAssertEqual(dest.phaser.depth, 0.8, accuracy: 1e-5)
        XCTAssertTrue(dest.tremoloEnabled)
        XCTAssertTrue(dest.tremolo.stereoPan)
        XCTAssertTrue(dest.compressorEnabled)
        XCTAssertEqual(dest.compressor.thresholdDb, -24, accuracy: 1e-5)
        XCTAssertEqual(dest.compressor.ratio, 6, accuracy: 1e-5)
        XCTAssertTrue(dest.reverbEnabled)
        XCTAssertEqual(dest.reverb.roomSize, 0.9, accuracy: 1e-5)
        XCTAssertEqual(dest.reverb.mix, 0.4, accuracy: 1e-5)
        XCTAssertEqual(dest.reverb.width, 0.7, accuracy: 1e-5)
        XCTAssertTrue(dest.harmonizerEnabled)
        XCTAssertEqual(dest.harmonizer.interval1, 3, accuracy: 1e-5)
        XCTAssertEqual(dest.harmonizer.mix, 0.6, accuracy: 1e-5)
    }

    func testJSONRoundTrip_isExact() throws {
        let preset = FXPreset.capture(from: makeDistinctiveChain(),
                                      fxEnabled: true, name: "Vapor Wash",
                                      tags: ["vapor", "lush"])
        let data = try JSONEncoder().encode(preset)
        let decoded = try JSONDecoder().decode(FXPreset.self, from: data)
        XCTAssertEqual(decoded, preset)
        XCTAssertEqual(decoded.tags, ["vapor", "lush"])
    }

    func testLenientDecode_fillsDefaultsForMissingFields() throws {
        // A minimal file (only a name) must still decode to a usable preset.
        let json = Data(#"{"name":"Sparse"}"#.utf8)
        let p = try JSONDecoder().decode(FXPreset.self, from: json)
        XCTAssertEqual(p.name, "Sparse")
        XCTAssertTrue(p.limiterEnabled, "limiter defaults on (safety brick-wall)")
        XCTAssertEqual(p.filterModeRaw, "lowpass")
        XCTAssertEqual(p.schema, 1)
    }

    func testCuratedCommunity_nonEmpty_uniqueIDs_named_tagged() {
        let lib = FXPreset.curatedCommunity
        XCTAssertGreaterThanOrEqual(lib.count, 5, "a curated starter set ships")
        XCTAssertEqual(Set(lib.map(\.id)).count, lib.count, "ids are unique")
        XCTAssertFalse(lib.contains { $0.name.isEmpty }, "every preset is named")
        XCTAssertTrue(lib.allSatisfy { !$0.tags.isEmpty }, "every curated preset is tagged")
    }

    func testCommunityIssueURL_isWellFormed_withEmbeddedJSON() {
        let p = FXPreset.capture(from: makeDistinctiveChain(),
                                 fxEnabled: true, name: "My Sound", tags: ["test"])
        guard let url = p.communityIssueURL() else { return XCTFail("nil URL") }
        XCTAssertEqual(url.host, "github.com")
        XCTAssertTrue(url.path.hasSuffix("/issues/new"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertTrue(items.contains { $0.name == "labels" && $0.value == "preset-submission" })
        XCTAssertTrue(items.contains { $0.name == "title" && ($0.value?.contains("My Sound") ?? false) })
        let body = items.first { $0.name == "body" }?.value ?? ""
        XCTAssertTrue(body.contains("\"name\""), "preset JSON is embedded in the issue body")
    }

    @MainActor
    func testRanking_favoritesThenRecentsThenNewestSave() {
        let a = UUID(), b = UUID(), c = UUID()
        let chain = EchoelFXChain()
        let presets = [
            FXPreset.capture(from: chain, fxEnabled: true, id: a, name: "A"),
            FXPreset.capture(from: chain, fxEnabled: true, id: b, name: "B"),
            FXPreset.capture(from: chain, fxEnabled: true, id: c, name: "C")
        ]
        // No personalization → newest save first.
        XCTAssertEqual(FXPresetStore.ranked(presets, favorites: [], recents: []).map(\.id), [c, b, a])
        // Favorite A → A first, then newest.
        XCTAssertEqual(FXPresetStore.ranked(presets, favorites: [a], recents: []).map(\.id), [a, c, b])
        // Recently used B → B first, then newest.
        XCTAssertEqual(FXPresetStore.ranked(presets, favorites: [], recents: [b]).map(\.id), [b, c, a])
        // Favorite beats recent: A (fav) → B (recent) → C.
        XCTAssertEqual(FXPresetStore.ranked(presets, favorites: [a], recents: [b]).map(\.id), [a, b, c])
    }

    func testUnknownEnumRaw_fallsBackSafely() {
        var preset = FXPreset.capture(from: EchoelFXChain(), fxEnabled: true, name: "Bad")
        preset.filterModeRaw = "not-a-mode"
        preset.delayModeRaw = "nonsense"
        let dest = EchoelFXChain()
        preset.apply(to: dest)
        XCTAssertEqual(dest.filterL.mode, .lowpass, "unknown filter mode → lowpass")
        XCTAssertEqual(dest.delay.mode, .digital, "unknown delay mode → digital")
    }
}
#endif
