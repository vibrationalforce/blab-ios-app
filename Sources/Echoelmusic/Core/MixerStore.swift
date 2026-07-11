// MixerStore.swift
// Echoel — the per-part MIXER (founder 2026-07-11: "trenne die Stimmen auf getrennte,
// mischbare Spuren … dann drehst du den Lead runter"). Module 1 of the comprehensive
// interface: the generated take's roles (bass · pad · lead) become user-mixable levels,
// layered ON TOP of each genre's built-in mix glue so genre character is preserved and
// the user simply trims — e.g. pulls a shrill lead down.
//
// The level is applied at compose time as a velocity multiplier (the same audio-thread-
// safe path `mixLevels` already uses), so there is NO audio-thread / render change.

import Foundation
import Observation

@MainActor @Observable
public final class MixerStore {

    // User level per role, linear (1.0 = the genre's own balance, unchanged). Persisted.
    public var bass:  Float { didSet { persist(Keys.bass,  bass)  } }
    public var pad:   Float { didSet { persist(Keys.pad,   pad)   } }   // harmony role
    public var lead:  Float { didSet { persist(Keys.lead,  lead)  } }
    public var drums: Float { didSet { persist(Keys.drums, drums) } }   // BeatPlayer master

    private enum Keys {
        static let bass  = "mixer.bass"
        static let pad   = "mixer.pad"
        static let lead  = "mixer.lead"
        static let drums = "mixer.drums"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // nil (never set) → unity, so a fresh install mixes exactly like before.
        bass  = MixerStore.read(defaults, Keys.bass)
        pad   = MixerStore.read(defaults, Keys.pad)
        lead  = MixerStore.read(defaults, Keys.lead)
        drums = MixerStore.read(defaults, Keys.drums)
    }

    private static func read(_ d: UserDefaults, _ key: String) -> Float {
        d.object(forKey: key) == nil ? 1.0 : d.float(forKey: key)
    }

    private func persist(_ key: String, _ value: Float) {
        defaults.set(value, forKey: key)
    }

    /// The user level for a note role.
    public func level(for role: NoteRole) -> Float {
        switch role {
        case .bass:    return bass
        case .harmony: return pad
        case .lead:    return lead
        }
    }

    /// Combine a genre's built-in role level with the user's mixer level. Pure so the
    /// mixing law is unit-testable. Unity user level = the genre level unchanged; the
    /// caller (compose `finish()`) still clamps the resulting velocity to [0, 1].
    public nonisolated static func combined(genre: Float, user: Float) -> Float {
        Swift.max(genre, 0) * Swift.max(user, 0)
    }

    /// Reset every fader to unity (the genre's own balance).
    public func resetToUnity() {
        bass = 1.0; pad = 1.0; lead = 1.0; drums = 1.0
    }

    /// The user-adjustable range for a fader: 0 (mute) … 1.5 (a little boost).
    public nonisolated static let range: ClosedRange<Float> = 0...1.5
}
