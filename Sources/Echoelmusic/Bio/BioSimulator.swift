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
            // Synthetic but plausible HRV metrics for the labeled Demo source so
            // the precise readouts have believable values to show.
            //
            // ⛔ RMSSD USED TO BE `hrvNormalized * 120`, AND THAT IS THE COPY-DRIFT DEFECT
            // #97 ALREADY FIXED — surviving here because #97 audited the three LIVE sources
            // and nobody looked at the demo. `HRVNormalization` exists to be the ONE ceiling
            // ("was ÷200 on the camera, ÷100 on the strap, ÷100 on HealthKit"), and this file
            // quietly carried a fourth divisor.
            //
            // Why it is a real inconsistency and not just an arbitrary constant: on EVERY real
            // source the published pair satisfies `hrvNormalized == HRVNormalization.normalize(
            // <that source's ms metric>)` EXACTLY — camera (`hrvNormalized = normalize(
            // analyzer.rmssd)`, `hrvRMSSDms = analyzer.rmssd`), Polar (same two lines), and
            // HealthKit (against SDNN, since it has no beat-to-beat RR). The demo published a
            // pair no converter in this app can reconcile: at `hrvNormalized` 0.5 it shipped
            // 60 ms, while the house rule says 60 ms IS 0.60. Measured across the whole walk
            // band (0.2…0.9): a flat **+20 % relative**, worst **+0.167 absolute on a 0…1
            // knob** — and it saturated to +11 % at the top only because `normalize` clamps.
            // A receiver that recomputes the knob from the ms value (several consumers do)
            // got a different number than the one on the wire beside it.
            //
            // The anchor is RMSSD, not SDNN, because that is the RR-source convention and the
            // demo imitates an RR source (it publishes RMSSD and pNN50, which only an RR
            // source has).
            hrvRMSSDms: hrvNormalized * Float(HRVNormalization.ceilingMs),
            // ⚠️ SDNN AND pNN50 DELIBERATELY DO **NOT** ROUND-TRIP, and the symmetrical-looking
            // tidy-up is the trap. On the camera and the strap `normalize(hrvSDNNms)` does not
            // equal `hrvNormalized` either — the knob is anchored on RMSSD there too — so
            // giving SDNN the same ceiling would not be consistency, it would make demo SDNN
            // EXACTLY equal to demo RMSSD, a pair no body produces and one that makes the demo
            // useless for a receiver plotting the two against each other. pNN50 is a percentage
            // and no source ties it to the knob at all.
            //
            // ⚠️ WHAT IS STILL WRONG HERE AND IS **NOT** FIXED, named rather than left for the
            // next reader: 90 < 100, so the demo publishes SDNN BELOW RMSSD at every point,
            // and at rest the standard short-term relationship runs the other way (Task Force
            // 1996 reports resting SDNN above RMSSD over 5-minute records). Changing it means
            // choosing a ratio, i.e. inventing physiology to make a demo prettier — that is a
            // separate decision with its own evidence, not a rider on an arithmetic fix.
            hrvSDNNms: hrvNormalized * 90,
            hrvPNN50: hrvNormalized * 40
        )
    }

    private func clamp(_ x: Float, in range: ClosedRange<Float>) -> Float {
        min(max(x, range.lowerBound), range.upperBound)
    }
}
