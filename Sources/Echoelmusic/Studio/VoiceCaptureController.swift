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
// ⛔ #866 RECORDED A CROSS-OWNER HAZARD HERE AS LIVE, AND IT IS NOT — retracted the same
// day (#868), because a note that invents a bug costs the next session a hunt.
// The SHAPE is real: `AudioEngine.stop(reason:)` stops the mic unconditionally, and if it
// ran mid-take the controller would sit on `.capturing` with a dead mic. What #866 did not
// check is the level above. `stop(reason:)` has exactly TWO production callers, both
// `.idleBackground` in `EchoelmusicApp`, and BOTH are gated on an `audioNeeded` chain whose
// disjuncts include `microphoneManager.isRecording` — which a take sets, because `begin()`
// starts the mic. Backgrounding mid-capture therefore keeps the engine up; the branch that
// would strand this controller is not reachable.
//
// ⭐ AND THE PROTECTION IS DELIBERATE, not luck: both chains are pinned by
// `TheBodyVoiceCountsAsAudibleTests` (`…SceneChainStillNamesEveryOtherSourceOfSound` and
// `…StopSubscriberStillNamesItsOwnSources`), whose failure text calls widening that chain
// "the 2.5.4 rejection signature". No guard is added here — a third home for one rule is
// the #416 defect, and the rule already has two.
//
// ⚠️ WHAT WOULD MAKE IT REACHABLE, stated so it is not rediscovered from scratch: dropping
// `microphoneManager.isRecording` from either chain, or starting a take WITHOUT starting
// the mic (`micStartedByUs == false`, i.e. some future second mic owner). Both go red in
// that test first, which is where the trail should start.
//
// Observable writes are change-gated (the sink fires up to ~47×/s — `installTap`'s
// 1024 bufferSize is advisory, real buffers can be larger; `progress` moves only when
// a voiced window lands, `hearingYou` only on transitions), and the ONLY view reading
// this object is the `VoiceCaptureRow` leaf — the 10.76.41/50 freeze law shape.
//
// Permission edge, honest: `begin` with no mic permission leaves `MicrophoneManager` to
// request it (its `startRecording` does) and the capture sits armed at 0 % until sound
// arrives; the user cancels or re-arms after granting. No second permission flow here.
//
// ⚠️ #891 — THAT WAIT IS FINE; THE OTHER WAY TO REACH 0 % IS NOT. Measured rather than
// counted, because a count here would rot: EXACTLY ONE line in `startRecording()` sets
// `isRecording = true`, and it is the last statement of the `do`. Every other way back —
// five `return`s and the `catch` — leaves it false with no tap installed, so NO sample
// can ever arrive and the take sits on `.capturing` 0 % forever, escapable only by Cancel.
// Which of those are LIVE, so nobody hunts the wrong one: the permission `return` resolves
// by itself ONLY WHEN THE STATE IS UNDETERMINED — ⛔ #891 wrote "RESOLVES by itself" flat,
// and for a user who has DENIED the microphone iOS shows no prompt and returns immediately,
// so `hasPermission` stays false forever and the take keeps the exact 0 % hang this slice
// exists to remove. That case is deliberately still open, not overlooked: closing it needs
// `MicrophoneManager.permissionDenied` to reach a surface, and it has no reader anywhere in
// the voice path today. Naming it here is what stops the next session from reading the
// discriminator as complete · the "already recording" `return` cannot
// be reached from here at all, because `micStartedByUs = !mic.isRecording` means this
// caller only starts a mic that is stopped · the two #889 guards are documented
// unreachable in their own comments · what remains, and what this abort exists for, is the
// #890 placeholder-format refusal and the `catch` around `audioEngine.start()`.
// On a phone a silent 0 % is indistinguishable from a hang,
// and it is exactly the state the founder's #890 device probe would land in: the probe
// asks "capture straight after launch, twice in a row", which is the placeholder's own
// window. A probe whose failure mode looks like a hang cannot answer the question it was
// filed for. `begin()` therefore re-reads `mic.isRecording` after starting it and, when
// the mic did NOT come up WITH permission granted, aborts the take instead of pretending.

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
    /// How many times IN A ROW `begin()` could not get the microphone running. 0 = the last
    /// interaction was not a refusal.
    ///
    /// ⛔ #893 — #891 MADE THIS A `Bool` AND THAT ANSWERED THE WRONG QUESTION. A second
    /// refusal rendered byte-identical to the first: same sentence, same button, same
    /// phase, all inside one synchronous tap. The founder's #890 probe asks for a capture
    /// "immediately after launch, TWICE IN A ROW" — with a Bool the second tap gives the
    /// player no evidence it did anything, so the probe could not distinguish "refused
    /// again" from "the button is dead", which is the very confusion #891 set out to end.
    /// A count is the smallest thing that changes on screen when the state repeats.
    ///
    /// ⚠️ DELIBERATELY NOT RESET IN `begin()` — that would make "in a row" impossible, and
    /// nothing renders it during `.capturing` anyway (the caption's `switch` takes its own
    /// branch there). It is cleared where the streak genuinely ENDS: a completed take,
    /// `cancel()`, `clearApplied()`. Read by exactly one leaf (`VoiceCaptureRow`'s
    /// caption); it moves at most once per button tap, nowhere near the 10.76.41/50 churn
    /// class.
    private(set) var micRefusals = 0

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
        if micStartedByUs {
            mic.startRecording()
            // #891: it can REFUSE, and from here that refusal is SILENT — see the header
            // for which exits are live (#890's placeholder guard and the `catch`). No tap,
            // no sample, no way out but Cancel.
            //
            // ⭐ This covers the whole surface, not just one door: measured 2026-08-30,
            // `MicrophoneManager.startRecording()` has exactly ONE production caller in
            // `Sources/`, and it is this line.
            //
            // ⚠️ `hasPermission` IS THE DISCRIMINATOR AND MUST STAY. The no-permission exit
            // also leaves `isRecording` false, but the mic manager has just opened the system
            // prompt: that wait RESOLVES, and the header documents it as intended. Aborting
            // there would break the permission flow on the very first capture a user ever
            // tries. Only a refusal WITH permission already granted is a dead end.
            if !mic.isRecording, mic.hasPermission {
                micRefusals += 1
                // #893: the count rides the breadcrumb too, so the exported log answers the
                // probe's "twice in a row" even when nobody was watching the screen.
                EchoelCrashLog.breadcrumb(
                    "voice: capture aborted — mic did not start (\(micRefusals)x in a row)")
                engine.cancel()
                phase = .idle
                progress = 0
                // ⛔ NOT `releaseMic()`, deliberately. That calls `mic.stopRecording()`, which
                // walks its own three-rung stop ladder and releases the record route a SECOND
                // time — the start side already released it on every refusing exit
                // (#889/#890). The double set-removal is harmless, but the rungs would
                // announce a teardown of a mic that never started, and a rung for a step that
                // did not happen is the lie the ladder law exists to forbid (#882).
                mic.captureSampleSink = nil
                micStartedByUs = false
                hearingYou = false
                return
            }
        }
    }

    /// Abort the take: nothing is applied, the mic is released if it was ours.
    func cancel() {
        EchoelCrashLog.breadcrumb("voice: capture cancelled")
        engine.cancel()
        phase = .idle
        progress = 0
        // #892: today this is always already false — Cancel only renders during
        // `.capturing`, and `begin()` clears the flag on the way in. It is written anyway
        // so the invariant is UNCONDITIONAL rather than "benign because of where the
        // button happens to be": that second form is a claim about the view, and the view
        // is exactly what changed underneath #891's own rationale one commit ago.
        micRefusals = 0
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
        // #892: THIS one is not theoretical. Clear is reachable with the flag still true —
        // a refusal, then a recalled patch carrying a voice profile, then Clear — and
        // without this line the microphone-failure sentence would come back as the caption
        // for a successful, unrelated action.
        micRefusals = 0
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
            // #893: a take that finished is the strongest possible end of a refusal streak.
            micRefusals = 0
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
