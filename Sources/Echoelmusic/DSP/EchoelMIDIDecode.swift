// EchoelMIDIDecode.swift
// Pure MIDI-1.0 channel-voice decode for the AUv3 instrument's render block.
//
// LOCATION: this lives in DSP/ on purpose. The EchoelmusicAUv3 extension globs
// Sources/Echoelmusic/DSP and compiles it in ISOLATION (no Core/Sequencer types
// are visible there), so this file must stay Foundation-only — no Core/Sequencer
// imports. Keeping the decode here (rather than inline in the audio unit) also
// makes it unit-testable WITHOUT instantiating a live AUAudioUnit: a test can
// decode a MIDI byte triple, feed the frequency into EchoelDDSP.noteOn, render,
// and assert amplitude > 0 — all Foundation/Accelerate only.
//
// Allocation-free and lock-free: the render block calls `action(status:…)` on the
// audio thread. Only `powf` (a C math function, audio-thread safe) and scalar
// arithmetic run here.

import Foundation

/// Pure MIDI-1.0 decode for the monophonic bio-reactive AUv3 instrument.
public enum EchoelMIDIDecode {

    /// What a decoded MIDI message asks the mono voice to do.
    public enum Action: Equatable {
        case noteOn(frequency: Float, velocity: Float)
        case noteOff
        case ignore
    }

    /// Equal-tempered MIDI note → Hz (A4 = note 69 = 440 Hz). Pure `powf`
    /// (C math, audio-thread safe). The note is masked to 0…127 so a malformed
    /// running-status byte can never index out of the audible range.
    public static func frequency(forNote note: UInt8) -> Float {
        440.0 * powf(2.0, (Float(note & 0x7F) - 69.0) / 12.0)
    }

    /// Decode the first bytes of a MIDI-1.0 message into a mono-voice action.
    /// Note-on with velocity 0 is the running-status convention for note-off.
    /// Every non-note message is ignored, so the free-running bio drone keeps
    /// playing when the host sends CC/clock/etc — EXCEPT the two "panic" channel-mode
    /// controllers (All Sound Off / All Notes Off), which must stop the voice.
    public static func action(status: UInt8, data1: UInt8, data2: UInt8) -> Action {
        switch status & 0xF0 {
        case 0x90:  // Note On (velocity 0 ⇒ Note Off)
            return data2 > 0
                ? .noteOn(frequency: frequency(forNote: data1), velocity: Float(data2) / 127.0)
                : .noteOff
        case 0x80:  // Note Off
            return .noteOff
        case 0xB0:  // Control Change — release the voice on a host panic (All Sound Off
                    // = CC 120, All Notes Off = CC 123); every other CC keeps the drone.
            return (data1 == 120 || data1 == 123) ? .noteOff : .ignore
        default:
            return .ignore
        }
    }
}
