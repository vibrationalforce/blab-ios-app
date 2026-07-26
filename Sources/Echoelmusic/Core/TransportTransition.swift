// TransportTransition.swift
// Echoelmusic — the PURE decision behind the app's ONE-Stop law (#161).
//
// The Studio reacts to exactly one signal, `Transport.isPlaying` changing, and has to pick one
// of four behaviours from it. That choice used to live inline in a SwiftUI `.onChange` closure
// where no test could reach it, and it shipped with a real defect: the `running` guard ran
// BEFORE the pause request was consumed, so a request raised while no take was live stayed
// outstanding and silently downgraded the NEXT real Stop to a pause — the app's Stop button
// stopping the music but leaving the camera and its torch on, with `running` still true.
//
// This type is that decision, extracted so it can be pinned (repo convention: `FlashGuard`,
// `AutomationCanvasMath`, `LaunchQuantizer.shouldDefer`). Pure value logic — no engine, no
// view, no `Sequencer`/`DSP` types — so it compiles and tests on every platform.
//
// THE CONTRACT THAT PREVENTS THE DEFECT: the caller must consume the one-shot pause request
// UNCONDITIONALLY, before calling `decide`, and pass the result in. `decide` therefore cannot
// be reached in a way that leaves a request outstanding — the guard that used to swallow it is
// now downstream of the read, expressed as `.ignore`.

import Foundation

/// What the Studio must do when the shared transport's `isPlaying` flips.
public enum TransportTransition: String, Equatable, Sendable, CaseIterable {

    /// Nothing to do — the clock moved but no take is live (e.g. the Notes editor auditioning
    /// a pattern before the body session was ever started).
    case ignore

    /// The clock started while a take IS live: re-arm whatever a previous pause cancelled.
    case resume

    /// The clock stopped and the Notes editor asked for a PLAYBACK-ONLY stop: release the
    /// voices and stop the generative drivers, but keep the body session (camera + pulse lock).
    case pausePlayback

    /// The clock stopped for any other reason: the ONE Stop — end the whole bio session.
    case endSession

    /// - Parameters:
    ///   - isPlaying: the transport's NEW value.
    ///   - running: whether a bio take is live.
    ///   - pauseRequested: the one-shot playback-only-stop request, **already consumed** by the
    ///     caller. Passing a value that was read conditionally re-opens the latch defect this
    ///     type exists to prevent.
    public static func decide(isPlaying: Bool,
                              running: Bool,
                              pauseRequested: Bool) -> TransportTransition {
        guard running else { return .ignore }
        if isPlaying { return .resume }
        return pauseRequested ? .pausePlayback : .endSession
    }
}
