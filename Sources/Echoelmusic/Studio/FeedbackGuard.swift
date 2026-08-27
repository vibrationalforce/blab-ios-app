//
//  FeedbackGuard.swift
//  Echoelmusic — Studio (live voice safety)
//
//  Pure, testable heuristics for acoustic-feedback (howlround) suppression on the
//  live mic/vocoder path. This file is the BRAIN only — no audio DSP here:
//    • detect runaway level build-up  → recommend a gain duck (dB)
//    • find the ringing frequency bin  → recommend a notch
//
//  ⛔ WHAT THIS HEADER CLAIMED UNTIL 2026-07-31, AND WHAT IS ACTUALLY WIRED.
//  It said: "The audio cycle applies them: Apple's Voice-Processing I/O for system AEC (the
//  FaceTime echo canceller) + a notch biquad + the recommended duck in the FX chain."
//  At the #298 measurement ONE of those three was real; since #595 (2026-08-14) it is TWO.
//  Checked by grep over `Sources/`:
//    • the DUCK is live — `AudioEngine.updateFeedbackGuard()` calls `gainReductionDB` and
//      scales `monitorMixer.outputVolume`. It ducks the MIC MONITOR only, never the music, and
//      touches no audio thread and no tap. It runs on the MainActor from the **60 Hz** meter
//      poll, gated to every 4th tick (`monitorPollTick % 4 == 0`), i.e. ~15 Hz. ⛔ The first
//      version of this line called it "the ~15 Hz meter poll" — the poll is 60 Hz and the GATE
//      makes it 15. Anyone budgeting work onto that poll from this sentence would be off by 4×.
//    • the NOTCH is WIRED since #595 — `AudioEngine` taps the monitor input into
//      `MonitorTapWindow` (lock queue, zero actor hops in the tap), the same ~15 Hz guard
//      tick runs the FFT + `ringingBin` on the MainActor, and an `AVAudioUnitEQ` parametric
//      band sits in the MONITOR path only (input → notchEQ → monitorMixer — the music never
//      passes through it, the duck's exact scoping). It engages ONLY while the duck already
//      fires AND one bin dominates (×8), its gain is slewed via `slewedNotchGainDB` (never
//      stepped), and it holds ~2 s past the last detection so it cannot audibly pump.
//      ⛔ Until #595 this bullet stated the opposite (unwired, `ringingBin` with ZERO callers
//      in `Sources/` — NOT quoted verbatim here: the two-way guard scans this RAW header for
//      the old sentence, and a verbatim quote would re-trigger it, the #491 collision);
//      that was true for a year. The paired two-way guard
//      (`AudioInputDoorTests.testFeedbackGuardHeaderMatchesWhatIsActuallyWired`) forces this
//      sentence and the wiring to move together, in BOTH directions.
//    • the AEC is NOT wired — `setVoiceProcessingEnabled` appears NOWHERE in `Sources/`.
//      Deliberate: it changes the whole I/O character and is Council-gated (see
//      `scratchpads/PLAN_VOICE_STAGE_2026-08-14.md`, "NICHT bauen").
//  This mattered more than a stale comment usually does: it is the file a session reads to
//  decide whether feedback suppression still needs work, and as written it answered "already
//  done, three layers deep". Headphone/IEM monitoring remains the zero-feedback path; on a
//  speaker the defence is now duck (level) + notch (frequency), still no AEC.
//
//  All functions are allocation-free over caller-provided buffers, so the audio
//  thread can call them directly (Accelerate does the FFT upstream).
//

import Foundation

public enum FeedbackGuard {

    /// ONE spelling of the duck's default depth (#416). A caller that widens the
    /// authority — Megaphone Mode uses `defaultMaxReductionDB + megaphoneBoostDB`,
    /// so the guard can always undo more than the boost — derives from this
    /// constant instead of restating the 12.
    public static let defaultMaxReductionDB: Float = 12

    /// Recommended gain reduction in dB (0 = none) when the level is both ABOVE a
    /// ceiling and trending upward across the short RMS history — the signature of
    /// feedback building up. Pure: depends only on the passed history.
    ///
    /// - Parameters:
    ///   - rmsHistory: recent broadband RMS samples, oldest → newest (0…1).
    ///   - ceiling: level above which we start worrying (0…1).
    ///   - maxReductionDB: clamp on how much we duck in one step.
    public static func gainReductionDB(rmsHistory: [Float],
                                       ceiling: Float = 0.85,
                                       maxReductionDB: Float = defaultMaxReductionDB) -> Float {
        guard let last = rmsHistory.last, rmsHistory.count >= 3 else { return 0 }
        let first = rmsHistory.first ?? last
        // Rising trend: newest meaningfully louder than oldest in the window.
        let rising = last > first * 1.10 && last > 0.001
        guard rising, last > ceiling else { return 0 }
        // Duck proportional to how far over the ceiling we are (linear → dB).
        let over = min(1, (last - ceiling) / max(0.0001, 1 - ceiling))
        return min(maxReductionDB, over * maxReductionDB)
    }

    /// The index of a dominant, persistent peak in a magnitude spectrum — the
    /// likely ringing frequency to notch — or nil when nothing clearly dominates.
    ///
    /// - Parameters:
    ///   - magnitudes: linear FFT magnitudes (bin 0 = DC).
    ///   - dominanceRatio: peak must exceed the mean by at least this factor.
    public static func ringingBin(magnitudes: [Float], dominanceRatio: Float = 8) -> Int? {
        guard magnitudes.count > 2 else { return nil }
        var sum: Float = 0
        var peak: Float = 0
        var peakIdx = 0
        // Skip DC (bin 0).
        for i in 1..<magnitudes.count {
            let m = magnitudes[i]
            sum += m
            if m > peak { peak = m; peakIdx = i }
        }
        let count = Float(magnitudes.count - 1)
        guard count > 0 else { return nil }
        let mean = sum / count
        guard mean > 0, peak >= mean * dominanceRatio else { return nil }
        return peakIdx
    }

    /// Convert an FFT bin to its centre frequency in Hz.
    public static func binToHz(_ bin: Int, fftSize: Int, sampleRate: Double) -> Double {
        guard fftSize > 0 else { return 0 }
        return Double(bin) * sampleRate / Double(fftSize)
    }

    /// Rate-based slew for the monitor notch's gain in dB (#595): moves `current`
    /// toward `target` by at most `stepDB` per guard tick (~15 Hz), so engaging and
    /// releasing the notch are RAMPS, never steps — the slew law that governs every
    /// audible parameter jump in this repo. A non-finite `current` (a poisoned state
    /// variable) restarts from 0 rather than propagating; a non-finite `target` is
    /// treated as release (0). Pure, allocation-free.
    public static func slewedNotchGainDB(current: Float, target: Float,
                                         stepDB: Float = 4) -> Float {
        let cur = current.isFinite ? current : 0
        let tgt = target.isFinite ? target : 0
        let step = Swift.max(0.1, stepDB.isFinite ? stepDB : 4)
        if cur < tgt { return Swift.min(tgt, cur + step) }
        if cur > tgt { return Swift.max(tgt, cur - step) }
        return cur
    }

    // MARK: - Early howl detection (#847 — founder 2026-08-27: "es soll erst gar kein
    // Piepsen entstehen")

    /// The PREVENTIVE half of the guard's brain: catches a howl while it is still quiet,
    /// so the wiring can notch the affected band before anything is audible.
    ///
    /// `ringingBin` above answers "which single bin dominates the whole spectrum RIGHT
    /// NOW" — a reactive question, asked only after the duck already fired. A howl's
    /// earlier signature is different and FOURFOLD: one spectral peak that (1) dominates
    /// its local NEIGHBOURHOOD (not the whole spectrum — a bass note dominates globally),
    /// (2) PERSISTS at the same bin (±1 for FFT-leakage jitter) across consecutive
    /// observations, (3) GROWS steadily (a regenerating loop always builds; a held note
    /// does not), and (4) has NO harmonic partner at 2f (a voice or instrument does).
    /// All four must hold — each one alone matches some musical signal.
    ///
    /// ⚠️ NOT YET WIRED as of #847: this type has zero production callers — it is the
    /// brain only. The wiring slice (multi-band notch) consumes it from the existing
    /// ~15 Hz MainActor guard tick and must move `TheNotchIsSlewedAndMonitorOnlyTests`'
    /// `if ducking,` needle in the same commit — the notch stops being gated on the duck,
    /// which becomes the last-resort defence. Behaviour is pinned by
    /// `AHowlIsCaughtBeforeItIsHeardTests` (END-TO-END, pure).
    ///
    /// Control-plane, MainActor cadence (~15 Hz): unlike the free functions above this
    /// type may allocate (bounded: `maxTracks`); it must NEVER be called from a render
    /// block — the FFT it consumes is already produced upstream on the MainActor.
    public struct HowlDetector {

        public struct Candidate: Equatable, Sendable {
            /// The affected FFT bin (the wiring maps it to Hz via `binToHz`).
            public let bin: Int
            /// Growth factor over the track's life — ranks candidates when the wiring
            /// has fewer EQ bands than candidates. Always finite.
            public let severity: Float
        }

        public struct Config: Sendable {
            /// Bins each side of a peak that form its neighbourhood mean.
            public var neighborhoodRadius: Int = 8
            /// Peak must exceed the neighbourhood mean by this factor. Lower than
            /// `ringingBin`'s global ×8 on purpose: local dominance is the sharper test.
            public var dominanceRatio: Float = 6
            /// Newest magnitude must exceed the track's first by this factor.
            public var growthRatio: Float = 1.25
            /// Consecutive observations before a track may become a candidate.
            /// At the ~15 Hz guard tick, 4 ≈ 270 ms — well inside a howl's build-up,
            /// well past any transient.
            public var persistenceTicks: Int = 4
            /// Veto: energy at 2×bin above this fraction of the peak = a musical note.
            public var harmonicMaxRatio: Float = 0.35
            /// Absolute floor — relative dominance over near-silence is not a howl.
            public var minMagnitude: Float = 0.001
            /// Bins below this are rumble/DC, never howl (the wiring additionally
            /// clamps to ≥ 40 Hz when converting to a filter frequency).
            public var minBin: Int = 2
            /// Upper bound on reported candidates per observation.
            public var maxCandidates: Int = 4
            public init() {}
        }

        private struct Track {
            var bin: Int
            var ticksSeen: Int
            var firstMagnitude: Float
            var lastMagnitude: Float
        }

        /// Bounded state: more simultaneous narrowband tracks than this is not a howl
        /// scenario, it is noise — the strongest survive.
        private static let maxTracks = 16

        public var config: Config
        private var tracks: [Track] = []

        public init(config: Config = Config()) {
            self.config = config
        }

        /// Forget all tracks (the wiring calls this when monitoring stops or the route
        /// changes — persistence must never survive a world change).
        public mutating func reset() {
            tracks.removeAll(keepingCapacity: true)
        }

        /// Feed one magnitude spectrum (bin 0 = DC, linear magnitudes); returns the
        /// bands whose four signatures all hold RIGHT NOW, strongest growth first.
        public mutating func observe(magnitudes: [Float]) -> [Candidate] {
            let peaks = localPeaks(in: magnitudes)

            // Match peaks to existing tracks (±1 bin — FFT leakage makes a stationary
            // howl breathe between neighbouring bins). One miss resets a track: at the
            // guard cadence a real regenerating loop never skips an observation.
            var next: [Track] = []
            var claimed = [Bool](repeating: false, count: peaks.count)
            for track in tracks {
                guard let i = peaks.indices.first(where: { !claimed[$0]
                    && abs(peaks[$0].bin - track.bin) <= 1 }) else { continue }
                claimed[i] = true
                var t = track
                t.bin = peaks[i].bin
                t.ticksSeen += 1
                t.lastMagnitude = peaks[i].magnitude
                next.append(t)
            }
            for i in peaks.indices where !claimed[i] {
                next.append(Track(bin: peaks[i].bin, ticksSeen: 1,
                                  firstMagnitude: peaks[i].magnitude,
                                  lastMagnitude: peaks[i].magnitude))
            }
            if next.count > Self.maxTracks {
                next.sort { $0.lastMagnitude > $1.lastMagnitude }
                next.removeLast(next.count - Self.maxTracks)
            }
            tracks = next

            var out: [Candidate] = []
            for t in tracks where t.ticksSeen >= Swift.max(1, config.persistenceTicks) {
                let base = Swift.max(t.firstMagnitude, Float.leastNormalMagnitude)
                let growth = t.lastMagnitude / base
                guard growth.isFinite, growth >= config.growthRatio else { continue }
                out.append(Candidate(bin: t.bin, severity: growth))
            }
            out.sort { $0.severity > $1.severity }
            if out.count > Swift.max(0, config.maxCandidates) {
                out.removeLast(out.count - Swift.max(0, config.maxCandidates))
            }
            return out
        }

        private struct Peak { let bin: Int; let magnitude: Float }

        /// Signatures (1) and (4): locally dominant, harmonic-free peaks above the
        /// absolute floor. Non-finite bins are invisible — skipped as a peak, excluded
        /// from every mean, vetoing nothing.
        private func localPeaks(in magnitudes: [Float]) -> [Peak] {
            let n = magnitudes.count
            let lo = Swift.max(1, config.minBin)
            guard n > lo + 1 else { return [] }
            var found: [Peak] = []
            for i in lo..<(n - 1) {
                let m = magnitudes[i]
                guard m.isFinite, m >= config.minMagnitude else { continue }
                let left = magnitudes[i - 1]
                let right = magnitudes[i + 1]
                guard m >= (left.isFinite ? left : 0),
                      m >= (right.isFinite ? right : 0) else { continue }
                // Neighbourhood mean, peak excluded, poisoned bins excluded.
                let r = Swift.max(1, config.neighborhoodRadius)
                var sum: Float = 0
                var count = 0
                for j in Swift.max(lo, i - r)...Swift.min(n - 1, i + r) where j != i {
                    let v = magnitudes[j]
                    guard v.isFinite else { continue }
                    sum += v
                    count += 1
                }
                guard count > 0 else { continue }
                let mean = sum / Float(count)
                guard mean > 0, m >= mean * config.dominanceRatio else { continue }
                // Harmonic veto: strong energy at 2f = a musical note, not a loop.
                let h = i * 2
                if h < n {
                    let hv = magnitudes[h]
                    if hv.isFinite, hv > m * config.harmonicMaxRatio { continue }
                }
                found.append(Peak(bin: i, magnitude: m))
            }
            return found
        }
    }
}
