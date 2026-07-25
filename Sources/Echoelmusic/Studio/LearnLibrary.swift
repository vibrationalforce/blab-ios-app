// LearnLibrary.swift
// Echoel — the single index behind the "app as a school" idea. Unifies the
// existing teaching content (bio metrics, music theory) plus a safety/scope note
// into one browsable, sectioned model, so a future "Learn" surface binds to ONE
// source instead of many silos. Pure Foundation, unit-tested. No new copy is
// invented here — it reuses BioMetric and MusicTheoryTopic verbatim.

import Foundation

public enum LearnSection: String, CaseIterable, Identifiable, Sendable {
    case body, bodyScience, music, light, safety

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .body:        return "Your Body"
        case .bodyScience: return "Body Science"
        case .music:       return "Music Theory"
        case .light:       return "Light & Colour"
        case .safety:      return "Safety & Scope"
        }
    }
}

/// One learnable entry, renderer-agnostic.
public struct LearnEntry: Identifiable, Sendable, Equatable {
    public let id: String
    public let section: LearnSection
    public let title: String
    public let summary: String
    public let detail: String

    public init(id: String, section: LearnSection, title: String, summary: String, detail: String) {
        self.id = id
        self.section = section
        self.title = title
        self.summary = summary
        self.detail = detail
    }
}

public enum LearnLibrary {

    /// Body metrics — straight from BioMetric (no duplicated copy).
    public static var bodyEntries: [LearnEntry] {
        BioMetric.allCases.map {
            LearnEntry(id: "body.\($0.rawValue)", section: .body,
                       title: $0.title, summary: $0.summary, detail: $0.detail)
        }
    }

    /// Body science — the cited research behind the biofeedback loop (resonance
    /// breathing, HRV coherence, baroreflex). FACTS + self-observation, no claim;
    /// makes the strongest-evidence part of the product visible. See BioScienceInfo.
    public static var bodyScienceEntries: [LearnEntry] {
        BioScienceTopic.allCases.map {
            LearnEntry(id: "bodyScience.\($0.rawValue)", section: .bodyScience,
                       title: $0.title, summary: $0.summary, detail: $0.detail)
        }
    }

    /// Music-theory primers — straight from MusicTheoryTopic.
    public static var musicEntries: [LearnEntry] {
        MusicTheoryTopic.allCases.map {
            LearnEntry(id: "music.\($0.rawValue)", section: .music,
                       title: $0.title, summary: $0.summary, detail: $0.detail)
        }
    }

    /// Light & colour science — straight from LightScienceTopic (cited facts, no
    /// claim). Grounds Echoel's Light (Art-Net/sACN) + colour output in real
    /// wavelengths; see vision-gate (inspiration.csv) for the brand line.
    public static var lightEntries: [LearnEntry] {
        LightScienceTopic.allCases.map {
            LearnEntry(id: "light.\($0.rawValue)", section: .light,
                       title: $0.title, summary: $0.summary, detail: $0.detail)
        }
    }

    /// Safety & scope. TWO entries, and the first one exists for a reachability
    /// reason worth keeping in mind: `CLAUDE.md` mandates five safety warnings in the
    /// app, and four of them lived ONLY in `OnboardingView` — which renders while
    /// `hasCompletedOnboarding == false` and has no reset path. So every existing
    /// tester, every device restore and any reviewer on a second launch had NO way to
    /// reach "not while driving" or "not under the influence". The two strings written
    /// to solve that (`BioSourceView`, `SessionView`) are both in unreachable views.
    /// Putting them here gives them a permanent home: `LearnView` renders every
    /// section from `entries(for:)`, so this needs no new view and — importantly — no
    /// new `.sheet` (the modifier chain is at its metadata ceiling).
    /// Contraindications come FIRST; the scope note follows.
    public static var safetyEntries: [LearnEntry] {
        [
            LearnEntry(
                id: "safety.contraindications", section: .safety,
                title: "When not to use Echoelmusic",
                summary: "Four limits — read them once, they matter.",
                detail: "Do not use rhythmic audio-visual pacing while driving or "
                    + "operating machinery. Do not use it under the influence of "
                    + "alcohol or drugs. If you are using Echoelmusic alongside any "
                    + "therapeutic programme, coordinate it — and any medication "
                    + "timing — with your own provider; Echoelmusic is not part of a "
                    + "treatment and replaces nothing. Visuals are capped at 3 flashes "
                    + "per second (W3C WCAG) and freeze entirely with Reduce Motion on; "
                    + "if you are photosensitive, turn Reduce Motion on before you "
                    + "start. Stop if you feel unwell."
            ),
            LearnEntry(
                id: "safety.scope", section: .safety,
                title: "Self-observation, not diagnosis",
                summary: "What Echoelmusic’s biofeedback is — and is not.",
                detail: BioMetric.disclaimer
                    + " Bio readings are most accurate from a chest strap; wrist and "
                    + "camera are estimates. Breathing guides are optional and never forced."
            )
        ]
    }

    public static func entries(for section: LearnSection) -> [LearnEntry] {
        switch section {
        case .body:        return bodyEntries
        case .bodyScience: return bodyScienceEntries
        case .music:       return musicEntries
        case .light:       return lightEntries
        case .safety:      return safetyEntries
        }
    }

    /// Everything, section-ordered (Body → Body Science → Music → Light → Safety).
    public static var all: [LearnEntry] {
        LearnSection.allCases.flatMap { entries(for: $0) }
    }
}
