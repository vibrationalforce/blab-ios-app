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

    /// 1 = the shape as of 2026-07-29 (#189 slice 4). Same stamp SHAPE as `Clip` — never
    /// decoded, never assigned, so the synthesized encoder writes the current version by
    /// construction — but reached differently: `Clip` keeps a synthesized decoder, while
    /// this type now hand-writes one that deliberately never touches `.schemaVersion`. See
    /// `Clip.currentSchemaVersion` for why this shape beats the provenance-carrying one used
    /// by `Project`/`TimelineDocument`.
    public static let currentSchemaVersion = 1

    /// ⚠️ Deliberately never read by `init(from:)` — the key exists so the ENCODER writes it,
    /// which is the whole job of a stamp added before the break it is meant to survive. Two
    /// consequences, both easy to trip over later: a loaded file's own version is available
    /// only as a local inside the decoder (that is where a migration reads it), and because
    /// every live instance holds the same constant, the synthesized `==` gains a term that
    /// cannot change any result. The day a migration DOES assign a decoded version here,
    /// that stops being true and `==` starts telling a loaded value apart from a fresh one.
    public private(set) var schemaVersion: Int = TrackFX.currentSchemaVersion

    public var filter: ChannelInsertFX.FilterType
    public var cutoffHz: Float
    public var resonance: Float
    public var drive: Float

    /// Clean passthrough — the default for every bus (bit-identical to no insert). Cutoff
    /// rests FULL-OPEN (18 kHz) so an off bus reads as "no filtering" in the UI, and the
    /// user disengages the filter simply by dragging the cutoff back up to the top.
    public static let off = TrackFX(filter: .off, cutoffHz: 18_000, resonance: 0.707, drive: 0)

    public init(filter: ChannelInsertFX.FilterType = .off, cutoffHz: Float = 1200,
                resonance: Float = 0.707, drive: Float = 0) {
        self.filter = filter
        self.cutoffHz = cutoffHz
        self.resonance = resonance
        self.drive = drive
    }

    // MARK: - Defensive decoding

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, filter, cutoffHz, resonance, drive
    }

    /// Custom decoder, and it closes a LIVE data-loss path rather than merely preparing for
    /// one — the version stamp above is the smaller half of this change.
    ///
    /// Until now `TrackFX` had a fully SYNTHESIZED decoder, and `TrackFXStore.read` turns any
    /// throw into `.off`. Two ordinary edits therefore silently wiped the user's filter and
    /// drive on ALL THREE buses at once, with no error anywhere:
    ///
    ///  1. Adding a non-optional field. The synthesized decoder throws `keyNotFound` on every
    ///     already-saved bus. This is exactly the bug that fired on `SynthPatch` (#95) and
    ///     took the whole patch library with it.
    ///  2. Touching `ChannelInsertFX.FilterType`. It is a raw-value enum, and synthesized
    ///     `RawRepresentable` decoding throws `dataCorrupted` on a value it does not know —
    ///     `decodeIfPresent` absorbs a MISSING key, never an unknown case. So a filter type
    ///     added in a newer build makes the settings unreadable to any older one, and
    ///     removing a type does the same in the other direction. Same mechanism, same cure,
    ///     as `TimelineLane.builtinInstrument` (`Sequencer/Timeline.swift`, the
    ///     `(try? decodeIfPresent(…)) ?? nil` line).
    ///
    /// Missing/unreadable fields fall back to `TrackFX.off`, NOT to the memberwise defaults.
    /// The difference is audible: the memberwise `cutoffHz` default is 1200 Hz, so falling
    /// back there would suddenly darken a bus that was full open. `.off` rests at 18 kHz —
    /// "as if no insert were dialed", which is what the surrounding store already promises.
    ///
    /// The `isFinite` check is NOT an audio-thread rescue — an earlier draft of this comment
    /// claimed it was, and that was false. `ChannelInsertFX` already sanitises: `recompute()`
    /// substitutes for a non-finite `cutoffHz`/`resonance`, `process(_:)` self-heals its
    /// biquad state, and the saturation path is behind `drive > 0`, which a NaN fails. What
    /// the check is really for is the SAME data-loss the rest of this decoder addresses: a
    /// number the file can hold but a `Float` cannot (`1e39`) used to throw and cost the
    /// whole bus, and it keeps an unusable value out of the `EchoelValueField` UI. A finite
    /// file is byte-identical through this path either way.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = TrackFX.off
        let storedFilter = (try? c.decodeIfPresent(ChannelInsertFX.FilterType.self,
                                                   forKey: .filter)) ?? nil
        filter    = storedFilter ?? fallback.filter
        cutoffHz  = TrackFX.finite(c, .cutoffHz,  fallback: fallback.cutoffHz)
        resonance = TrackFX.finite(c, .resonance, fallback: fallback.resonance)
        drive     = TrackFX.finite(c, .drive,     fallback: fallback.drive)
    }

    private static func finite(_ c: KeyedDecodingContainer<CodingKeys>,
                               _ key: CodingKeys, fallback: Float) -> Float {
        guard let value = (try? c.decodeIfPresent(Float.self, forKey: key)) ?? nil,
              value.isFinite else { return fallback }
        return value
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
