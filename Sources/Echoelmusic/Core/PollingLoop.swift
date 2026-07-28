//
//  PollingLoop.swift
//  Echoelmusic — Core
//
//  Reusable @MainActor polling loop. Owns one cancellable Task that invokes
//  `body` every `interval` until stopped. Centralizes the start/stop +
//  cancellation scaffolding that was copy-pasted across every EngineBus
//  control-plane subscriber (OSCSender, BioReactiveSynthVoice,
//  ModulationEngine, SessionRecorder).
//
//  Behavior-preserving extraction (audit P1, 2026-05-31): the body runs once
//  per interval exactly as before; each subscriber keeps its own observed
//  active flag and its own timestamp-dedup logic. Only the Task plumbing moves
//  here. Pure Foundation — cross-platform.
//
//  2026-07-28: the interval is no longer baked at `start()`. A loop may opt in to
//  the app-wide `PollingRateCeiling` so device pressure can slow it down while it
//  runs — see the type below for why that indirection exists.
//

import Foundation

/// App-wide CEILING on how often the control-plane bio loops may wake the main
/// actor. Published by `ResourceGovernor` from `QualitySettings.bioHz`; read by
/// every `PollingLoop` that opted in via `governedByBioCeiling`.
///
/// **Why a shared holder and not an injected reference** (FlashGuard precedent):
/// thermal state and battery level are properties of the DEVICE, not of any one
/// subscriber, and `PollingLoop` is the single chokepoint every control-plane
/// subscriber already goes through. Threading a `ResourceGovernor` into six
/// `@Observable` engine classes plus the app's environment wiring would be a far
/// larger diff for the same one value. `ResourceGovernor` is the ONLY writer.
///
/// **CEILING, never a target.** `QualitySettings.bioHz` reaches 15 at the `high`
/// tier while every governed loop's nominal rate is 10 Hz — read as a target it
/// would SPEED loops UP on a charging phone, i.e. spend more battery in the name
/// of saving it. `interval(nominal:ceilingHz:)` can only ever lengthen an interval.
@MainActor
public enum PollingRateCeiling {

    /// Current ceiling in Hz. `0` = uncapped (the launch default, and the value a
    /// non-finite or non-positive input is normalised to).
    public private(set) static var bioHz: Double = 0

    /// Publish a new ceiling. Called by `ResourceGovernor` only.
    public static func setBioHz(_ hz: Double) {
        bioHz = (hz.isFinite && hz > 0) ? hz : 0
    }

    /// Pure: the interval a loop should actually sleep. `nonisolated` so the policy
    /// is testable (and reusable) without hopping to the main actor.
    /// The slowest a ceiling may make any loop. Not caution for its own sake: this is
    /// a public pure function, and `1.0 / ceilingHz` for a denormal-small input is a
    /// number `Duration.seconds(_:)` cannot represent. A ceiling below this is a
    /// nonsense reading, and answering it with "once every 5 s" is a far better
    /// failure than an overflow trap in a control loop.
    nonisolated public static let slowestInterval = Duration.seconds(5)

    /// Pure: the interval a loop should actually sleep. `nonisolated` so the policy
    /// is testable (and reusable) without hopping to the main actor.
    nonisolated public static func interval(nominal: Duration, ceilingHz: Double) -> Duration {
        guard ceilingHz.isFinite, ceilingHz > 0 else { return nominal }
        let capped = ceilingHz >= 0.2 ? Duration.seconds(1.0 / ceilingHz) : slowestInterval
        return Swift.max(nominal, capped)
    }
}

@MainActor
public final class PollingLoop {

    private var task: Task<Void, Never>?

    public init() {}

    public var isRunning: Bool { task != nil }

    /// Starts the loop if not already running. `body` is invoked on the main
    /// actor every `interval` until `stop()` (or app exit). `body` should
    /// capture its owner weakly.
    ///
    /// - Parameter governedByBioCeiling: opt in to `PollingRateCeiling.bioHz`, so a
    ///   thermally stressed or nearly empty device wakes this loop LESS often. The
    ///   ceiling is re-read before every sleep, so a tier change reaches a loop that
    ///   is already running (the reason the interval could not simply stay a `let`:
    ///   baking it at `start()` is exactly why `bioHz` had no consumer at all).
    ///   Default `false` keeps every existing call site bit-identical.
    public func start(interval: Duration,
                      governedByBioCeiling: Bool = false,
                      _ body: @escaping @MainActor () -> Void) {
        guard task == nil else { return }
        // The ceiling is read from the shared holder rather than from a stored
        // property, so this task still captures no `self` — as it never did. Keeping
        // it that way is the point: a `self`-capturing task would be retained by the
        // very loop it is stored on.
        task = Task { @MainActor in
            while !Task.isCancelled {
                body()
                let sleep = governedByBioCeiling
                    ? PollingRateCeiling.interval(nominal: interval,
                                                  ceilingHz: PollingRateCeiling.bioHz)
                    : interval
                try? await Task.sleep(for: sleep)
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }
}
