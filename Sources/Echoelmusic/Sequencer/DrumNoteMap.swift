// DrumNoteMap.swift
// Echoel — S2-W2-2 (dissolution, "Spur = Instrument", plan
// scratchpads/PLAN_S2W2_VOICEKIND_ROUTING.md §3): the PURE MIDI-pitch → drum-pad
// mapping for a drums LANE. A piano-roll note on an EchoelDrums track picks a
// pad (GM-informed zones), a per-pitch `DrumSynthParams` preset for the modal
// voice, and a velocity gain. TOTAL (every pitch maps — no dead keys),
// deterministic, no state, no audio.
//
// Guarded like DrumSynthVoice: `DrumSynthParams` lives behind the AVFoundation+
// Accelerate guard, so this pure map shares it (tested on the macOS SwiftPM CI —
// the repo has no Linux gate).

#if canImport(AVFoundation) && canImport(Accelerate)
import Foundation

/// Pure MIDI note → drum-pad decisions for the lane drum kit (S2-W2).
public enum DrumNoteMap {

    /// The four physical pads of a `LaneDrumKitVoice`. Raw value = pad index.
    public enum Pad: Int, CaseIterable, Sendable, Equatable {
        case kick = 0, snare = 1, hat = 2, perc = 3
    }

    /// Number of physical pads a lane drum kit carries.
    public static let padCount = Pad.allCases.count

    /// One playable hit: the pad to strike, the modal preset it should carry for
    /// this pitch, and the velocity gain. Pure value.
    public struct Hit: Equatable, Sendable {
        public let pad: Pad
        public let params: DrumSynthParams
        public let gain: Float
        public init(pad: Pad, params: DrumSynthParams, gain: Float) {
            self.pad = pad
            self.params = params
            self.gain = gain
        }
    }

    /// GM-informed pad zones: kick 35/36 · snare family 37–40 (rim/snare/clap/
    /// e-snare) · hats 42/44/46 · EVERYTHING else = the pitched perc/tom pad —
    /// total, so no key on the roll is ever dead.
    public static func pad(forPitch pitch: Int) -> Pad {
        switch pitch {
        case 35, 36:     return .kick
        case 37...40:    return .snare
        case 42, 44, 46: return .hat
        default:         return .perc
        }
    }

    /// Velocity → linear gain with an audible floor (a played note never
    /// vanishes) and a hard 1.0 ceiling. Out-of-range velocities clamp.
    public static func gain(forVelocity velocity: Int) -> Float {
        let v = Swift.max(0, Swift.min(127, velocity))
        return Swift.max(0.05, Float(v) / 127)
    }

    /// The modal preset for a pitch — per-PITCH variants within a pad (a pedal
    /// hat chokes harder than a closed one; toms follow the played note).
    /// Deterministic + total; frequencies stay in a musical band.
    public static func params(forPitch pitch: Int) -> DrumSynthParams {
        var p = DrumSynthParams()
        p.material = "Drum"
        switch pad(forPitch: pitch) {
        case .kick:
            // 35 = acoustic bass drum (deeper), 36 = bass drum 1.
            p.frequency = pitch == 35 ? 48 : 55
            p.damping = 0.5
            p.brightness = 0.25
            p.strikePosition = 0.1
            p.size = 1.5
        case .snare:
            switch pitch {
            case 37:  // rimshot — tight, high crack
                p.frequency = 320; p.damping = 0.85; p.brightness = 0.8; p.size = 0.5
            case 39:  // clap — broad, quick
                p.frequency = 240; p.damping = 0.75; p.brightness = 0.75; p.size = 0.7
            case 40:  // electric snare — a touch fuller
                p.frequency = 200; p.damping = 0.55; p.brightness = 0.7; p.size = 0.9
            default:  // 38 acoustic snare
                p.frequency = 190; p.damping = 0.6; p.brightness = 0.6; p.size = 0.9
            }
            p.stiffness = 0.15
            p.strikePosition = 0.3
        case .hat:
            // Metallic character via the plate modes; damping orders the family:
            // pedal (44) chokes hardest, closed (42) tight, open (46) rings.
            p.material = "Plate"
            p.frequency = 780
            p.size = 0.35
            p.brightness = 0.9
            p.strikePosition = 0.5
            switch pitch {
            case 44: p.damping = 0.95
            case 42: p.damping = 0.9
            default: p.damping = 0.35   // 46 open
            }
        case .perc:
            // Pitched tom/perc: follow the played note (clamped to MIDI range,
            // then to a musical 40…600 Hz band). 45 (low tom) ≈ 110 Hz anchor.
            let clamped = Swift.max(0, Swift.min(127, pitch))
            let raw = 110 * powf(2, Float(clamped - 45) / 12)
            p.frequency = Swift.max(40, Swift.min(600, raw))
            p.damping = 0.55
            p.brightness = 0.45
            p.strikePosition = 0.25
            p.size = 0.9
        }
        return p
    }

    /// The full hit decision for a note-on. Pure composition of the three maps.
    public static func hit(pitch: Int, velocity: Int) -> Hit {
        Hit(pad: pad(forPitch: pitch), params: params(forPitch: pitch),
            gain: gain(forVelocity: velocity))
    }
}
#endif
