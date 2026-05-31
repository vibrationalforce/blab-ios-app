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

    @ObservationIgnored
    private weak var bus: EngineBus?

    @ObservationIgnored
    private var destinations: [String: (Float) -> Void] = [:]

    @ObservationIgnored
    private var task: Task<Void, Never>?

    @ObservationIgnored
    private var lastFrameTimestamp: TimeInterval = -1

    @ObservationIgnored
    private let defaults: UserDefaults

    @ObservationIgnored
    private let storageKey = "modulationMatrix.v1"

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
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, let bus = self.bus else { break }
                self.tick(from: bus)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        isActive = false
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

    /// Pure-ish apply: evaluate the matrix for `frame` and forward outputs to
    /// handlers. Exposed for tests (call directly without the polling Task).
    public func apply(_ frame: BioSampleFrame) {
        let outputs = matrix.evaluate(frame)
        guard !outputs.isEmpty else { return }
        for (destination, value) in outputs {
            destinations[destination.key]?(value)
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
