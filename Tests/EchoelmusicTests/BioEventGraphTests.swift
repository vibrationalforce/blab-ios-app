import XCTest
@testable import Echoelmusic

final class BioEventGraphTests: XCTestCase {

    // MARK: - Heartbeat detection

    func testHeartbeat_periodicPeaks_detectsRegularBeats() {
        let sr = 130.0
        var graph = BioEventGraph(sampleRate: sr)

        // Synthesize 1 Hz pulse train (60 bpm): a sharp peak every
        // `sr` samples. Feed 5 seconds.
        var beats: [BioEvent] = []
        let totalSamples = Int(sr * 5)
        let period = Int(sr) // 1 second
        for n in 0..<totalSamples {
            let phaseInPeriod = n % period
            // Narrow triangular pulse at the start of each period.
            let sample: Float = phaseInPeriod < 5
                ? Float(5 - phaseInPeriod) / 5.0
                : 0
            let t = Double(n) / sr
            beats += graph.process(cleanedHeart: sample, breathPhase: 0, motionEnergy: 0, timestamp: t)
                .filter { $0.kind == .heartbeat }
        }

        // ~5 beats in 5 seconds at 60 bpm (first beat has no IBI).
        XCTAssertGreaterThanOrEqual(beats.count, 4)
        XCTAssertLessThanOrEqual(beats.count, 6)
    }

    func testHeartbeat_refractory_suppressesDoublePeaks() {
        let sr = 130.0
        var graph = BioEventGraph(sampleRate: sr)

        // Two peaks 100 ms apart — second is inside the 300 ms
        // refractory window and must be suppressed.
        var beats: [BioEvent] = []
        let totalSamples = Int(sr * 1)
        for n in 0..<totalSamples {
            var sample: Float = 0
            if n == 10 { sample = 1.0 }
            if n == 10 + Int(0.1 * sr) { sample = 1.0 }  // +100 ms
            let t = Double(n) / sr
            beats += graph.process(cleanedHeart: sample, breathPhase: 0, motionEnergy: 0, timestamp: t)
                .filter { $0.kind == .heartbeat }
        }
        XCTAssertEqual(beats.count, 1, "Second peak within refractory window must be suppressed")
    }

    func testHeartbeat_interBeatInterval_inAux() {
        let sr = 100.0
        var graph = BioEventGraph(sampleRate: sr)
        var beats: [BioEvent] = []
        // Peaks at t=0.1s and t=0.9s → IBI 800 ms.
        for n in 0..<Int(sr * 2) {
            var sample: Float = 0
            if n == 10 { sample = 1.0 }
            if n == 90 { sample = 1.0 }
            let t = Double(n) / sr
            beats += graph.process(cleanedHeart: sample, breathPhase: 0, motionEnergy: 0, timestamp: t)
                .filter { $0.kind == .heartbeat }
        }
        XCTAssertEqual(beats.count, 2)
        XCTAssertEqual(beats[1].aux, 800, accuracy: 20)  // ~800 ms IBI
    }

    // MARK: - Breath onsets

    func testBreath_inhaleOnset_atHalfPhaseCrossing() {
        var graph = BioEventGraph(sampleRate: 100)
        // phase rising through 0.5.
        _ = graph.process(cleanedHeart: 0, breathPhase: 0.4, motionEnergy: 0, timestamp: 0)
        let events = graph.process(cleanedHeart: 0, breathPhase: 0.6, motionEnergy: 0, timestamp: 0.01)
        XCTAssertTrue(events.contains { $0.kind == .breathInhaleOnset })
    }

    func testBreath_exhaleOnset_atPhaseWrap() {
        var graph = BioEventGraph(sampleRate: 100)
        _ = graph.process(cleanedHeart: 0, breathPhase: 0.95, motionEnergy: 0, timestamp: 0)
        let events = graph.process(cleanedHeart: 0, breathPhase: 0.05, motionEnergy: 0, timestamp: 0.01)
        XCTAssertTrue(events.contains { $0.kind == .breathExhaleOnset })
    }

    // MARK: - Motion peak

    func testMotion_peak_firesOnceWithHysteresis() {
        var graph = BioEventGraph(sampleRate: 100)
        var peaks = 0
        // Energy rises above 0.6, stays high, then drops — should fire once.
        let series: [Float] = [0.1, 0.4, 0.7, 0.8, 0.75, 0.65, 0.7, 0.2, 0.1]
        for (i, e) in series.enumerated() {
            peaks += graph.process(cleanedHeart: 0, breathPhase: 0, motionEnergy: e, timestamp: Double(i) * 0.01)
                .filter { $0.kind == .motionPeak }.count
        }
        XCTAssertEqual(peaks, 1, "Sustained-high motion must produce one peak, not chatter")
    }

    func testMotion_reArmsAfterDrop() {
        var graph = BioEventGraph(sampleRate: 100)
        var peaks = 0
        // Two distinct bursts separated by a drop below 0.3.
        let series: [Float] = [0.7, 0.1, 0.7]
        for (i, e) in series.enumerated() {
            peaks += graph.process(cleanedHeart: 0, breathPhase: 0, motionEnergy: e, timestamp: Double(i) * 0.01)
                .filter { $0.kind == .motionPeak }.count
        }
        XCTAssertEqual(peaks, 2, "Two bursts separated by a low dip must fire twice")
    }

    // MARK: - Reset

    func testReset_clearsState() {
        var graph = BioEventGraph(sampleRate: 100)
        _ = graph.process(cleanedHeart: 1.0, breathPhase: 0.6, motionEnergy: 0.7, timestamp: 0)
        graph.reset()
        // After reset, breath detector has no previous phase, so a single
        // sample must not emit a (spurious) onset.
        let events = graph.process(cleanedHeart: 0, breathPhase: 0.6, motionEnergy: 0, timestamp: 1.0)
        XCTAssertFalse(events.contains { $0.kind == .breathInhaleOnset })
    }
}
