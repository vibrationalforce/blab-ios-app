// TimelineTests.swift
// Echoel — locks the Arrange-timeline foundation (Stage 1): the 480-PPQ time
// model, the snap engine (snap-to-beat AND stepless), and the document's
// Codable/query behaviour. Pure — runs on Linux CI.

import XCTest
@testable import Echoelmusic

final class TimelineTests: XCTestCase {

    // MARK: - Time constants (the one shared resolution)

    func testTimeConstants_matchNotePPQ() {
        XCTAssertEqual(TimelineTime.ticksPerQuarter, Note.ticksPerQuarter)   // 480
        XCTAssertEqual(TimelineTime.ticksPerBar, 1920)
        XCTAssertEqual(TimelineTime.ticksPerTransportStep, Note.ticksPerStep) // 120
    }

    func testTransportStepConversion() {
        // Transport absoluteStep = bar*16 + step; bar 2, step 4 → (2*16+4)*120.
        XCTAssertEqual(TimelineTime.tick(fromAbsoluteStep: 0), 0)
        XCTAssertEqual(TimelineTime.tick(fromAbsoluteStep: 36), 4320)
    }

    func testSecondsConversion() {
        // 120 BPM: one quarter (480 ticks) = 0.5 s; one bar = 2 s.
        XCTAssertEqual(TimelineTime.seconds(fromTicks: 480, bpm: 120), 0.5, accuracy: 1e-9)
        XCTAssertEqual(TimelineTime.seconds(fromTicks: 1920, bpm: 120), 2.0, accuracy: 1e-9)
        // Guard: nonsense tempo never divides by zero.
        XCTAssertEqual(TimelineTime.seconds(fromTicks: 480, bpm: 0), 0)
    }

    // MARK: - Snap engine

    func testSnap_toBeat_roundsToNearestGridLine() {
        XCTAssertEqual(TimelineSnap.snap(0, to: .beat), 0)
        XCTAssertEqual(TimelineSnap.snap(239, to: .beat), 0)      // below half-grid → down
        XCTAssertEqual(TimelineSnap.snap(241, to: .beat), 480)    // above half-grid → up
        XCTAssertEqual(TimelineSnap.snap(480, to: .beat), 480)    // on-grid unchanged
    }

    func testSnap_off_isStepless_identity() {
        // "aber auch stufenlose Verschiebung" — .off must never quantize.
        for tick in [0, 1, 7, 119, 481, 1919, 12345] {
            XCTAssertEqual(TimelineSnap.snap(tick, to: .off), tick)
        }
    }

    func testSnap_neverNegative() {
        XCTAssertEqual(TimelineSnap.snap(-500, to: .beat), 0)
        XCTAssertEqual(TimelineSnap.snap(-3, to: .off), 0)
    }

    func testSnap_allResolutions_produceOnGridResults() {
        for res in SnapResolution.allCases where res != .off {
            guard let grid = res.ticks else { return XCTFail("grid nil for \(res)") }
            let snapped = TimelineSnap.snap(1000, to: res)
            XCTAssertEqual(snapped % grid, 0, "\(res) must land on its grid")
        }
    }

    func testMagneticSnap_pullsOnlyWithinMagnetRange() {
        // 30 ticks from the beat line, magnet 40 → pulled onto the line.
        XCTAssertEqual(TimelineSnap.magneticSnap(450, to: .beat, magnetTicks: 40), 480)
        // 30 ticks away but magnet only 20 → stays free (stepless feel).
        XCTAssertEqual(TimelineSnap.magneticSnap(450, to: .beat, magnetTicks: 20), 450)
        // Off = always free regardless of magnet.
        XCTAssertEqual(TimelineSnap.magneticSnap(450, to: .off, magnetTicks: 1000), 450)
    }

    // MARK: - Regions + document

    func testRegion_clampsAndEndTick() {
        let lane = UUID(), clip = UUID()
        let r = TimelineRegion(laneID: lane, clipID: clip,
                               startTick: -10, lengthTicks: 0, contentOffsetSeconds: -1)
        XCTAssertEqual(r.startTick, 0)          // no negative start
        XCTAssertEqual(r.lengthTicks, 1)        // never zero-length
        XCTAssertEqual(r.contentOffsetSeconds, 0)
        XCTAssertEqual(r.endTick, 1)
    }

    func testDocument_laneQuery_sortsByStart() {
        let lane = TimelineLane(name: "MIDI 1", kind: .midi)
        let other = TimelineLane(name: "Audio 1", kind: .audio)
        let clip = UUID()
        let a = TimelineRegion(laneID: lane.id, clipID: clip, startTick: 1920, lengthTicks: 480)
        let b = TimelineRegion(laneID: lane.id, clipID: clip, startTick: 0, lengthTicks: 480)
        let c = TimelineRegion(laneID: other.id, clipID: clip, startTick: 960, lengthTicks: 480)
        let doc = TimelineDocument(lanes: [lane, other], regions: [a, b, c])

        XCTAssertEqual(doc.regions(in: lane.id).map(\.startTick), [0, 1920])
        XCTAssertEqual(doc.endTick, 2400)       // a ends at 1920+480
    }

    func testDocument_codableRoundTrip() throws {
        let lane = TimelineLane(name: "Bio", kind: .visual, isBio: true)
        let region = TimelineRegion(laneID: lane.id, clipID: UUID(),
                                    startTick: 333, lengthTicks: 777,
                                    contentOffsetSeconds: 1.25)
        let doc = TimelineDocument(lanes: [lane], regions: [region])
        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(TimelineDocument.self, from: data)
        XCTAssertEqual(back, doc)               // stepless positions survive exactly
    }

    // MARK: - Legacy-song migration (Stage 1b)

    @MainActor
    func testMigration_sectionsBecomeBarAlignedRegionsOnMIDILane() {
        let clipA = UUID(), clipB = UUID()
        let sections = [
            ArrangementSection(clipID: clipA, name: "Intro", colorIndex: 0, lengthBars: 2),
            ArrangementSection(clipID: nil,   name: "Gap",   colorIndex: 0, lengthBars: 1),
            ArrangementSection(clipID: clipB, name: "Drop",  colorIndex: 1, lengthBars: 4),
        ]
        let doc = TimelineStore.migrate(sections: sections)

        // Lanes: one MIDI + one empty Audio (multi-lane shape from day one).
        XCTAssertEqual(doc.lanes.map(\.kind), [.midi, .audio])
        let midiLane = doc.lanes[0]

        // Regions: gap creates none but advances the cursor; all bar-aligned.
        let regions = doc.regions(in: midiLane.id)
        XCTAssertEqual(regions.count, 2)
        XCTAssertEqual(regions[0].clipID, clipA)
        XCTAssertEqual(regions[0].startTick, 0)
        XCTAssertEqual(regions[0].lengthTicks, 2 * TimelineTime.ticksPerBar)
        XCTAssertEqual(regions[1].clipID, clipB)
        // Drop starts after Intro (2 bars) + Gap (1 bar) = bar 3.
        XCTAssertEqual(regions[1].startTick, 3 * TimelineTime.ticksPerBar)
        XCTAssertEqual(regions[1].lengthTicks, 4 * TimelineTime.ticksPerBar)
        XCTAssertEqual(doc.regions(in: doc.lanes[1].id), [])
    }

    @MainActor
    func testMigration_emptySong_seedsDefaultLanesOnly() {
        let doc = TimelineStore.migrate(sections: [])
        XCTAssertEqual(doc.lanes.count, 2)
        XCTAssertTrue(doc.regions.isEmpty)
        XCTAssertEqual(doc.endTick, 0)
    }

    func testSnapResolution_rawValues_stableForPersistence() {
        XCTAssertEqual(SnapResolution.bar.rawValue, "bar")
        XCTAssertEqual(SnapResolution.sixteenth.rawValue, "sixteenth")
        XCTAssertEqual(SnapResolution.off.rawValue, "off")
    }

    // MARK: - Lane mixer math (K2a)

    func testEffectiveGain_levelMuteAndClamp() {
        var doc = TimelineDocument(lanes: [
            TimelineLane(name: "MIDI 1", kind: .midi),
            TimelineLane(name: "Audio 1", kind: .audio, level: 0.5),
        ])
        XCTAssertEqual(doc.effectiveGain(for: doc.lanes[0].id), 1)
        XCTAssertEqual(doc.effectiveGain(for: doc.lanes[1].id), 0.5)
        doc.lanes[0].isMuted = true
        XCTAssertEqual(doc.effectiveGain(for: doc.lanes[0].id), 0)
        // Level clamps into 0…2 even if a stored document carries junk.
        doc.lanes[1].level = 9
        XCTAssertEqual(doc.effectiveGain(for: doc.lanes[1].id), 2)
        // Unknown lane → silent, never a crash.
        XCTAssertEqual(doc.effectiveGain(for: UUID()), 0)
    }

    func testEffectiveGain_soloSilencesOthers_muteWinsOverOwnSolo() {
        var doc = TimelineDocument(lanes: [
            TimelineLane(name: "A", kind: .midi),
            TimelineLane(name: "B", kind: .audio, level: 0.8, isSoloed: true),
        ])
        XCTAssertEqual(doc.effectiveGain(for: doc.lanes[0].id), 0)     // not soloed
        XCTAssertEqual(doc.effectiveGain(for: doc.lanes[1].id), 0.8)   // the solo
        // Mute beats the lane's own solo.
        doc.lanes[1].isMuted = true
        XCTAssertEqual(doc.effectiveGain(for: doc.lanes[1].id), 0)
    }

    func testRollSlotGain_firstNonBioMIDILaneOwnsTheRoll() {
        var doc = TimelineDocument(lanes: [
            TimelineLane(name: "Bio", kind: .midi, isBio: true),
            TimelineLane(name: "MIDI 1", kind: .midi, level: 0.7),
            TimelineLane(name: "MIDI 2", kind: .midi, level: 0.2),
        ])
        XCTAssertEqual(doc.rollSlotGain, 0.7)                    // bio lane skipped
        doc.lanes[1].isMuted = true
        XCTAssertEqual(doc.rollSlotGain, 0)                      // mute reaches the roll
        // No MIDI lane at all → unity (roll not represented on the timeline).
        let audioOnly = TimelineDocument(lanes: [TimelineLane(name: "A", kind: .audio)])
        XCTAssertEqual(audioOnly.rollSlotGain, 1)
    }

    // MARK: - Roll-slot silence reason + one-tap fix (#22, "alles ist still")

    func testRollSilenceReason_audibleByDefault_isNil() {
        let doc = TimelineDocument(lanes: [
            TimelineLane(name: "MIDI 1", kind: .midi),
            TimelineLane(name: "Audio 1", kind: .audio),
        ])
        XCTAssertNil(doc.rollSlotSilenceReason)          // fresh lanes are audible
        // No MIDI lane at all → not "silenced", just unrepresented.
        let audioOnly = TimelineDocument(lanes: [TimelineLane(name: "A", kind: .audio)])
        XCTAssertNil(audioOnly.rollSlotSilenceReason)
    }

    func testRollSilenceReason_muteWinsOverForeignSoloAndLevel() {
        var doc = TimelineDocument(lanes: [
            TimelineLane(name: "MIDI 1", kind: .midi),
            TimelineLane(name: "Drums", kind: .audio, isSoloed: true),
        ])
        // A foreign solo silences the roll…
        XCTAssertEqual(doc.rollSlotSilenceReason, .otherSoloed)
        // …but an explicit mute on the roll lane takes precedence (matches effectiveGain).
        doc.lanes[0].isMuted = true
        XCTAssertEqual(doc.rollSlotSilenceReason, .muted)
    }

    func testRollSilenceReason_levelZero() {
        var doc = TimelineDocument(lanes: [TimelineLane(name: "MIDI 1", kind: .midi)])
        doc.lanes[0].level = 0
        XCTAssertEqual(doc.rollSlotSilenceReason, .levelZero)
    }

    func testUnsilenceRollSlot_unmutesLiftsFaderAndClearsForeignSolo() {
        var doc = TimelineDocument(lanes: [
            TimelineLane(name: "MIDI 1", kind: .midi, level: 0, isMuted: true),
            TimelineLane(name: "Drums", kind: .audio, isSoloed: true),
        ])
        XCTAssertNotNil(doc.rollSlotSilenceReason)
        doc.unsilenceRollSlot()
        XCTAssertNil(doc.rollSlotSilenceReason)           // now audible
        XCTAssertFalse(doc.lanes[0].isMuted)
        XCTAssertEqual(doc.lanes[0].level, 1)             // zeroed fader lifted to unity
        XCTAssertFalse(doc.lanes[1].isSoloed)             // foreign solo cleared
        XCTAssertEqual(doc.rollSlotGain, 1)
        doc.unsilenceRollSlot()                           // idempotent
        XCTAssertNil(doc.rollSlotSilenceReason)
    }

    /// `healRollSlotNamingCause` exists so the Start breadcrumb cannot name the wrong
    /// thing. The two-step form (read the reason, then heal) is order-dependent — after
    /// the heal the reason is nil by construction — and a reordered read fails SILENTLY,
    /// logging "unknown" forever while both halves stay individually correct.
    ///
    /// My first version of this test was named for that ordering and could not detect a
    /// reordering, because it exercised only this type and never the call site. Review
    /// caught it. The answer was not a better test but a better shape: one call, so there
    /// is no order left to get wrong. This now tests the thing that removed the hazard.
    func testHealRollSlotNamingCause_returnsTheCauseItRepaired() {
        let cases: [(TimelineLane, TimelineDocument.RollSilenceReason)] = [
            (TimelineLane(name: "MIDI 1", kind: .midi, isMuted: true), .muted),
            (TimelineLane(name: "MIDI 1", kind: .midi, level: 0), .levelZero),
        ]
        for (lane, expected) in cases {
            var doc = TimelineDocument(lanes: [lane])
            XCTAssertEqual(doc.healRollSlotNamingCause(), expected)
            XCTAssertNil(doc.rollSlotSilenceReason, "and it healed while naming")
        }

        // A foreign solo is the third cause, and needs a second lane to hold it.
        var soloed = TimelineDocument(lanes: [
            TimelineLane(name: "MIDI 1", kind: .midi),
            TimelineLane(name: "Audio", kind: .audio, isSoloed: true),
        ])
        XCTAssertEqual(soloed.healRollSlotNamingCause(), .otherSoloed)
        XCTAssertNil(soloed.rollSlotSilenceReason)
    }

    /// Nothing wrong ⇒ nil, and nothing written. Without this the breadcrumb could fire
    /// on every Start of a perfectly healthy project and turn the diag log into noise —
    /// which is how a real cause stops being noticed.
    func testHealRollSlotNamingCause_isNilAndInertWhenAlreadyAudible() {
        var doc = TimelineDocument(lanes: [TimelineLane(name: "MIDI 1", kind: .midi)])
        let before = doc
        XCTAssertNil(doc.healRollSlotNamingCause())
        XCTAssertEqual(doc, before, "a healthy document must not be rewritten")
    }

    /// The three causes must stay distinguishable in a log line. A raw value that
    /// collides or renames turns a founder's pasted log into a wrong diagnosis.
    func testSilenceReasonRawValuesAreDistinctAndStable() {
        // (A `Set(...).count == 3` check stood here and was DELETED: Swift rejects
        // duplicate enum raw values at compile time, so it could never go red — the
        // same can't-fail category as task #140. The line below strictly subsumes it.)
        let all: [TimelineDocument.RollSilenceReason] = [.muted, .otherSoloed, .levelZero]
        XCTAssertEqual(all.map(\.rawValue), ["muted", "otherSoloed", "levelZero"])
    }

    func testUnsilenceRollSlot_keepsRollOwnSolo_andNonZeroLevel() {
        var doc = TimelineDocument(lanes: [
            TimelineLane(name: "MIDI 1", kind: .midi, level: 0.7, isMuted: true, isSoloed: true),
        ])
        doc.unsilenceRollSlot()
        XCTAssertFalse(doc.lanes[0].isMuted)
        XCTAssertTrue(doc.lanes[0].isSoloed)              // its OWN solo is untouched
        XCTAssertEqual(doc.lanes[0].level, 0.7)           // a healthy level is not reset
    }

    func testLaneDecode_preK2aDocumentWithoutMixKeys_defaultsToUnity() throws {
        // A lane persisted BEFORE the mixer strip existed (no level/mute/solo keys)
        // must decode with unity defaults — nobody's timeline may fail to load.
        let legacyJSON = """
        {"id":"\(UUID().uuidString)","name":"MIDI 1","kind":"midi","isBio":false}
        """
        let lane = try JSONDecoder().decode(TimelineLane.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(lane.level, 1)
        XCTAssertFalse(lane.isMuted)
        XCTAssertFalse(lane.isSoloed)
        XCTAssertEqual(lane.pan, 0)   // pre-B2: no pan key → center
    }

    func testLaneMixState_roundTripsThroughCodable() throws {
        let lane = TimelineLane(name: "A", kind: .audio, level: 1.25,
                                isMuted: true, isSoloed: true, pan: -0.4)
        let data = try JSONEncoder().encode(lane)
        let back = try JSONDecoder().decode(TimelineLane.self, from: data)
        XCTAssertEqual(back, lane)
    }

    // MARK: - Per-track patch (per-instrument EchoelSynth, Module 1 foundation)

    func testLaneDecode_preTrackPatchDocument_defaultsToNilPatch() throws {
        // A lane persisted BEFORE per-track patches existed carries no `patch`
        // key — it must decode to nil (= today's global sound), never fail to load.
        let legacyJSON = """
        {"id":"\(UUID().uuidString)","name":"MIDI 1","kind":"midi","isBio":false,"level":1}
        """
        let lane = try JSONDecoder().decode(TimelineLane.self, from: Data(legacyJSON.utf8))
        XCTAssertNil(lane.patch)
    }

    func testLanePatch_roundTripsThroughCodable() throws {
        let patch = try XCTUnwrap(SynthPatch.factory.first)
        let lane = TimelineLane(name: "Lead", kind: .midi, patch: patch)
        let data = try JSONEncoder().encode(lane)
        let back = try JSONDecoder().decode(TimelineLane.self, from: data)
        XCTAssertEqual(back, lane)
        XCTAssertEqual(back.patch, patch)
    }

    func testLanePatch_defaultInitIsNil_noBehaviorChange() {
        // The additive field must default to nil so every existing construction
        // site (which doesn't pass `patch:`) stays bit-identical.
        let lane = TimelineLane(name: "MIDI 1", kind: .midi)
        XCTAssertNil(lane.patch)
    }

    // MARK: - Per-track composition group (genre / mood / variation — Module 2 foundation)

    func testLaneComposition_defaultInitIsNil_noBehaviorChange() {
        let lane = TimelineLane(name: "MIDI 1", kind: .midi)
        XCTAssertNil(lane.genreOverride)
        XCTAssertNil(lane.mood)
        XCTAssertNil(lane.variationSeed)
    }

    func testLaneDecode_preCompositionDocument_defaultsToNil() throws {
        // A lane persisted before per-track genre/mood/variation carries none of
        // those keys — it must decode to nil (= follow the global choice), not fail.
        let legacyJSON = """
        {"id":"\(UUID().uuidString)","name":"MIDI 1","kind":"midi","isBio":false,"level":1}
        """
        let lane = try JSONDecoder().decode(TimelineLane.self, from: Data(legacyJSON.utf8))
        XCTAssertNil(lane.genreOverride)
        XCTAssertNil(lane.mood)
        XCTAssertNil(lane.variationSeed)
    }

    func testLaneComposition_roundTripsThroughCodable() throws {
        let mood = MoodProfile(liveliness: 0.8, darkness: 0.2, tension: 0.4, romance: 0.6,
                               weird: 0.1, virtuosity: 0.5, syncopation: 0.3, humanize: 0.4)
        // A near-UInt64.max seed asserts the JSON round-trip stays exact (not routed
        // through Double, which would corrupt any value above 2^53).
        let bigSeed: UInt64 = 0xFFFF_FFFF_FFFF_FFF0
        let lane = TimelineLane(name: "Lead", kind: .midi,
                                genreOverride: .dubTechno, mood: mood, variationSeed: bigSeed)
        let data = try JSONEncoder().encode(lane)
        let back = try JSONDecoder().decode(TimelineLane.self, from: data)
        XCTAssertEqual(back, lane)
        XCTAssertEqual(back.genreOverride, .dubTechno)
        XCTAssertEqual(back.mood, mood)
        XCTAssertEqual(back.variationSeed, bigSeed)
    }

    // MARK: - Lane sample ref (EchoelSampler, S2-W3)

    func testLaneSamplePath_defaultInitIsNil_noBehaviorChange() {
        // Additive field: every existing construction site (no samplePath:) stays
        // bit-identical.
        let lane = TimelineLane(name: "EchoelSampler", kind: .midi, builtinInstrument: .sampler)
        XCTAssertNil(lane.samplePath)
    }

    func testLaneDecode_preSamplerDocument_defaultsToNilSamplePath() throws {
        // A lane persisted BEFORE the sampler ref existed carries no `samplePath`
        // key — it must decode to nil (no sample assigned), never fail to load.
        let legacyJSON = """
        {"id":"\(UUID().uuidString)","name":"MIDI 1","kind":"midi","isBio":false,"level":1}
        """
        let lane = try JSONDecoder().decode(TimelineLane.self, from: Data(legacyJSON.utf8))
        XCTAssertNil(lane.samplePath)
    }

    func testLaneSamplePath_roundTripsThroughCodable() throws {
        // Both persisted conventions round-trip verbatim (they are opaque strings
        // to the document — resolution happens at the rack door).
        for ref in ["drum:Kick", "lib:Bass/808", "/media/home/ABC.wav"] {
            let lane = TimelineLane(name: "Smp", kind: .midi,
                                    builtinInstrument: .sampler, samplePath: ref)
            let data = try JSONEncoder().encode(lane)
            let back = try JSONDecoder().decode(TimelineLane.self, from: data)
            XCTAssertEqual(back, lane)
            XCTAssertEqual(back.samplePath, ref)
        }
    }

    // MARK: - Lane pan (B2)

    func testRollSlotPan_firstNonBioMIDILane_clampedMuteIgnored() {
        var doc = TimelineDocument(lanes: [
            TimelineLane(name: "Bio", kind: .midi, isBio: true, pan: 1),
            TimelineLane(name: "MIDI 1", kind: .midi, pan: -0.5),
            TimelineLane(name: "MIDI 2", kind: .midi, pan: 0.9),
        ])
        XCTAssertEqual(doc.rollSlotPan, -0.5)                    // bio lane skipped
        // Mute/solo are gain's business — pan position is untouched.
        doc.lanes[1].isMuted = true
        XCTAssertEqual(doc.rollSlotPan, -0.5)
        // A stored document carrying junk clamps into −1…1.
        doc.lanes[1].pan = -7
        XCTAssertEqual(doc.rollSlotPan, -1)
        // No MIDI lane at all → center.
        let audioOnly = TimelineDocument(lanes: [TimelineLane(name: "A", kind: .audio)])
        XCTAssertEqual(audioOnly.rollSlotPan, 0)
    }

    @MainActor
    func testStore_setLanePan_clampsAndGuardsUnknownId() {
        let store = TimelineStore()
        store.addLane(kind: .midi, name: "M")
        guard let id = store.document.lanes.last?.id else { return XCTFail("no lane") }
        store.setLanePan(id: id, 5)                 // above range → clamps to +1
        XCTAssertEqual(store.document.lanes.last?.pan, 1)
        store.setLanePan(id: id, -9)                // below range → clamps to −1
        XCTAssertEqual(store.document.lanes.last?.pan, -1)
        store.setLanePan(id: UUID(), 0.5)           // unknown id → no crash, no change
        XCTAssertEqual(store.document.lanes.last?.pan, -1)
    }

    // MARK: - healRollSlotAudibility (#22 follow-up, founder log v255)

    func testHealRollSlot_unmutesAndFloorsLevel() {
        var doc = TimelineDocument(lanes: [
            TimelineLane(name: "Bio", kind: .midi, isBio: true),
            TimelineLane(name: "MIDI 1", kind: .midi, level: 0, isMuted: true),
        ])
        XCTAssertEqual(doc.rollSlotGain, 0)
        XCTAssertTrue(doc.healRollSlotAudibility())
        XCTAssertFalse(doc.lanes[1].isMuted)
        XCTAssertEqual(doc.lanes[1].level, 1)
        XCTAssertGreaterThan(doc.rollSlotGain, 0, "the heal's whole point: audible again")
    }

    func testHealRollSlot_clearsStaleSoloElsewhere() {
        var doc = TimelineDocument(lanes: [
            TimelineLane(name: "MIDI 1", kind: .midi),
            TimelineLane(name: "MIDI 2", kind: .midi, isSoloed: true),
        ])
        XCTAssertEqual(doc.rollSlotGain, 0, "solo elsewhere gates the roll lane")
        XCTAssertTrue(doc.healRollSlotAudibility())
        XCTAssertFalse(doc.lanes[1].isSoloed, "stale solo cleared (H4 lesson)")
        XCTAssertGreaterThan(doc.rollSlotGain, 0)
    }

    func testHealRollSlot_audibleRoll_isUntouchedNoop() {
        var doc = TimelineDocument(lanes: [
            TimelineLane(name: "MIDI 1", kind: .midi, level: 0.7),
            TimelineLane(name: "MIDI 2", kind: .midi, isMuted: true),
        ])
        let before = doc
        XCTAssertFalse(doc.healRollSlotAudibility(),
                       "an audible roll means Start changes NOTHING — deliberate mutes survive")
        XCTAssertEqual(doc, before)
    }

    func testHealRollSlot_noMIDILane_isNoop() {
        var doc = TimelineDocument(lanes: [TimelineLane(name: "A", kind: .audio, isMuted: true)])
        XCTAssertFalse(doc.healRollSlotAudibility())
    }

    func testHealRollSlot_subThresholdLevel_heals() {
        // Review MEDIUM pin: 0.0005 is gated silent EVERYWHERE (the ≤ 0.001
        // audibility law) — the heal must use the same threshold, not == 0.
        var doc = TimelineDocument(lanes: [TimelineLane(name: "MIDI 1", kind: .midi, level: 0.0005)])
        XCTAssertTrue(doc.healRollSlotAudibility())
        XCTAssertEqual(doc.lanes[0].level, 1)
    }

    func testHealRollSlot_secondCall_isIdempotentNoop() {
        var doc = TimelineDocument(lanes: [TimelineLane(name: "M", kind: .midi, isMuted: true)])
        XCTAssertTrue(doc.healRollSlotAudibility())
        XCTAssertFalse(doc.healRollSlotAudibility(), "healed once ⇒ audible ⇒ gate refuses")
    }
}
