//
//  VoicePitchCorrector.swift
//  Echoelmusic — DSP (Voice Live VL1+VL2, the Syng legacy)
//
//  Pure pitch-correction ("Autotune") and scale-harmony maths for a live
//  voice/instrument input. PitchTracker (YIN) detects the fundamental; this
//  turns it into a correction RATIO for a pitch shifter and into scale-true
//  harmony intervals for EchoelHarmonizer. No audio I/O, no allocation
//  beyond value types — fully unit-tested on every platform.
//
//  The Echoel edge over every market autotune: the key is not GUESSED from
//  the signal — the instrument KNOWS it (MusicalKey drives the composer),
//  and the correction grid is Kammerton-true (A4 = 432/440/… — the target
//  frequencies move with the session's a4Hz, not a hardcoded 440).
//
//  Retune behaviour: `retuneSpeed` 1 = instant hard snap (the classic
//  quantized-vocal effect), 0 = very slow drift (natural). Smoothing is a
//  one-pole low-pass on the correction in CENTS, stepped with an explicit
//  `dt` so behaviour is deterministic and testable (no wall clock).
//
//  Consumers: VL3 is WIRED since #599 — AudioEngine's guard tick runs
//  mic tap → MonitorTapWindow → PitchTracker → process(detectedHz:dt:) and writes
//  `appliedCents` onto an `AVAudioUnitTimePitch` in the MONITOR path ("Tune to
//  key", default off). ⛔ This header described that consumer as a plan ("ratio
//  into a delay-line shifter") for the whole first day it was shipped — wrong
//  quantity (cents, not ratio) and wrong mechanism (first-party graph node).
//  ⛔ AND THE LINE BELOW THAT ONE AGED THE SAME WAY, one slice later: it said
//  "VL2 (`VoiceHarmony` → EchoelHarmonizer intervals) is genuinely still OPEN —
//  #599b, next slice". VL2 IS wired: `Tools/DiatonicHarmonyFollower.swift` is the
//  ~10 Hz bridge (`EngineBus.latestMusical` → `VoiceHarmony.interval` →
//  `EchoelHarmonizer.interval1/2`), constructed in `EchoelmusicApp` and doored by
//  the FX panel's "Follow the key". Its own header says "VL2 wired — #599b" while
//  this one said OPEN. **A header that calls a built thing open is worse than a
//  stale number: it makes the next session BUILD IT AGAIN.** Its maths stays
//  pinned by Test 4 of TheVoiceTuneSnapsToTheSessionKeyTests.
//
//  ⚠️ WHAT IS GENUINELY STILL OPEN, so this header does not simply flip to a
//  rosier lie: the harmonizer follows the SOUNDING LEAD (the piano-roll note the
//  studio publishes), and it lives on `EchoelFXChain`, which is NOT in the monitor
//  graph. Measured with a recipe that literally PRINTS the number, because `git grep
//  -c` on a no-match file prints nothing at all and exits 1 — quoting that as "= 0"
//  is the EchoelModalBank trap (a recipe whose output contradicts the prose beside it
//  reads as a contradiction, not as a sloppy command):
//      git grep -c EchoelFXChain -- Sources/Echoelmusic/Audio/AudioEngine.swift | wc -l
//  → 0. The monitor path is `input → notchEQ → [voiceTunePitch] → monitorMixer`.
//  So the singer's own voice reaches the notch and this corrector, and reaches NO
//  harmonizer, reverb or delay. That gap is the vocal-chain host node (V1a), not
//  VL2.
//

import Foundation

/// One frame of correction output.
public struct VoicePitchCorrection: Sendable, Equatable {
    /// Multiply the signal's pitch by this (1 = no change).
    public let ratio: Float
    /// The in-key target MIDI note (nil while unvoiced).
    public let targetMidi: Int?
    /// The target frequency in Hz at the session Kammerton (nil while unvoiced).
    public let targetHz: Double?
    /// The correction currently applied, in cents (smoothed).
    public let appliedCents: Double

    public static let bypass = VoicePitchCorrection(ratio: 1, targetMidi: nil,
                                                    targetHz: nil, appliedCents: 0)
}

/// Deterministic, allocation-free pitch-correction state machine (VL1).
public struct VoicePitchCorrector: Sendable {

    /// The key the correction snaps into (the session's Tonart).
    public var key: MusicalKey
    /// Session Kammerton — the A4 reference the target grid is built on.
    public var a4Hz: Double
    /// 0 = off (ratio 1), 1 = full correction to the in-key target.
    public var strength: Double
    /// 1 = instant snap, 0 = slowest drift. See header.
    public var retuneSpeed: Double

    /// Smoothed correction in cents (the one-pole state).
    private var smoothedCents: Double = 0

    public init(key: MusicalKey = MusicalKey(),
                a4Hz: Double = 440,
                strength: Double = 1,
                retuneSpeed: Double = 1) {
        self.key = key
        self.a4Hz = a4Hz.isFinite && a4Hz > 0 ? a4Hz : 440
        self.strength = strength.isFinite ? min(max(strength, 0), 1) : 1
        self.retuneSpeed = retuneSpeed.isFinite ? min(max(retuneSpeed, 0), 1) : 1
        self.key = key
    }

    /// Advance one analysis frame. `detectedHz` nil/<=0 = unvoiced (the
    /// correction relaxes toward bypass); `dt` = seconds since last frame.
    public mutating func process(detectedHz: Double?, dt: Double) -> VoicePitchCorrection {
        let safeDt = (dt.isFinite && dt > 0) ? dt : 0.01
        guard let f = detectedHz, f.isFinite, f > 0,
              a4Hz.isFinite, a4Hz > 0 else {
            // Unvoiced: relax the applied correction toward zero so the next
            // voiced onset doesn't inherit a stale bend.
            smoothedCents += smoothingAlpha(dt: safeDt) * (0 - smoothedCents)
            if abs(smoothedCents) < 0.01 { smoothedCents = 0 }
            return VoicePitchCorrection(ratio: ratioFromCents(smoothedCents),
                                        targetMidi: nil, targetHz: nil,
                                        appliedCents: smoothedCents)
        }

        // Hz → fractional MIDI on the session's Kammerton grid.
        let fracMidi = 69.0 + 12.0 * log2(f / a4Hz)
        guard fracMidi.isFinite, fracMidi > 0, fracMidi < 128 else {
            return VoicePitchCorrection(ratio: 1, targetMidi: nil, targetHz: nil,
                                        appliedCents: smoothedCents)
        }

        let target = Self.nearestInKeyMidi(to: fracMidi, key: key)
        let desiredCents = (Double(target) - fracMidi) * 100.0 * strength
        smoothedCents += smoothingAlpha(dt: safeDt) * (desiredCents - smoothedCents)

        let targetHz = a4Hz * pow(2.0, (Double(target) - 69.0) / 12.0)
        return VoicePitchCorrection(ratio: ratioFromCents(smoothedCents),
                                    targetMidi: target,
                                    targetHz: targetHz,
                                    appliedCents: smoothedCents)
    }

    /// Reset the smoothing state (e.g. when the input source changes).
    public mutating func reset() { smoothedCents = 0 }

    // MARK: - Pure helpers (exposed for tests)

    /// The in-key MIDI note nearest to a fractional MIDI pitch. Ties resolve
    /// to the LOWER note (deterministic, mirrors MusicalKey.quantize).
    public static func nearestInKeyMidi(to fracMidi: Double, key: MusicalKey) -> Int {
        let center = Int(fracMidi.rounded())
        var best = center
        var bestDist = Double.infinity
        // ±7 semitones always contains an in-key note for every shipped scale.
        for candidate in (center - 7)...(center + 7) where key.contains(candidate) {
            let dist = abs(Double(candidate) - fracMidi)
            if dist < bestDist - 1e-9 ||
               (abs(dist - bestDist) <= 1e-9 && candidate < best) {
                best = candidate
                bestDist = dist
            }
        }
        return best
    }

    private func smoothingAlpha(dt: Double) -> Double {
        if retuneSpeed >= 1 { return 1 }
        // Time constant: speed 0 → ~350 ms drift, approaching 0 s at speed 1.
        let tau = 0.35 * (1.0 - retuneSpeed) + 0.002
        return 1.0 - exp(-dt / tau)
    }

    private func ratioFromCents(_ cents: Double) -> Float {
        let r = pow(2.0, cents / 1200.0)
        return r.isFinite ? Float(r) : 1
    }
}

// MARK: - Autotune character (the founder's "Charakter Einstellungen", #681)

/// A NAMED combination of the corrector's two numbers, because "Charakter" is a
/// choice with names and not a number to decode — the same law that turned the
/// harmonizer's semitone field into `HarmonyInterval` (CLAUDE.md, "READ THE WORD
/// NUMERIC"). The two `EchoelValueField` rows stay: this is a preset ON them, the
/// `presetRow` shape the sound panel already uses, never a replacement for them.
///
/// ⭐ THE SELECTION IS DERIVED, NEVER STORED. `matching(strength:retuneSpeed:)`
/// reads the live values back; there is deliberately no "selected character"
/// property anywhere. A stored selection goes stale the instant a finger moves
/// either field, and a control that lies about what is active is worse than no
/// control — the ownership lesson `DiatonicHarmonyFollower` paid for. `nil` means
/// the performer has dialled something of their own, and the door says so.
///
/// ⚠️ `tight` IS THE SHIPPED DEFAULT, not a new taste. `AudioEngine` has launched
/// with `voiceTuneStrength = 1` / `voiceTuneRetune = 0.8` since #599, so naming
/// that exact pair keeps this slice a LABEL over existing behaviour — no user
/// hears a different monitor because a picker appeared. Moving either literal
/// changes what people already ship with; the guard pins the pair to this case.
public enum VoiceTuneCharacter: String, CaseIterable, Sendable, Identifiable {
    /// A nudge. Vibrato and scoops survive; the pitch centre is merely tidied.
    case natural
    /// Clearly corrected, still recognisably a human moving between notes.
    case smooth
    /// Studio-tight: full correction, a short audible glide into each note.
    case tight
    /// The classic quantised effect — full correction, no glide at all.
    case hard

    public var id: String { rawValue }

    /// How far toward the in-key target (`VoicePitchCorrector.strength`, 0…1).
    public var strength: Double {
        switch self {
        case .natural: return 0.55
        case .smooth:  return 0.80
        case .tight:   return 1.00
        case .hard:    return 1.00
        }
    }

    /// How fast it gets there (`VoicePitchCorrector.retuneSpeed`, 0…1; 1 = instant
    /// snap). The corrector turns this into a time constant — that maths lives
    /// THERE and is not restated here (#416).
    public var retuneSpeed: Double {
        switch self {
        case .natural: return 0.15
        case .smooth:  return 0.45
        case .tight:   return 0.80
        case .hard:    return 1.00
        }
    }

    /// Short label for the picker.
    public var label: String {
        switch self {
        case .natural: return "Natural"
        case .smooth:  return "Smooth"
        case .tight:   return "Tight"
        case .hard:    return "Hard"
        }
    }

    /// The character whose pair the CURRENT values sit on, or `nil` when the
    /// performer has moved a field off every named point. The tolerance is wide
    /// enough to survive `Float` → `Double` widening at the door (0.8 as a `Float`
    /// widens to 0.800000011920929) and far narrower than the gap between any two
    /// neighbouring characters, the smallest of which is 0.20.
    public static func matching(strength: Double, retuneSpeed: Double) -> VoiceTuneCharacter? {
        guard strength.isFinite, retuneSpeed.isFinite else { return nil }
        let tolerance = 1e-3
        return allCases.first {
            abs($0.strength - strength) <= tolerance &&
            abs($0.retuneSpeed - retuneSpeed) <= tolerance
        }
    }
}

// MARK: - VL2: scale-true harmony intervals (feeds EchoelHarmonizer)

/// Diatonic harmony maths: given the note a performer is singing, what are
/// the semitone offsets to the voices N scale-degrees above? Unlike the
/// fixed-interval harmonizer default (always +4/+7), these intervals breathe
/// with the key — a third above E in C major is G (+3), not G# (+4).
public enum VoiceHarmony {

    /// Semitone offset to the note `degreesUp` scale degrees above `midi`,
    /// in `key`. `midi` is quantized into the key first and the offset is
    /// measured FROM THE QUANTIZED note (in the VL3 chain the corrector
    /// snaps the voice before the harmonizer reads these intervals).
    /// `degreesUp` may be negative (harmony below).
    public static func interval(from midi: Int, degreesUp: Int, key: MusicalKey) -> Int {
        let snapped = key.quantize(midi)
        guard let index = degreeIndex(of: snapped, key: key) else { return 0 }
        // Recover the octave so that key.degree(index, octave:) == snapped,
        // then step the degree ladder. (snapped − root − interval) is an
        // exact multiple of 12 by construction.
        let rel = key.scale.intervals[index]
        let octave = (snapped - key.root - rel) / 12 - 1
        return key.degree(index + degreesUp, octave: octave) - snapped
    }

    /// Degree index (0-based, octave-relative) of an in-key MIDI note, or nil
    /// when the note's pitch class is outside the key.
    static func degreeIndex(of midi: Int, key: MusicalKey) -> Int? {
        let pc = ((midi % 12) + 12) % 12
        let relative = ((pc - key.root) % 12 + 12) % 12
        return key.scale.intervals.firstIndex(of: relative)
    }
}
