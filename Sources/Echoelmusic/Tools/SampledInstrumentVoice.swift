// SampledInstrumentVoice.swift
// Echoel — REAL instruments as a sound source (founder 2026-07-04: "klingt
// alles mega scheiße" → decision "Ja, bauen"). Wraps Apple's built-in
// AVAudioUnitSampler (zero new code dependencies) and plays General-MIDI
// programs from the bundled GeneralUser GS soundfont (free license; fetched
// into Resources/Instruments by .github/workflows/fetch-instruments.yml).
//
// Design:
//   • One instance = one instrument (a GM program on its own sampler node),
//     mirroring the PolySynthVoice-per-role pattern (lead / harmony).
//   • GRACEFUL ABSENCE: until the soundfont asset lands in the bundle,
//     `isReady` stays false and the piano-roll router falls back to the
//     classic DDSP synth — builds and TestFlight stay green either way.
//   • The sampler renders on Apple's own audio unit — nothing is added to our
//     render path; attach follows the proven pause→attach→connect pattern.
//   • Bio-reactivity is preserved at the master level (FXBioModulator shapes
//     the FX chain); per-voice timbre modulation stays a classic-synth trait.

#if canImport(AVFoundation)
import AVFoundation
import Observation

@MainActor
@Observable
public final class SampledInstrumentVoice {

    /// GM programs this app uses (GeneralUser GS, melodic bank 0x79/0).
    public enum Program: UInt8, Sendable {
        case grandPiano = 0
        case ePiano     = 4
        case strings    = 48
        case warmPad    = 89
        case fingerBass = 33
    }

    @ObservationIgnored private let sampler = AVAudioUnitSampler()

    /// True once a program is loaded from the bundled soundfont. False =
    /// callers must fall back to the classic synth (router does this).
    public private(set) var isReady = false

    private let midiChannel: UInt8 = 0

    public init() {}

    // MARK: - Asset

    /// The bundled soundfont. nil until the CI-fetched asset ships in a build.
    public static var soundFontURL: URL? {
        Bundle.main.url(forResource: "GeneralUserGS", withExtension: "sf2")
    }

    /// Whether real instruments can play at all in this build.
    public static var isAvailable: Bool { soundFontURL != nil }

    // MARK: - Graph

    /// Attach the sampler node into the master graph. Safe before or after
    /// engine start (AudioEngine pauses/rewires/restarts internally).
    public func attach(to audioEngine: AudioEngine) {
        audioEngine.attachInstrument(sampler)
    }

    /// Load a GM program from the bundled bank. Safe to call again to switch
    /// instruments. No-op (isReady = false) while the asset is absent.
    public func load(program: Program) {
        guard let url = Self.soundFontURL else {
            isReady = false
            return
        }
        do {
            // 0x79 = kAUSampler_DefaultMelodicBankMSB, 0x00 = default bank LSB
            try sampler.loadSoundBankInstrument(at: url,
                                                program: program.rawValue,
                                                bankMSB: 0x79,
                                                bankLSB: 0x00)
            isReady = true
            log.log(.info, category: .audio, "SampledInstrument: loaded GM program \(program.rawValue)")
        } catch {
            isReady = false
            log.log(.error, category: .audio, "SampledInstrument: load failed — \(error.localizedDescription)")
        }
    }

    // MARK: - Notes (same shape as PolySynthVoice — NoteVoice routing)

    public func noteOn(pitch: Int, velocity: Float = 0.8) {
        guard isReady else { return }
        sampler.startNote(Self.midiPitch(pitch),
                          withVelocity: Self.midiVelocity(velocity),
                          onChannel: midiChannel)
    }

    public func noteOff(pitch: Int) {
        guard isReady else { return }
        sampler.stopNote(Self.midiPitch(pitch), onChannel: midiChannel)
    }

    public func allNotesOff() {
        guard isReady else { return }
        sampler.sendController(123, withValue: 0, onChannel: midiChannel)  // CC123 All Notes Off
    }

    // MARK: - Pure mapping helpers (unit-tested)

    /// 0…1 velocity → MIDI 1…127 (never 0 — 0 would be a note-off on wire).
    static func midiVelocity(_ v: Float) -> UInt8 {
        UInt8(min(max(Int((v * 127).rounded()), 1), 127))
    }

    /// Clamp any pitch into the MIDI range.
    static func midiPitch(_ p: Int) -> UInt8 {
        UInt8(min(max(p, 0), 127))
    }
}
#endif
