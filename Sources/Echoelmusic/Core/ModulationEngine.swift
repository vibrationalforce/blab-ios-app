//
//  ModulationEngine.swift
//  Echoelmusic — Core control-plane modulation runtime
//
//  Makes a `ModulationMatrix` live: on each control-plane tick it reads the
//  latest bio frame from `EngineBus`, evaluates every route, and dispatches
//  the normalized [0..1] output to a registered destination handler.
//
//  Destinations are registered as closures keyed by `ModDestination.key`,
//  so this engine stays fully decoupled from any concrete parameter type
//  (synth, sequencer, OSC) and remains cross-platform (pure Foundation).
//  The owning app wires real parameters in (e.g. tempo, a synth param),
//  scaling the [0..1] value into the parameter's own range inside the closure.
//
//  Mirrors the OSCSender / BioReactiveSynthVoice subscriber pattern: a
//  @MainActor Task polling `bus.latestBio` at 100 ms, timestamp-deduped.
//  Reads the control-plane snapshot — never the lock-free SPSC queues — so
//  it never contends with the audio-thread consumers.
//
//  Default matrix is empty: with no routes the engine applies nothing, so
//  adding it to the app is a zero-behavior-change wiring step. Routes are
//  authored later (UI cycle) or seeded by the app.
//

import Foundation
#if canImport(Observation)
import Observation
#endif

@MainActor
@Observable
public final class ModulationEngine {

    /// The live routing table. Mutate to add/remove routes; the next tick
    /// picks up the change. `@Observable` so a routing UI can bind to it.
    public var matrix: ModulationMatrix

    public private(set) var isActive = false

    /// Control-plane time of the last applied tick — lets the UI render an
    /// activity dot without its own timer.
    public private(set) var lastAppliedTimestamp: TimeInterval = 0

    /// The most recent per-destination modulation outputs (summed, clamped
    /// [0..1]) from the last applied tick — the data spine for a LIVE "which
    /// parameter is the body moving, and by how much" readout (REIHENFOLGE
    /// item 2). Deduped (only reassigned when it actually changes) and cleared
    /// on `stop()`, so an idle engine doesn't churn observers. Observable and
    /// updates ~10 Hz while bio moves a route, so read it ONLY inside its own
    /// small leaf view — never a root/ancestor body (the 10 Hz menu-freeze law).
    /// Empty when no route produced output this tick.
    public private(set) var lastOutputs: [ModDestination: Float] = [:]

    /// `lastOutputs` as a key-sorted list — a stable display order for the
    /// item-2 meter (a dictionary has none). Pure; safe to compute in the leaf.
    public var orderedOutputs: [(destination: ModDestination, value: Float)] {
        lastOutputs
            .sorted { $0.key.key < $1.key.key }
            .map { (destination: $0.key, value: $0.value) }
    }

    @ObservationIgnored
    private weak var bus: EngineBus?

    @ObservationIgnored
    private var destinations: [String: (Float) -> Void] = [:]

    /// Optional observer called for every evaluated output (destination, value)
    /// on each apply — used to stream modulation values out over OSC without
    /// coupling the engine to the network layer.
    @ObservationIgnored
    public var outputTap: ((ModDestination, Float) -> Void)?

    @ObservationIgnored
    private let loop = PollingLoop()

    @ObservationIgnored
    private var lastFrameTimestamp: TimeInterval = -1

    @ObservationIgnored
    private let defaults: UserDefaults

    @ObservationIgnored
    private let storageKey = "modulationMatrix.v1"

    /// Per-route one-pole smoothing state (last emitted value), keyed by route
    /// id. Only routes with `smoothingTau > 0` keep an entry. Seeded at a
    /// route's first value (no startup ramp), pruned when a route is removed
    /// or disabled, cleared on `stop()`.
    @ObservationIgnored
    private var routeSmoothing: [UUID: Float] = [:]

    /// Timestamp of the frame the smoothing state was last advanced with. Separate from
    /// `lastFrameTimestamp` on purpose: that one belongs to `tick`'s dedup and is not set
    /// when `apply(_:)` is called directly (tests, and any future caller), so reusing it
    /// would make `dt` depend on WHICH door the frame came through.
    @ObservationIgnored
    private var lastSmoothedFrameTimestamp: TimeInterval = -1

    /// ⛔ #336 — WHAT USED TO BE HERE WAS A CONSTANT `tickSeconds: Float = 0.1`, described as
    /// "matches the 100 ms polling loop" and handed to `BioNormalizer.alpha` as `dt`. The poll
    /// IS 100 ms; the SMOOTHING is not advanced by the poll. `tick` returns early unless
    /// `frame.timestamp` changed, and every wired publisher sends at ~1 Hz (CLAUDE.md pins this,
    /// `BioApplyRateIsTheDedupedRateTests` guards it). So one `alpha` step covered ~1 s of wall
    /// clock while claiming 0.1 s — a route asking for a 2 s slew took about 20 s. Same family as
    /// #315 (60 Hz assumed, ~1 Hz delivered) and #332, and the third time this repo has paid for
    /// a rate ASSUMED instead of measured.
    ///
    /// ⭐ THE FIX IS #337'S SHAPE AT ONE SITE: measure `dt` from the two frames themselves.
    /// `BioSampleFrame.timestamp` already carries it, so this needs no clock, stays pure, and is
    /// deterministic in a test — a `Date()` here would have been untestable AND would have made
    /// the smoothing depend on how long the main actor was busy.
    ///
    /// ⚠️ HONEST SCOPE, because it decides how much this slice may claim: **no shipped route is
    /// smoothed today.** `ModRoute.smoothingTau` defaults to 0, the default matrix is empty, and
    /// `git grep smoothingTau -- Sources` finds no writer outside the model and this file. So the
    /// branch below is unreachable in the shipped app and this change is audibly a no-op. It is
    /// worth doing anyway for one reason: #136 exists to give `ModRoute` a UI, and the day that
    /// lands, every slew a user dials would have been ten times too slow with nothing on screen
    /// to explain it.
    ///
    /// The nominal period used when there is no previous frame to measure against. 1 s, not the
    /// old 0.1 s, because that is the rate every wired publisher actually sends at. Only reached
    /// on the first applied frame after `start`/`stop`, where the smoothing seeds at the raw
    /// value anyway (`prev = raw` ⇒ the result is `raw` for any alpha) — so it is a floor against
    /// nonsense, not a behavioural knob.
    @ObservationIgnored
    static let nominalFramePeriod: Float = 1.0

    /// Ceiling on a measured gap. Beyond this the previous smoothed value is not a neighbour to
    /// slew from, it is history: the longest normal publisher cadence is ~1 s (camera · BLE ·
    /// simulator) and HealthKit's sensor is 4–5 s, so any larger gap means the link was down.
    /// Capping makes `alpha` land near 1 (i.e. essentially snap to the new reading) instead of
    /// letting an unbounded number decide.
    ///
    /// ⛔ THE CAP IS NOT BELT-AND-BRACES, and #398 is why it is written down. `timestamp` is
    /// wall-clock derived; `Date()` does not advance monotonically, so an NTP or timezone step
    /// makes a FINITE, enormous gap reachable — the exact species of input that stalled the
    /// evolve loop for an hour there. The sanitiser below therefore bounds the finite case too,
    /// not only NaN/±inf.
    @ObservationIgnored
    static let maxSmoothingGap: Float = 5.0

    /// Seconds between two APPLIED bio frames, sanitised — the `dt` the one-pole smoothing is
    /// actually stepped with.
    ///
    /// Pure and `Date`-free so the arithmetic can be driven directly in the blocking bundle.
    /// - Parameters:
    ///   - previous: the previously applied frame's timestamp, or a negative value for "none yet".
    ///   - current: this frame's timestamp.
    /// - Returns: a finite gap in `(0, maxSmoothingGap]`. A missing, non-finite, zero or
    ///   backwards gap degrades to `nominalFramePeriod` rather than to 0 — a 0 would make
    ///   `alpha` 0 and freeze every smoothed route at its seed value, which is silence-shaped
    ///   and would look like the route was never wired.
    nonisolated static func smoothingGap(previous: TimeInterval, current: TimeInterval) -> Float {
        guard previous >= 0, previous.isFinite, current.isFinite else { return nominalFramePeriod }
        let gap = Float(current - previous)
        guard gap.isFinite, gap > 0 else { return nominalFramePeriod }
        return Swift.min(gap, maxSmoothingGap)
    }

    public init(matrix: ModulationMatrix = ModulationMatrix(), defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.matrix = matrix
        load() // a persisted matrix, if any, wins over the passed default
    }

    // MARK: - Persistence

    /// Saves the current routing table. Call after edits (the routing UI
    /// invokes this on any change to `matrix.routes`).
    public func save() {
        guard let data = try? JSONEncoder().encode(matrix) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(ModulationMatrix.self, from: data) else { return }
        matrix = decoded
    }

    // MARK: - Destination registry

    /// Registers a handler for a destination key. The handler receives the
    /// summed, clamped [0..1] modulation value and is responsible for scaling
    /// it into its parameter's range. Re-registering a key replaces it.
    public func register(_ key: String, _ apply: @escaping (Float) -> Void) {
        destinations[key] = apply
    }

    public func unregister(_ key: String) {
        destinations[key] = nil
    }

    /// Destination keys this build knows how to drive (for UI discovery).
    public var registeredDestinations: [String] {
        destinations.keys.sorted()
    }

    // MARK: - Lifecycle

    public func start(subscribing bus: EngineBus) {
        guard !isActive else { return }
        self.bus = bus
        isActive = true
        loop.start(interval: .milliseconds(100)) { [weak self] in
            guard let self, let bus = self.bus else { return }
            self.tick(from: bus)
        }
    }

    public func stop() {
        loop.stop()
        isActive = false
        routeSmoothing.removeAll() // a fresh start re-seeds smoothing, no stale ramp
        // …and the gap the next frame is measured against must go with it. Left standing, a
        // session paused for ten minutes would hand the first frame after restart a gap across
        // the whole pause. It would be CAPPED and therefore harmless, but it would also be a
        // measurement of nothing — the two facts (`no previous frame` vs `a real gap`) have to
        // stay distinguishable, which is the same lesson `RegenSchedule` was extracted for.
        lastSmoothedFrameTimestamp = -1
        lastOutputs = [:]          // the item-2 meter clears when modulation stops
    }

    // MARK: - Tick

    /// Evaluates the matrix against the latest bio frame and dispatches each
    /// destination's value to its handler. Deduped on frame timestamp so an
    /// unchanged snapshot does no work. Destinations without a registered
    /// handler are silently ignored.
    public func tick(from bus: EngineBus) {
        // Freshness-gate the modulation brain (#60): a frozen bio reading — a
        // dropped strap, a lifted finger, a stalled Watch — must NOT keep driving
        // tempo/params off a dead value. `usableBio()` returns the freshest frame
        // only while it is within ITS OWN source's window (rPPG/BLE 6 s, Watch 90 s),
        // else nil, so the mod-brain simply idles instead of steering on stale data.
        guard let frame = bus.usableBio() else {
            // Stale/absent bio: the mod-brain idles AND the item-2 meter must go BLANK —
            // never keep displaying the last amounts as if the body still drove them
            // (the honesty companion to the freshness gate). Guarded so a steady stale
            // state doesn't churn the @Observable every tick.
            if !lastOutputs.isEmpty { lastOutputs = [:] }
            return
        }
        guard frame.timestamp != lastFrameTimestamp else { return }
        lastFrameTimestamp = frame.timestamp
        apply(frame)
    }

    /// Evaluate the matrix for `frame`, apply per-route smoothing, aggregate per
    /// destination, and forward outputs to handlers. Exposed for tests (call
    /// directly without the polling Task).
    ///
    /// Behavior is identical to the pure `matrix.evaluate(frame)` for routes
    /// with `smoothingTau == 0`; routes with `smoothingTau > 0` are one-pole
    /// low-passed across ticks (seeded at their first value, so no startup ramp).
    public func apply(_ frame: BioSampleFrame) {
        var result: [ModDestination: Float] = [:]
        var active = Set<UUID>()
        // Measured once per applied frame, not once per route: every route in this pass is
        // advanced by the SAME elapsed time, and reading it per route would let a mid-loop
        // state change hand two routes different clocks for one frame.
        let dt = Self.smoothingGap(previous: lastSmoothedFrameTimestamp, current: frame.timestamp)
        lastSmoothedFrameTimestamp = frame.timestamp

        for route in matrix.routes where route.enabled {
            active.insert(route.id)
            let raw = ModulationMatrix.output(for: route, frame: frame)

            var value = raw
            if route.smoothingTau > 0 {
                let alpha = BioNormalizer.alpha(tauSeconds: route.smoothingTau, dtSeconds: dt)
                let prev = routeSmoothing[route.id] ?? raw // seed at first value
                value = alpha * raw + (1 - alpha) * prev
                routeSmoothing[route.id] = value
            }

            guard value > 0 else { continue } // matches evaluate(): skip zero
            result[route.destination, default: 0] =
                ModulationMatrix.clamp01((result[route.destination] ?? 0) + value)
        }

        // Drop smoothing state for routes that were removed or disabled.
        // Skipped entirely when nothing is smoothed (the common, zero-cost path).
        if !routeSmoothing.isEmpty {
            routeSmoothing = routeSmoothing.filter { active.contains($0.key) }
        }

        // Item-2 live snapshot: reflect the applied outputs (incl. clearing to
        // empty when nothing moved). Deduped so an idle engine doesn't notify
        // observers every tick. Set before the empty-guard so the meter clears.
        if lastOutputs != result { lastOutputs = result }
        guard !result.isEmpty else { return }
        // 5.1.3 egress parity. The on-device apply (`destinations[]`) ALWAYS runs — a
        // HealthKit/.watch/.oura reading may drive the LOCAL tempo/params, which never
        // leaves the device. But the NETWORK tap (`outputTap` → OSC /echoelmusic/mod/*)
        // must honor the SAME `BioEgressPolicy` as every frame sender: the raw frame from
        // a blocked source is withheld in `OSCSender.sendIfFresh`, so a modulation value
        // DERIVED from it must not egress either. Gate ONLY the tap on the frame's source.
        let allowsEgress = BioEgressPolicy.allowsEgress(frame.source)
        for (destination, value) in result {
            destinations[destination.key]?(value)
            if allowsEgress { outputTap?(destination, value) }
        }
        lastAppliedTimestamp = CFAbsoluteTimeGetCurrent()
    }
}

// MARK: - Canonical destination keys

/// Well-known destination keys the app wires up. Keeping them here lets both
/// the binding site and any routing UI refer to the same strings.
public enum ModDestinationKey {
    /// Sequencer tempo. Closure scales [0..1] → [30..300] BPM.
    public static let tempo = "seq.tempo"
}
