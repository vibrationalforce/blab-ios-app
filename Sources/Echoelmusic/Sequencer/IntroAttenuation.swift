// IntroAttenuation.swift
//
// ⛔ READ THIS FIRST: EVERYTHING BELOW IS WRITTEN IN THE PRESENT TENSE AND DESCRIBES A BEHAVIOUR
// THAT HAS NEVER OCCURRED. All 25 curated genres set `HarmonicProfile.leadDensity` to 0, so no
// `.lead`-role note is ever composed and `apply` returns every take unchanged (pinned by
// `LeadRoleAbsenceTests` in the blocking bundle; the full finding is in `RoleRhythm.swift`'s A5
// paragraph). The paragraphs below are the DESIGN, kept because the softened entrance is a real
// intent and this is where it belongs the moment a genre sings again — not a shipping description.
// The "known scope limit" note at the bottom is a limit of a feature that does not run.
//
// Echoel — founder ear-feedback 2026-07-21 (task #77): "viele klingen am Anfang
// etwas zu unruhig wegen lauter Melodie" (many genres sound a bit restless at the
// start because of a loud melody). The lead melody plays at full genre-mix loudness
// from its very first note, before the groove (bass/pad/drums) has had a bar to
// establish — so the take opens busy instead of settling in. Pure, audio-thread-safe
// velocity scaling (same pattern as the existing genre mix glue in
// EchoelStudioView.generate()'s `finish` closure). Wired into
// `PianoRollModel.loadArrangement`'s stopped/fresh-take branch, applied ONLY to the
// note array staged into `.notes` for the very first play — NEVER baked into
// `arrangementBars` (the array every loop wrap and `arrangementForExport()` read
// from) — so a listener hears the softened entrance exactly once per fresh
// Generate/Play, not on every repeat of the loop.
//
// Known scope limit (accepted, not a bug): a 1-bar loop (`LoopBarLength.one`) never
// reaches this — `PianoRollModel.loadArrangement`'s existing `bars.count > 1` guard
// routes it through the plain `load()` fallback instead, which has no separate
// "cycling array" to keep clean, so there is nowhere safe to apply a one-shot
// softening without it recurring every bar. Only multi-bar loops (the default is
// 8 bars) get the softened entrance today.

import Foundation

/// Softens the LEAD role only, for the opening bar of a take.
///
/// ⛔ **THIS HAS NEVER AUDIBLY DONE ANYTHING, and that is not a defect here.** All 25 curated genres
/// set `HarmonicProfile.leadDensity` to 0, so `BioComposer` composes no `.lead`-role note and
/// `apply` returns every take unchanged (pinned by `LeadRoleAbsenceTests` in the blocking bundle).
/// Kept because the softened entrance is a real intent and this is where it belongs the moment a
/// genre sings again — but do not cite this type as a shipping behaviour, and do not "fix" a
/// too-loud opening bar by tuning `leadFactor`: today it would change nothing.
public enum IntroAttenuation {

    /// How much the lead's velocity is pulled back on bar 0 (multiplicative).
    /// 0.72 sits it clearly under the genre mix's own lead level without going
    /// inaudible — the groove gets a bar of room before the melody is at full
    /// presence.
    public static let leadFactor: Float = 0.72

    /// Returns `notes` unchanged when `isFirstBar` is false (every loop bar after
    /// the first) or the array is empty. Otherwise returns a copy with every
    /// `.lead`-role note's velocity scaled by `leadFactor` (clamped to [0, 1]) —
    /// bass, harmony and pad notes are untouched.
    public static func apply(_ notes: [Note], isFirstBar: Bool) -> [Note] {
        guard isFirstBar else { return notes }
        return notes.map { note in
            guard note.role == .lead else { return note }
            var m = note
            m.velocity = min(1, max(0, note.velocity * leadFactor))
            return m
        }
    }
}
