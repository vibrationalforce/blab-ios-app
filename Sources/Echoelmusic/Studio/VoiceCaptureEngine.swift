// VoiceCaptureEngine.swift
// Echoelmusic — Studio (voice → timbre capture)
//
// The capture coordinator of the EchoelVoice plan (`scratchpads/PLAN_ECHOEL_VOICE.md`,
// #592a — the core half; the mic wiring and the `soundPanel` door are the second half).
// It joins the three tested pieces end to end, all on the CONTROL thread:
//
//   mic chunks → 4096-sample windows → `VoiceAnalyzer` (F0 + voicing)
//                                    → `EchoelRealFFT` (magnitudes)
//                                    → `VoiceTimbreProfiler` (median per harmonic)
//                                    → `profile` once enough VOICED windows landed.
//
// The 4096 window is trap 3 of the plan: the shipped mic tap delivers 1024-sample
// buffers, too short to resolve a 70 Hz fundamental — chunks are aggregated here, so
// callers feed whatever the tap gives them. The voicing gate is what makes the capture
// consent-shaped: silence, breath and broadband noise never fill it; only a
// deliberately held tone does. No audio persists beyond the current analysis window —
// at most 4,095 raw samples (~85 ms) wait in `pending` for the next window, are
// analyzed, and are dropped; what accumulates is the spectral envelope, parameters
// only (the same privacy shape as `VoiceTimbreProfiler`, which lets v1 ship under the
// mic-permission promise "Audio is not recorded").
//
// NOT thread-safe by design: call `start`/`cancel`/`ingest` from one thread (the main
// actor in practice — the mic tap's samples already arrive there). Never call from a
// render block: `analyze` and `forward` are control-rate work.

import Foundation

#if canImport(Accelerate)   // EchoelRealFFT exists only with Accelerate (EchoelVDSPKit)

public final class VoiceCaptureEngine {

    public enum State: Equatable {
        case idle
        case capturing
        case done
    }

    /// Analysis window in samples. ≥ 2048 is required for a 70 Hz fundamental
    /// (trap 3); 4096 at 48 kHz ≈ 85 ms — comfortable for autocorrelation and fine
    /// (11.7 Hz) FFT bins for the harmonic sampling.
    public static let windowSize = 4096

    /// Voiced windows needed to finish a take. The default (64 ≈ 5.5 s of voiced
    /// material at 48 kHz) matches the plan's "5–10 s Tönen"; tests use a small value.
    public let targetVoicedFrames: Int

    public private(set) var state: State = .idle
    /// Voiced windows accumulated so far — drives a progress UI.
    public private(set) var voicedFrames = 0
    /// Whether the most recent window read as voiced — drives a live "we hear you" dot.
    public private(set) var lastFrameWasVoiced = false
    /// The most recent voiced window's fundamental (Hz); 0 before the first one.
    public private(set) var lastPitchHz: Double = 0
    /// The finished take: `VoiceTimbreProfiler.profile()`. Non-nil exactly in `.done`.
    public private(set) var profile: [Float]?

    public var progress: Double {
        Swift.min(1, Double(voicedFrames) / Double(targetVoicedFrames))
    }

    private let analyzer = VoiceAnalyzer()
    private let fft = EchoelRealFFT(size: VoiceCaptureEngine.windowSize)
    private var profiler: VoiceTimbreProfiler
    private var pending: [Float] = []

    /// `harmonicCount` mirrors `VoiceTimbreProfiler`'s default (64), whose own drift
    /// guard against the engine socket is behavioral
    /// (`TheVoiceProfileIsMeasuredNotRecordedTests.testTheProfileFitsTheEngineSocket`).
    /// The target is capped at the profiler's frame cap — above it the profiler would
    /// silently ignore frames and the capture could never finish.
    public init(targetVoicedFrames: Int = 64, harmonicCount: Int = 64) {
        self.targetVoicedFrames = Swift.min(VoiceTimbreProfiler.maxFrames,
                                            Swift.max(1, targetVoicedFrames))
        self.profiler = VoiceTimbreProfiler(harmonicCount: harmonicCount)
    }

    /// Begin a fresh take (clears any previous state, including a finished profile).
    public func start() {
        reset()
        state = .capturing
    }

    /// Abort and clear — the #277 arm shape: nothing is captured unless armed.
    public func cancel() {
        reset()
    }

    /// Feed mic samples in any chunking (the shipped tap delivers 1024-sample buffers).
    /// Ignored unless `.capturing` — an unarmed or finished engine does not listen.
    public func ingest(_ samples: [Float], sampleRate: Double) {
        guard state == .capturing, sampleRate.isFinite, sampleRate > 0 else { return }
        pending.append(contentsOf: samples)
        while state == .capturing, pending.count >= Self.windowSize {
            let window = Array(pending.prefix(Self.windowSize))
            pending.removeFirst(Self.windowSize)
            process(window, sampleRate: sampleRate)
        }
    }

    private func process(_ window: [Float], sampleRate: Double) {
        let frame = analyzer.analyze(window, sampleRate: sampleRate)
        lastFrameWasVoiced = frame.voiced && !frame.isSilent
        guard lastFrameWasVoiced else { return }
        // Below the guard on purpose: a breath gap must not reset the held pitch to 0
        // (review #592a — the doc says "most recent VOICED window", so the code does too).
        lastPitchHz = frame.pitchHz

        let magnitudes = fft.forward(window).magnitudes
        profiler.add(magnitudes: magnitudes, f0: Float(frame.pitchHz),
                     voiced: true, sampleRate: Float(sampleRate))
        voicedFrames = profiler.voicedFrameCount

        if voicedFrames >= targetVoicedFrames {
            guard let p = profiler.profile() else {
                // Unreachable in practice (a voiced window has energy, so the envelope
                // cannot be all-zero) — but "done with no profile" would be a lie, so
                // the take starts over rather than finishing empty.
                profiler.reset()
                voicedFrames = 0
                return
            }
            profile = p
            state = .done
            pending.removeAll(keepingCapacity: true)
        }
    }

    private func reset() {
        state = .idle
        voicedFrames = 0
        lastFrameWasVoiced = false
        lastPitchHz = 0
        profile = nil
        profiler.reset()
        pending.removeAll(keepingCapacity: true)
    }
}

#endif  // canImport(Accelerate)
