// MusicTheoryPrimer.swift
// Echoelmusic — the "app as a school" layer for music theory. Plain-language primers
// for the concepts the composer uses (intervals, scales, chords, cadences, key,
// tempo, swing, dynamics) so a learner understands WHY a take sounds the way it
// does. Science/craft-first, no esoterica. Pure Foundation content (unit-tested);
// the on-device EchoelAI explains, grounded in these — it never invents theory.
//
// Per the 2026-06-17 decision: theory ships as encoded knowledge (not a scraped
// corpus); open-access OER are LINKED later, not bundled. This file is the
// encoded core.

import Foundation

/// One teachable music-theory concept the instrument actually uses.
public enum MusicTheoryTopic: String, CaseIterable, Identifiable, Sendable {
    case interval, scale, chord, progression, cadence, key, tempo, swing, dynamics

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .interval:    return "Interval"
        case .scale:       return "Scale & Mode"
        case .chord:       return "Chord"
        case .progression: return "Chord Progression"
        case .cadence:     return "Cadence"
        case .key:         return "Key"
        case .tempo:       return "Tempo"
        case .swing:       return "Swing"
        case .dynamics:    return "Dynamics"
        }
    }

    /// One-line summary.
    public var summary: String {
        switch self {
        case .interval:    return "The distance in pitch between two notes."
        case .scale:       return "The set of pitches a piece draws from."
        case .chord:       return "Several notes sounding together."
        case .progression: return "The order chords move through over time."
        case .cadence:     return "A chord move that ends or pauses a phrase."
        case .key:         return "The home note and scale a piece centres on."
        case .tempo:       return "How fast the music goes, in beats per minute."
        case .swing:       return "Shifting off-beats later for a rolling feel."
        case .dynamics:    return "How loud or soft the music is, moment to moment."
        }
    }

    /// A short, plain-language paragraph — craft, not mysticism.
    public var detail: String {
        switch self {
        case .interval:
            return "Measured in semitones (the smallest step on a keyboard). Small intervals feel close and smooth; wider ones feel like leaps. Echoelmusic builds melodies by choosing intervals that stay inside your key."
        case .scale:
            return "A ladder of pitches — major sounds bright, minor sounds darker, the modes (Dorian, Phrygian…) each have their own colour. Echoelmusic keeps every generated note on the chosen scale so nothing sounds wrong."
        case .chord:
            return "Usually three or more notes stacked in thirds (a triad). Major and minor triads are the basic colours; sevenths add tension. The body's coherence opens Echoelmusic toward more consonant, settled chords."
        case .progression:
            return "Chords don't sit still — they move, creating pull and release. Common moves (like I–V–vi–IV) feel satisfying because each chord sets up the next. Echoelmusic rotates progressions so a loop doesn't repeat the same change."
        case .cadence:
            return "The punctuation of harmony: a strong V→I lands like a full stop, while other cadences leave a phrase hanging. Echoelmusic resolves a loop with a turnaround cadence so it feels finished, not cut off."
        case .key:
            return "A piece's centre of gravity — its home note plus the scale around it (e.g. C minor). Everything is heard in relation to home. Echoelmusic locks the take to one key (with your concert pitch, default A440) so stems drop into your DAW already in tune."
        case .tempo:
            return "Beats per minute. Slow tempos feel calm, fast ones energetic. In Echoelmusic tempo can follow your heart rate or be locked to an exact BPM for export."
        case .swing:
            return "Straight rhythms place notes evenly; swing pushes every other note slightly late, giving jazz, hip-hop and house their groove. Echoelmusic's swing amount is adjustable per take."
        case .dynamics:
            return "The loud-and-soft shape of a performance. Accents on strong beats and gentle swells make a line feel human rather than mechanical — Echoelmusic adds these with its phrasing and humanize controls."
        }
    }

    /// Shown under the primers — honest framing, not a claim.
    public static let footer =
        "A starting point, not the whole story — music has many traditions. Echoelmusic encodes these so the generator stays in key and the on-device assistant can explain what it did."
}
