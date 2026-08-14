// VoiceCaptureController.swift
// Echoelmusic — Studio (voice → timbre, the control-plane glue)
//
// EchoelVoice #592b: the thin @Observable layer between the tested pieces. It arms the
// capture (the #277 shape — nothing listens until the user asks), routes the mic's
// existing main-thread sample blocks into `VoiceCaptureEngine` via
// `MicrophoneManager.captureSampleSink`, mirrors the engine's progress into observable
// state for the ONE leaf row that renders it, and on completion hands the measured
// profile to `PolySynthVoice.applyVoiceProfile` — the #591a pathway that survives patch
// recalls. Mic lifecycle is borrowed, not owned: only a mic THIS controller started is
// stopped. (The `micStartedByUs` check is DEFENSIVE, not a live interaction — measured
// at review #592b: the one production caller of `microphoneManager.startRecording()`
// sits behind `inputMonitoringEnabled`, which has zero writers in `Sources/`, so
// `mic.isRecording` is false at every reachable `begin()` today. The discipline stays
// so a future mic owner cannot be stopped out from under.)
//
// Observable writes are change-gated (the sink fires up to ~47×/s — `installTap`'s
// 1024 bufferSize is advisory, real buffers can be larger; `progress` moves only when
// a voiced window lands, `hearingYou` only on transitions), and the ONLY view reading
// this object is the `VoiceCaptureRow` leaf — the 10.76.41/50 freeze law shape.
//
// Permission edge, honest: `begin` with no mic permission leaves `MicrophoneManager` to
// request it (its `startRecording` does) and the capture sits armed at 0 % until sound
// arrives; the user cancels or re-arms after granting. No second permission flow here.

import Foundation

#if canImport(Accelerate)   // VoiceCaptureEngine exists only with Accelerate

@MainActor
@Observable
final class VoiceCaptureController {

    enum Phase: Equatable {
        case idle
        case capturing
        case done
    }

    private(set) var phase: Phase = .idle
    /// 0…1, moves only when a voiced window lands (~12 Hz worst case).
    private(set) var progress: Double = 0
    /// The live "we hear you" dot — true while the last window read as voiced.
    private(set) var hearingYou = false

    @ObservationIgnored private var engine = VoiceCaptureEngine()
    @ObservationIgnored private weak var mic: MicrophoneManager?
    @ObservationIgnored private weak var synth: PolySynthVoice?
    @ObservationIgnored private var micStartedByUs = false

    init() {}

    /// Arm a capture. `mic`/`synth` are borrowed for this one take.
    func begin(mic: MicrophoneManager, synth: PolySynthVoice) {
        guard phase != .capturing else { return }
        self.mic = mic
        self.synth = synth
        engine.start()
        phase = .capturing
        progress = 0
        hearingYou = false
        micStartedByUs = !mic.isRecording
        mic.captureSampleSink = { [weak self] samples, sampleRate in
            self?.ingest(samples, sampleRate: sampleRate)
        }
        if micStartedByUs { mic.startRecording() }
    }

    /// Abort the take: nothing is applied, the mic is released if it was ours.
    func cancel() {
        engine.cancel()
        phase = .idle
        progress = 0
        releaseMic()
    }

    /// Remove the applied voice timbre — hands the sound back to the patch pathway
    /// (`clearVoiceProfile` re-applies the remembered patch) and returns to idle.
    ///
    /// ⛔ F5b (#593c): the synth is a required PARAMETER, not the weak `self.synth` —
    /// that reference is set only by `begin()`, so when the profile arrived embedded
    /// in a recalled patch (no capture this launch) the weak var was nil and the old
    /// `synth?.clearVoiceProfile()` was a silent no-op: a Clear button that did
    /// nothing, on exactly the path a SHARED patch takes. The row passes its own
    /// `@Environment` synth; no default, so no call site can forget (#431).
    func clearApplied(synth: PolySynthVoice) {
        synth.clearVoiceProfile()
        phase = .idle
        progress = 0
    }

    private func ingest(_ samples: [Float], sampleRate: Double) {
        engine.ingest(samples, sampleRate: sampleRate)
        if engine.lastFrameWasVoiced != hearingYou {
            hearingYou = engine.lastFrameWasVoiced
        }
        let p = engine.progress
        if p != progress { progress = p }
        if engine.state == .done {
            if let profile = engine.profile {
                synth?.applyVoiceProfile(profile)
            }
            phase = .done
            releaseMic()
        }
    }

    private func releaseMic() {
        mic?.captureSampleSink = nil
        if micStartedByUs { mic?.stopRecording() }
        micStartedByUs = false
        hearingYou = false
    }
}

#endif  // canImport(Accelerate)
