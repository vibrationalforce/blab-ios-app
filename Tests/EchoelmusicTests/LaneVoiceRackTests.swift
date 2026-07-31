// LaneVoiceRackTests.swift
// Echoel — pins the S2-W1 melodic-insert fan-out: LaneVoiceRack.setInsert must
// reach EVERY slot voice (review LOW from e73122c: the fan-out had no test).
// Voices are installed via the test seam (attachAll needs a live AudioEngine,
// which unit tests must not construct); PolySynthVoice construction alone adds
// no audio-graph node, so this runs on the Xcode gate without an engine.

#if canImport(AVFoundation) && canImport(Accelerate)
import AVFoundation
import XCTest
@testable import Echoelmusic

@MainActor
final class LaneVoiceRackTests: XCTestCase {

    func testSetInsert_unattached_isSafeNoOp() {
        let rack = LaneVoiceRack(capacity: 4)
        rack.setInsert(TrackFX(filter: .lowPass, cutoffHz: 900, resonance: 1.1, drive: 0.2))
        XCTAssertFalse(rack.isActive, "setInsert must not fake an attach")
        XCTAssertTrue(rack.voices.isEmpty, "no voice may be created outside attachAll")
    }

    func testSetInsert_fansOutToEveryVoice() {
        let rack = LaneVoiceRack(capacity: 3, maxVoicesPerSlot: 2)
        rack.installVoicesForTests((0..<3).map { _ in PolySynthVoice(maxVoices: 2) })
        let fx = TrackFX(filter: .lowPass, cutoffHz: 750, resonance: 1.4, drive: 0.35)
        rack.setInsert(fx)
        XCTAssertEqual(rack.voices.count, 3)
        for (i, v) in rack.voices.enumerated() {
            XCTAssertEqual(v.appliedInsert, fx, "slot \(i) missed the melodic insert")
        }
    }

    func testVoiceSlot_boundsAndAttachGate() {
        let rack = LaneVoiceRack(capacity: 2)
        XCTAssertNil(rack.voice(slot: 0), "unattached rack must not vend voices")
        rack.installVoicesForTests([PolySynthVoice(maxVoices: 2), PolySynthVoice(maxVoices: 2)])
        XCTAssertNotNil(rack.voice(slot: 0))
        XCTAssertNotNil(rack.voice(slot: 1))
        XCTAssertNil(rack.voice(slot: 2), "out-of-range slot must be nil, not a crash")
        XCTAssertNil(rack.voice(slot: -1))
    }

    // MARK: - Performance panic (audit 2026-07-26: the panic button reached 3 of 7 voices)

    /// The bio voice is the ONE rack voice whose note state flips synchronously
    /// (`isPlayingNote`, no render needed), so it is the only arm of the sweep a unit test can
    /// observe end-to-end. Use it as the proof that `allNotesOff()` really walks the kind
    /// arrays and is not, say, iterating `voices` alone.
    func testAllNotesOff_releasesAHeldBioNote() {
        let rack = LaneVoiceRack(capacity: 2)
        rack.installVoicesForTests([PolySynthVoice(maxVoices: 2), PolySynthVoice(maxVoices: 2)])
        let bio = BioReactiveSynthVoice()
        rack.installKindUnitsForTests(subs: [], samplers: [], bios: [bio])
        bio.playNote(frequency: 220)
        XCTAssertTrue(bio.isPlayingNote, "precondition: the bio voice must be holding a note")

        rack.allNotesOff()

        XCTAssertFalse(bio.isPlayingNote,
                       "rack panic did not reach the .bio arm — a stuck bio note survives it")
    }

    /// The four non-bio arms differ from each other, so state the strength of each rather
    /// than one blanket disclaimer (the earlier "nothing observable changes without a render"
    /// was wrong for `.subBass`, which records its enqueue on a Debug seam):
    ///   · `.subBass` — PROVEN below via `lastNoteCommandForTests`: the panic really reaches it.
    ///     Precisely: it proves the `allOff` COMMAND was enqueued, not that the sub went
    ///     silent — the release itself happens when the audio thread drains the queue.
    ///   · `.poly` / `.sampler` — enqueue a command the AUDIO thread drains, with no control-
    ///     plane seam, so a green run here does NOT prove they went silent.
    /// (⛔ A fourth bullet here described `.drums` as "a provable no-op". It went with #167 —
    ///  `LaneDrumKitVoice` no longer exists and the rack has no `.drums` arm to sweep.)
    /// What the rest of this test pins: the sweep is bounds-safe over every kind array, and
    /// panicking must not attach, vend or create voices as a side effect.
    func testAllNotesOff_isBoundsSafeAndReachesTheSub() {
        let empty = LaneVoiceRack(capacity: 2)
        empty.allNotesOff()                       // unattached: must be a no-op, not a crash
        XCTAssertFalse(empty.isActive, "panic must not fake an attach")
        XCTAssertTrue(empty.voices.isEmpty, "panic must not create a voice")

        let rack = LaneVoiceRack(capacity: 3)
        rack.installVoicesForTests((0..<3).map { _ in PolySynthVoice(maxVoices: 2) })
        rack.installKindUnitsForTests(subs: [SubBassVoice()],
                                      samplers: [SamplerVoice()],
                                      bios: [BioReactiveSynthVoice()])
        // Pre-stamp the seam so a MISSED .subBass arm reads as ("on", 33) rather than nil —
        // the assertion below is falsifiable either way, this just makes the failure legible.
        rack.subs[0].noteOn(pitch: 33)
        rack.allNotesOff()

        // The one arm with a control-plane seam: prove the sweep actually hit it.
        XCTAssertEqual(rack.subs[0].lastNoteCommandForTests?.kind, "allOff",
                       "rack panic did not reach the .subBass arm")

        XCTAssertEqual(rack.voices.count, 3, "panic changed the voice roster")
        XCTAssertEqual(rack.subs.count, 1)
        XCTAssertEqual(rack.samplers.count, 1)
        XCTAssertEqual(rack.bios.count, 1)
    }

    // MARK: - S2-W2-3 kind-routing facade (pure allocation + routing laws)

    func testSetKind_zeroUnits_isTheFlagOffShape_allPoly() {
        let rack = LaneVoiceRack(capacity: 2)
        rack.installVoicesForTests([PolySynthVoice(maxVoices: 2), PolySynthVoice(maxVoices: 2)])
        rack.setKind(slot: 0, kind: .sampler)    // no sampler units installed
        rack.setKind(slot: 1, kind: .subBass)    // no sub units installed
        XCTAssertEqual(rack.bindingsForTests[0], .poly(0), "no units ⇒ poly fallback (today's sound)")
        XCTAssertEqual(rack.bindingsForTests[1], .poly(1))
    }

    /// #167 (founder 2026-07-27) removed the kit half of this law. `.drums` no longer
    /// HAS a unit array to bind to, so it is pinned here from the other side: a lane
    /// persisted as drums must land on poly — audible, never silent — and it must not
    /// steal or disturb the sub the neighbouring lane holds.
    func testSetKind_bindsSub_andADrumsLaneFallsToPolyWithoutTouchingIt() {
        let rack = LaneVoiceRack(capacity: 3)
        rack.installVoicesForTests((0..<3).map { _ in PolySynthVoice(maxVoices: 2) })
        rack.installKindUnitsForTests(subs: [SubBassVoice()])
        rack.setKind(slot: 0, kind: .drums)
        rack.setKind(slot: 1, kind: .subBass)
        XCTAssertEqual(rack.bindingsForTests[0], .poly(0),
                       "a persisted drums lane must fall back to poly, never to silence")
        XCTAssertEqual(rack.bindingsForTests[1], .subBass(0))
        // Sub routing proof via the sub's command seam; poly path no-crash.
        rack.noteOn(slot: 0, pitch: 36, velocity: 1.0)   // drums→poly, must not reach the sub
        rack.noteOn(slot: 1, pitch: 33, velocity: 0.8)
        XCTAssertEqual(rack.subs[0].lastNoteCommandForTests?.kind, "on")
        XCTAssertEqual(rack.subs[0].lastNoteCommandForTests?.pitch, 33)
        rack.noteOn(slot: 2, pitch: 60, velocity: 0.8)
        // Note-OFF routes to the CURRENT binding only (audio review MEDIUM on
        // 89814a2: a fan to all subs could cut a foreign lane's held note).
        rack.noteOff(slot: 0, pitch: 36)   // poly-bound → must not reach the sub
        XCTAssertEqual(rack.subs[0].noteCommandCountForTests, 1,
                       "a poly slot's off must NOT reach the sub")
        rack.noteOff(slot: 1, pitch: 33)   // sub-bound → matching off
        XCTAssertEqual(rack.subs[0].lastNoteCommandForTests?.kind, "off")
        XCTAssertEqual(rack.subs[0].lastNoteCommandForTests?.pitch, 33)
    }

    func testMidiVelocityMapping_edges() {
        XCTAssertEqual(LaneVoiceRack.midiVelocity(1.0), 127)
        XCTAssertEqual(LaneVoiceRack.midiVelocity(0.0), 0)
        XCTAssertEqual(LaneVoiceRack.midiVelocity(0.5), 64, "0.5 × 127 = 63.5 rounds to 64")
        XCTAssertEqual(LaneVoiceRack.midiVelocity(1.5), 127, "over-range clamps")
        XCTAssertEqual(LaneVoiceRack.midiVelocity(-1.0), 0, "under-range clamps")
        XCTAssertEqual(LaneVoiceRack.midiVelocity(.nan), 0, "non-finite fails silent")
        XCTAssertEqual(LaneVoiceRack.midiVelocity(.infinity), 0)
    }

    func testRebind_releasesThePreviouslyBoundSub() {
        let rack = LaneVoiceRack(capacity: 2)
        rack.installVoicesForTests((0..<2).map { _ in PolySynthVoice(maxVoices: 2) })
        let sub = SubBassVoice()
        rack.installKindUnitsForTests(subs: [sub])
        rack.setKind(slot: 0, kind: .subBass)
        rack.noteOn(slot: 0, pitch: 40, velocity: 0.9)
        XCTAssertEqual(sub.lastNoteCommandForTests?.kind, "on")
        rack.setKind(slot: 0, kind: .poly)   // rebind ⇒ old voice released
        XCTAssertEqual(sub.lastNoteCommandForTests?.kind, "allOff",
                       "carry (b): rebind must allNotesOff the previously bound voice")
        XCTAssertEqual(rack.bindingsForTests[0], .poly(0))
    }

    /// Contention was pinned on `.drums` until #167 took the kit units away; the law is
    /// the allocator's, not the kit's, so it moves onto `.subBass` unchanged: one unit,
    /// two claimants, lowest slot wins and the loser falls back to poly (never silence).
    func testSetKind_lowerRankWinsContention_andRebindRestoresPoly() {
        let rack = LaneVoiceRack(capacity: 3)
        rack.installVoicesForTests((0..<3).map { _ in PolySynthVoice(maxVoices: 2) })
        rack.installKindUnitsForTests(subs: [SubBassVoice()])
        rack.setKind(slot: 2, kind: .subBass)
        XCTAssertEqual(rack.bindingsForTests[2], .subBass(0), "sole sub lane takes the unit")
        rack.setKind(slot: 0, kind: .subBass)
        XCTAssertEqual(rack.bindingsForTests[0], .subBass(0), "lower rank claims the unit on rebind")
        XCTAssertEqual(rack.bindingsForTests[2], .poly(2), "outbid lane falls back to poly, never silence")
        rack.setKind(slot: 0, kind: .poly)
        XCTAssertEqual(rack.bindingsForTests[0], .poly(0))
        XCTAssertEqual(rack.bindingsForTests[2], .subBass(0), "freed unit returns to the remaining sub lane")
    }

    func testFacade_unattached_isSafeNoOp() {
        let rack = LaneVoiceRack(capacity: 2)
        rack.setKind(slot: 0, kind: .drums)
        XCTAssertTrue(rack.bindingsForTests.isEmpty, "setKind must gate on attach")
        rack.noteOn(slot: 0, pitch: 36, velocity: 1.0)   // routes nowhere, no crash
        rack.noteOff(slot: 0, pitch: 36)
        rack.setGain(slot: 0, 1.0)
        rack.setPan(slot: 0, 0.5)
        rack.setTranspose(slot: 0, semitones: 12)
        rack.setDetune(slot: 0, cents: 10)
        rack.setSample(slot: 0, url: URL(fileURLWithPath: "/x.wav"))   // attach-gated no-op
    }

    func testTranspose_pitchesSubAtEnqueue_andChangeReleasesHeldSub() {
        let rack = LaneVoiceRack(capacity: 2)
        rack.installVoicesForTests((0..<2).map { _ in PolySynthVoice(maxVoices: 2) })
        let sub = SubBassVoice()
        rack.installKindUnitsForTests(subs: [sub])
        rack.setKind(slot: 0, kind: .subBass)
        XCTAssertEqual(rack.bindingsForTests[0], .subBass(0))
        rack.setTranspose(slot: 0, semitones: -12)
        rack.noteOn(slot: 0, pitch: 45, velocity: 0.9)
        XCTAssertEqual(sub.lastNoteCommandForTests?.pitch, 33, "sub is pitched at enqueue (45−12)")
        rack.setTranspose(slot: 0, semitones: 0)
        XCTAssertEqual(sub.lastNoteCommandForTests?.kind, "allOff",
                       "shift change while sub-bound must release (off-matching law)")
        rack.noteOff(slot: 0, pitch: 45)                  // off at NEW shift — harmless
        XCTAssertEqual(sub.lastNoteCommandForTests?.pitch, 45, "off carries the current shift")
    }

    // MARK: - S2-W2-5 bus-insert + tuning fans

    /// ⛔ `setDrumsInsert` and its own fan-out test (`testSetDrumsInsert_fansToEveryKit`)
    ///    were DELETED with #167 — the method had no production caller left once the kit
    ///    voices went, so an insert fan with nothing to fan to is a lying control.
    func testBusFans_emptyRack_areSafeNoOps() {
        // flag-OFF shape: no subs ⇒ the .bass/tuning fans touch nothing.
        let rack = LaneVoiceRack(capacity: 2)
        rack.installVoicesForTests([PolySynthVoice(maxVoices: 2), PolySynthVoice(maxVoices: 2)])
        rack.setBassInsert(TrackFX(filter: .lowPass, cutoffHz: 120, resonance: 0.8, drive: 0.1))
        rack.setTuning(a4Hz: 432)
        XCTAssertTrue(rack.subs.isEmpty)
    }

    func testSetBassInsert_andTuning_fanToEverySub() {
        let rack = LaneVoiceRack(capacity: 2)
        rack.installVoicesForTests([PolySynthVoice(maxVoices: 2)])
        let sub = SubBassVoice()
        rack.installKindUnitsForTests(subs: [sub])
        let fx = TrackFX(filter: .lowPass, cutoffHz: 90, resonance: 0.7, drive: 0.15)
        rack.setBassInsert(fx)
        XCTAssertEqual(sub.lastInsertForTests, fx, "bass bus insert must reach the sub")
        rack.setTuning(a4Hz: 432)
        XCTAssertEqual(sub.lastTuningForTests ?? -1, 432, accuracy: 1e-6,
                       "concert pitch must reach the lane sub (in tune at A=432)")
    }

    func testSetTuning_fansToEveryLaneMelodicVoice() {
        // The lane MELODIC voices (the PolySynthVoice pool) must follow the concert
        // pitch too — before this they were skipped by setTuning and droned at the
        // hardcoded 440 while subs/bios/global synth retuned to e.g. A=432 (out of tune).
        let rack = LaneVoiceRack(capacity: 2)
        let v0 = PolySynthVoice(maxVoices: 2)
        let v1 = PolySynthVoice(maxVoices: 2)
        rack.installVoicesForTests([v0, v1])
        rack.setTuning(a4Hz: 432)
        XCTAssertEqual(v0.lastTuningForTests ?? -1, 432, accuracy: 1e-6,
                       "concert pitch must reach lane melodic voice 0 (was droning at 440)")
        XCTAssertEqual(v1.lastTuningForTests ?? -1, 432, accuracy: 1e-6,
                       "concert pitch must reach lane melodic voice 1")
    }

    // MARK: - S2-W3 sampler unit (EchoelSampler lane audible)

    func testSetKind_sampler_bindsTheSamplerUnit_andNoteOnFiresIt() {
        let rack = LaneVoiceRack(capacity: 2)
        rack.installVoicesForTests((0..<2).map { _ in PolySynthVoice(maxVoices: 2) })
        let sampler = SamplerVoice()
        rack.installKindUnitsForTests(subs: [], samplers: [sampler])
        rack.setKind(slot: 0, kind: .sampler)
        XCTAssertEqual(rack.bindingsForTests[0], .sampler(0))
        // Routing proof: a note-ON on the sampler slot triggers the SAMPLER unit
        // (its render block picks the trigger up on the next block — the fire
        // counter is the observable), not the poly slot voice.
        rack.noteOn(slot: 0, pitch: 60, velocity: 0.8)
        renderOneBlock(voice: sampler, frameCount: 64)
        XCTAssertTrue(sampler._testIsPlaying,
                      "the sampler-bound slot's note-ON must fire the sampler unit")
        // One-shot: note-OFF is a documented no-op — it must not silence the hit.
        rack.noteOff(slot: 0, pitch: 60)
        renderOneBlock(voice: sampler, frameCount: 64)
        XCTAssertTrue(sampler._testIsPlaying, "a one-shot ignores note-OFF (drum convention)")
        // allNotesOff on the binding cuts it (silence on the next block).
        rack.setKind(slot: 0, kind: .poly)   // rebind ⇒ allNotesOff(old) ⇒ silence()
        renderOneBlock(voice: sampler, frameCount: 64)
        XCTAssertFalse(sampler._testIsPlaying, "rebind must silence the sampler unit")
    }

    func testSetKind_sampler_withoutUnit_fallsBackToPoly() {
        let rack = LaneVoiceRack(capacity: 2)
        rack.installVoicesForTests((0..<2).map { _ in PolySynthVoice(maxVoices: 2) })
        rack.installKindUnitsForTests(subs: [])   // zero sampler units
        rack.setKind(slot: 0, kind: .sampler)
        XCTAssertEqual(rack.bindingsForTests[0], .poly(0),
                       "no sampler unit ⇒ poly fallback, never silence")
        rack.noteOn(slot: 0, pitch: 60, velocity: 0.8)   // poly path, no crash
        rack.noteOff(slot: 0, pitch: 60)
    }

    func testSetSample_loadsIntoTheBoundSamplerUnit() throws {
        let url = try makeTempWav(seconds: 0.02, frequency: 440)
        defer { try? FileManager.default.removeItem(at: url) }
        let rack = LaneVoiceRack(capacity: 2)
        rack.installVoicesForTests((0..<2).map { _ in PolySynthVoice(maxVoices: 2) })
        let sampler = SamplerVoice()
        rack.installKindUnitsForTests(subs: [], samplers: [sampler])
        rack.setKind(slot: 0, kind: .sampler)
        rack.setSample(slot: 0, url: url)
        XCTAssertTrue(sampler.isLoaded, "setSample must load into the bound sampler unit")
        XCTAssertEqual(sampler.sourceURL, url)
    }

    func testSetSample_beforeBinding_isLoadedOnRebind() throws {
        // The sample memo follows the LANE: assigned while the slot is still
        // poly-bound, it must land in the unit when the slot LATER binds sampler.
        let url = try makeTempWav(seconds: 0.02, frequency: 220)
        defer { try? FileManager.default.removeItem(at: url) }
        let rack = LaneVoiceRack(capacity: 2)
        rack.installVoicesForTests((0..<2).map { _ in PolySynthVoice(maxVoices: 2) })
        let sampler = SamplerVoice()
        rack.installKindUnitsForTests(subs: [], samplers: [sampler])
        rack.setSample(slot: 0, url: url)                 // slot is poly (no kind yet)
        XCTAssertFalse(sampler.isLoaded, "an unbound slot's sample must not load yet")
        rack.setKind(slot: 0, kind: .sampler)             // rebind loads the memo
        XCTAssertTrue(sampler.isLoaded)
        XCTAssertEqual(sampler.sourceURL, url)
    }

    func testSetSample_unresolvableURL_logsAndKeepsCalm() {
        let rack = LaneVoiceRack(capacity: 2)
        rack.installVoicesForTests((0..<2).map { _ in PolySynthVoice(maxVoices: 2) })
        let sampler = SamplerVoice()
        rack.installKindUnitsForTests(subs: [], samplers: [sampler])
        rack.setKind(slot: 0, kind: .sampler)
        rack.setSample(slot: 0, url: URL(fileURLWithPath: "/nonexistent/nothing.wav"))
        XCTAssertFalse(sampler.isLoaded, "a failed load must not fake isLoaded")
        rack.setSample(slot: 0, url: nil)                 // clear — no crash
    }

    // MARK: - Persisted sample refs (BeatPlayer conventions shared with the lane)

    func testSampleRefDisplayName_coversAllConventions() {
        XCTAssertEqual(BeatPlayer.sampleRefDisplayName("drum:Kick"), "Kick")
        XCTAssertEqual(BeatPlayer.sampleRefDisplayName("lib:Bass/808 Long"), "808 Long")
        XCTAssertEqual(BeatPlayer.sampleRefDisplayName("/tmp/media/ABC-123.wav"), "ABC-123")
        XCTAssertNil(BeatPlayer.sampleRefDisplayName(nil))
        XCTAssertNil(BeatPlayer.sampleRefDisplayName(""))
    }

    func testResolveSampleRef_absolutePathAndNil() throws {
        XCTAssertNil(BeatPlayer.resolveSampleRef(nil))
        XCTAssertNil(BeatPlayer.resolveSampleRef(""))
        // A mediaRef-style absolute path to an existing file resolves directly.
        let url = try makeTempWav(seconds: 0.01, frequency: 330)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(BeatPlayer.resolveSampleRef(url.path), url)
    }

    // MARK: - Sampler test helpers (mirrors SamplerVoiceTests' render harness)

    /// Writes a temporary mono float32 WAV at 44.1 kHz with a sine wave.
    private func makeTempWav(seconds: Double, frequency: Double) throws -> URL {
        let sr: Double = 44_100
        let frames = Int(seconds * sr)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lane-rack-sampler-\(UUID().uuidString).wav")
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sr,
                                         channels: 1, interleaved: false) else {
            throw NSError(domain: "test", code: 0)
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(frames)) else {
            throw NSError(domain: "test", code: 1)
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        if let ch = buffer.floatChannelData?[0] {
            for i in 0..<frames {
                ch[i] = Float(sin(2 * .pi * frequency * Double(i) / sr) * 0.5)
            }
        }
        try file.write(from: buffer)
        return url
    }

    /// Drives one render block synchronously (the SamplerVoice test seam), so
    /// trigger/silence state becomes observable without a live engine.
    private func renderOneBlock(voice: SamplerVoice, frameCount: Int) {
        let out = UnsafeMutablePointer<Float>.allocate(capacity: frameCount)
        out.initialize(repeating: 0, count: frameCount)
        let abl = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        abl.pointee.mNumberBuffers = 1
        abl.pointee.mBuffers.mNumberChannels = 1
        abl.pointee.mBuffers.mDataByteSize = UInt32(frameCount * MemoryLayout<Float>.size)
        abl.pointee.mBuffers.mData = UnsafeMutableRawPointer(out)
        defer {
            out.deinitialize(count: 1)
            out.deallocate()
            abl.deallocate()
        }
        voice._testRender(frameCount: frameCount, audioBufferList: abl)
    }

    func testPolySynthVoice_setInsert_recordsAppliedInsert() {
        let v = PolySynthVoice(maxVoices: 2)
        XCTAssertNil(v.appliedInsert, "fresh voice has no insert memory")
        let fx = TrackFX(filter: .highPass, cutoffHz: 240, resonance: 0.9, drive: 0.1)
        v.setInsert(fx)
        XCTAssertEqual(v.appliedInsert, fx)
        v.setInsert(.off)
        XCTAssertEqual(v.appliedInsert, .off, "later writes win — memory mirrors the last call")
    }
}
#endif
