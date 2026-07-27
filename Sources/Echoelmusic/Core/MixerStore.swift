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
    ///
    /// THE USER TERM IS CAPPED AT UNITY, and that cap is the point (device log 2470).
    /// `range` runs to 1.5, so a fader pushed past unity used to multiply every note's
    /// velocity up into `finish()`'s `min(1, …)` clamp. The result was not "louder" — it
    /// was every note pinned at velocity exactly 1.000, i.e. **velocity dynamics
    /// destroyed**: no accents, no phrasing, one flat fortissimo. The founder's log shows
    /// it directly — session A varies 0.63…0.66, session B sits at 1.000 across dozens of
    /// samples with no variation at all.
    ///
    /// It is also the leading mechanism behind "es knistert": full-velocity notes stack
    /// (the render's polyphony makeup is a 1/√N law written for INCOHERENT sums, and an
    /// in-key chord sums coherently on its shared partials) and drive the chain's
    /// zero-lookahead, instant-attack limiter into per-sample gain steps — which is a
    /// click, once per ceiling crossing, indistinguishable from CPU-overload dropouts.
    ///
    /// So in the VELOCITY path a fader may only attenuate. Above-unity boost is a GAIN
    /// question, not a velocity question, and needs a per-role output gain to answer
    /// honestly — the same distinction the felt sub just got (`SubBassVoice.mixLevel`).
    /// Until that exists the top third of the pad/lead faders does nothing; that is a
    /// known, recorded gap, and it is strictly better than silently flattening the take.
    public nonisolated static func combined(genre: Float, user: Float) -> Float {
        Swift.max(genre, 0) * Swift.min(1, Swift.max(user, 0))
    }

    /// Reset every fader to unity (the genre's own balance).
    public func resetToUnity() {
        bass = 1.0; pad = 1.0; lead = 1.0; drums = 1.0
    }

    /// The user-adjustable range for a fader: 0 (mute) … 1.5 (a little boost).
    public nonisolated static let range: ClosedRange<Float> = 0...1.5
}
