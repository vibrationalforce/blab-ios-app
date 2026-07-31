// PatternEngine.swift
// Echoel — 16-step × 8-track drum sequencer (model + tempo clock).
//
// W1 of v10 sprint: pure pattern model + Timer-driven step trigger.
// W2 will replace the Timer with a sample-accurate AVAudioSourceNode tick
// when SamplerVoice is wired into AudioEngine.

import Foundation
import Observation

/// 16-step × 8-track drum pattern with a tempo-driven trigger.
///
/// The engine owns the pattern grid (`steps`), the transport (`isPlaying`,
/// `currentStep`), and a timer that advances `currentStep` at 16th-note
/// resolution. When a step plays and that cell is `true`, `onStep(track,step)`
/// is called on the main actor — wire that callback to `SamplerVoice` (W2).
///
/// **Timing model:** 4/4 time, 16 steps per bar = 4 sixteenth-notes per beat.
/// Step duration = (60 / BPM) / 4 seconds. At 120 BPM, that's 125 ms.
///
/// **Concurrency:** `@MainActor`. A DispatchSourceTimer fires on the **main
/// queue** and calls `advance()` via `MainActor.assumeIsolated` — same pattern as
/// `AudioEngine.startMeterPollTimer`. The timer must NOT run on a background queue:
/// the Swift-6 executor check would trap (see `scheduleTick`).
@MainActor
@Observable
public final class PatternEngine {

    // MARK: - Constants

    public static let trackCount: Int = 8
    public static let stepCount: Int = 16
    // The musical-tempo RANGE is a control-plane concern owned by `Transport`
    // (Core/), the declared single authoritative clock. PatternEngine still owns the
    // real timer, but it reads the bounds from that one source so the range can never
    // drift across Transport / PatternEngine / BioTempoDirector. Values are unchanged
    // (30 / 300 / 120); Transport's constants are `nonisolated static let`.
    public static let minTempo: Double = Transport.minTempo
    public static let maxTempo: Double = Transport.maxTempo
    public static let defaultTempo: Double = Transport.defaultTempo

    // MARK: - Observed state

    /// 8 tracks × 16 steps. `steps[track][step] == true` means the cell triggers.
    public private(set) var steps: [[Bool]]

    /// Accent grid, parallel to `steps`. An accented active cell hits louder.
    public private(set) var accents: [[Bool]]

    /// Velocity (gain) for a non-accented vs accented hit.
    public static let normalVelocity: Float = 0.82
    public static let accentVelocity: Float = 1.0

    /// Transport state. `true` while the timer is running.
    public private(set) var isPlaying: Bool = false

    /// Current 16th-note position, 0..<stepCount. Resets to 0 on `stop()`.
    public private(set) var currentStep: Int = 0

    /// Wall-clock time (CFAbsoluteTimeGetCurrent) of the most recent DOWNBEAT tick
    /// (step 0). Lets the WAV loop exporter cut its capture bar-aligned (audit C7:
    /// "keep last" grabbed an arbitrary-phase window → seam click in the DAW).
    /// Polled imperatively at export time, never rendered — hence ignored by
    /// observation so the 1-per-bar write can't churn any view.
    @ObservationIgnored public private(set) var lastBarStartAt: CFAbsoluteTime = 0

    /// Beats per minute, clamped to [`minTempo`, `maxTempo`].
    public private(set) var tempo: Double = PatternEngine.defaultTempo

    /// Target tempo for a smooth GLIDE (0 = no glide in flight). When >0, `advance()` eases
    /// `tempo` toward it each tick so a body re-seed slides in instead of jumping ("bpm springt").
    /// Set via `glideTempo(to:)`; any explicit `setTempo` cancels it (an edit is precise/instant).
    @ObservationIgnored private var tempoGlideTarget: Double = 0

    /// A lightweight main-queue timer that eases the tempo toward `tempoGlideTarget` while the
    /// transport is STOPPED — `advance()` does the easing while playing, but a stopped take has
    /// no ticks, so a body re-seed would otherwise SNAP the displayed tempo ("bpm springt
    /// plötzlich"). This keeps the guarantee "the tempo number never jumps, ever": whether
    /// playing or paused, a glide always slides. Cancelled the moment playback starts (advance()
    /// takes over) or an explicit edit lands. Same main-queue DispatchSourceTimer pattern as the
    /// beat clock (see the isolation NOTE on `scheduleTick`).
    @ObservationIgnored private var stoppedGlideTimer: DispatchSourceTimer?

    /// Swing amount [0...0.5]. Lengthens the gap before off-beat (odd) 16ths,
    /// shortening the following gap so overall tempo is preserved. 0 = straight.
    public private(set) var swing: Double = 0

    /// Grids staged by `loadAtBoundary`, applied exactly on the next step-0 downbeat
    /// so a live re-seed never chops the sounding bar (mirrors the roll's
    /// `pendingNotes`). Imperative staging only — never rendered — so observation-
    /// ignored; the visible `steps`/`accents` update at the boundary as usual.
    @ObservationIgnored private var pendingSteps: [[Bool]]?
    @ObservationIgnored private var pendingAccents: [[Bool]]?

    // MARK: - Step-trigger callback

    /// Invoked on the main actor for every active cell at every step boundary.
    /// Wire this to `SamplerVoice.trigger(track:)` once SamplerVoice exists.
    public var onStep: ((_ track: Int, _ step: Int) -> Void)?

    /// Invoked once per step boundary (after drum cells), regardless of content.
    /// A second consumer on the SAME clock — used by the piano roll / melody lane
    /// so drums and melody share one transport (no two-timer drift).
    public var onTick: ((_ step: Int) -> Void)?

    /// Called whenever the transport stops, so the consumer can flush held notes
    /// (release every sounding voice). Centralised here so NO caller can forget
    /// to silence notes on stop and leave a drone ringing.
    public var onStop: (() -> Void)?

    // MARK: - Transport relay

    /// The single authoritative musical clock. PatternEngine remains the source of
    /// real-time pulses (it owns the timer); it RELAYS each pulse into `Transport`
    /// so position/tempo/play-state live in one observable place that future
    /// consumers (timeline playhead, MIDI clock, Ableton Link) can all ride.
    /// NOT a no-op mirror any more (that was true for one cycle only): the metronome,
    /// the haptic pulse and the stop-subscribers ride on Transport, so a tempo that
    /// moves the sequencer WITHOUT relaying here leaves the click behind. Existing
    /// `onStep`/`onTick`/`onStop` also stay wired and firing.
    /// Weak so the app owns Transport's lifetime.
    @ObservationIgnored public weak var transport: Transport?

    // MARK: - Internal

    // A DispatchSourceTimer that fires ON THE MAIN QUEUE. A DispatchSource (vs a
    // RunLoop Timer) still fires while the run loop is in tracking mode — UI
    // scrolling no longer needs `.common` mode to keep the beat — but by targeting
    // the main queue the handler runs on the main thread, where the engine's
    // @MainActor work (model/UI/synth mutation) is valid WITHOUT any cross-thread
    // executor hop. See scheduleTick for why a background queue is fatal here.
    // nonisolated(unsafe) so the nonisolated deinit can cancel it; the source is
    // only mutated on the main actor.
    @ObservationIgnored nonisolated(unsafe) private var timer: DispatchSourceTimer?

    // MARK: - Init

    public init() {
        self.steps = Array(
            repeating: Array(repeating: false, count: PatternEngine.stepCount),
            count: PatternEngine.trackCount
        )
        self.accents = Array(
            repeating: Array(repeating: false, count: PatternEngine.stepCount),
            count: PatternEngine.trackCount
        )
    }

    deinit {
        // Cancel the timer source so its handler closure is released (breaks the
        // retain cycle). DispatchSourceTimer.cancel() is thread-safe, so it's safe
        // from the nonisolated deinit.
        timer?.cancel()
    }

    // MARK: - Pattern editing

    /// Flip a single cell. Out-of-range track/step is a silent no-op.
    public func toggleStep(track: Int, step: Int) {
        guard track >= 0, track < PatternEngine.trackCount else { return }
        guard step >= 0, step < PatternEngine.stepCount else { return }
        steps[track][step].toggle()
    }

    /// Set a single cell explicitly. Out-of-range track/step is a silent no-op.
    public func setStep(track: Int, step: Int, on: Bool) {
        guard track >= 0, track < PatternEngine.trackCount else { return }
        guard step >= 0, step < PatternEngine.stepCount else { return }
        steps[track][step] = on
    }

    /// Toggle the accent flag on a cell. Out-of-range is a silent no-op.
    public func toggleAccent(track: Int, step: Int) {
        guard track >= 0, track < PatternEngine.trackCount else { return }
        guard step >= 0, step < PatternEngine.stepCount else { return }
        accents[track][step].toggle()
    }

    /// Set the accent flag on a cell explicitly. Out-of-range is a silent no-op.
    public func setAccent(track: Int, step: Int, on: Bool) {
        guard track >= 0, track < PatternEngine.trackCount else { return }
        guard step >= 0, step < PatternEngine.stepCount else { return }
        accents[track][step] = on
    }

    /// Velocity (gain) for a cell: accent → loud, active → grooved, off → 0.
    ///
    /// Non-accented hits used to fire at one flat `normalVelocity` (0.82), the textbook
    /// "machine-gun hats" tell — every 16th identical. Instead we apply a deterministic
    /// GROOVE curve: a metric weighting (downbeat > 8th > 16th) plus a small (±6%) seeded
    /// jitter keyed on (track, step) so hats/percussion breathe like a human player without
    /// ever wandering. Accents stay exactly 1.0, so drawn accents are untouched. Pure +
    /// deterministic (same grid → same groove), so it's fully unit-testable.
    public func velocity(track: Int, step: Int) -> Float {
        guard track >= 0, track < PatternEngine.trackCount,
              step >= 0, step < PatternEngine.stepCount,
              steps[track][step] else { return 0 }
        if accents[track][step] { return PatternEngine.accentVelocity }
        return PatternEngine.groovedVelocity(track: track, step: step)
    }

    /// Deterministic groove velocity for a non-accented active cell. Metric emphasis:
    /// downbeats (÷4) loudest, backbeat 8ths (÷2) mid, off-16ths softest (ghosted); a
    /// bounded ±6% hash jitter adds micro-humanity. Centered on `normalVelocity`.
    static func groovedVelocity(track: Int, step: Int) -> Float {
        let base = normalVelocity
        // Metric weight: THE ONE (bar downbeat, step 0) > other beats > 8th > 16th.
        // Founder ("manchmal ist es schwierig die Eins zu erkennen"): the old curve
        // pushed beats 1·2·3·4 identically, so nothing marked the bar's "one". Now
        // step 0 is the strongest grooved hit — the ear anchors to it every bar.
        let metric: Float
        if step == 0          { metric =  0.16 }   // THE ONE — strongest, anchors the bar
        else if step % 4 == 0 { metric =  0.07 }   // other beats (2·3·4) — pushed, but under the one
        else if step % 2 == 0 { metric =  0.02 }   // 8th — slight
        else                  { metric = -0.10 }   // off-16th — ghost
        // Deterministic bounded jitter in [-0.06, 0.06] from a cheap (track,step) hash.
        // The ONE gets NO jitter — a steady anchor that never wanders below a backbeat,
        // so the downbeat is reliably the strongest grooved hit (metric gap < jitter span).
        let h = (UInt32(bitPattern: Int32(step &* 73 &+ track &* 19 &+ 1)) &* 2654435761) >> 8
        let jitter: Float = step == 0 ? 0 : (Float(h % 1000) / 1000.0 - 0.5) * 0.12   // ±0.06
        let v = base + metric + jitter
        return Swift.min(0.98, Swift.max(0.35, v))             // stay below accent, audible floor
    }

    /// Set the swing amount, clamped to [0, 0.5].
    public func setSwing(_ amount: Double) {
        swing = Swift.min(Swift.max(amount, 0), 0.5)
        transport?.setSwing(swing)
    }

    /// Replace the whole grid (steps + accents), e.g. when launching a clip.
    /// Mismatched dimensions are ignored per-track so a bad clip can't crash.
    /// An explicit immediate load supersedes any groove staged at the boundary.
    public func load(steps newSteps: [[Bool]], accents newAccents: [[Bool]]) {
        pendingSteps = nil
        pendingAccents = nil
        guard newSteps.count == PatternEngine.trackCount,
              newAccents.count == PatternEngine.trackCount else { return }
        for t in 0..<PatternEngine.trackCount {
            guard newSteps[t].count == PatternEngine.stepCount,
                  newAccents[t].count == PatternEngine.stepCount else { continue }
            steps[t] = newSteps[t]
            accents[t] = newAccents[t]
        }
    }

    /// Stage a new groove to land exactly on the NEXT downbeat (step 0) instead of
    /// chopping the bar that is currently sounding. This mirrors the piano roll's
    /// `loadAtBoundary` so a live re-seed swaps melody AND drums together, musically
    /// — the mid-bar drum cut was an audible "holprig" source (founder 2026-07-06B:
    /// "organisch und professionell klingen"). When stopped, it loads immediately
    /// (nothing is sounding, and the grid must be present before playback starts).
    public func loadAtBoundary(steps newSteps: [[Bool]], accents newAccents: [[Bool]]) {
        guard isPlaying else { load(steps: newSteps, accents: newAccents); return }
        pendingSteps = newSteps
        pendingAccents = newAccents
    }

    /// Turn every cell off (steps + accents) without changing transport state.
    public func clear() {
        pendingSteps = nil    // a cleared grid must not resurrect a staged groove
        pendingAccents = nil
        for t in 0..<PatternEngine.trackCount {
            for s in 0..<PatternEngine.stepCount {
                steps[t][s] = false
                accents[t][s] = false
            }
        }
    }

    // MARK: - Transport

    /// Set tempo in BPM. Values outside [minTempo, maxTempo] are clamped.
    /// If the engine is playing, the timer restarts at the new interval.
    public func setTempo(_ bpm: Double) {
        // NaN-safe: THIS is the type that computes the step interval
        // (`Transport.stepDuration(atTempo:)`, fed to `swingGap`), so a NaN landing here does not
        // mis-time the sequencer — it silences it. (`DispatchTime + NaN` saturates to
        // `Int64.max`, so a tick is technically scheduled and then never fires.)
        // `Swift.min(Swift.max(bpm, lo), hi)` passes NaN through both clamps.
        // The live entry is the persisted `studio.lockedBPM` (an AppStorage Double);
        // parameter automation cannot deliver NaN — `AutomationTarget.value(forNormalized:)`
        // opens with `Swift.max(0, n)`, whose argument order makes it NaN-safe already.
        let clamped = bpm.clamped(to: PatternEngine.minTempo...PatternEngine.maxTempo)
        tempoGlideTarget = 0   // an explicit edit is precise + instant → cancel any in-flight glide
        stopStoppedGlide()     // …including a stopped-glide timer, so the edit lands exactly
        // Relay to the authoritative Transport FIRST, before the no-op early return below.
        // If Transport.tempo ever diverged (a write before the relay was wired, or a direct
        // Transport edit), a subsequent same-value setTempo must still re-sync the displayed
        // value — otherwise the transport bar keeps showing a stale tempo forever.
        transport?.setTempo(clamped)
        guard clamped != tempo else { return }
        tempo = clamped
        // Re-arm at the new rate if playing, otherwise the already-scheduled tick
        // would still fire at the OLD interval (one lagged step after a tempo
        // change / regenerate). scheduleTick invalidates the old timer first.
        if isPlaying {
            let base = Transport.stepDuration(atTempo: tempo)
            // Between ticks `currentStep` is the NEXT step to play; the gap before
            // it is decided by the JUST-PLAYED step (currentStep − 1), exactly as
            // advance() schedules it. Passing `currentStep` here inverted the swing
            // for the one step right after a mid-play tempo change.
            let justPlayed = (currentStep + PatternEngine.stepCount - 1) % PatternEngine.stepCount
            scheduleTick(after: PatternEngine.swingGap(afterStep: justPlayed, base: base, swing: swing))
        }
    }

    /// Smoothly GLIDE the tempo to `bpm` over ~2 s instead of snapping — used when the body
    /// re-seeds the take tempo, so the beat eases into the new pulse rather than jumping
    /// ("bpm springt plötzlich"). While PLAYING, `advance()` does the per-tick easing. While
    /// STOPPED there are no ticks, so a small main-queue timer eases it instead (it used to
    /// snap — the founder still saw the transport tempo jump when a re-seed landed on a paused
    /// take). Either way the number always slides, never jumps. User/transport edits keep using
    /// `setTempo` (instant + precise). Values are clamped to [minTempo, maxTempo].
    public func glideTempo(to bpm: Double) {
        // NaN-safe for the same reason as `setTempo`. The body-derived callers are
        // already NaN-proof by argument order (`StudioCalculator.seedTempo`'s
        // `Swift.min(160, x)` inside a `Swift.max(50, …)`, and the `displayBPM > 0`
        // gate in BodyTempoField); the reachable entry is again the persisted
        // `studio.lockedBPM`, via the compose path.
        let clamped = bpm.clamped(to: PatternEngine.minTempo...PatternEngine.maxTempo)
        if isPlaying {
            tempoGlideTarget = clamped
            stopStoppedGlide()   // ticks are running → advance() eases it
        } else if abs(clamped - tempo) <= 0.5 {
            // Already there (the initial generate holds the current tempo) — set exactly, no
            // timer, no lag. Only a genuine change eases while stopped.
            tempoGlideTarget = 0
            stopStoppedGlide()
            tempo = clamped
            transport?.setTempo(clamped)
        } else {
            tempoGlideTarget = clamped
            startStoppedGlide()  // no ticks → ease the displayed tempo here
        }
    }

    /// Begin (or restart) the stopped-glide timer. ~20 Hz, main queue — a control-plane
    /// display ease, not audio-thread work. Self-terminates once within 0.5 bpm.
    private func startStoppedGlide() {
        stoppedGlideTimer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 0.05, repeating: 0.05, leeway: .milliseconds(5))
        t.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.stepStoppedGlide() }
        }
        t.resume()
        stoppedGlideTimer = t
    }

    /// One easing step of the stopped glide (mirrors `advance()`'s one-pole toward the
    /// target). Stops itself when playback starts (advance() takes over), when the target is
    /// cleared, or when it arrives. Relays each step so the transport bar / click stay in sync.
    private func stepStoppedGlide() {
        guard !isPlaying, tempoGlideTarget > 0 else { stopStoppedGlide(); return }
        let diff = tempoGlideTarget - tempo
        if abs(diff) <= 0.5 {
            tempo = tempoGlideTarget
            tempoGlideTarget = 0
            transport?.setTempo(tempo)
            stopStoppedGlide()
        } else {
            tempo += diff * 0.12               // ~20 Hz → ~2–3 s ease, matching the playing path
            transport?.setTempo(tempo)
        }
    }

    private func stopStoppedGlide() {
        stoppedGlideTimer?.cancel()
        stoppedGlideTimer = nil
    }

    /// WHO started playback. The stop side has carried a reason since the ONE-Stop work
    /// (`stopEverything(reason)`, `"stop source: roll-pause"`); the play side carried
    /// nothing, so a device log could show notes arriving with no record of what started
    /// the clock — the founder's log 2466 has notes 67 s BEFORE the only play breadcrumb
    /// that existed ("Start tapped", logged by the UI, not by the transport).
    ///
    /// Six named call sites exist in code; only THREE can appear in a log today, because
    /// the rest sit behind surfaces the pure-instrument epic already deleted. Stated
    /// explicitly so nobody reads this enum as a map of live topology — and KEEP THE
    /// COUNTS IN STEP with the list below: the previous revision left "Seven/FOUR"
    /// standing while the list underneath already said otherwise, which is the exact
    /// mis-mapping this block exists to prevent.
    ///   REACHABLE — `.transportButton`, `.generate`, `.loopExport`.
    ///   UNREACHABLE — `.pianoRoll` (`PianoRollView` has zero instantiations since #178),
    ///   `.arrangement` (`ArrangementPlayer.play(store:…)` has no caller since
    ///   `ArrangementView` went with #121 Slice 4), and `.timelineRegion`, whose only
    ///   writer is `TimelineRegionPlayer.play(document:)` — that method lost its last
    ///   production caller when ▶ stopped consulting the timeline document. All three
    ///   retire with #132; the cases stay only so the call sites keep naming themselves,
    ///   and `TimelineRegionPlayer` dies as one piece in Slice 5c rather than being
    ///   hollowed out first.
    ///   `.launchQuantized` is GONE (#132 Slice 5a): `LaunchQuantizer` is deleted, so the
    ///   case had no possible writer at all — an unreachable case whose type still exists
    ///   documents a dormant path, one whose type does not just lies.
    ///   `.unspecified` has no production caller either — seeing it in a log means a NEW
    ///   call site was added without naming itself, which is exactly what it is for.
    public enum PlayCause: String, Sendable, CaseIterable {
        /// `WorkspaceView`'s ▶ — but only its THIRD branch. That button also routes to
        /// `timelinePlayer.play` (→ `.timelineRegion`) and to the bio toggle (→ `.generate`),
        /// so this does not mean "the play button was tapped", it means "▶ started the
        /// live loop directly".
        case transportButton
        /// `EchoelStudioView` starting a fresh take. Conflates ▶-on-empty-project, Start,
        /// and applyVariation — the `generate[<reason>]` breadcrumb on the next log line
        /// disambiguates which.
        case generate
        case pianoRoll         // UNREACHABLE (#178) — PianoRollView is unmounted
        case arrangement       // UNREACHABLE — ArrangementPlayer.play has no caller
        case timelineRegion    // TimelineRegionPlayer (unreachable since ▶ stopped reading the document)
        case loopExport        // LoopExporter (offline render)
        case unspecified       // a caller that has not been given a cause yet
    }

    /// Start the timer from step 0. Idempotent: calling while playing is a no-op.
    ///
    /// `cause` is diagnostic ONLY — it never changes behavior. It is logged once per
    /// real stop→play transition (not per tick, not on the idempotent no-op), so the
    /// cost is one breadcrumb per Play, on the main actor, never on the audio thread.
    public func play(cause: PlayCause = .unspecified) {
        guard !isPlaying else { return }
        // BEFORE the cascade, not after — the stop side learned this the expensive way
        // (`WorkspaceView`: "name the finger BEFORE the stop cascades — the 2361 log's
        // source-less 'transport-stopped' burned a triage cycle proving it was a tap").
        // `transport?.play()` fans out to every tempo/step subscriber; if that hangs or
        // traps, a breadcrumb written after it would be the one line we needed and lost.
        EchoelCrashLog.breadcrumb("transport play (\(cause.rawValue)) tempo=\(Int(tempo))")
        isPlaying = true
        currentStep = 0
        // Hand any in-flight stopped-glide over to advance() (which eases toward the same
        // tempoGlideTarget) so starting playback mid-glide stays seamless, no snap.
        stopStoppedGlide()
        transport?.play()
        // One step later, not now — see `Transport.play()`. Read from the shared helper
        // (#300 Nachlese) because the MIDI clock has to wait exactly this long before its
        // Start, and a private copy of `60.0 / tempo / 4.0` here would let the two drift
        // apart. (⛔ The first version of this comment said "two copies" while THREE more
        // survived in this same file — `setTempo`'s re-arm and `advance`'s next-gap. Both
        // now read the helper too; there is one formula in the app.)
        scheduleTick(after: Transport.stepDuration(atTempo: tempo))
    }

    /// Stop the timer and reset `currentStep` to 0. Safe to call while stopped.
    public func stop() {
        timer?.cancel()
        timer = nil
        currentStep = 0
        isPlaying = false
        // A groove staged for the next downbeat must not be lost when the bar never
        // arrives — apply it now so the next play starts on the newest pattern.
        if let ps = pendingSteps, let pa = pendingAccents {
            load(steps: ps, accents: pa)   // load() clears the pending pair
        }
        // An in-flight glide must LAND at its target, not be dropped mid-ease:
        // zeroing it here used to STRAND the clock partway (founder screenshot
        // 2026-07-12: tempo locked at 100, but Stop had cancelled the glide at
        // ~64 — the session name honestly showed the stranded Transport value
        // while the lock field claimed 100, and the next Play ran at 64).
        // Landing now is inaudible (nothing is playing) and keeps pattern /
        // Transport / session name / lock display in agreement.
        if tempoGlideTarget > 0 {
            tempo = tempoGlideTarget
            transport?.setTempo(tempo)
        }
        tempoGlideTarget = 0
        stopStoppedGlide()
        transport?.stop()
        onStop?()   // flush held notes so nothing drones after stop
    }

    // MARK: - Timer (self-rescheduling, swing-aware)

    /// Schedules one tick after `interval`. Re-armed by `advance()` so each gap
    /// can carry a different (swing) duration.
    ///
    /// Uses a DispatchSourceTimer **on the main queue** with zero leeway: it fires
    /// precisely on time and, unlike a RunLoop Timer, keeps firing while the run
    /// loop is in tracking mode (UI scrolling no longer starves it — the reason
    /// the old Timer needed `.common` mode). The handler runs on the main thread,
    /// so `MainActor.assumeIsolated` recovers the static isolation needed to mutate
    /// model/UI/synth state — exactly the proven `AudioEngine.startMeterPollTimer`
    /// pattern.
    ///
    /// iOS 18 / Swift 6 NOTE — DO NOT move this timer to a background queue.
    /// Both `MainActor.assumeIsolated` AND `Task { @MainActor in }` HARD-TRAP
    /// (`dispatch_assert_queue_fail` → SIGTRAP) when the handler runs on a
    /// background dispatch worker under the strict Swift-6 executor: the runtime's
    /// isolation check asserts it is literally on the main queue and aborts when it
    /// isn't. (Builds 1769/1777 crashed exactly here — first with `assumeIsolated`,
    /// then with `Task`.) The only crash-safe options from a non-main thread are
    /// `DispatchQueue.main.async { … }` or, as here, firing on `.main` directly.
    private func scheduleTick(after interval: TimeInterval) {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + interval, leeway: .nanoseconds(0))
        t.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.advance() }
        }
        t.resume()
        timer = t
    }

    // DIAG (temporary): one-shot breadcrumb confirming the first tick fired on the
    // main thread without the Swift-6 executor trap. Remove once build 1777's
    // beat-clock SIGTRAP is confirmed resolved on device.
    @ObservationIgnored private var didLogFirstTick = false

    private func advance() {
        if !didLogFirstTick {
            didLogFirstTick = true
            EchoelCrashLog.breadcrumb("pattern: first tick OK (main-queue timer)")
        }
        // A timer block already dispatched to main can arrive AFTER stop()/setTempo
        // cancelled the source. Bail before firing so no ghost step/note sounds
        // once the transport is stopped (the spurious step-0 hit after Stop).
        guard isPlaying else { return }

        let step = currentStep
        if step == 0 {
            lastBarStartAt = CFAbsoluteTimeGetCurrent()   // downbeat stamp (C7)
            // A staged groove lands exactly here — the new bar's step-0 hits come
            // from the NEW pattern, in sync with the roll's own boundary swap.
            if let ps = pendingSteps, let pa = pendingAccents {
                load(steps: ps, accents: pa)   // load() also clears the pending pair
            }
        }
        // Relay this pulse into the authoritative clock FIRST, so any Transport
        // subscriber sees the new position before the legacy onStep/onTick consumers
        // act on it (priority ordering lives in Transport). Zero-cost when unwired.
        transport?.tick(step: step)
        for track in 0..<PatternEngine.trackCount {
            if steps[track][step] {
                onStep?(track, step)
            }
        }
        onTick?(step)
        currentStep = (step + 1) % PatternEngine.stepCount

        // Ease the tempo toward a body-seeded glide target so a re-seed SLIDES in instead of
        // jumping ("bpm springt"). One-pole (~0.15/tick → ~2 s settle); snaps + clears when
        // within 0.5 bpm. Relay each step so the transport bar / click glide in lockstep.
        if tempoGlideTarget > 0 {
            let diff = tempoGlideTarget - tempo
            if abs(diff) <= 0.5 {
                tempo = tempoGlideTarget
                tempoGlideTarget = 0
            } else {
                tempo += diff * 0.15
            }
            transport?.setTempo(tempo)
        }

        // Gap to the NEXT step. Swing lengthens the gap that follows a downbeat
        // (even step), delaying the off-beat; the following gap shortens to keep
        // each beat-pair the same total length (tempo preserved). Shared with the
        // setTempo re-arm via swingGap so the two paths can never diverge again.
        let base = Transport.stepDuration(atTempo: tempo)
        scheduleTick(after: PatternEngine.swingGap(afterStep: step, base: base, swing: swing))
    }

    /// The gap (seconds) that FOLLOWS `justPlayedStep` — the wait before the next
    /// step. Swing lengthens the gap after an EVEN step (delaying the off-beat) and
    /// shortens the one after an odd step, so each even/odd pair keeps the same
    /// total length (tempo preserved). Pure + `nonisolated` — the single source of
    /// truth for both `advance()` and the `setTempo` re-arm. `swing` is clamped to
    /// [0, 0.5]. The re-arm MUST pass the JUST-PLAYED step (currentStep − 1),
    /// because between ticks `currentStep` already points at the NEXT step.
    nonisolated static func swingGap(afterStep justPlayedStep: Int,
                                     base: Double, swing: Double) -> Double {
        let s = Swift.min(Swift.max(swing, 0), 0.5)
        return (justPlayedStep % 2 == 0) ? base * (1 + s) : base * (1 - s)
    }
}
