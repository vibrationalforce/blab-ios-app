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

    /// Control-plane tick spacing in seconds (matches the 100 ms polling loop).
    /// Used as `dt` for the smoothing time constant.
    @ObservationIgnored
    private static let tickSeconds: Float = 0.1

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
        lastOutputs = [:]          // the item-2 meter clears when modulation stops
    }

    // MARK: - Tick

    /// Evaluates the matrix against the latest bio frame and dispatches each
    /// destination's value to its handler. Deduped on frame timestamp so an
    /// unchanged snapshot does no work. Destinations without a registered
    /// handler are silently ignored.
    public func tick(from bus: EngineBus) {
        guard let frame = bus.latestBio else { return }
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

        for route in matrix.routes where route.enabled {
            active.insert(route.id)
            let raw = ModulationMatrix.output(for: route, frame: frame)

            var value = raw
            if route.smoothingTau > 0 {
                let alpha = BioNormalizer.alpha(tauSeconds: route.smoothingTau, dtSeconds: Self.tickSeconds)
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
        for (destination, value) in result {
            destinations[destination.key]?(value)
            outputTap?(destination, value)
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
