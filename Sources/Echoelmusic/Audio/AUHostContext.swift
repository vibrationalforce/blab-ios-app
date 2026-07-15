// AUHostContext.swift
// Echoelmusic — Audio
//
// H9b: installs the host context blocks — `musicalContextBlock` +
// `transportStateBlock` — on every AU we host (global AUv3Host channel,
// master-bus effects, per-lane H5/H9a chains). Until now hosted plugins got
// MIDI only and NO tempo: an Eventide-style tempo-synced delay or LFO
// free-ran instead of locking to the song. With these blocks, plugins that
// ask their host for musical context get Echoel's one authoritative clock.
//
// RENDER-THREAD LAW: plugins call these blocks from the render thread. The
// closures below therefore do ONLY plain reads of the `HostMusicalState`
// mirror (word-width values, main-actor-written) and arithmetic — no locks,
// no allocation, no ObjC messaging, no captures of @MainActor objects.
//
// Honest limits (documented, not faked):
// - beatPosition advances per transport STEP (16th note) — plugins needing
//   sub-step phase interpolate from tempo, as they do with any coarse host.
// - `.changed` transport flag is never set (tracking it would need per-AU
//   mutable state written from N render threads); `.moving` + tempo cover
//   the tempo-sync use case. Cycle/loop bounds are not reported.
// - Time signature is fixed 4/4 — Transport's own model (stepsPerBar 16).

#if canImport(AVFoundation)
import AVFoundation
import Foundation

enum AUHostContext {

    /// Install both context blocks on a hosted AU. Call at load/attach time
    /// (control plane), BEFORE the unit renders. Idempotent — reinstalling
    /// just replaces the blocks with equivalent ones.
    @MainActor
    static func install(on au: AUAudioUnit, state: HostMusicalState = .shared) {
        // Capture the Sendable mirror only — never self, never an engine.
        au.musicalContextBlock = { tempoPtr, timeSigNumPtr, timeSigDenPtr,
                                   beatPtr, sampleOffsetPtr, downbeatPtr in
            let tempo = state.tempo
            let beat = state.beatPosition
            tempoPtr?.pointee = tempo
            timeSigNumPtr?.pointee = 4
            timeSigDenPtr?.pointee = 4
            beatPtr?.pointee = beat
            // Best-effort (review MEDIUM): a hardwired 0 would claim "the next
            // beat is NOW" every callback — this is step-granular but honest,
            // and exactly 0 when the position sits ON a beat.
            sampleOffsetPtr?.pointee = Int(HostBeatMath.samplesToNextBeat(
                beat: beat, tempo: tempo, sampleRate: state.sampleRate))
            downbeatPtr?.pointee = HostBeatMath.measureDownbeat(beat: beat)
            return true
        }
        au.transportStateBlock = { flagsPtr, samplePosPtr, cycleStartPtr, cycleEndPtr in
            let playing = state.isPlaying
            if let flagsPtr {
                flagsPtr.pointee = playing ? .moving : AUHostTransportStateFlags()
            }
            // ONE field, ACCUMULATED by Transport (review HIGH: deriving
            // beat×tempo here ran backward under the bio tempo-glide and made
            // relocation-detecting plugins re-sync every glide tick).
            samplePosPtr?.pointee = state.samplePosition
            cycleStartPtr?.pointee = 0
            cycleEndPtr?.pointee = 0
            return true
        }
    }
}
#endif
