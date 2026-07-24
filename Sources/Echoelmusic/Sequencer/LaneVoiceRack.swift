// LaneVoiceRack.swift
// Multi-Roll device wiring (B07) — a FIXED pool of pre-attached PolySynthVoice slots
// so each MIDI lane can play its OWN voice. Behind FeatureFlags.multiRoll (registered
// DEFAULT-ON since 2026-07-14; the OFF rollback path stays intact): the rack is
// created + attached ONLY in `attachAll()`, which the app calls only when the flag
// is ON — with the flag OFF the rack holds ZERO voices, nothing is added to the
// audio graph, and the build is bit-identical to the single-voice path.
//
// Slot assignment is decided by the already-pure, CI-tested LaneVoicePool /
// LaneVoiceRackPlan; this class is only the device-side voice container + graph
// attach. Each PolySynthVoice already owns its lock-free SPSCQueue<NoteCommand> +
// sourceNode + render block, so there is NO new audio-thread code here. Attach runs
// in the startup "attaching voices" block BEFORE audioEngine.start() (attach-before-
// start law); the render/graph correctness is device-verified before the flag flips.
//
// S2-W2-3 (dissolution, "Spur = Instrument"): the rack is now a FACADE over a
// heterogeneous pool — behind FeatureFlags.voiceKindRouting (registration-ON
// since 2026-07-17; dev-OFF override stays the rollback lever) it also
// carries 1 LaneDrumKitVoice + 1 dedicated lane SubBassVoice + 1 lane
// SamplerVoice one-shot unit (S2-W3), and the pure
// KindVoiceAllocator binds each rank slot's KIND to a physical voice. Rank slots
// stay the authoritative contract everywhere else; only the routing INSIDE this
// class changes meaning. Flag OFF ⇒ zero kind units ⇒ the allocator resolves every
// slot to `.poly(slot)` ⇒ bit-identical to the S2-W1 rack.
//
// Guarded AVFoundation+Accelerate since S2-W2-3 (LaneDrumKitVoice/DrumSynthVoice
// live behind Accelerate; every Apple platform has both, non-Apple CI compiles out
// either way) — the gate is the Xcode compile check + on-device verification.

#if canImport(AVFoundation) && canImport(Accelerate)
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

    // MARK: - S2-W2 heterogeneous pool (flag-gated; empty while OFF)

    /// Physical kind units — created in attachAll ONLY when
    /// FeatureFlags.voiceKindRouting is ON. Control-plane state: never read by
    /// SwiftUI bodies (leaf-body law), so observation is ignored throughout.
    @ObservationIgnored public private(set) var kits: [LaneDrumKitVoice] = []
    @ObservationIgnored public private(set) var subs: [SubBassVoice] = []
    @ObservationIgnored public private(set) var samplers: [SamplerVoice] = []
    /// BodyVibe B1: lane BioReactiveSynthVoice units — REAL instances (each owns
    /// its own EchoelDDSP + source node), COEXISTING with the global armed voice
    /// (separate instance, separate attach — never a double-attach of one node).
    /// A rack unit is NEVER `start(subscribing:)`-ed: that would drain the
    /// shared controllerEvents SPSC queue (single-consumer!) and let breath
    /// onsets bypass the sequencer gate. Timbre comes via `feedBio(from:)`
    /// (the app fans the global voice's existing 10 Hz tick); the ENVELOPE is
    /// owned by the sequencer note gate (noteOn → playNote, noteOff/allNotesOff
    /// → releaseNote), so the track follows the arrangement instead of droning.
    @ObservationIgnored public private(set) var bios: [BioReactiveSynthVoice] = []
    /// The declared kind per rank slot (setKind) and the allocator's current
    /// slot→physical bindings. Absent slot ⇒ `.poly(slot)` — today's sound.
    @ObservationIgnored private var kinds: [Int: LaneVoiceKind] = [:]
    @ObservationIgnored private var bindings: [Int: PhysicalVoiceRef] = [:]
    /// Per-slot semitone shift, needed control-side because the mono sub is
    /// pitched at enqueue time (poly voices shift render-side themselves).
    @ObservationIgnored private var transposeBySlot: [Int: Int] = [:]
    /// The sample URL each rank slot's LANE carries (setSample) — kept per SLOT,
    /// not per unit, so rebinding loads the newly bound lane's own sample into
    /// the sampler unit (the sample follows the lane, like transpose).
    @ObservationIgnored private var sampleURLBySlot: [Int: URL] = [:]
    /// BodyVibe B1: the RAW (pre-transpose) pitch currently gating each bio-bound
    /// slot's mono voice. Mono last-note-wins: only the CURRENT note's off may
    /// close the envelope — a stale off from an overlap must not cut the newer
    /// note. Matched on the raw pitch, so a transpose change can never strand
    /// a held note (offs arrive raw too).
    @ObservationIgnored private var bioHeldPitchBySlot: [Int: Int] = [:]

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
        // S2-W2-3: the heterogeneous units, still strictly before
        // audioEngine.start() (attach-before-start law). Flag OFF ⇒ none exist
        // ⇒ the allocator maps every slot to poly ⇒ bit-identical graph.
        if FeatureFlags.voiceKindRouting {
            let kit = LaneDrumKitVoice()
            kit.attach(to: audioEngine)
            kits = [kit]
            let sub = SubBassVoice()
            sub.attach(to: audioEngine)
            subs = [sub]
            // S2-W3: one lane sampler one-shot unit. SamplerVoice has no
            // attach(to:) of its own — its sourceNode goes through the SAME
            // AudioEngine door BeatPlayer uses (pause→attach→connect→restart),
            // still strictly before audioEngine.start().
            let sampler = SamplerVoice()
            audioEngine.attachSourceNode(sampler.sourceNode)
            samplers = [sampler]
            // BodyVibe B1: one lane bio unit — its OWN BioReactiveSynthVoice
            // instance (fresh EchoelDDSP + fresh source node), attached exactly
            // like the global voice but NEVER subscribed to the bus (see `bios`
            // doc). Launch-silent by construction: the voice's hasEverSounded
            // gate stays false until the first sequencer noteOn.
            let bio = BioReactiveSynthVoice()
            bio.attach(to: audioEngine)
            bios = [bio]
        }
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
        // Deliberately poly-only: kits/subs belong to the .drums/.bass BUS
        // inserts, fanned in S2-W2-5 via setDrumsInsert/setBassInsert. The
        // sampler unit has its own per-channel insert (configureInsertFX),
        // un-fanned in slice 1 — no bus claims it yet.
    }

    /// S2-W2-5: push the `.drums` bus insert (filter/drive) to every lane drum
    /// kit — the mirror of the S2-W1 melodic fan for the kit voices. No-op while
    /// unattached / voiceKindRouting OFF (kits is empty), so an un-dialed drums
    /// bus stays bit-identical. Control-path only (kit.setInsert enqueues).
    public func setDrumsInsert(_ fx: TrackFX) {
        for k in kits { k.setInsert(fx) }
    }

    /// S2-W2-5: push the `.bass` bus insert to every dedicated lane sub — mirror
    /// of setDrumsInsert. No-op while unattached / flag OFF (subs is empty).
    public func setBassInsert(_ fx: TrackFX) {
        for s in subs { s.setInsert(fx) }
    }

    /// S2-W2-5: match every lane sub to the instrument's concert pitch, so a
    /// sub-bound lane stays in tune when A4 leaves 440 (the primary sub already
    /// gets this; without it a lane sub droned off-pitch at e.g. A=432). No-op
    /// while flag OFF (subs empty). Control-path (setTuning writes an atomic).
    public func setTuning(a4Hz: Double) {
        // The lane MELODIC voices (the PolySynthVoice pool) must follow A4 too — they
        // were skipped here and every lane MIDI note played at the hardcoded 440 while
        // subs/bios/global synth retuned, so a melodic lane droned off-pitch at e.g.
        // A=432. Same atomic control-path (setTuning writes poly.a4Hz, read at next note).
        for v in voices { v.setTuning(a4Hz: a4Hz) }
        for s in subs { s.setTuning(a4Hz: a4Hz) }
        // BodyVibe B1: the lane BIO voices must follow A4 too — without this a lane bio
        // unit played every MIDI note at a hardcoded 440 and drifted off-pitch at e.g.
        // A=432 while the rest of the instrument retuned. Same atomic control-path.
        for b in bios { b.setTuning(a4Hz: a4Hz) }
    }

    // MARK: - S2-W2-3 kind-routing facade
    // Rank slots stay authoritative; ONLY here does a slot resolve to a physical
    // voice. Every method is control-plane (main actor) — the physical voices'
    // own lock-free counters/queues carry the change to the render thread.

    /// Declare the voice KIND slot `slot`'s lane plays through, then re-run the
    /// pure allocation. On any binding change the PREVIOUSLY bound physical
    /// voice gets allNotesOff (S2-W2-1 carry: the allocator guarantees no lane-
    /// identity stability across rank shifts, so rebind must never strand a
    /// gate-held note). Idempotent for an unchanged kind.
    public func setKind(slot: Int, kind: LaneVoiceKind) {
        guard attached, slot >= 0, slot < voices.count else { return }
        guard kinds[slot] != kind else { return }
        kinds[slot] = kind
        rebindAll()
    }

    /// The physical voice a slot currently resolves to (absent ⇒ poly — the
    /// allocator's "never silence" law, and the flag-OFF shape).
    private func binding(forSlot slot: Int) -> PhysicalVoiceRef {
        bindings[slot] ?? .poly(slot)
    }

    /// Recompute all bindings from the declared kinds. Side-effectful iteration
    /// runs over keys.sorted() (S2-W2-1 carry: dictionary order is
    /// nondeterministic and allNotesOff is a side effect).
    private func rebindAll() {
        let ordered = kinds.keys.sorted().map { (slot: $0, kind: kinds[$0] ?? .poly) }
        let fresh = KindVoiceAllocator.allocate(ordered: ordered,
                                                drumUnits: kits.count, subUnits: subs.count,
                                                samplerUnits: samplers.count,
                                                bioUnits: bios.count)
        let touched = Set(bindings.keys).union(fresh.keys)
        for slot in touched.sorted() {
            let old = bindings[slot] ?? .poly(slot)
            let new = fresh[slot] ?? .poly(slot)
            if old != new {
                allNotesOff(on: old)
                // A slot leaving its bio unit must drop the gate memo too, or a
                // later re-bind could match a stale pitch and mis-release.
                if case .bio = old { bioHeldPitchBySlot[slot] = nil }
            }
        }
        bindings = fresh
        // The sampler units carry per-LANE buffers: after a binding change, load
        // each sampler-bound slot's remembered sample into its unit (setSample may
        // have run while the slot was poly-fallback / bound elsewhere). Sorted for
        // deterministic order; loadSampleIfNeeded skips an already-loaded URL.
        for slot in bindings.keys.sorted() {
            if case .sampler(let i) = bindings[slot], samplers.indices.contains(i),
               let url = sampleURLBySlot[slot] {
                loadSampleIfNeeded(url, intoSampler: i)
            }
        }
    }

    private func allNotesOff(on ref: PhysicalVoiceRef) {
        switch ref {
        case .poly(let i):    if voices.indices.contains(i) { voices[i].allNotesOff() }
        case .drums(let i):   if kits.indices.contains(i) { kits[i].allNotesOff() }
        case .subBass(let i): if subs.indices.contains(i) { subs[i].allNotesOff() }
        case .sampler(let i): if samplers.indices.contains(i) { samplers[i].silence() }
        case .bio(let i):     if bios.indices.contains(i) { bios[i].releaseNote() }
        }
    }

    /// Route a note-ON to the slot's bound physical voice. Velocity arrives in
    /// the poly convention (0…1 Float); the kit takes MIDI 0…127.
    public func noteOn(slot: Int, pitch: Int, velocity: Float) {
        switch binding(forSlot: slot) {
        case .poly:
            voice(slot: slot)?.noteOn(pitch: pitch, velocity: velocity)
        case .drums(let i):
            guard kits.indices.contains(i) else { return }
            kits[i].noteOn(pitch: pitch, velocity: Self.midiVelocity(velocity))
        case .subBass(let i):
            guard subs.indices.contains(i) else { return }
            subs[i].noteOn(pitch: pitch + (transposeBySlot[slot] ?? 0))
        case .sampler(let i):
            guard samplers.indices.contains(i) else { return }
            // One-shot sampler, drum-machine retrigger convention (SamplerVoice
            // contract): MONO — a new hit resets playback to the start, no voice
            // stealing, no overlap. Root = MIDI 60; the note's distance from it
            // (plus the lane transpose, folded in control-side like the sub)
            // pitches the sample via playback rate, clamped ±24 st by the voice.
            samplers[i].configurePlayback(
                pitchSemitones: Float(pitch - 60 + (transposeBySlot[slot] ?? 0)))
            samplers[i].fire(gain: velocity)   // velocity is already 0…1
        case .bio(let i):
            guard bios.indices.contains(i) else { return }
            // BodyVibe B1: the sequencer GATE. Monophonic last-note-wins (the
            // voice's own playNote contract); pitched control-side at enqueue
            // like the sub (transpose folded in, clamped to MIDI range).
            // Velocity is deliberately unused: the body drives this voice's
            // dynamics (breath envelope depth, bio timbre) — the lane fader is
            // the level control. playNote flips the voice's launch-silence
            // latch, so the unit first sounds when its TRACK actually plays.
            let midi = UInt8(Swift.max(0, Swift.min(127, pitch + (transposeBySlot[slot] ?? 0))))
            bios[i].playNote(frequency: bios[i].soundingFrequency(forMIDINote: midi))
            bioHeldPitchBySlot[slot] = pitch
        }
    }

    /// Route the note-OFF to the slot's CURRENT binding only. The H5b mid-take-
    /// flip law is already covered WITHOUT a fan: every binding change goes
    /// through rebindAll → allNotesOff(old) and every sub shift change releases
    /// too, so a note can never remain gate-held on a unit the slot is no longer
    /// bound to. A fan to ALL subs would instead CUT a foreign lane's held sub
    /// note on a pitch collision (audio review MEDIUM on 89814a2) — the sub's
    /// off is pitch-matched, not slot-scoped.
    public func noteOff(slot: Int, pitch: Int) {
        switch binding(forSlot: slot) {
        case .poly:
            voice(slot: slot)?.noteOff(pitch: pitch)
        case .drums(let i):
            guard kits.indices.contains(i) else { return }
            kits[i].noteOff(pitch: pitch)
        case .subBass(let i):
            guard subs.indices.contains(i) else { return }
            subs[i].noteOff(pitch: pitch + (transposeBySlot[slot] ?? 0))
        case .sampler:
            // One-shot: the hit plays to its end (or the next retrigger) — a
            // note-OFF is a documented no-op, like a drum pad. A binding change
            // or allNotesOff still cuts it via silence().
            break
        case .bio(let i):
            guard bios.indices.contains(i) else { return }
            // Mono last-note-wins: only the CURRENTLY gating note's off may
            // close the envelope — a stale off (legato overlap) must not cut
            // the newer note. Raw-pitch match, see bioHeldPitchBySlot.
            guard bioHeldPitchBySlot[slot] == pitch else { return }
            bioHeldPitchBySlot[slot] = nil
            bios[i].releaseNote()
        }
    }

    /// Pure poly→MIDI velocity mapping for the kit path (0…1 Float → 0…127;
    /// non-finite → 0 BEFORE clamping so NaN can't slip through min/max).
    internal static func midiVelocity(_ velocity: Float) -> Int {
        Int((Swift.max(0, Swift.min(1, velocity.isFinite ? velocity : 0)) * 127).rounded())
    }

    /// Per-slot transpose: poly shifts render-side as today; the sub is pitched
    /// control-side at enqueue, so a CHANGE while sub-bound releases the mono
    /// sub first (a held note's OFF would arrive with the new shift and miss —
    /// the off-matching law); a drum kit is unpitched — documented ignore.
    /// The bio unit is also pitched at enqueue, but its gate matches the RAW
    /// pitch (bioHeldPitchBySlot), so a mid-note transpose change cannot strand
    /// a held note — no release needed; the next noteOn carries the new shift.
    public func setTranspose(slot: Int, semitones: Int) {
        let old = transposeBySlot[slot] ?? 0
        transposeBySlot[slot] = semitones
        voice(slot: slot)?.setTranspose(semitones: semitones)
        if old != semitones, case .subBass(let i) = binding(forSlot: slot),
           subs.indices.contains(i) {
            subs[i].allNotesOff()
        }
    }

    /// Fine detune is a poly-voice capability (the sub folds octaves, the kit is
    /// unpitched) — documented poly-only.
    public func setDetune(slot: Int, cents: Float) {
        voice(slot: slot)?.setDetune(cents: cents)
    }

    /// Oktaver (one doubled voice an octave up/down) is a poly-voice capability,
    /// same limits as detune (the sub folds octaves anyway, the kit is unpitched)
    /// — documented poly-only. Mix stays the engine's one default; direction is
    /// the one per-lane control.
    public func setOctave(slot: Int, direction: Int) {
        voice(slot: slot)?.setOctaver(direction: direction)
    }

    /// A SynthPatch shapes the poly engine — documented no-op for kit/sub (their
    /// timbre comes from DrumNoteMap presets / the sub's fixed felt-band voice).
    public func applyPatch(slot: Int, _ patch: SynthPatch) {
        voice(slot: slot)?.apply(patch)
    }

    /// Lane gain per bound kind. All paths honor the lane-fader contract 0…2
    /// (1 = unity; PolySynthVoice/LaneDrumKitVoice clamp internally); non-finite
    /// fails SILENT (0) per app convention.
    public func setGain(slot: Int, _ gain: Float) {
        switch binding(forSlot: slot) {
        case .poly:
            voice(slot: slot)?.setGain(gain)
        case .drums(let i):
            guard kits.indices.contains(i) else { return }
            kits[i].setGain(gain)
        case .subBass(let i):
            guard subs.indices.contains(i) else { return }
            subs[i].setGain(gain)   // encapsulated: clamps 0…2, attach-guarded
        case .sampler(let i):
            guard samplers.indices.contains(i) else { return }
            // The lane fader lands on the sampler's shape LEVEL (clamped to the
            // lane-fader contract 0…2, non-finite fails silent per app
            // convention). attackMs/lengthMs stay at their defaults (0 = no
            // fade-in, full sample) — the lane path never reshapes the hit.
            samplers[i].configureShape(
                level: Swift.max(0, Swift.min(2, gain.isFinite ? gain : 0)),
                attackMs: 0, lengthMs: 0)
        case .bio(let i):
            guard bios.indices.contains(i) else { return }
            bios[i].setGain(gain)   // encapsulated: clamps 0…2 at the mixer stage
        }
    }

    /// Lane pan per bound kind. The mono sub stays un-panned (pro-audio
    /// convention: subs are not localized) — documented no-op. The sampler is a
    /// mono source node without a pan stage (slice 1) — documented no-op too.
    /// The bio unit pans at its source node's mixer stage (AVAudioMixing, the
    /// B2/PolySynthVoice engine path).
    public func setPan(slot: Int, _ pan: Float) {
        switch binding(forSlot: slot) {
        case .poly:
            voice(slot: slot)?.setPan(pan)
        case .drums(let i):
            guard kits.indices.contains(i) else { return }
            kits[i].setPan(pan)
        case .bio(let i):
            guard bios.indices.contains(i) else { return }
            bios[i].setPan(pan)   // encapsulated: clamps −1…1
        case .subBass, .sampler:
            break
        }
    }

    /// Assign (or clear, with nil) the SAMPLE a slot's lane plays through its
    /// sampler unit. Control-plane only: remembers the URL per SLOT and loads it
    /// into the CURRENTLY bound sampler unit (rebindAll re-loads on any later
    /// binding change, so the sample follows the lane). A load failure logs and
    /// keeps the unit's previous buffer sounding — never a crash, no force-unwrap.
    /// nil clears the memo; the unit keeps its buffer until another lane's sample
    /// replaces it (an unbound buffer can't sound — fire() routes by binding).
    public func setSample(slot: Int, url: URL?) {
        guard attached, slot >= 0, slot < voices.count else { return }
        sampleURLBySlot[slot] = url
        guard let url, case .sampler(let i) = binding(forSlot: slot),
              samplers.indices.contains(i) else { return }
        loadSampleIfNeeded(url, intoSampler: i)
    }

    /// BodyVibe B1: forward the bus's latest bio snapshot into every lane bio
    /// unit's timbre. Called from the GLOBAL BioReactiveSynthVoice's existing
    /// 10 Hz poll tick (app wiring via `onPollTick`) — no second timer, no
    /// per-frame MainActor hop. Zero cost while `bios` is empty (flag OFF /
    /// unattached). Timbre only: the envelope stays with the sequencer gate,
    /// so a silent (gated) unit still tracks the body and sounds current the
    /// moment its track plays.
    public func feedBio(from bus: EngineBus) {
        for b in bios { b.applyBioFrame(from: bus) }
    }

    /// Load `url` into sampler unit `i` unless that exact file is already its
    /// loaded buffer (region loads re-push the lane's sample every prime — the
    /// skip keeps that idempotent, no disk churn). Main-thread file I/O at
    /// load/prime time only; the buffer travels to the render thread over the
    /// voice's lock-free slab handshake.
    private func loadSampleIfNeeded(_ url: URL, intoSampler i: Int) {
        guard samplers.indices.contains(i) else { return }
        if samplers[i].isLoaded, samplers[i].sourceURL == url { return }
        do {
            try samplers[i].loadSample(from: url)
        } catch {
            log.log(.error, category: .audio,
                    "LaneVoiceRack: sample load failed for \(url.lastPathComponent): \(error)")
        }
    }

    #if DEBUG
    /// TEST SEAM (Debug-only, review-hardened): install pre-built voices WITHOUT an
    /// engine attach, so the Xcode gate can pin the `setInsert` fan-out (attachAll
    /// needs a live AudioEngine, which unit tests must not construct). Never call
    /// from app code — `attachAll` is the one production path, and this flips
    /// `attached` without any graph work.
    internal func installVoicesForTests(_ testVoices: [PolySynthVoice]) {
        voices = testVoices
        attached = true
    }
    /// TEST SEAM (Debug-only): install kind units WITHOUT an engine so the Xcode
    /// gate can pin the S2-W2-3 facade routing (attachAll's unit creation is
    /// flag+engine-gated). Call AFTER installVoicesForTests.
    internal func installKindUnitsForTests(kits testKits: [LaneDrumKitVoice],
                                           subs testSubs: [SubBassVoice],
                                           samplers testSamplers: [SamplerVoice] = [],
                                           bios testBios: [BioReactiveSynthVoice] = []) {
        kits = testKits
        subs = testSubs
        samplers = testSamplers
        bios = testBios
    }
    /// TEST SEAM (Debug-only): the live slot→physical bindings, to pin the
    /// allocator integration (first-rank-wins, fallback, flag-OFF shape).
    internal var bindingsForTests: [Int: PhysicalVoiceRef] { bindings }
    #endif
}
#endif
