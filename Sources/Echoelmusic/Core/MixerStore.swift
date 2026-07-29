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
    /// It also removes the largest single amplitude excursion feeding "es knistert" —
    /// though NOT, on the numbers, the leading mechanism, and two earlier framings of mine
    /// were wrong enough to correct here rather than let them propagate:
    /// · The makeup law `0.85/√N` is RIGHT for RMS — 12-TET pitches are irrational-ratio,
    ///   so they do not phase-lock and the RMS sum really does grow as √N. The failure is
    ///   that the downstream stage is PEAK-sensitive: peak approaches N·a at quasi-periodic
    ///   alignments, so 1/√N leaves a √N peak excursion recurring at the beat rate (#195).
    /// · The limiter does not produce "clicks". `g = ceiling/peak` makes the output of the
    ///   louder channel EXACTLY ±ceiling every time — algebraically a per-sample HARD
    ///   CLIPPER, not a fast limiter. Un-oversampled at 48 kHz, its odd harmonics fold back
    ///   below Nyquist as inharmonic ALIASING, which is the gritty/digital texture the
    ///   founder actually described far better than a periodic click would be (#194).
    /// · And the makeup one-pole's 250 ms lag means a chord ATTACK is compensated at the
    ///   previous, sparser gain — which overshoots the ceiling already at velocity 0.47.
    ///   So the clipper was being driven on every sparse→dense entry at ANY fader position.
    ///   A boosted fader made that continuous instead of transient: a large aggravation,
    ///   not the root. Expect crackle to persist after this until #194 lands.
    ///
    /// So in the VELOCITY path a fader may only attenuate. Above-unity boost is a GAIN
    /// question, not a velocity question, and needs a per-role output gain to answer
    /// honestly — the same distinction the felt sub got (`SubBassVoice.mixLevel`, #196).
    ///
    /// ⛔ THE PRODUCT IS CAPPED, NOT JUST THE USER TERM — corrected 2026-07-27 after the
    /// first version capped only `user` and left the hole open. **The GENRE term itself
    /// exceeds 1**: `MusicStyle.mixLevels` gives bass **1.18** on dubTechno/trap and 1.10
    /// on ska/rocksteady/disco/punk/rock/rocknroll/heavyMetal/doom, and harmony 1.05 on the
    /// meditation genres. Bass velocities reach 0.9 (`BioComposer`), and 0.9 × 1.18 = 1.062
    /// → still exactly 1.000 at the clamp. The pinned-at-1.000 signature from log 2470 was
    /// therefore STILL reproducible with every fader at unity, on two shipped genres.
    /// Capping the product makes `finish()`'s `min(1, …)` unreachable by construction — a
    /// documented no-op instead of a live failure mode.
    ///
    /// The genre levels are deliberately NOT edited: they are a curated tonal balance, and
    /// re-normalizing them would change how every genre sounds. Capping here bounds the
    /// result without touching the mix design.
    public nonisolated static func combined(genre: Float, user: Float) -> Float {
        Swift.min(1, Swift.max(genre, 0) * Swift.min(1, Swift.max(user, 0)))
    }

    /// The finished note velocity: the composer's raw velocity carrying both the genre's
    /// mix glue and the user's fader. This is THE mixing law — the primary take and the
    /// secondary lanes each used to carry their own identical copy of it, which is how a
    /// fix to one could silently leave the other on the old law.
    ///
    /// ⚠ IT MUST BE APPLIED TO THE COMPOSER'S RAW VELOCITY, NEVER TO AN ALREADY-MIXED ONE.
    /// It is a multiplication, so a second application COMPOUNDS (0.5 twice = 0.25) — the
    /// caller re-balancing a take that is already playing has to keep the raw bars and
    /// re-derive from them (#174). A test in the blocking bundle pins exactly that.
    ///
    /// NON-FINITE INPUT, stated precisely because the halves differ and a blanket
    /// "NaN-safe" claim here would be false:
    /// · a non-finite VELOCITY leaves a silent note — the clamp is written `Swift.max(0, x)`,
    ///   which returns 0 for NaN, where `Swift.max(x, 0)` would return NaN and poison the
    ///   voice (this repo has shipped that permanent-silence bug before).
    /// · a non-finite `genre` or `user` is treated as UNITY, not as zero, because
    ///   `combined` uses the other argument order and `Swift.min(1, .nan)` returns 1.
    ///   Neither is reachable today (genre levels are constants, the fader is persisted
    ///   from a bounded field) and, more importantly, neither can escape: the result is
    ///   provably in [0, 1] and never NaN for ANY input, so nothing non-finite reaches
    ///   the audio thread. That invariant — not the argument order — is what the
    ///   blocking-bundle test pins.
    public nonisolated static func mixedVelocity(_ velocity: Float,
                                                 genre: Float,
                                                 user: Float) -> Float {
        Swift.min(1, Swift.max(0, velocity * combined(genre: genre, user: user)))
    }

    /// Reset every fader to unity (the genre's own balance).
    public func resetToUnity() {
        bass = 1.0; pad = 1.0; lead = 1.0; drums = 1.0
    }

    /// PERSISTENCE tolerance, not the fader's range any more (2026-07-27). The Mix fields
    /// are drawn `0...1` because above unity nothing responds; this wider bound stays so a
    /// value saved at e.g. 1.35 by an older build still decodes and still means unity via
    /// `combined`'s cap — no migration, no data loss. Restore it as the UI range only
    /// together with a per-role output gain (#196).
    public nonisolated static let range: ClosedRange<Float> = 0...1.5
}
