// AUNoteVoice.swift
// Echoelmusic — Audio
//
// H5a (healing block, founder 2026-07-15: "auv3 Plugins von third Party wie
// Eventide … ermöglichen"; audit CRITICAL: `lane.instrument` was persisted
// intent NO engine code read). This is the per-LANE hosted-instrument voice:
// one third-party AUv3 instrument instance, wrapped behind the same `NoteVoice`
// seam the built-in PolySynthVoice uses, so the multi-roll fan-out can drive it
// interchangeably. The global AUv3Host (one app-wide channel, primary roll)
// stays untouched — this is its per-lane sibling, not a replacement.
//
// Control-plane only: notes go through the AU's host MIDI block
// (`scheduleMIDIEventBlock`, AUEventSampleTimeImmediate — the proven
// AUv3Host.sendMIDI pattern); gain/pan land on the lane's own mixer node
// (AVAudioMixing, applied downstream by the engine). Nothing here runs on the
// render thread. Instantiation is async and happens ONLY at assignment /
// restore / play-start via LaneAUInstrumentHost — never at a mid-song region
// onset (graph attach pauses the engine).
//
// HONEST LIMIT: per-lane DETUNE (cents) cannot be expressed as plain 3-byte
// MIDI — it is NOT applied to AU lanes (transpose in whole semitones is).
// Faking it via pitch-bend would fight the plugin's own bend state; deferred.

import Foundation

/// Pure MIDI byte mapping for the AU note path — kept outside the AVFoundation
/// gate so the clamp/transpose laws are Linux-CI-tested. Same mapping for on
/// and off so every note-off mirrors its note-on's final pitch.
public enum AUNoteMIDI {

    /// MIDI pitch after transpose, or nil when the result leaves 0…127 —
    /// dropped, not folded (a folded octave would sound wrong AND desync offs).
    public static func transposedPitch(_ pitch: Int, transpose: Int) -> UInt8? {
        let p = pitch + transpose
        guard (0...127).contains(p) else { return nil }
        return UInt8(p)
    }

    /// Velocity 0…1 (the NoteVoice contract) → MIDI 1…127. Anything audible
    /// never maps to 0 (0 would read as note-off on many instruments).
    public static func midiVelocity(_ velocity: Float) -> UInt8 {
        let v = velocity.isFinite ? velocity : 0
        return UInt8(Swift.max(1, Swift.min(127, (v * 127).rounded())))
    }
}

#if canImport(AVFoundation)
import AVFoundation

/// One hosted AUv3 INSTRUMENT bound to one timeline lane. Conforms to the same
/// note seam as PolySynthVoice (`NoteVoice` — conformance declared where the
/// protocol lives, SwiftUI-gated) so the fan-out treats both alike.
@MainActor
public final class AUNoteVoice {

    /// The hosted instrument node (attached to the engine by the host service).
    public let avUnit: AVAudioUnit
    /// H9a: the lane's hosted insert-effect stages, in chain order
    /// (instrument → effects… → laneMixer). Owned here so release can detach
    /// exactly what attach wired; empty for an effect-less assignment.
    public let effectUnits: [AVAudioUnit]
    /// The lane's own mix stage: AU → [fx…] → laneMixer → masterMixer. Carries
    /// the lane's live gain (outputVolume) + pan (AVAudioMixing into the master).
    public let laneMixer = AVAudioMixerNode()

    /// Whole-semitone per-lane transpose, folded into every note-on/off pitch
    /// (same source as the built-in voice's `setTranspose`). Detune is NOT
    /// supported on AU lanes — see the header's honest limit.
    public var transposeSemitones = 0

    /// ORIGINAL pitch → SOUNDED (post-transpose) MIDI pitch for every note
    /// currently on. Offs look up what the on actually sent, so a transpose
    /// change while notes are held can never mistarget an off (review NIT);
    /// allNotesOff also releases these explicitly for plugins ignoring CC 123.
    private var activePitches: [Int: UInt8] = [:]

    public init(avUnit: AVAudioUnit, effectUnits: [AVAudioUnit] = []) {
        self.avUnit = avUnit
        self.effectUnits = effectUnits
    }

    // MARK: - Notes (NoteVoice shape)

    public func noteOn(pitch: Int, velocity: Float) {
        guard let p = AUNoteMIDI.transposedPitch(pitch, transpose: transposeSemitones) else { return }
        if let stale = activePitches.updateValue(p, forKey: pitch), stale != p {
            sendMIDI(status: 0x80, data1: stale, data2: 0)   // retrigger across a transpose edit
        }
        sendMIDI(status: 0x90, data1: p, data2: AUNoteMIDI.midiVelocity(velocity))
    }

    public func noteOff(pitch: Int) {
        // Release what the on ACTUALLY sounded (transpose may have moved since);
        // an off for a pitch we never started is dropped, not guessed.
        guard let p = activePitches.removeValue(forKey: pitch) else { return }
        sendMIDI(status: 0x80, data1: p, data2: 0)
    }

    public func allNotesOff() {
        // CC 123 for well-behaved plugins + explicit offs for the rest.
        sendMIDI(status: 0xB0, data1: 123, data2: 0)
        for p in activePitches.values { sendMIDI(status: 0x80, data1: p, data2: 0) }
        activePitches.removeAll()
    }

    // MARK: - Live mixer (H4 sinks land here too)

    /// Lane gain 0…2 on the lane's own mixer stage — control-plane, mirrors
    /// PolySynthVoice.setGain so mute/solo/level treat AU lanes identically.
    public func setGain(_ gain: Float) {
        laneMixer.outputVolume = max(0, min(2, gain.isFinite ? gain : 0))
    }

    /// Lane pan −1…1 (laneMixer feeds the master mixer, AVAudioMixing).
    public func setPan(_ pan: Float) {
        laneMixer.pan = max(-1, min(1, pan.isFinite ? pan : 0))
    }

    // MARK: - MIDI plumbing (AUv3Host.sendMIDI pattern)

    private func sendMIDI(status: UInt8, data1: UInt8, data2: UInt8) {
        guard let block = avUnit.auAudioUnit.scheduleMIDIEventBlock else { return }
        let bytes: [UInt8] = [status, data1, data2]
        bytes.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            block(AUEventSampleTimeImmediate, 0, bytes.count, base)
        }
    }
}
#endif
