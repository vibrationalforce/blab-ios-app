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

import Foundation

@MainActor
public final class PollingLoop {

    private var task: Task<Void, Never>?

    public init() {}

    public var isRunning: Bool { task != nil }

    /// Starts the loop if not already running. `body` is invoked on the main
    /// actor every `interval` until `stop()` (or app exit). `body` should
    /// capture its owner weakly.
    public func start(interval: Duration, _ body: @escaping @MainActor () -> Void) {
        guard task == nil else { return }
        task = Task { @MainActor in
            while !Task.isCancelled {
                body()
                try? await Task.sleep(for: interval)
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }
}
