// TrackFXStore.swift
// Echoel — PER-TRACK FX, Module 2 of the comprehensive interface (founder 2026-07-11:
// "trenne alles … in unserem all-umfassenden Interface wieder zusammensetzen … die
// Effekte wie in der Musik durch Biofeedback beeinflusst"). Each rendering BUS gets its
// own insert effect (resonant filter + drive) — the dubby filter-sweep on the melodic
// bus, the analog drive on the bass — layered on top of the genre FX + master chain.
//
// SPINE ONLY (this cycle): the persisted control model + a ready-to-run `ChannelInsertFX`
// per bus. Every bus defaults to `.off`, and `ChannelInsertFX(type: .off, drive: 0)` is an
// EXACT passthrough — so wiring this into the render paths (next cycle) is bit-identical
// until the user dials a knob. The audible per-bus wiring + UI + bio-modulation routing
// are the following cycles (device pass required — audio can't be verified in the sandbox).
// See scratchpads/PLAN_PER_TRACK_FX.md.

import Foundation
import Observation

/// Which rendering bus an insert sits on. Only PHYSICALLY-SEPARATE buses appear here:
/// bass = `SubBassVoice`, melodic = the poly synth (lead+harmony share one bus until the
/// graph split), drums = `BeatPlayer`. The lead/pad split arrives with that refactor.
public enum FXBus: String, CaseIterable, Codable, Sendable {
    case bass, melodic, drums

    public var title: String {
        switch self {
        case .bass:    return "Bass"
        case .melodic: return "Melodic"
        case .drums:   return "Drums"
        }
    }
}

/// The persisted control-plane settings for one bus insert. Pure value type (Codable) so
/// it round-trips independent of any audio framework and is unit-testable off-thread.
public struct TrackFX: Codable, Equatable, Sendable {
    public var filter: ChannelInsertFX.FilterType
    public var cutoffHz: Float
    public var resonance: Float
    public var drive: Float

    /// Clean passthrough — the default for every bus (bit-identical to no insert).
    public static let off = TrackFX(filter: .off, cutoffHz: 1200, resonance: 0.707, drive: 0)

    public init(filter: ChannelInsertFX.FilterType = .off, cutoffHz: Float = 1200,
                resonance: Float = 0.707, drive: Float = 0) {
        self.filter = filter
        self.cutoffHz = cutoffHz
        self.resonance = resonance
        self.drive = drive
    }

    /// True when this insert does nothing — the render path can skip it entirely.
    public var isPassthrough: Bool { filter == .off && drive <= 0 }

    /// Build a ready-to-run insert for the audio boundary. Pure — the caller owns the
    /// returned value's biquad state and calls `process` on the audio thread.
    public func makeInsert(sampleRate: Float) -> ChannelInsertFX {
        ChannelInsertFX(type: filter, cutoffHz: cutoffHz, resonance: resonance,
                        drive: drive, sampleRate: sampleRate)
    }
}

@MainActor @Observable
public final class TrackFXStore {

    // Per-bus insert settings. Persisted as JSON. Default `.off` → a fresh install (and
    // every un-dialed bus) is exactly as before.
    public var bass:    TrackFX { didSet { persist(Keys.bass,    bass)    } }
    public var melodic: TrackFX { didSet { persist(Keys.melodic, melodic) } }
    public var drums:   TrackFX { didSet { persist(Keys.drums,   drums)   } }

    private enum Keys {
        static let bass    = "trackfx.bass"
        static let melodic = "trackfx.melodic"
        static let drums   = "trackfx.drums"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        bass    = TrackFXStore.read(defaults, Keys.bass)
        melodic = TrackFXStore.read(defaults, Keys.melodic)
        drums   = TrackFXStore.read(defaults, Keys.drums)
    }

    /// Settings for a bus.
    public func settings(for bus: FXBus) -> TrackFX {
        switch bus {
        case .bass:    return bass
        case .melodic: return melodic
        case .drums:   return drums
        }
    }

    /// Update a bus (routes through the observed property so the UI + persistence fire).
    public func set(_ fx: TrackFX, for bus: FXBus) {
        switch bus {
        case .bass:    bass = fx
        case .melodic: melodic = fx
        case .drums:   drums = fx
        }
    }

    /// A ready insert for the audio boundary — nil when the bus is a passthrough, so the
    /// caller can skip installing an insert entirely.
    public func insert(for bus: FXBus, sampleRate: Float) -> ChannelInsertFX? {
        let fx = settings(for: bus)
        return fx.isPassthrough ? nil : fx.makeInsert(sampleRate: sampleRate)
    }

    /// Reset every bus to clean passthrough.
    public func resetToClean() {
        bass = .off; melodic = .off; drums = .off
    }

    // MARK: Persistence (JSON blob per bus — nil/undecodable → clean passthrough)

    private static func read(_ d: UserDefaults, _ key: String) -> TrackFX {
        guard let data = d.data(forKey: key),
              let fx = try? JSONDecoder().decode(TrackFX.self, from: data) else { return .off }
        return fx
    }

    private func persist(_ key: String, _ fx: TrackFX) {
        guard let data = try? JSONEncoder().encode(fx) else { return }
        defaults.set(data, forKey: key)
    }

    // MARK: Control ranges (shared by the UI)

    public nonisolated static let cutoffRange: ClosedRange<Float> = 40...18_000
    public nonisolated static let resonanceRange: ClosedRange<Float> = 0.5...8
    public nonisolated static let driveRange: ClosedRange<Float> = 0...1
}
