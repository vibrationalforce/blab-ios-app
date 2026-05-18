//
//  BioSimulator.swift
//  Echoelmusic
//
//  DEBUG-only placeholder bio source. Publishes a slowly-walking
//  BioSampleFrame onto EngineBus once per second so dev builds show
//  a live bus while no real sensor (Oura, HealthKit, BLE) is wired in.
//
//  Compiled out of Release builds via #if DEBUG so TestFlight users
//  see an honest "no source connected" state instead of fabricated
//  biometric data. Master prompt §1: science-first display, real data
//  only — the simulator's source label is `.fallback` and the strip
//  flags it as a demo.
//

#if DEBUG
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
    public func start(publishing to bus: EngineBus) {
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
            source: .fallback
        )
    }

    private func clamp(_ x: Float, in range: ClosedRange<Float>) -> Float {
        min(max(x, range.lowerBound), range.upperBound)
    }
}
#endif
