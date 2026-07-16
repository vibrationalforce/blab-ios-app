// LaneDrumKitVoice.swift
// Echoel — S2-W2-2 (dissolution, "Spur = Instrument"): the device-side drum kit
// ONE drums LANE plays through — 4 pre-attached `DrumSynthVoice` pads (kick /
// snare / hat / pitched perc), driven by the pure `DrumNoteMap`. This is the
// physical `.drums(i)` unit the `KindVoiceAllocator` binds a rank slot to
// (rack facade = S2-W2-3); it is NOT the BeatPlayer step-sequencer kit — a
// dedicated kit per lane is the only honest mixer story (two writers on one
// voice was rejected in the plan §2).
//
// NO new render code: every pad is a stock DrumSynthVoice whose control→render
// handoff is the existing lock-free counter pattern (configure/fire/insert-FX
// all main-thread setters, audio thread applies). Attach-before-start law: the
// rack calls `attach(to:)` inside the startup "attaching voices" block, before
// audioEngine.start() — never at runtime.

#if canImport(AVFoundation) && canImport(Accelerate)
import AVFoundation
import Foundation

/// One lane's drum kit: 4 modal pads behind the pure `DrumNoteMap`.
@MainActor
public final class LaneDrumKitVoice {

    private let pads: [DrumSynthVoice]
    /// Per-pad cache of the last-configured preset — a hit only reconfigures its
    /// pad when the pitch demands a DIFFERENT preset (avoids a modal-bank
    /// reconfigure request per hit on a steady groove).
    private var appliedParams: [DrumSynthParams?]
    private var attached = false

    public init() {
        pads = (0..<DrumNoteMap.padCount).map { _ in DrumSynthVoice() }
        appliedParams = Array(repeating: nil, count: DrumNoteMap.padCount)
    }

    /// True once the pads are attached to the engine (flag-ON path only).
    public var isActive: Bool { attached }

    /// Attach all pads. Idempotent; call BEFORE audioEngine.start() (attach-
    /// before-start law) — the rack's attachAll drives this, flag-gated.
    public func attach(to engine: AudioEngine) {
        guard !attached else { return }
        for p in pads { engine.attachSourceNode(p.sourceNode) }
        attached = true
    }

    /// Strike the pad `DrumNoteMap` picks for `pitch`, reconfiguring the pad's
    /// modal preset only when this pitch needs a different one. Control-plane:
    /// configure/fire are lock-free requests the audio thread applies.
    public func noteOn(pitch: Int, velocity: Int) {
        let hit = DrumNoteMap.hit(pitch: pitch, velocity: velocity)
        let i = hit.pad.rawValue
        guard pads.indices.contains(i) else { return }
        if appliedParams[i] != hit.params {
            pads[i].configure(hit.params)
            appliedParams[i] = hit.params
        }
        pads[i].fire(gain: hit.gain)
    }

    /// One-shots decay naturally — a drum has no gate to release.
    public func noteOff(pitch: Int) {}

    /// Documented no-op: modal strikes are short and self-decaying; there is no
    /// sustained state to silence (the H5b off-fan calls this harmlessly).
    public func allNotesOff() {}

    /// Fan the `.drums` bus insert (filter/drive) over all pads — the S2-W2-5
    /// mirror of the S2-W1 melodic fan. Main-thread setters; atomic mirrors.
    public func setInsert(_ fx: TrackFX) {
        for p in pads {
            p.configureInsertFX(type: fx.filter.rawValue, cutoff: fx.cutoffHz,
                                resonance: fx.resonance, drive: fx.drive)
        }
    }

    /// Lane gain via the pads' AVAudioMixing volume (the B2 engine path).
    /// Guarded on `attached` so unit tests never force a lazy source node;
    /// clamped to AVAudioMixing's documented 0…1.
    public func setGain(_ gain: Float) {
        guard attached else { return }
        let g = Swift.max(0, Swift.min(1, gain.isFinite ? gain : 1))
        for p in pads { p.sourceNode.volume = g }
    }

    /// Lane stereo position via AVAudioMixing pan (−1…1), same guard as gain.
    public func setPan(_ pan: Float) {
        guard attached else { return }
        let v = Swift.max(-1, Swift.min(1, pan.isFinite ? pan : 0))
        for p in pads { p.sourceNode.pan = v }
    }

    #if DEBUG
    /// TEST SEAM (Debug-only): expose the per-pad preset cache so the Xcode gate
    /// can pin the reconfigure-only-on-change behavior without an engine.
    internal var appliedParamsForTests: [DrumSynthParams?] { appliedParams }
    #endif
}
#endif
