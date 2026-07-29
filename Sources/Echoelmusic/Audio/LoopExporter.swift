// LoopExporter.swift
// Echoel — "Loop → .wav", the whole output of the app. Live-capture path (chosen
// over offline-bounce for zero crash risk): play the generated loop once, capture
// the master mix through the already-installed RetroCapture tap, then run it
// through SingleExport for a clean, LUFS-normalised .wav. Reuses fully-wired audio
// infrastructure — no new render code on the audio thread.
//
// DAW-GRID GUARANTEE (audit C6/C7, 2026-07-04): the written WAV is EXACTLY
// `bars` long and cut on a downbeat, so it loops seamlessly in Ableton/Logic/FL.
//   • C6 — the planned export used to write pre-roll + loop + 0.4 s tail (and the
//     LUFS gain was measured across that junk). Now: capture with ZERO pre-roll,
//     record the tail for natural decay, then SingleExport trims the output to the
//     exact bar-aligned loop window and normalises ONLY that window.
//   • C7 — "keep last" used to cut an arbitrary-phase window ending "now" (seam
//     click mid-phrase). Now: the window is snapped back to the last downbeat via
//     PatternEngine.lastBarStartAt.
//   • Both paths add a ~4 ms edge micro-fade against residual seam ticks.

import Foundation

@MainActor
@Observable
public final class LoopExporter {

    public enum Status: Equatable {
        case idle
        case capturing
        case rendering
        case done(URL)
        case failed(String)
    }

    public private(set) var status: Status = .idle

    /// Set by `cancel()`, read by the capture wait. `@ObservationIgnored` because the UI
    /// never reads THIS one — it reads `isCancellable`, which is built from `status` and
    /// `captureIsAbortable` below.
    @ObservationIgnored private var cancelRequested = false

    /// True only while the PLANNED capture is waiting out its take — the one phase that
    /// can actually be stopped.
    ///
    /// ⚠️ OBSERVED on purpose (no `@ObservationIgnored`), unlike `cancelRequested`. It is
    /// half of `isCancellable`, which the button reads. With it unobserved, the SET was
    /// masked by the `status` write next to it, but the CLEAR notified nobody — so across
    /// the following `await` the button kept rendering as a lit "Stop and discard" that
    /// silently ignored the tap. That is the lying control this whole slice exists to
    /// remove, reintroduced by an attribute. It flips twice per export; there is no churn
    /// risk in observing it.
    private var captureIsAbortable = false

    /// Whether an abort is possible RIGHT NOW.
    ///
    /// Deliberately narrower than "is busy", on both sides:
    /// · Rendering is a single `await` inside `SingleExport` (AVAssetReader/Writer) that we
    ///   cannot interrupt from out here without lying about having stopped it.
    /// · The RETROACTIVE path is `.capturing` too, but only for the instant it takes to
    ///   read the ring — offering Cancel there would be a button that flashes past and
    ///   does nothing.
    /// A Cancel button that goes dead for the last few seconds is honest; one that stays
    /// lit and ignores the tap is the lying-control class again.
    public var isCancellable: Bool { status == .capturing && captureIsAbortable }

    /// Abort the take in progress — founder 2026-07-28: "wichtig das man die Aufnahme dann
    /// auch abbrechen kann, wenn man sich verspielt hat". No-op unless a capture is running.
    ///
    /// The capture wait polls this ~10×/s, so the stop is felt immediately rather than at
    /// the end of the take. Everything it started is undone: the transport it began, the
    /// recording it opened, and the temp file it wrote. Status returns to `.idle`, NOT
    /// `.failed` — a deliberate choice is not a failure. This used to add "and the two are
    /// indistinguishable downstream anyway (nothing consumes `.failed`)", which #216 made
    /// false: `.failed` now survives the end of an attempt and renders a warning line above
    /// the Record button. That makes the choice here MORE load-bearing, not less — an abort
    /// must not accuse the app of losing your take.
    public func cancel() {
        guard isCancellable else { return }
        cancelRequested = true
    }

    /// A short tail (seconds) recorded past the loop so reverb/delay decay stays
    /// natural while the loop plays out — the trim then cuts the file back to the
    /// exact loop, so the tail never overhangs the DAW grid.
    private let tailSeconds: Double = 0.4

    /// Micro fade at the loop edges (seam-tick safety; inaudible as a dip).
    private let edgeFadeSeconds: Double = 0.004

    /// The retro ring holds 30 s at 48 kHz — the hard history limit for the
    /// "keep last" path (slightly conservative so rate drift can't bite).
    ///
    /// PUBLIC and `nonisolated` since #200: the UI has to be able to ask BEFORE the tap
    /// whether the chosen length can be delivered retroactively. Until now it could only
    /// find out afterwards, from the failure alert — a control that accepts the tap and
    /// then refuses is the lying-control class this repo keeps paying for.
    nonisolated public static let retroRingSeconds: Double = 29.5

    /// Can the RETROACTIVE path ("keep the last N bars, without replaying them") actually
    /// deliver `bars` at `bpm`? Pure, so the UI and the exporter share ONE arithmetic
    /// instead of two that drift.
    ///
    /// The two loop directions the founder asked for are NOT symmetric, and this function
    /// is where that asymmetry lives:
    ///   • "ab dem ersten Takt" → `exportWav` records LIVE to a file. No history, no limit.
    ///   • "rückwirkend für die letzten" → `exportRecentLoop` reads the always-on ring. It
    ///     can only return what the ring still holds.
    /// A bar is 4 beats, so `barSeconds = 240 / bpm`: at 120 BPM the ring holds 14 whole
    /// bars, at 60 BPM only 7. That is why the answer cannot be baked into
    /// `LoopBarLength` — it depends on the (bio-modulated) tempo at the moment of asking.
    nonisolated public static func canKeepLast(bars: Int, bpm: Double) -> Bool {
        guard bpm.isFinite, bpm > 0 else { return false }
        let seconds = StudioCalculator(bpm: bpm).loopSeconds(bars: Swift.max(1, bars))
        return seconds > 0 && seconds <= retroRingSeconds
    }

    /// The longest length the PICKER ACTUALLY OFFERS that the ring can hold at this tempo.
    ///
    /// ⛔ This exists because the obvious version was a lying control of its own. The first
    /// draft named `keepableBars` — the raw whole-bar capacity — in the refusal text, so at
    /// 120 BPM it told the user "keep up to 14", and 14 is not a `LoopBarLength` case. It
    /// sent them looking for a segment that does not exist on the control right above.
    /// `allCases` is ascending and `canKeepLast` is monotonic in `bars`, so `.last(where:)`
    /// is the largest offered length that fits. `nil` = nothing fits (unusable tempo).
    nonisolated public static func longestKeepable(bpm: Double) -> LoopBarLength? {
        LoopBarLength.allCases.last { canKeepLast(bars: $0.rawValue, bpm: bpm) }
    }

    /// How many whole bars the ring CAN hold at this tempo — 0 when the tempo is not a
    /// usable number. **Not a UI-facing number** (see `longestKeepable`): it is the raw
    /// capacity, useful for diagnostics and for reasoning about the ring, not for telling
    /// a user what to pick.
    ///
    /// The `isFinite` guard is not defensive decoration: `Int(nan)` TRAPS in Swift, and
    /// the tempo reaching here comes from a bio-modulated transport.
    nonisolated public static func keepableBars(bpm: Double) -> Int {
        guard bpm.isFinite, bpm > 0 else { return 0 }
        let barSeconds = 240.0 / bpm
        guard barSeconds.isFinite, barSeconds > 0 else { return 0 }
        let whole = (retroRingSeconds / barSeconds).rounded(.down)
        guard whole.isFinite, whole >= 1 else { return 0 }
        return Int(Swift.min(whole, 1_000))
    }

    nonisolated static func tooLongMessage(bars: Int, bpm: Double) -> String {
        guard let fits = longestKeepable(bpm: bpm) else {
            return "\(bars) bars is longer than the 30 s capture buffer — use Record instead"
        }
        return "\(bars) bars is longer than the 30 s capture buffer at this tempo — keep \(fits.label) or fewer, or use Record instead"
    }

    public init() {}

    /// How often the capture wait checks for an abort. 100 ms reads as instant to a hand
    /// on a button, and ten main-actor resumptions per second is nothing next to what the
    /// instrument already does.
    private static let cancelPollSeconds = 0.1

    /// Wait out the take, polling for an abort. Returns `true` if the full duration
    /// elapsed, `false` if it was cancelled.
    ///
    /// The `catch` also treats task cancellation as an abort. Note honestly that NOTHING
    /// cancels this task today — the caller is a bare `Task { }`, not a `.task {}`
    /// modifier, so tearing the view down does not reach it. The branch is there so that
    /// making the caller structured later cannot silently produce a truncated file; it is
    /// not currently a reachable path, and should not be cited as one.
    private func waitForCapture(seconds: Double) async -> Bool {
        guard seconds.isFinite, seconds > 0 else { return true }
        var remaining = seconds
        while remaining > 0 {
            if cancelRequested { return false }
            let step = Swift.min(Self.cancelPollSeconds, remaining)
            do {
                try await Task.sleep(for: .seconds(step))
            } catch {
                // The sleep only throws on cancellation. Treat it exactly like a tapped
                // Cancel rather than falling through, which is what the old `try?` did.
                cancelRequested = true
                return false
            }
            remaining -= step
        }
        return !cancelRequested
    }

    /// Close the recording and hand back its file, or `nil` if there was nothing to close.
    ///
    /// ⚠️ THE GUARD IS LOAD-BEARING, not defensive noise. `RetroCapture.stopRecording`
    /// begins with `guard isRecording else { return }` and in that case NEVER calls its
    /// completion — and `startRecording` fails SILENTLY on several paths (format creation,
    /// file creation, pre-roll write), leaving `isRecording` false. Awaiting a completion
    /// that will not arrive suspends `exportWav` forever: `status` stays `.capturing`, the
    /// Record button stays disabled reading "Recording loop…" for the rest of the session,
    /// the caller's `finishAttempt()` never runs, and the continuation leaks. The camera route activating
    /// mid-session is exactly when that format/file creation can fail.
    private func finishRecording(_ engine: AudioEngine) async -> URL? {
        guard engine.retroCapture.isRecording else { return nil }
        let url = await withCheckedContinuation { continuation in
            engine.retroCapture.stopRecording { continuation.resume(returning: $0) }
        }
        // The tap may have stopped reaching disk mid-take (full volume, revoked
        // container). `stopRecording` lifts that latch, so it is readable HERE and
        // nowhere earlier. Without this check the export continues over a truncated or
        // empty file: trim, LUFS-normalise the fragment, and present it as a finished
        // loop. The floating WAV button already shows the failure; this path is the more
        // prominent one and had no signal at all.
        //
        // `url` is NOT Optional: `stopRecording(completion:)` hands the closure a plain
        // `URL` and only calls it at all when `lastURL` is set — which `startRecording`
        // assigns in the same block that sets `isRecording`, so the guard above is what
        // makes the continuation certain to resume.
        if engine.retroCapture.writeFailed {
            status = .failed("Recording could not be written to disk")
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return url
    }

    /// Undo everything `exportWav` started: the transport it began, the recording it
    /// opened, and the temp file it wrote. `stopRecording` runs even though the result is
    /// discarded — it is what closes the file handle.
    private func abortCapture(engine: AudioEngine, beatPlayer: BeatPlayer) async {
        beatPlayer.pattern.stop()
        if let url = await finishRecording(engine) {
            try? FileManager.default.removeItem(at: url)
        }
        cancelRequested = false
        status = .idle
    }

    /// Seconds since the transport's last downbeat — the phase offset that snaps
    /// a capture window back onto the bar grid. 0 when unknown (never played).
    private func secondsSinceBarStart(_ beatPlayer: BeatPlayer) -> Double {
        let stamp = beatPlayer.pattern.lastBarStartAt
        guard stamp > 0 else { return 0 }
        return max(0, CFAbsoluteTimeGetCurrent() - stamp)
    }

    /// Render the current loop to a `.wav`. Plays the transport for one loop
    /// length (+ decay tail), captures the master, then trims + normalises the
    /// exact bar-aligned loop. Returns the file URL on success.
    @discardableResult
    public func exportWav(engine: AudioEngine, beatPlayer: BeatPlayer, bars: Int, targetLUFS: Float?) async -> URL? {
        guard status != .capturing, status != .rendering else { return nil }

        let bpm = beatPlayer.pattern.tempo
        let calc = StudioCalculator(bpm: bpm)
        let seconds = calc.loopSeconds(bars: max(1, bars))
        guard seconds > 0 else { status = .failed("Invalid loop length"); return nil }

        // 1. Record live-only (NO 30 s pre-roll — C6) and play the loop from the top.
        cancelRequested = false
        captureIsAbortable = true
        status = .capturing
        beatPlayer.pattern.stop()
        engine.retroCapture.startRecording(preRoll: 0)
        beatPlayer.pattern.play(cause: .loopExport)

        // 2. Record one loop + the decay tail past its end — in SLICES, not one long
        //    sleep, so `cancel()` is felt within ~100 ms instead of at the end of the take.
        //    This matters most exactly where it is hardest to sit through: 64 bars at 30 BPM
        //    is 8.5 minutes, and the reason to abort ("man hat sich verspielt") is known in
        //    the first few seconds.
        let completed = await waitForCapture(seconds: seconds + tailSeconds)
        captureIsAbortable = false      // past the abortable phase either way
        if !completed {
            await abortCapture(engine: engine, beatPlayer: beatPlayer)
            return nil
        }

        // Phase offset NOW (closest to the tap-off moment): we are `ago` past the
        // loop's final downbeat, so the exact loop is the `seconds` before it.
        // Sanity-cap at one bar — a stale stamp must never shift the cut wildly.
        let ago = min(secondsSinceBarStart(beatPlayer), calc.barSeconds)

        // Same guarded path as the abort — this site had the identical hang, reachable
        // whenever `startRecording` failed silently, only after the whole take had elapsed.
        let cafURL = await finishRecording(engine)
        guard let cafURL else {
            // `finishRecording` may already have set a SPECIFIC reason (the tap stopped
            // reaching disk). Do not paper that over with the generic line — "Capture
            // failed" tells the user nothing they can act on, "could not be written to
            // disk" tells them to free space.
            if case .failed = status {} else { status = .failed("Capture failed") }
            return nil
        }

        // 3. Trim to the exact bar-aligned loop, normalise ONLY that window, write .wav.
        return await renderTrimmed(engine: engine, sourceURL: cafURL,
                                   loopSeconds: seconds, fromEnd: ago, targetLUFS: targetLUFS)
    }

    /// Retroactive capture — "die Stelle war gut → behalten": keep the last `bars`
    /// of what ALREADY played from the always-on ring buffer (no transport restart),
    /// snapped back to the last downbeat (C7) so the cut loops on the DAW grid.
    /// Returns the file URL on success.
    @discardableResult
    public func exportRecentLoop(engine: AudioEngine, beatPlayer: BeatPlayer, bars: Int, targetLUFS: Float?) async -> URL? {
        guard status != .capturing, status != .rendering else { return nil }

        let bpm = beatPlayer.pattern.tempo
        let calc = StudioCalculator(bpm: bpm)
        let seconds = calc.loopSeconds(bars: max(1, bars))
        guard seconds > 0 else { status = .failed("Invalid loop length"); return nil }
        guard Self.canKeepLast(bars: bars, bpm: bpm) else {
            // The ring only holds ~30 s of history — an honest limit beats a
            // silently truncated, unloopable file. Since #200 the UI asks the SAME
            // function before enabling the button, so this guard is the backstop
            // (tempo can drift between render and tap), not the first line of defence.
            status = .failed(Self.tooLongMessage(bars: bars, bpm: bpm))
            return nil
        }

        // 1. Window = loop + phase-to-downbeat, all ending "now". If the ring
        //    can't hold the snap margin, degrade to the unsnapped cut (better an
        //    exact-length loop off-phase than no loop at all).
        status = .capturing
        let ago = beatPlayer.pattern.isPlaying
            ? min(secondsSinceBarStart(beatPlayer), calc.barSeconds)
            : 0
        let window = min(seconds + ago, Self.retroRingSeconds)
        let effectiveAgo = max(0, window - seconds)
        guard let cafURL = engine.retroCapture.captureRecent(seconds: window) else {
            // Wording deliberately not "Nothing to capture yet": it is rendered as
            // "<reason>. Nothing was saved." and read "Nothing … nothing".
            status = .failed("The capture buffer is empty")
            return nil
        }

        // 2. Trim to the exact bar-aligned loop + normalise (same path as planned).
        return await renderTrimmed(engine: engine, sourceURL: cafURL,
                                   loopSeconds: seconds, fromEnd: effectiveAgo, targetLUFS: targetLUFS)
    }

    /// Shared tail: configure SingleExport for the bar-aligned loop window
    /// (trim + edge fades + LUFS on the window only) and run it.
    private func renderTrimmed(engine: AudioEngine, sourceURL: URL,
                               loopSeconds: Double, fromEnd: Double, targetLUFS: Float?) async -> URL? {
        status = .rendering
        engine.singleExport.reset()
        engine.singleExport.outputFormat = .wav
        engine.singleExport.targetLUFS = targetLUFS
        engine.singleExport.trimLengthSeconds = loopSeconds
        engine.singleExport.trimFromEndSeconds = fromEnd
        engine.singleExport.edgeFadeSeconds = edgeFadeSeconds
        await engine.singleExport.export(sourceURL: sourceURL)

        if let url = engine.singleExport.exportState.exportedURL {
            status = .done(url)
            return url
        } else {
            status = .failed("Export failed")
            return nil
        }
    }

    /// Force back to `.idle`, whatever happened.
    ///
    /// ⚠️ NO PRODUCTION CALLER since #216 — both view sites now use `finishAttempt()`.
    /// Said out loud because a `public` method that reads as "the blunt instrument" looks
    /// in-use, and this repo's whole audit history is about surfaces that quietly stopped
    /// having a caller. Kept deliberately: it is what the tests drive, and it is the honest
    /// force-idle for any future path that must discard a failure rather than show it.
    public func reset() { status = .idle }

    // MARK: - Ending an attempt without erasing why it failed (#216)

    /// Whether an attempt that has just returned should drop back to `.idle`.
    ///
    /// THE DEFECT THIS EXISTS FOR. Both callers in `EchoelStudioView` ended with an
    /// unconditional `exporter.reset()` — correct in spirit (a finished attempt must never
    /// leave the button stuck on "Writing .wav…") but it also wiped `.failed`, in the same
    /// synchronous turn, before SwiftUI could ever render it. This class writes `.failed` at
    /// six places — the write failed, the loop is longer than the ring, the ring is empty,
    /// the render produced nothing, the loop length is invalid, the capture failed — and NOT
    /// ONE of them could reach a user.
    /// The button simply returned to "Record 8 bars → send" and the take was gone, which
    /// reads as "nothing happened" rather than "that did not work".
    ///
    /// So `.failed` is the one status that must survive the reset. It costs nothing: the
    /// button's own label already falls through to the idle wording for `.failed`, so it
    /// stays live and tappable, and the next capture overwrites the status anyway. Nothing
    /// hangs.
    ///
    /// Pure and static so both answers are testable without an `AudioEngine`, a device or
    /// a real capture — the failure paths all need one, and a test that cannot reach them
    /// would be pinning nothing.
    public static func shouldReturnToIdle(after status: Status) -> Bool {
        if case .failed = status { return false }
        return true
    }

    /// Called by the UI when an export attempt has returned, successfully or not.
    /// Returns to idle unless the attempt failed — see `shouldReturnToIdle`.
    public func finishAttempt() {
        if Self.shouldReturnToIdle(after: status) { status = .idle }
    }
}
