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
// stopped. The `micStartedByUs` check is DEFENSIVE, not a live interaction — but its
// stated reason was wrong twice over, so here is the measured one (#866).
//
// ⛔ WHAT #592b WROTE: "the one production caller of `microphoneManager.startRecording()`
// sits behind `inputMonitoringEnabled`, which has zero writers". BOTH halves failed. The
// zero-writer half was TRUE and is now moot — that flag and its dead branch are deleted
// (see the tombstone in `AudioEngine`). The "one caller" half was FALSE the day it was
// written: there were two, and the second is line ~69 of THIS file. The sentence looked
// past the only caller that can actually make `mic.isRecording` true — its own.
//
// ⭐ THE CONCLUSION SURVIVES ON A STRONGER INVARIANT, which is why the check stays.
// `begin()` opens `guard phase != .capturing`, so re-entry is only possible from `.idle`
// or `.done`; and EVERY exit from `.capturing` releases the mic (completion and
// `cancel()` both call `releaseMic()`). `clearApplied(synth:)` returns to `.idle` without
// releasing, and that is safe because it is reachable only from `.done`, where the mic is
// already released. So the controller can never re-enter `begin()` with a mic it started
// still running — `mic.isRecording` is false at every reachable `begin()` because of the
// PHASE MACHINE, not because some other caller happens to be dormant. The discipline
// stays so a future mic owner cannot be stopped out from under.
//
// ⚠️ ONE CROSS-OWNER INTERACTION IS REAL AND PRE-DATES ALL OF THIS, recorded so it is not
// later misattributed to the deletion: `AudioEngine.stop(reason:)` stops the mic
// unconditionally, so backgrounding mid-take kills a mic this controller started while
// `phase` stays `.capturing` and `micStartedByUs` stays `true`. The later
// `releaseMic()` is harmless (`stopRecording` is idempotent), but the controller is left
// armed behind its own guard. Unfixed, deliberately out of this slice.
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
        // #859b: the voice-timbre take is a mic-lifecycle event — it must speak in the
        // exported log like every other input path (see MicrophoneManager's rungs).
        EchoelCrashLog.breadcrumb("voice: capture armed")
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
        EchoelCrashLog.breadcrumb("voice: capture cancelled")
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
            EchoelCrashLog.breadcrumb("voice: capture done — profile applied")
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
