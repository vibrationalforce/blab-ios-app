// StudioDefaultKeysTests.swift
// H15-KEYSTORE: pins the single-sourced shared-preference defaults. These are
// FOUNDER decisions — if one of these assertions fails, someone changed a
// canonical default (needs a founder ask), re-introduced a per-view literal,
// or broke a key string. Pure value checks, Linux-CI safe.

import XCTest
@testable import Echoelmusic

final class StudioDefaultKeysTests: XCTestCase {

    func testCanonicalDefaults_matchFounderDecisions() {
        // Composition: the 8-bar produce-able phrase (H15-LOOPBARS shipped v271).
        XCTAssertEqual(StudioDefaultKeys.loopBars.value, .eight)
        // Genre home is self-observation — the visual's old .vaporwave copy put a
        // wrong genre into MP4 filenames on fresh installs.
        XCTAssertEqual(StudioDefaultKeys.genre.value, .selfObservation)
        XCTAssertEqual(StudioDefaultKeys.scale.value, .minor)
        XCTAssertEqual(StudioDefaultKeys.rootIndex.value, 0)
        XCTAssertFalse(StudioDefaultKeys.lockBPM.value)
        XCTAssertEqual(StudioDefaultKeys.lockedBPM.value, 70.0)
        XCTAssertEqual(StudioDefaultKeys.loudnessTarget.value, LoudnessTarget.streaming.rawValue)
        // The living visual greets a fresh install ("wow von Sekunde 1") — the
        // studio panel's old false copy made its toggle button lie until first write.
        XCTAssertTrue(StudioDefaultKeys.floatingVisualVisible.value)
        XCTAssertEqual(StudioDefaultKeys.visualStyle.value, 5)
        XCTAssertEqual(StudioDefaultKeys.visualStyleB.value, 0)
        XCTAssertEqual(StudioDefaultKeys.visualBlend.value, 0.0)
        XCTAssertEqual(StudioDefaultKeys.visualIntensity.value, 1.0)
        XCTAssertEqual(StudioDefaultKeys.visualDetail.value, 40.0)
        XCTAssertEqual(StudioDefaultKeys.visualMotion.value, 1.0)
        XCTAssertEqual(StudioDefaultKeys.visualSpread.value, 1.0)
        XCTAssertEqual(StudioDefaultKeys.visualHue.value, 0.0)
        XCTAssertEqual(StudioDefaultKeys.visualSaturation.value, 0.82)
        XCTAssertEqual(StudioDefaultKeys.touchMorphDepth.value, 0.6)
        XCTAssertEqual(StudioDefaultKeys.touchSlideVibrato.value, 0.35)
        XCTAssertEqual(StudioDefaultKeys.touchSlideChorus.value, 0.30)
        XCTAssertEqual(StudioDefaultKeys.touchGlide.value, 0.0)
        XCTAssertFalse(StudioDefaultKeys.weatherEnabled.value)
    }

    func testKeys_areTheShippedStringsAndUnique() {
        // The key STRINGS are the on-disk contract with every already-shipped
        // install — a typo here silently resets that preference for everyone.
        let keys = [
            StudioDefaultKeys.loopBars.key, StudioDefaultKeys.genre.key,
            StudioDefaultKeys.scale.key, StudioDefaultKeys.rootIndex.key,
            StudioDefaultKeys.lockBPM.key, StudioDefaultKeys.lockedBPM.key,
            StudioDefaultKeys.loudnessTarget.key,
            StudioDefaultKeys.visualStyle.key, StudioDefaultKeys.visualStyleB.key,
            StudioDefaultKeys.visualBlend.key, StudioDefaultKeys.visualIntensity.key,
            StudioDefaultKeys.visualDetail.key, StudioDefaultKeys.visualMotion.key,
            StudioDefaultKeys.visualSpread.key, StudioDefaultKeys.visualHue.key,
            StudioDefaultKeys.visualSaturation.key,
            StudioDefaultKeys.floatingVisualVisible.key,
            StudioDefaultKeys.touchMorphDepth.key,
            StudioDefaultKeys.touchSlideVibrato.key,
            StudioDefaultKeys.touchSlideChorus.key, StudioDefaultKeys.touchGlide.key,
            StudioDefaultKeys.weatherEnabled.key,
        ]
        XCTAssertEqual(keys.count, Set(keys).count, "keys must be unique")
        XCTAssertEqual(StudioDefaultKeys.loopBars.key, "studio.loopBars")
        XCTAssertEqual(StudioDefaultKeys.genre.key, "studio.genre")
        XCTAssertEqual(StudioDefaultKeys.scale.key, "studio.scale")
        XCTAssertEqual(StudioDefaultKeys.rootIndex.key, "studio.rootIndex")
        XCTAssertEqual(StudioDefaultKeys.lockBPM.key, "studio.lockBPM")
        XCTAssertEqual(StudioDefaultKeys.lockedBPM.key, "studio.lockedBPM")
        XCTAssertEqual(StudioDefaultKeys.loudnessTarget.key, "studio.loudnessTarget")
        XCTAssertEqual(StudioDefaultKeys.visualStyle.key, "visual.style")
        XCTAssertEqual(StudioDefaultKeys.visualStyleB.key, "visual.styleB")
        XCTAssertEqual(StudioDefaultKeys.visualBlend.key, "visual.blend")
        XCTAssertEqual(StudioDefaultKeys.visualIntensity.key, "visual.intensity")
        XCTAssertEqual(StudioDefaultKeys.visualDetail.key, "visual.detail")
        XCTAssertEqual(StudioDefaultKeys.visualMotion.key, "visual.motion")
        XCTAssertEqual(StudioDefaultKeys.visualSpread.key, "visual.spread")
        XCTAssertEqual(StudioDefaultKeys.visualHue.key, "visual.hue")
        XCTAssertEqual(StudioDefaultKeys.visualSaturation.key, "visual.saturation")
        XCTAssertEqual(StudioDefaultKeys.floatingVisualVisible.key, "visual.floating.visible")
        XCTAssertEqual(StudioDefaultKeys.touchMorphDepth.key, "touch.morphDepth")
        XCTAssertEqual(StudioDefaultKeys.touchSlideVibrato.key, "touch.slideVibrato")
        XCTAssertEqual(StudioDefaultKeys.touchSlideChorus.key, "touch.slideChorus")
        XCTAssertEqual(StudioDefaultKeys.touchGlide.key, "touch.glide")
        XCTAssertEqual(StudioDefaultKeys.weatherEnabled.key, "weather.enabled")
    }
}
