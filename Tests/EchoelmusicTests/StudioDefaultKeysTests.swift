// StudioDefaultKeysTests.swift
// H15-KEYSTORE: pins the single-sourced shared-preference defaults. These are
// FOUNDER decisions — if one of these assertions fails, someone changed a
// canonical default (needs a founder ask), re-introduced a per-view literal,
// or broke a key string. Pure value checks, Linux-CI safe.

import XCTest
@testable import Echoelmusic

final class StudioDefaultKeysTests: XCTestCase {

    func testCanonicalDefaults_matchFounderDecisions() {
        // #603 B1: guide OFF on fresh installs — invited, never imposed (first contact
        // belongs to Onboarding + instrument home). Key read by WorkspaceView + the
        // Save & Export toggle, hence keystore.
        XCTAssertEqual(StudioDefaultKeys.guideVisible.value, false)
        XCTAssertEqual(StudioDefaultKeys.guideVisible.key, "studio.guideVisible")
        // #604: hint retires on lesson-learned or the cap — key string deliberately kept
        // from the pre-keystore literal so already-taught users stay retired.
        XCTAssertEqual(StudioDefaultKeys.instrumentHintSeen.value, false)
        XCTAssertEqual(StudioDefaultKeys.instrumentHintSeen.key, "onboard.instrumentHintSeen")
        XCTAssertEqual(StudioDefaultKeys.instrumentHintShows.value, 0)
        XCTAssertEqual(StudioDefaultKeys.instrumentHintShows.key, "onboard.instrumentHintShows")
        XCTAssertEqual(StudioDefaultKeys.instrumentHintShowCap, 5)
        // #608: Auto mode ships OFF — steering the mood dials unasked is the one
        // thing the feature must never do first. Key read by AutoModeRow (door) +
        // makeComposerInput (fold), hence keystore. The BLOCKING pin lives in
        // Tests/CISmoke/AutoModeStartsOffAndOwnsNoTempoTests (this suite is
        // compiled by no gate, #208).
        XCTAssertEqual(StudioDefaultKeys.autoMode.value, false)
        XCTAssertEqual(StudioDefaultKeys.autoMode.key, "studio.autoMode")
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

        // #187 — inbound Apple Network MIDI (RTP-MIDI) is OFF on a fresh install.
        // This is a FOUNDER decision, not a taste setting: with it on, the device
        // advertises _apple-midi._udp and accepts a connection from ANY host on the
        // LAN (connectionPolicy .anyone) from launch, with nothing in the UI saying
        // so. A default-ON inbound network service is not something a performer opts
        // into by installing an instrument. If this assertion ever fails, someone
        // re-armed an always-on listener — that needs a founder ask, not a commit.
        XCTAssertFalse(StudioDefaultKeys.networkMIDI.value)
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
            StudioDefaultKeys.autoMode.key,
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
            StudioDefaultKeys.touchSyncStrength.key, StudioDefaultKeys.touchSyncGrid.key,
            StudioDefaultKeys.weatherEnabled.key,
            StudioDefaultKeys.networkMIDI.key,
            // #713/#714. Also pinned in the BLOCKING bundle
            // (`Tests/CISmoke/MIDIOutQualitySwitchesTests`, claim 1) together with their
            // defaults — listed here too because `StudioDefaultKeys`' own header asks for it,
            // and because THIS is the uniqueness check.
            StudioDefaultKeys.midiOutMPE.key, StudioDefaultKeys.midiOutExpression.key,
        ]
        XCTAssertEqual(keys.count, Set(keys).count, "keys must be unique")
        // ULTRASYNC ships OFF. This pins that as a decision, not an accident: the value
        // controls WHEN a played note sounds, and nobody should meet that by surprise
        // after an update. Changing it is a founder call.
        XCTAssertEqual(StudioDefaultKeys.touchSyncStrength.value, 0,
                       "touch sync must ship off — it changes when a played note sounds")
        XCTAssertEqual(StudioDefaultKeys.touchSyncGrid.value, .sixteenth)
        XCTAssertEqual(StudioDefaultKeys.loopBars.key, "studio.loopBars")
        XCTAssertEqual(StudioDefaultKeys.genre.key, "studio.genre")
        XCTAssertEqual(StudioDefaultKeys.scale.key, "studio.scale")
        XCTAssertEqual(StudioDefaultKeys.rootIndex.key, "studio.rootIndex")
        XCTAssertEqual(StudioDefaultKeys.lockBPM.key, "studio.lockBPM")
        XCTAssertEqual(StudioDefaultKeys.lockedBPM.key, "studio.lockedBPM")
        XCTAssertEqual(StudioDefaultKeys.loudnessTarget.key, "studio.loudnessTarget")
        XCTAssertEqual(StudioDefaultKeys.networkMIDI.key, "midi.networkSession")
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
