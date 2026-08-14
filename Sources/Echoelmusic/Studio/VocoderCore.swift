//
//  VocoderCore.swift
//  Echoelmusic — Studio (voice → audiovisual)
//
//  The pure, tested foundation of the physical AUDIOVISUAL VOCODER (the founder's
//  flagship vision): one analysed voice signal drives sound AND image AND light at
//  once — inclusive by design, because the same utterance is heard, seen and felt.
//
//  This file is data + deterministic mapping only — NO audio DSP, NO Metal, NO
//  SwiftUI. `VoiceFrame`s are produced IN PRODUCTION since #592a (`VoiceAnalyzer`,
//  fed by the voice-capture chain — ⛔ "a future voice analyser" stood here after it
//  shipped); a future synth / renderer / Art-Net sender consumes one
//  `VocoderMapping` — THAT half is still unconsumed (0 callers, measured
//  2026-08-14). Flash safety is baked in (pulse routed through FlashGuard), so no
//  consumer can strobe by construction.
//
//  Pitch → colour uses the chromatic circle = colour circle (octave↔hue, real
//  physics — Newton/Scriabin lineage), NOT esoteric "frequency healing".
//

import Foundation

/// One analysed frame of the incoming voice. Produced by `VoiceAnalyzer` (live
/// since #592a); pure value type so the mapping is unit-tested.
public struct VoiceFrame: Sendable, Equatable {
    /// Fundamental frequency in Hz; 0 when unvoiced/silent.
    public var pitchHz: Double
    /// Whether a pitched (voiced) sound is present.
    public var voiced: Bool
    /// Loudness, normalised 0…1 (RMS).
    public var energy: Double
    /// Spectral centroid normalised 0…1 (dark → bright timbre).
    public var brightness: Double
    public var timestamp: Double

    public init(pitchHz: Double, voiced: Bool, energy: Double,
                brightness: Double, timestamp: Double = 0) {
        self.pitchHz = pitchHz
        self.voiced = voiced
        self.energy = energy
        self.brightness = brightness
        self.timestamp = timestamp
    }

    /// Silence (also the launch-safe default — maps to dark + quiet).
    public static let silent = VoiceFrame(pitchHz: 0, voiced: false, energy: 0, brightness: 0)

    /// Below this energy (and/or unvoiced) the frame is treated as silence.
    public var isSilent: Bool { !voiced || energy < 0.02 }

    /// The detected pitch as a (fractional) MIDI note, or nil when unvoiced.
    /// 69 + 12·log2(f / 440).
    public var midiNote: Double? {
        guard voiced, pitchHz > 0 else { return nil }
        return 69.0 + 12.0 * log2(pitchHz / 440.0)
    }

    /// Pitch class 0…11 (C…B), or nil when unvoiced.
    public var pitchClass: Int? {
        guard let n = midiNote else { return nil }
        return ((Int(n.rounded()) % 12) + 12) % 12
    }
}

/// The unified audiovisual output for one voice frame: sound, image and light
/// parameters derived from the SAME signal, so every dimension stays in sync.
public struct VocoderMapping: Sendable, Equatable {

    // — Sound —
    /// Carrier pitch as a MIDI note (nil = unvoiced → no tone). The synth voices it.
    public var carrierMidi: Int?
    /// Formant shift, -1…1, from voice brightness (dark ↔ bright).
    public var formantShift: Double
    /// Output level 0…1, from voice energy.
    public var level: Double

    // — Visual —
    /// Hue 0…1 from pitch class (chromatic circle = colour circle).
    public var hue: Double
    /// Brightness/fill 0…1 from energy.
    public var intensity: Double
    /// Heartbeat pulse in Hz — flash-clamped (0…3 Hz; 0 = still). Comes from the
    /// optional bio frame, independent of the voice.
    public var pulseHz: Double

    // — Light (Art-Net / sACN ready) —
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(carrierMidi: Int?, formantShift: Double, level: Double,
                hue: Double, intensity: Double, pulseHz: Double,
                red: Double, green: Double, blue: Double) {
        self.carrierMidi = carrierMidi
        self.formantShift = formantShift
        self.level = level
        self.hue = hue
        self.intensity = intensity
        self.pulseHz = pulseHz
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Silent default: no tone, dark, quiet (launch-safe).
    public static let silent = VocoderMapping(
        carrierMidi: nil, formantShift: 0, level: 0,
        hue: 0, intensity: 0, pulseHz: 0, red: 0, green: 0, blue: 0)

    /// Pure voice(+bio) → audiovisual mapping. `reduceMotion` freezes the pulse.
    public static func from(voice: VoiceFrame,
                            bio: BioSampleFrame? = nil,
                            reduceMotion: Bool = false) -> VocoderMapping {
        // Pulse comes from the heart (flash-safe), not the voice — so a sustained
        // note never strobes. 0 when there is no bio frame.
        let hr = Double(bio?.heartRateBPM ?? 0)
        let pulse = hr > 0
            ? FlashGuard.safeFrequency(min(max(hr / 60.0, 0.5), 2.0), reduceMotion: reduceMotion)
            : 0

        guard !voice.isSilent else {
            // Keep the heartbeat pulse alive in silence; everything else dark/quiet.
            return VocoderMapping(carrierMidi: nil, formantShift: 0, level: 0,
                                  hue: 0, intensity: 0, pulseHz: pulse,
                                  red: 0, green: 0, blue: 0)
        }

        let level = clamp01(voice.energy)
        let intensity = clamp01(voice.energy)
        let hue = voice.pitchClass.map { Double($0) / 12.0 } ?? 0
        let formant = clamp(voice.brightness * 2.0 - 1.0, -1, 1)
        let carrier = voice.midiNote.map { min(127, max(0, Int($0.rounded()))) }
        let (r, g, b) = hsvToRGB(h: hue, s: 1.0, v: intensity)

        return VocoderMapping(carrierMidi: carrier, formantShift: formant, level: level,
                              hue: hue, intensity: intensity, pulseHz: pulse,
                              red: r, green: g, blue: b)
    }
}

// MARK: - Pure helpers

private func clamp01(_ x: Double) -> Double { min(max(x, 0), 1) }
private func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { min(max(x, lo), hi) }

/// HSV→RGB, all components 0…1. Saturation 1, value = intensity gives the
/// pitch-coloured light/visual that darkens with quietness.
private func hsvToRGB(h: Double, s: Double, v: Double) -> (Double, Double, Double) {
    let hh = ((h.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)) * 6.0
    let i = Int(hh)
    let f = hh - Double(i)
    let p = v * (1 - s)
    let q = v * (1 - s * f)
    let t = v * (1 - s * (1 - f))
    switch i % 6 {
    case 0:  return (v, t, p)
    case 1:  return (q, v, p)
    case 2:  return (p, v, t)
    case 3:  return (p, q, v)
    case 4:  return (t, p, v)
    default: return (v, p, q)
    }
}
