// LaneVoiceRack.swift
// Multi-Roll device wiring (B07) — a FIXED pool of pre-attached PolySynthVoice slots
// so each MIDI lane can play its OWN voice. Behind FeatureFlags.multiRoll (default
// OFF): the rack is created + attached ONLY in `attachAll()`, which the app calls
// only when the flag is ON — so when OFF the rack holds ZERO voices, nothing is
// added to the audio graph, and the build is bit-identical to today's single-voice
// path.
//
// Slot assignment is decided by the already-pure, CI-tested LaneVoicePool /
// LaneVoiceRackPlan; this class is only the device-side voice container + graph
// attach. Each PolySynthVoice already owns its lock-free SPSCQueue<NoteCommand> +
// sourceNode + render block, so there is NO new audio-thread code here. Attach runs
// in the startup "attaching voices" block BEFORE audioEngine.start() (attach-before-
// start law); the render/graph correctness is device-verified before the flag flips.
//
// AVFoundation-guarded like AudioEngine (which it attaches to) — so on non-Apple CI
// it compiles out; its gate is the Xcode compile check + on-device verification.

#if canImport(AVFoundation)
import Foundation
#if canImport(Observation)
import Observation
#endif

@MainActor
@Observable
public final class LaneVoiceRack {

    /// Dedicated voice slots. Lanes beyond this overflow (LaneVoiceRackPlan silences
    /// the lowest-priority) — start small (4), raise only after on-device CPU/mem.
    public let capacity: Int
    /// Per-slot polyphony budget (smaller than the main pad voice; one lane's chord).
    public let maxVoicesPerSlot: Int

    public private(set) var voices: [PolySynthVoice] = []
    private var attached = false

    public init(capacity: Int = 4, maxVoicesPerSlot: Int = 8) {
        self.capacity = Swift.max(1, capacity)
        self.maxVoicesPerSlot = Swift.max(1, maxVoicesPerSlot)
    }

    /// True once the slot voices are created + attached (flag-ON path only).
    public var isActive: Bool { attached }

    /// Create + attach `capacity` slot voices to the engine. Idempotent. Called ONLY
    /// when FeatureFlags.multiRoll is ON — when OFF this never runs, so no voice is
    /// instantiated and the graph is unchanged. Attach-before-start law: invoke in the
    /// startup "attaching voices" block, BEFORE audioEngine.start().
    public func attachAll(to audioEngine: AudioEngine) {
        guard !attached else { return }
        voices = (0..<capacity).map { _ in PolySynthVoice(maxVoices: maxVoicesPerSlot) }
        for v in voices { v.attach(to: audioEngine) }
        attached = true
    }

    /// Subscribe each slot voice to the bus (mirrors polyVoice.start). Call AFTER
    /// audioEngine.start(), flag-ON path only. Idempotent per voice.
    public func startAll(subscribing bus: EngineBus) {
        for v in voices { v.start(subscribing: bus) }
    }

    /// The voice bound to a slot index (nil if not attached or out of range). The
    /// fan-out (B08) routes a lane's notes to `voice(slot: binding.slot)`.
    public func voice(slot: Int) -> PolySynthVoice? {
        guard attached, slot >= 0, slot < voices.count else { return nil }
        return voices[slot]
    }

    /// S2-W1 (dissolution): push the melodic-bus insert (filter/drive) to EVERY
    /// rack slot voice, so the "Melodic" strip and "Sound & FX (this track)"
    /// honestly reach ALL poly lanes — before this, only the primary
    /// synth+leadSynth received the insert and a secondary lane's filter edit
    /// silently did nothing to that lane's own voice. Control-path only
    /// (PolySynthVoice.setInsert mirrors params for the render thread); no-op
    /// while unattached (multiRoll OFF) — bit-identical then.
    public func setInsert(_ fx: TrackFX) {
        for v in voices { v.setInsert(fx) }
    }
}
#endif
