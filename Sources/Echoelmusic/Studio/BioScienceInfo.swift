// BioScienceInfo.swift
// Echoelmusic — the "app as a school" entries for the BODY SCIENCE behind the
// biofeedback loop. Echoel already COMPUTES this (ResonanceFinder's Lehrer
// sweep, HRVCoherence's frequency-domain coherence, the baroreflex physiology
// the whole loop rests on); this surface simply teaches the real, cited
// research so the strongest-evidence part of the product is visible, not buried.
//
// HARD BRAND LINE (CLAUDE.md · inspiration.csv · vision-gate): FACTS + self-
// observation only. "Show the number, never promise the benefit." No medical or
// therapeutic claim, no condition treated, no pain/wound/organ language. Sources
// are peer-reviewed (Lehrer & Vaschillo; Goessl, Curtiss & Hofmann 2017).
//
// Pure Foundation (no SwiftUI) so the copy is unit-tested like the other schools.

import Foundation

/// A body-science topic Echoelmusic can explain — grounded in real physiology
/// and cited research, never a health claim.
public enum BioScienceTopic: String, CaseIterable, Identifiable, Sendable {
    case resonanceFrequency, hrvCoherence, baroreflex, hrvResearch, scope

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .resonanceFrequency: return "Resonance breathing (~6 breaths/min)"
        case .hrvCoherence:       return "Heart-rate variability & coherence"
        case .baroreflex:         return "The baroreflex loop"
        case .hrvResearch:        return "What the research measures"
        case .scope:              return "What this is — and is not"
        }
    }

    /// One-line gist for a list row.
    public var summary: String {
        switch self {
        case .resonanceFrequency: return "The pace where breath and heartbeat couple most."
        case .hrvCoherence:       return "A smooth, single-peak heart rhythm you can watch."
        case .baroreflex:         return "The blood-pressure loop that links the two."
        case .hrvResearch:        return "What controlled studies actually reported."
        case .scope:              return "Science for self-observation, not diagnosis."
        }
    }

    public var detail: String {
        switch self {
        case .resonanceFrequency:
            return "Breathing at roughly six breaths per minute (about 0.1 Hz) is the pace at which breathing-driven and blood-pressure-driven influences on heart rate line up, so heart-rate swings grow largest. The exact best pace is individual — usually between 4.5 and 7 breaths per minute — which is why Echoelmusic can sweep several paces and show you which one raises your own heart-rate variability most (the Lehrer & Vaschillo resonance-frequency method). Echoelmusic paces and measures it; it does not prescribe it. (Source: peer-reviewed HRV-biofeedback literature, Lehrer & Vaschillo.)"
        case .hrvCoherence:
            return "Heart-rate variability (HRV) is the beat-to-beat change in your heart rate; more variation at rest generally reflects an adaptable system. \u{201C}Coherence\u{201D} here is a specific, measurable thing: a smooth, single-peak rhythm in the heart rate near 0.1 Hz. Echoelmusic computes it in the frequency domain (a Lomb-Scargle periodogram for the unevenly-timed heartbeats, with Welch averaging) — a standard signal-processing approach, not a score of worth. It is a number to observe, nothing more. (Source: peer-reviewed HRV signal-processing methods.)"
        case .baroreflex:
            return "The baroreflex is the body's fast blood-pressure feedback loop: sensors in the arteries adjust heart rate to keep pressure steady. Breathing near your resonance pace pushes this loop into a large, regular heart-rate swing in step with each breath — that is the physiology the whole biofeedback loop rests on. Echoelmusic lets you watch it happen. (Source: cardiovascular-physiology reviews.)"
        case .hrvResearch:
            return "In a 2017 meta-analysis (Goessl, Curtiss & Hofmann, Psychological Medicine), HRV biofeedback was associated with reduced self-reported stress and anxiety across controlled studies, with a large average effect. That is what the studies measured — self-reported states — and Echoelmusic simply shows you the same live signal to observe. Nothing here is prescribed, and it is not a substitute for professional care. (Source: Goessl, Curtiss & Hofmann, 2017, Psychological Medicine 47:2578–2586.)"
        case .scope:
            return "Echoelmusic measures and explains your heart rhythm and breath honestly so you can observe how they couple, and so your body can drive the music and visuals. It is for self-observation and creative expression. It is NOT a medical device, diagnoses nothing, treats no condition, makes no wellness or health claim, and is not a substitute for professional care. Chest-strap readings are most accurate; wrist and camera are estimates. If you are exploring breathing or heart rhythm for a health reason, talk to a qualified clinician."
        }
    }
}
