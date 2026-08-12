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
//  the bio synth voice ("guaranteed launch silence").
//
//  ⛔ THIS HEADER PROMISED BOTH DRIVERS AS FUTURE WORK, AND HALF OF THEM HAS BEEN
//  LIVE FOR MONTHS (#552, measured 2026-08-12). The BEAT path is complete end to
//  end: `EchoelmusicApp` registers `transport.addStepSubscriber("haptics", …)`,
//  that closure calls `tapBeat(step:)`, and the arming switch is reachable —
//  `hapticsRow` ("Haptic beat (feel)") sits in `tempoToolsPanel` behind the
//  Tempo chip. The BREATH path is the half that is genuinely absent:
//  `breath(phase:coherence:)` has ZERO production callers.
//
//  ⚠️ AND THE RECIPE FOR THAT LAST FACT IS DELIBERATELY NOT QUOTED HERE. The
//  draft of this block wrote out a `git grep` for the call form and claimed it
//  finds nothing — which the block itself then falsified, because writing the
//  call form into a comment IS a hit. Same shape as the `EchoelModalBank` recipe
//  that CLAUDE.md had to retract: a comment about a symbol contaminates any raw
//  search for that symbol. The measurement that survives being written down is a
//  comment-stripped one, and it lives in
//  `Tests/CISmoke/TheHapticBeatIsWiredAndTheBreathIsNotTests`.
//
//  ⭐ WHY A HALF-TRUE PROMISE IS WORSE THAN A WRONG ONE, and this is the part
//  worth carrying: a stale FACT gets contradicted the moment a reader checks it,
//  but a stale PLAN reads as correct as long as ANY part of it is still undone.
//  This one deferred BOTH drivers to a coming cycle — one of which ships and one
//  of which does not — so a session confirming the unwired half would conclude
//  the whole sentence holds, and either rebuild the beat path that already exists
//  or file the door as missing. Prescriptive prose that is half right is not half
//  a defect (#550). (The deferral phrase itself is described, not quoted: the
//  guard is a prose scan and the quote would red the commit that repairs it —
//  fifth such collision this session, and by now a routine of the job, not a
//  surprise of it.)
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
    ///
    /// ⚠️ NO PRODUCTION CALLER TODAY, and the obvious place to add one is a trap.
    /// The tick a session would reach for is `bioVoice.onPollTick` (`EchoelmusicApp`,
    /// ~10 Hz) — but `BioHaptics.breathPulse` defaults to `duration: 0.1`, so ten
    /// 0,1-s CONTINUOUS cues per second abut into one unbroken vibration, the exact
    /// opposite of the "gentle, eyes-free breathe-with-me" the cue is shaped for.
    /// Worse, the bio APPLY rate is ~1 Hz (every consumer dedupes on
    /// `frame.timestamp`), so nine of those ten would carry identical phase and
    /// coherence. Wiring this needs its own slice: either drive it from the bio
    /// frame's arrival rather than the poll, or lengthen `duration` to the interval
    /// it actually covers. Not a one-liner, and a device probe decides it.
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
