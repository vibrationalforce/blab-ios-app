//
//  HapticController.swift
//  Echoelmusic — Studio (eyes-free performance feedback)
//
//  A small, NON-availability-gated coordinator the app and views talk to, so no
//  call site needs `@available`/`if #available` of its own. It encapsulates the
//  iOS 13 / macOS 11 `HapticEngine` behind runtime availability checks and a
//  plain API, plus pure step→cue logic that is unit-tested without hardware.
//
//  Armed model: OFF by default — silent until the user enables it, exactly like
//  the bio synth voice ("guaranteed launch silence"). Driving it (sequencer step
//  → beat tap, bio tick → breath pulse) is wired in the next cycle.
//

#if canImport(CoreHaptics)
import Foundation
#if canImport(Observation)
import Observation
#endif

@MainActor
@Observable
public final class HapticController {

    /// User-armed. Off by default; toggling it starts/stops the engine.
    public var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            isEnabled ? startEngine() : stopEngine()
        }
    }

    // Stored as AnyObject so this type needs no `@available` annotation; the
    // concrete `HapticEngine` is only named inside `if #available` blocks.
    @ObservationIgnored private var engineBox: AnyObject?

    public init() {}

    // MARK: - Drivers (no-op unless armed)

    /// Fire a transport pulse for a sequencer step. Only quarter-note steps
    /// pulse (a felt beat, not a 16th-note buzz); the down-beat is strongest.
    public func tapBeat(step: Int) {
        guard isEnabled, Self.isPulseStep(step) else { return }
        play(Self.beatCue(forStep: step))
    }

    /// Fire the continuous breath/coherence cue for one control tick.
    public func breath(phase: Float, coherence: Float) {
        guard isEnabled else { return }
        play(BioHaptics.breathPulse(breathPhase: phase, coherence: coherence))
    }

    // MARK: - Pure step → cue logic (unit-tested; no hardware)

    /// True on quarter-note steps (every 4th of a 16-step bar). Negative steps
    /// are handled with a floored modulo so a reversed/edge index never crashes.
    public static func isPulseStep(_ step: Int) -> Bool {
        floorMod(step, 16) % 4 == 0
    }

    /// The cue for a quarter-note step: the down-beat (step 0 of the bar) is the
    /// strong landmark; the other quarters are soft taps.
    public static func beatCue(forStep step: Int) -> HapticCue {
        BioHaptics.beat(isDownbeat: floorMod(step, 16) == 0)
    }

    private static func floorMod(_ a: Int, _ n: Int) -> Int {
        let m = a % n
        return m < 0 ? m + n : m
    }

    // MARK: - Engine bridge (availability-gated)

    private func startEngine() {
        if #available(iOS 13.0, macOS 11.0, *) {
            let engine = (engineBox as? HapticEngine) ?? HapticEngine()
            engine.start()
            engineBox = engine
        }
    }

    private func stopEngine() {
        if #available(iOS 13.0, macOS 11.0, *) {
            (engineBox as? HapticEngine)?.stop()
        }
    }

    private func play(_ cue: HapticCue) {
        if #available(iOS 13.0, macOS 11.0, *) {
            (engineBox as? HapticEngine)?.play(cue)
        }
    }
}
#endif
