// ScopeTrigger.swift
// Echoel — the pure maths that makes an oscilloscope STAND STILL.
//
// ⭐ WHY THIS EXISTS AT ALL, because "just draw the samples" is the obvious idea and it
// looks broken. `AudioEngine.copyLatestOutputSamples` hands back the newest N samples, and
// the phase of the newest sample has no relation to the previous frame's — so a plain plot
// of a steady 110 Hz tone SLIDES sideways at whatever rate the frame period and the signal
// period happen to beat at. Every hardware scope solves this the same way: do not start
// drawing at the buffer edge, start at a repeatable feature of the WAVE. That feature is
// the rising crossing of a trigger level.
//
// Pure value maths, no imports beyond Foundation, so it is unit-testable in the blocking
// bundle without a view, a renderer or an audio graph.
//
// ⚠️ NOT A DSP FILE ON PURPOSE. It lives in `Studio/` next to `SpectrumAnalysis` and
// `SpectralColor` because it serves a VIEW, and because `DSP/` carries the rule that its
// files must compile without Core/Sequencer types for the isolated build. Nothing here
// runs on the audio thread — the sample ring is copied on the main thread by design
// (`AudioEngine.copyLatestOutputSamples` says so), and the FFT/plot follow it there.

import Foundation

enum ScopeTrigger {

    /// Hysteresis band around the trigger level, in the same units as the samples
    /// (master output, so roughly ±1). Without it, noise around the level re-triggers on
    /// consecutive samples and the display jitters by one sample per frame — which reads
    /// as a fine tremble rather than an obvious bug, and is therefore worse.
    static let hysteresis: Float = 0.002

    /// Index in `samples` where a stable display window should begin.
    ///
    /// Returns the first index `i` in the searchable range such that SOME earlier sample
    /// fell below `level - hysteresis` (arming the trigger) and `samples[i]` is at or above
    /// `level` — a rising crossing. Falls back to 0 when no crossing exists in range
    /// (silence, DC, or a period longer than the search window), which is the honest
    /// fallback: an untriggered scope draws from the buffer start rather than pretending to
    /// be locked.
    ///
    /// ⛔ "SOME EARLIER SAMPLE", not `samples[i-1]`, and the difference is not pedantic —
    /// the first version of this doc said the immediate predecessor must sit below the arm
    /// band, and the primary test vector disproves it: a 64-sample sine has
    /// `samples[64] = −2.4e-16`, which is above `−hysteresis`, yet index 65 is (correctly)
    /// returned because the arm was set back at sample 33. Anyone who "fixed" the loop to
    /// match the old wording would have moved every trigger by one whole period on a signal
    /// that dwells near zero. The arm is STICKY until it fires or a non-finite sample
    /// clears it; that is the contract.
    ///
    /// The search is bounded to `samples.count - windowLength` so the returned index plus
    /// the window always stays inside the buffer — the caller never has to clamp.
    ///
    /// NON-FINITE INPUT is treated as "not a crossing" rather than propagated: a NaN in
    /// the ring (a bad frame upstream) must not decide where the picture starts. The
    /// comparisons below are written so NaN fails BOTH the below-test and the above-test,
    /// so a NaN sample can neither arm nor fire the trigger.
    static func startIndex(in samples: [Float],
                           windowLength: Int,
                           level: Float = 0) -> Int {
        let n = samples.count
        guard windowLength > 0, n > windowLength else { return 0 }
        let lastStart = n - windowLength
        guard lastStart >= 1 else { return 0 }
        let arm = level - hysteresis
        var armed = false
        for i in 0...lastStart {
            let s = samples[i]
            guard s.isFinite else { armed = false; continue }
            if armed && s >= level { return i }
            if s < arm { armed = true }
        }
        return 0
    }

    /// Map a triggered window onto the unit interval for drawing: returns `count` samples
    /// starting at `start`, each clamped to −1…1, oldest first.
    ///
    /// Clamping and not normalising, deliberately: a scope whose vertical scale follows the
    /// signal cannot show you that the signal got louder, which is most of what a performer
    /// wants from it. ±1 is therefore full scale, and a trace welded to the rails is a real
    /// over.
    ///
    /// ⛔ NOT "the master bus is already trimmed to −1 dBFS, so a clean take never touches
    /// the rails" — that is what this said and it is the wrong way round. The −1 dBFS trim
    /// is `mainMixerNode.outputVolume`, which sits DOWNSTREAM of the tap that fills the ring
    /// these samples come from (`AudioEngine`: the meter tap is on
    /// `autoMixChain.chainOutputNode`). The window therefore carries the UNtrimmed chain
    /// output, where full scale is full scale and the limiter is the only thing keeping it
    /// off the rails. The picture is honest either way; the reasoning was not, and it is the
    /// reasoning the next person would have re-used to size something else.
    ///
    /// Out-of-range requests return an all-zero window rather than trapping — this is
    /// called from a draw loop, where a crash is the one outcome worse than a blank frame.
    static func window(_ samples: [Float], start: Int, count: Int) -> [Float] {
        guard count > 0 else { return [] }
        guard start >= 0, start + count <= samples.count else {
            return [Float](repeating: 0, count: count)
        }
        var out = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let s = samples[start + i]
            out[i] = s.isFinite ? Swift.min(Swift.max(s, -1), 1) : 0
        }
        return out
    }

    /// Peak absolute value of a window, for the "is anything playing" gate and the
    /// clip indicator. NaN-safe by the same rule as `window`.
    static func peak(_ window: [Float]) -> Float {
        var p: Float = 0
        for s in window where s.isFinite {
            let a = abs(s)
            if a > p { p = a }
        }
        return p
    }
}
