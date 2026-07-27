// MixerStoreTests.swift
// Echoel — the per-part MIXER (Module 1 of the comprehensive interface, founder
// 2026-07-11: "trenne die Stimmen auf mischbare Spuren … dann drehst du den Lead
// runter"). Guards the mixing law + persistence + the unity-default (a fresh
// install mixes exactly as before).

import XCTest
@testable import Echoelmusic

final class MixerStoreTests: XCTestCase {

    // MARK: - The mixing law (pure)

    func testCombinedIsGenreTimesUser() {
        XCTAssertEqual(MixerStore.combined(genre: 0.9, user: 1.0), 0.9, accuracy: 1e-6,
                       "unity user leaves the genre balance unchanged")
        XCTAssertEqual(MixerStore.combined(genre: 0.9, user: 0.0), 0.0, accuracy: 1e-6,
                       "user 0 mutes the part")
        XCTAssertEqual(MixerStore.combined(genre: 0.9, user: 0.5), 0.45, accuracy: 1e-6,
                       "the user pulls the shrill part down")
    }

    func testCombinedClampsNegativesToZero() {
        XCTAssertEqual(MixerStore.combined(genre: -1, user: 1), 0)
        XCTAssertEqual(MixerStore.combined(genre: 1, user: -1), 0)
    }

    func testFaderRangeAllowsMuteAndSlightBoost() {
        XCTAssertEqual(MixerStore.range.lowerBound, 0, "a part can be fully muted")
        XCTAssertGreaterThan(MixerStore.range.upperBound, 1, "a part can be lifted above unity")
    }

    // MARK: - Store behaviour (persistence + defaults)

    @MainActor
    private func freshDefaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "mixer.test.\(UUID().uuidString)")!
        return d
    }

    @MainActor
    func testFreshInstallIsUnity() {
        let store = MixerStore(defaults: freshDefaults())
        XCTAssertEqual(store.bass, 1.0)
        XCTAssertEqual(store.pad, 1.0)
        XCTAssertEqual(store.lead, 1.0)
        XCTAssertEqual(store.drums, 1.0)
    }

    @MainActor
    func testLevelForRoleMapsToTheRightFader() {
        let store = MixerStore(defaults: freshDefaults())
        store.bass = 0.7; store.pad = 0.8; store.lead = 0.3
        XCTAssertEqual(store.level(for: .bass), 0.7)
        XCTAssertEqual(store.level(for: .harmony), 0.8, "pad fader drives the harmony role")
        XCTAssertEqual(store.level(for: .lead), 0.3)
    }

    @MainActor
    func testLevelsPersistAcrossReload() {
        let defaults = freshDefaults()
        do {
            let store = MixerStore(defaults: defaults)
            store.lead = 0.4
            store.bass = 1.2
        }
        let reloaded = MixerStore(defaults: defaults)
        XCTAssertEqual(reloaded.lead, 0.4, accuracy: 1e-6, "the pulled-down lead survives relaunch")
        XCTAssertEqual(reloaded.bass, 1.2, accuracy: 1e-6)
        XCTAssertEqual(reloaded.pad, 1.0, "an untouched fader is still unity")
    }

    @MainActor
    func testResetToUnity() {
        let store = MixerStore(defaults: freshDefaults())
        store.bass = 0.2; store.pad = 0.3; store.lead = 0.1; store.drums = 0.5
        store.resetToUnity()
        XCTAssertEqual(store.bass, 1.0)
        XCTAssertEqual(store.pad, 1.0)
        XCTAssertEqual(store.lead, 1.0)
        XCTAssertEqual(store.drums, 1.0)
    }

    @MainActor
    func testDrumsLevelPersists() {
        let defaults = freshDefaults()
        do { MixerStore(defaults: defaults).drums = 0.6 }
        XCTAssertEqual(MixerStore(defaults: defaults).drums, 0.6, accuracy: 1e-6,
                       "the drums fader survives relaunch")
    }

    /// The cap that keeps a fader from destroying velocity dynamics (device log 2470).
    /// `range` allows 1.5, so without this a fader past unity multiplied every note into
    /// `finish()`'s `min(1, …)` clamp — every note pinned at exactly 1.000, one flat
    /// fortissimo, and the stacked full-scale chord that drives the limiter into
    /// per-sample gain steps ("es knistert").
    func testCombined_userAboveUnity_cannotBoost() {
        // The whole above-unity span collapses to the unity result — no boost, and no
        // dependence on how far past unity the fader sits.
        for user in [Float(1.0), 1.1, 1.25, 1.5] {
            XCTAssertEqual(MixerStore.combined(genre: 0.9, user: user), 0.9, accuracy: 1e-6,
                           "user \(user) must not boost past the genre level")
        }
        // Attenuation is untouched — the direction that always worked still works.
        XCTAssertEqual(MixerStore.combined(genre: 0.9, user: 0.25), 0.225, accuracy: 1e-6)
    }

    /// The failure this guards, stated end-to-end: a full-velocity note through a
    /// boosted fader must not come back at the clamp ceiling.
    func testCombined_boostedFader_doesNotPinAFullVelocityNoteAtOne() {
        let f = MixerStore.combined(genre: 1.0, user: 1.5)
        let velocity = Swift.min(Float(1), Swift.max(0, 0.66 * f))
        XCTAssertEqual(velocity, 0.66, accuracy: 1e-6,
                       "a boosted fader flattened a 0.66 note to the 1.0 clamp")
    }
}
