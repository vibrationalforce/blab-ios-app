//
//  BioReactiveSynthVoice.swift
//  Echoelmusic
//
//  First EngineBus subscriber. Hosts one EchoelDDSP voice and maps
//  the latest BioSampleFrame onto its applyBioReactive(...) surface
//  every time the bus publishes a new frame. The DDSP voice updates
//  its own internal state (harmonicity, brightness, vibrato, etc.)
//  but does NOT yet feed an AVAudioSourceNode — audio output is the
//  next cycle, so this voice is observed-only for now and proves the
//  pub/sub chain end-to-end without touching the audio thread.
//
//  Master prompt §2: "Bio is input. DSP, visuals, lighting, OSC out
//  are subscribers." This is the first subscriber.
//

#if canImport(Observation)
import Observation
#endif
import Foundation

@MainActor
@Observable
public final class BioReactiveSynthVoice {

    /// Underlying synthesizer. Public so a later cycle can hand its
    /// `render(buffer:frameCount:)` to an AVAudioSourceNode.
    @ObservationIgnored
    public let synth: EchoelDDSP

    public private(set) var isSubscribed = false

    /// Last bio frame applied to the synth, for UI observation.
    public private(set) var lastApplied: BioSampleFrame?

    /// Count of frames applied since subscription started. Lets a debug
    /// strip prove the subscriber is alive.
    public private(set) var framesApplied: UInt64 = 0

    @ObservationIgnored
    private weak var bus: EngineBus?

    @ObservationIgnored
    private var task: Task<Void, Never>?

    @ObservationIgnored
    private var lastTimestamp: TimeInterval = -1

    public init(sampleRate: Double = 48_000) {
        self.synth = EchoelDDSP(sampleRate: sampleRate)
    }

    /// Begin observing the bus. Polls latestBio at 10 Hz and applies
    /// it to the synth whenever a fresh frame arrives. Idempotent.
    public func start(subscribing to bus: EngineBus) {
        guard !isSubscribed else { return }
        self.bus = bus
        isSubscribed = true
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, let bus = self.bus else { break }
                self.applyLatestIfFresh(from: bus)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        isSubscribed = false
    }

    // MARK: - Bio → Synth mapping

    private func applyLatestIfFresh(from bus: EngineBus) {
        guard let frame = bus.latestBio else { return }
        guard frame.timestamp != lastTimestamp else { return }
        lastTimestamp = frame.timestamp
        lastApplied = frame
        framesApplied &+= 1

        // BioSampleFrame carries the five normalized channels we need
        // out of applyBioReactive's seven inputs. breathDepth and
        // lfHfRatio default to neutral (0.5); coherenceTrend defaults
        // to 0 (no change) until a future cycle computes it.
        let hrNormalized = clampUnit((frame.heartRateBPM - 40) / 160)
        synth.applyBioReactive(
            coherence: clampUnit(frame.coherence),
            hrvVariability: clampUnit(frame.hrvNormalized),
            heartRate: hrNormalized,
            breathPhase: clampUnit(frame.breathPhase),
            breathDepth: 0.5,
            lfHfRatio: 0.5,
            coherenceTrend: 0
        )
    }

    private func clampUnit(_ x: Float) -> Float {
        min(max(x, 0), 1)
    }
}
