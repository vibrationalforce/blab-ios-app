//
//  BioSimulator.swift
//  Echoelmusic
//
//  Explicit, user-initiated DEMO bio source. Publishes a slowly-walking
//  BioSampleFrame onto EngineBus once per second so the instrument is
//  playable without paired hardware (Oura, HealthKit, BLE) — essential
//  for evaluating the bio-reactive synth, modulation matrix, and OSC out
//  on a device that has no sensor connected.
//
//  Honesty: the frame's source is `.fallback`, so the bio strip always
//  labels it "Demo" — it is never presented as real biometric data, and
//  it only runs when the user explicitly enables it (or, in DEBUG, auto-on
//  for development). It defers to any real bio publisher already on the bus.
//  Master prompt §1: science-first display — the demo is clearly flagged.
//

import Foundation
#if canImport(Observation)
import Observation
#endif

@MainActor
@Observable
public final class BioSimulator {

    public private(set) var isRunning = false

    @ObservationIgnored
    private var task: Task<Void, Never>?

    @ObservationIgnored
    private var heartRateBPM: Float = 72

    @ObservationIgnored
    private var hrvNormalized: Float = 0.5

    @ObservationIgnored
    private var breathPhase: Float = 0

    @ObservationIgnored
    private var coherence: Float = 0.6

    public init() {}

    /// Begin publishing one frame per second to the given bus.
    /// No-op if already running.
    public func start(publishing bus: EngineBus) {
        guard !isRunning else { return }
        isRunning = true
        task = Task { @MainActor [weak self, weak bus] in
            while !Task.isCancelled {
                guard let self, let bus else { break }
                // Defer to any real bio publisher already on the bus.
                if let latest = bus.latestBio, latest.source != .fallback {
                    try? await Task.sleep(for: .seconds(2))
                    continue
                }
                bus.publish(bio: self.nextFrame())
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    private func nextFrame() -> BioSampleFrame {
        heartRateBPM = clamp(heartRateBPM + Float.random(in: -1.5...1.5), in: 58...92)
        hrvNormalized = clamp(hrvNormalized + Float.random(in: -0.02...0.02), in: 0.2...0.9)
        // 12 bpm ≈ phase += 0.2 per second
        breathPhase = (breathPhase + 0.2).truncatingRemainder(dividingBy: 1.0)
        coherence = clamp(coherence + Float.random(in: -0.03...0.03), in: 0.2...0.9)

        return BioSampleFrame(
            timestamp: CFAbsoluteTimeGetCurrent(),
            heartRateBPM: heartRateBPM,
            hrvNormalized: hrvNormalized,
            breathRate: 12,
            breathPhase: breathPhase,
            coherence: coherence,
            motionEnergy: 0,
            source: .fallback,
            // Synthetic but plausible RMSSD (ms) for the labeled Demo source so
            // the precise HRV readout has something believable to show.
            hrvRMSSDms: hrvNormalized * 120
        )
    }

    private func clamp(_ x: Float, in range: ClosedRange<Float>) -> Float {
        min(max(x, range.lowerBound), range.upperBound)
    }
}
